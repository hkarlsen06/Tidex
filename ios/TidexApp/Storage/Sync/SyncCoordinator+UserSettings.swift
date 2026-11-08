import Foundation
import Observation
import Synchronization
import os.log

extension SyncCoordinator {

  // MARK: - User Settings Push

  func pushUserSettings(userId: String) async throws -> TablePushResult {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    // The profile picture is server owned, so it never counts as a local edit.
    await storeActor.dropServerOwnedSettingsFields(userId: userId)
    guard let settings = try await storeActor.dirtyUserSettingsCopy(userId: userId) else {
      return TablePushResult(table: .userSettings, rowsPushed: 0, newConflicts: 0, rebased: 0)
    }

    let result: PushResult
    do {
      result = try await pushUserSettingsRow(
        settings, userId: userId, storeActor: storeActor, isRetry: false)
    } catch let error where Self.isRowRejection(error) {
      syncCoordinatorLogger.error("Server rejected user settings: \(error.localizedDescription)")
      await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: nil)
      result = .conflict
    }

    var rowsPushed = 0
    var newConflicts = 0
    var rebased = 0

    switch result {
    case .success:
      rowsPushed = 1

    case .conflict:
      newConflicts = 1

    case .rebased:
      rebased = 1
      rowsPushed = 1

    case .noChange, .deleted:
      break
    }

    try await storeActor.save()
    return TablePushResult(
      table: .userSettings, rowsPushed: rowsPushed, newConflicts: newConflicts, rebased: rebased)
  }

  /// Columns of a partial user settings UPDATE, limited to the fields marked dirty.
  private func userSettingsUpdatePayload(
    for settings: LocalUserSettings, userId: String, dirtyFields: Set<UserSettingsField>
  ) throws -> [String: AnyJSON] {
    var update = PartialUpdatePayload(dirtyFields: dirtyFields)
    update.set(.monthlyGoal, "monthly_goal", settings.monthlyGoal.jsonOrNull { .integer($0) })
    try update.set(
      .monthlyGoalsByMonth, "monthly_goals_by_month",
      try requireAnyJSON(
        try requireEncode(
          settings.monthlyGoalsByMonth,
          typeName: "UserSettings.monthlyGoalsByMonth"
        ),
        table: .userSettings,
        id: userId,
        field: "monthly_goals_by_month"
      ))
    update.set(
      .defaultShiftsView, "default_shifts_view",
      settings.defaultShiftsView.jsonOrNull { .string($0) })
    update.set(.payrollDay, "payroll_day", settings.payrollDay.jsonOrNull { .integer($0) })
    update.set(.theme, "theme", .string(settings.theme))
    update.set(
      .calendarContentColorStyle, "calendar_content_color_style",
      .string(settings.effectiveCalendarContentColorStyle))
    update.set(
      .showDashboardClockButtons, "show_dashboard_clock_buttons",
      .bool(settings.effectiveShowDashboardClockButtons))
    update.set(.halfTaxMonth, "half_tax_month", settings.halfTaxMonth.jsonOrNull { .integer($0) })
    update.set(.currency, "currency", settings.currency.jsonOrNull { .string($0) })
    update.set(
      .defaultStartupTab, "default_startup_tab", .string(settings.effectiveDefaultStartupTab))
    update.set(
      .lastActive, "last_active",
      settings.lastActive.jsonOrNull { .string(formatTimestamp($0)) })
    return update.data
  }

  func pushUserSettingsRow(
    _ settings: LocalUserSettings,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let dirtyFields = settings.dirtyFieldKeys
    if dirtyFields.isEmpty {
      await storeActor.markUserSettingsClean(userId: userId)
      return .noChange
    }

    // Check if this is a new record that needs INSERT (serverRevision == 0 means never synced)
    if settings.serverRevision == 0 {
      return try await insertUserSettings(settings, userId: userId, storeActor: storeActor)
    }

    let baseline = SyncPushBaseline(settings)
    let updateData = try userSettingsUpdatePayload(
      for: settings, userId: userId, dirtyFields: dirtyFields)

    let outcome: SyncWriteOutcome<SyncUserSettingsRow> = try await SyncConvex.update(
      .userSettings, owner: settings.userId, id: nil,
      expectedRevision: settings.serverRevision, data: updateData)

    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(
        returnedRow.updated_at, table: .userSettings, id: userId)
      let serverSnapshot = UserSettingsServerSnapshot.from(
        row: returnedRow.toUserSettings(),
        updatedAt: serverUpdatedAt,
        revision: returnedRow.revision
      )

      await storeActor.markUserSettingsPushed(
        userId: userId,
        serverRow: returnedRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        snapshot: serverSnapshot,
        baseline: baseline
      )

      syncCoordinatorLogger.debug("Pushed user settings for \(userId.prefix(8))")
      return .success
    case .conflict(let serverRow):
      return try await handleUserSettingsPushConflict(
        settings: settings,
        serverRow: serverRow,
        userId: userId,
        storeActor: storeActor,
        isRetry: isRetry
      )
    }
  }

  /// Insert new user settings that were created locally (serverRevision == 0)
  private func insertUserSettings(
    _ settings: LocalUserSettings,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let baseline = SyncPushBaseline(settings)
    // Build full insert data
    var insertData: [String: AnyJSON] = [
      "user_id": .string(userId),
      "theme": .string(settings.theme),
      "calendar_content_color_style": .string(settings.effectiveCalendarContentColorStyle),
      "show_dashboard_clock_buttons": .bool(settings.effectiveShowDashboardClockButtons),
    ]

    let monthlyGoalsByMonthEncoded = try requireEncode(
      settings.monthlyGoalsByMonth,
      typeName: "UserSettings.monthlyGoalsByMonth"
    )
    let monthlyGoalsByMonthDecoded = try requireAnyJSON(
      monthlyGoalsByMonthEncoded,
      table: .userSettings,
      id: userId,
      field: "monthly_goals_by_month"
    )
    insertData["monthly_goals_by_month"] = monthlyGoalsByMonthDecoded

    // Optional fields
    if let goal = settings.monthlyGoal {
      insertData["monthly_goal"] = .integer(goal)
    }
    if let view = settings.defaultShiftsView {
      insertData["default_shifts_view"] = .string(view)
    }
    if let day = settings.payrollDay {
      insertData["payroll_day"] = .integer(day)
    }
    if let month = settings.halfTaxMonth {
      insertData["half_tax_month"] = .integer(month)
    }
    if let currency = settings.currency {
      insertData["currency"] = .string(currency)
    }
    insertData["default_startup_tab"] = .string(settings.effectiveDefaultStartupTab)
    if let lastActive = settings.lastActive {
      insertData["last_active"] = .string(formatTimestamp(lastActive))
    }

    let outcome: SyncInsertOutcome<SyncUserSettingsRow> = try await SyncConvex.insert(
      .userSettings, owner: settings.userId, row: insertData)

    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(
        returnedRow.updated_at, table: .userSettings, id: userId)
      let serverSnapshot = UserSettingsServerSnapshot.from(
        row: returnedRow.toUserSettings(),
        updatedAt: serverUpdatedAt,
        revision: returnedRow.revision
      )

      await storeActor.markUserSettingsPushed(
        userId: userId,
        serverRow: returnedRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        snapshot: serverSnapshot,
        baseline: baseline
      )

      syncCoordinatorLogger.debug("Inserted new user settings for \(userId.prefix(8))")
      return .success
    case .exists(let serverRow):
      // The row exists, usually because an earlier insert committed after the request timed
      // out locally or the server created it. Merge onto it.
      syncCoordinatorLogger.warning("User settings for \(userId.prefix(8)) already exist on server, merging")
      return try await handleUserSettingsPushConflict(
        settings: settings, serverRow: serverRow, userId: userId, storeActor: storeActor,
        isRetry: false)
    }
  }

  private func handleUserSettingsPushConflict(
    settings: LocalUserSettings,
    serverRow: SyncUserSettingsRow?,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    guard let serverRow else {
      // Server row doesn't exist - check if this is a new local record that needs INSERT
      if settings.serverRevision == 0 {
        syncCoordinatorLogger.debug(
          "User settings for \(userId.prefix(8)) is new (serverRevision=0), attempting INSERT")
        return try await insertUserSettings(settings, userId: userId, storeActor: storeActor)
      }
      syncCoordinatorLogger.debug("User settings for \(userId.prefix(8)) were deleted on server")
      await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: nil)
      return .conflict
    }

    let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .userSettings, id: userId)

    let newServerSnapshot = UserSettingsServerSnapshot.from(
      row: serverRow.toUserSettings(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision
    )
    guard !isRetry else {
      await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: newServerSnapshot)
      return .conflict
    }

    await storeActor.rebaseUserSettings(
      userId: userId,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRow.revision,
      newSnapshot: newServerSnapshot
    )

    if let rebasedSettings = try await storeActor.userSettingsCopy(userId: userId) {
      let retryResult = try await pushUserSettingsRow(
        rebasedSettings, userId: userId, storeActor: storeActor, isRetry: true)
      if retryResult == .success {
        return .rebased
      }
      return retryResult
    }
    return .conflict
  }
}
