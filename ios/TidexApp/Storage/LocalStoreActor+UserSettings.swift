import Foundation
import SwiftData
import os.log

extension LocalStoreActor {

  // MARK: - User Settings Operations

  /// Upsert user settings from server data
  internal func upsertUserSettings(_ settings: LocalUserSettings) throws {
    let settingsUserId = settings.userId
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == settingsUserId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      // Update existing
      existing.monthlyGoal = settings.monthlyGoal
      existing.monthlyGoalsByMonthData = settings.monthlyGoalsByMonthData
      existing.defaultShiftsView = settings.defaultShiftsView
      existing.profilePictureUrl = settings.profilePictureUrl
      existing.payrollDay = settings.payrollDay
      existing.theme = settings.theme
      existing.calendarContentColorStyle = settings.calendarContentColorStyle
      existing.showDashboardClockButtons = settings.showDashboardClockButtons
      existing.halfTaxMonth = settings.halfTaxMonth
      existing.currency = settings.currency
      existing.defaultStartupTab = settings.defaultStartupTab
      existing.lastActive = settings.lastActive
      existing.createdAt = settings.createdAt
      existing.serverUpdatedAt = settings.serverUpdatedAt
      existing.serverRevision = settings.serverRevision
      existing.syncStatusRaw = settings.syncStatusRaw
      existing.dirtyFields = settings.dirtyFields
      existing.lastSyncedSnapshot = settings.lastSyncedSnapshot
      existing.localUpdatedAt = settings.localUpdatedAt
      existing.conflictServerSnapshot = settings.conflictServerSnapshot
    } else {
      // Insert new
      modelContext.insert(settings)
    }
  }

  /// Get user settings by user ID
  internal func getUserSettings(userId: String) throws -> LocalUserSettings? {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor).first
  }

  /// Get dirty user settings that need to be pushed
  internal func getDirtyUserSettings(userId: String) throws -> LocalUserSettings? {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { settings in
        settings.userId == userId
          && (settings.syncStatusRaw == "dirty"
            // Include conflict records that were never synced (serverRevision=0)
            // These are new local records that failed initial sync and need INSERT
            || (settings.syncStatusRaw == "conflict" && settings.serverRevision == 0))
      }
    )
    return try modelContext.fetch(descriptor).first
  }

  internal func hasDirtyUserSettings(userId: String) throws -> Bool {
    var descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { settings in
        settings.userId == userId
          && (settings.syncStatusRaw == "dirty"
            || (settings.syncStatusRaw == "conflict" && settings.serverRevision == 0))
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  // MARK: - Local User Settings Write Operations

  /// Create a new local user settings entry
  /// Used during onboarding when no settings exist yet
  internal func createUserSettings(
    userId: String,
    payrollDay: Int? = nil,
    currency: String? = nil,
    theme: String = "system",
    calendarContentColorStyle: String = "workplace",
    showDashboardClockButtons: Bool = true,
    monthlyGoal: Int? = nil,
    monthlyGoalsByMonth: [String: Int] = [:],
    defaultShiftsView: String? = nil,
    halfTaxMonth: Int? = nil,
    defaultStartupTab: String? = nil
  ) throws -> UserSettings {
    let now = Date()

    // Build the server snapshot for sync tracking
    let serverSnapshot = UserSettingsServerSnapshot(
      monthlyGoal: monthlyGoal,
      monthlyGoalsByMonth: monthlyGoalsByMonth,
      defaultShiftsView: defaultShiftsView,
      profilePictureUrl: nil,
      payrollDay: payrollDay,
      theme: theme,
      calendarContentColorStyle: calendarContentColorStyle,
      showDashboardClockButtons: showDashboardClockButtons,
      halfTaxMonth: halfTaxMonth,
      currency: currency,
      defaultStartupTab: defaultStartupTab,
      lastActive: now,
      updatedAt: now,
      revision: 0
    )

    // Track all non-nil fields as dirty so they get pushed to server
    var dirtyFields: [UserSettingsField] = [
      .theme, .calendarContentColorStyle, .showDashboardClockButtons, .lastActive,
    ]
    if payrollDay != nil { dirtyFields.append(.payrollDay) }
    if currency != nil { dirtyFields.append(.currency) }
    if monthlyGoal != nil { dirtyFields.append(.monthlyGoal) }
    if !monthlyGoalsByMonth.isEmpty { dirtyFields.append(.monthlyGoalsByMonth) }
    if defaultShiftsView != nil { dirtyFields.append(.defaultShiftsView) }
    if halfTaxMonth != nil { dirtyFields.append(.halfTaxMonth) }
    if defaultStartupTab != nil { dirtyFields.append(.defaultStartupTab) }

    let dirtyFieldsData =
      (try? kCanonicalJSONEncoder.encode(dirtyFields.map(\.rawValue))) ?? Data()

    let localSettings = LocalUserSettings(
      userId: userId,
      monthlyGoal: monthlyGoal,
      monthlyGoalsByMonthData: (try? kCanonicalJSONEncoder.encode(monthlyGoalsByMonth))
        ?? Data(),
      defaultShiftsView: defaultShiftsView,
      profilePictureUrl: nil,
      payrollDay: payrollDay,
      theme: theme,
      calendarContentColorStyle: calendarContentColorStyle,
      showDashboardClockButtons: showDashboardClockButtons,
      halfTaxMonth: halfTaxMonth,
      currency: currency,
      defaultStartupTab: defaultStartupTab,
      lastActive: now,
      createdAt: now,
      serverUpdatedAt: now,
      serverRevision: 0,
      syncStatus: .dirty,
      dirtyFields: dirtyFieldsData,
      lastSyncedSnapshot: serverSnapshot.encoded(),
      localUpdatedAt: now,
      conflictServerSnapshot: nil
    )

    modelContext.insert(localSettings)
    try modelContext.save()
    return localSettings.toUserSettings()
  }

  /// Get or create user settings for a user
  /// Returns existing settings if found, otherwise creates new settings
  internal func getOrCreateUserSettings(
    userId: String,
    payrollDay: Int? = nil,
    currency: String? = nil
  ) throws -> UserSettings {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      return existing.toUserSettings()
    }

    // Create new settings
    return try createUserSettings(
      userId: userId,
      payrollDay: payrollDay,
      currency: currency
    )
  }

  // swiftlint:disable:next function_parameter_count
  internal func updateUserSettings(
    userId: String,
    monthlyGoal: Int?,
    monthlyGoalsByMonth: [String: Int]?,
    defaultShiftsView: String?,
    profilePictureUrl: String?,
    payrollDay: Int?,
    theme: String?,
    calendarContentColorStyle: String? = nil,
    showDashboardClockButtons: Bool? = nil,
    halfTaxMonth: Int?,
    currency: String?,
    defaultStartupTab: String?
  ) throws -> UserSettings {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let localSettings = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var newDirtyFields = localSettings.dirtyFieldKeys
    let now = Date()

    if let newGoal = monthlyGoal, newGoal != localSettings.monthlyGoal {
      localSettings.monthlyGoal = newGoal
      newDirtyFields.insert(.monthlyGoal)
    }

    if let newMonthlyGoalsByMonth = monthlyGoalsByMonth,
      newMonthlyGoalsByMonth != localSettings.monthlyGoalsByMonth
    {
      localSettings.monthlyGoalsByMonth = newMonthlyGoalsByMonth
      newDirtyFields.insert(.monthlyGoalsByMonth)
    }

    if let newView = defaultShiftsView, newView != localSettings.defaultShiftsView {
      localSettings.defaultShiftsView = newView
      newDirtyFields.insert(.defaultShiftsView)
    }

    if let newUrl = profilePictureUrl, newUrl != localSettings.profilePictureUrl {
      localSettings.profilePictureUrl = newUrl
      newDirtyFields.insert(.profilePictureUrl)
    }

    if let newDay = payrollDay, newDay != localSettings.payrollDay {
      localSettings.payrollDay = newDay
      newDirtyFields.insert(.payrollDay)
    }

    // Theme: Always mark dirty when explicitly set, even if value appears unchanged
    // This handles the case where UserDefaults cache differs from SwiftData
    // (e.g., user changed theme but sync failed, SwiftData has old server value)
    if let newTheme = theme {
      localSettings.theme = newTheme
      newDirtyFields.insert(.theme)
    }

    if let newStyle = calendarContentColorStyle {
      localSettings.calendarContentColorStyle = newStyle
      newDirtyFields.insert(.calendarContentColorStyle)
    }

    if let newShowDashboardClockButtons = showDashboardClockButtons {
      localSettings.showDashboardClockButtons = newShowDashboardClockButtons
      newDirtyFields.insert(.showDashboardClockButtons)
    }

    if let newHalfTax = halfTaxMonth, newHalfTax != localSettings.halfTaxMonth {
      localSettings.halfTaxMonth = newHalfTax
      newDirtyFields.insert(.halfTaxMonth)
    }

    if let newCurrency = currency, newCurrency != localSettings.currency {
      localSettings.currency = newCurrency
      newDirtyFields.insert(.currency)
    }

    if let newDefaultStartupTab = defaultStartupTab,
      newDefaultStartupTab != localSettings.defaultStartupTab
    {
      localSettings.defaultStartupTab = newDefaultStartupTab
      newDirtyFields.insert(.defaultStartupTab)
    }

    localSettings.dirtyFieldKeys = newDirtyFields
    localSettings.localUpdatedAt = now

    // Mark as dirty if we have dirty fields and status allows it
    if !newDirtyFields.isEmpty, localSettings.syncStatus == .clean {
      localSettings.syncStatus = .dirty
    }

    try modelContext.save()
    return localSettings.toUserSettings()
  }

  /// Clear the profile picture URL (set to nil)
  /// This is separate from updateUserSettings because Swift optionals can't distinguish
  /// between "not provided" and "explicitly set to nil"
  internal func clearProfilePictureUrl(userId: String) throws -> UserSettings {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let localSettings = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    localSettings.profilePictureUrl = nil
    localSettings.dirtyFieldKeys.insert(.profilePictureUrl)
    localSettings.localUpdatedAt = Date()

    if localSettings.syncStatus == .clean {
      localSettings.syncStatus = .dirty
    }

    try modelContext.save()
    return localSettings.toUserSettings()
  }

  internal func resolveStoredUserSettingsConflictKeepLocal(userId: String) throws {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let localSettings = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localSettings.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    guard
      let serverSnapshot = UserSettingsServerSnapshot.decode(
        from: localSettings.conflictServerSnapshot ?? Data()
      )
    else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localSettings.serverRevision = serverSnapshot.revision
    localSettings.serverUpdatedAt = serverSnapshot.updatedAt
    localSettings.syncStatus = .dirty
    localSettings.conflictServerSnapshot = nil
    localSettings.localUpdatedAt = Date()

    try modelContext.save()
  }

  internal func resolveStoredUserSettingsConflictKeepServer(userId: String) throws {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let localSettings = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localSettings.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    let conflictData = localSettings.conflictServerSnapshot ?? Data()
    guard let serverSnapshot = UserSettingsServerSnapshot.decode(from: conflictData) else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localSettings.monthlyGoal = serverSnapshot.monthlyGoal
    localSettings.monthlyGoalsByMonth = serverSnapshot.monthlyGoalsByMonth
    localSettings.defaultShiftsView = serverSnapshot.defaultShiftsView
    localSettings.profilePictureUrl = serverSnapshot.profilePictureUrl
    localSettings.payrollDay = serverSnapshot.payrollDay
    localSettings.theme = serverSnapshot.theme
    localSettings.calendarContentColorStyle = serverSnapshot.calendarContentColorStyle
    localSettings.showDashboardClockButtons = serverSnapshot.showDashboardClockButtons
    localSettings.halfTaxMonth = serverSnapshot.halfTaxMonth
    localSettings.currency = serverSnapshot.currency
    localSettings.defaultStartupTab = serverSnapshot.defaultStartupTab
    localSettings.lastActive = serverSnapshot.lastActive
    localSettings.serverRevision = serverSnapshot.revision
    localSettings.serverUpdatedAt = serverSnapshot.updatedAt
    localSettings.syncStatus = .clean
    localSettings.dirtyFieldKeys = []
    localSettings.lastSyncedSnapshot = conflictData
    localSettings.conflictServerSnapshot = nil
    localSettings.localUpdatedAt = Date()

    try modelContext.save()
  }
}
