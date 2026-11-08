import Foundation
import Observation
import Synchronization
import os.log

extension SyncCoordinator {

  // MARK: - Pull Implementation

  /// Pull changes for a single table
  /// Pages through `sync:pull` by revision, oldest first, until the server says it is done
  func pullTable(
    _ table: SyncTable,
    userId: String,
    after start: Int64
  ) async throws -> TablePullResult {
    var cursor = start
    var totalRows = 0
    var newConflicts = 0
    var autoMerged = 0
    var affectedMonths: Set<ShiftChangeAffectedMonth> = []

    syncCoordinatorLogger.debug("Pulling \(table.displayName) after revision \(cursor)")

    while true {
      let result: PagePullResult

      switch table {
      case .jobs:
        result = try await pullJobsPage(userId: userId, cursor: cursor)

      case .userShifts:
        result = try await pullUserShiftsPage(userId: userId, cursor: cursor)

      case .events:
        result = try await pullEventsPage(userId: userId, cursor: cursor)

      case .recurringShifts:
        result = try await pullRecurringShiftsPage(userId: userId, cursor: cursor)

      case .wageSnapshots:
        result = try await pullWageSnapshotsPage(userId: userId, cursor: cursor)

      case .payrollAdjustments:
        result = try await pullPayrollAdjustmentsPage(userId: userId, cursor: cursor)

      case .userSettings:
        result = try await pullUserSettingsPage(userId: userId, cursor: cursor)

      case .notificationPreferences:
        result = try await pullNotificationPreferencesPage(userId: userId, cursor: cursor)
      }

      totalRows += result.rowsProcessed
      newConflicts += result.newConflicts
      autoMerged += result.autoMerged
      affectedMonths.formUnion(result.affectedMonths)

      // The cursor only moves after the page is applied and saved, so a failed page pulls again.
      let advanced = result.cursor > cursor
      if advanced {
        cursor = result.cursor
        let storeActor = await MainActor.run { LocalStore.shared.storeActor }
        await storeActor.updateSyncState(userId: userId) { state in
          state.updateCursor(for: table, to: result.cursor)
        }
      }

      // A page that does not advance the cursor would repeat for ever.
      if !result.hasMore || !advanced {
        break
      }

      await Task.yield()
    }

    syncCoordinatorLogger.debug("Pulled \(table.displayName): \(totalRows) rows, cursor now at \(cursor)")

    return TablePullResult(
      table: table,
      rowsProcessed: totalRows,
      lastUpdatedAt: nil,
      lastUpdatedAtTieId: nil,
      maxRevision: cursor,
      newConflicts: newConflicts,
      autoMerged: autoMerged,
      affectedMonths: affectedMonths
    )
  }

  /// Result of pulling a single page
  struct PagePullResult {
    let rowsProcessed: Int
    /// Revision of the last row in this page, where the next page starts
    let cursor: Int64
    let newConflicts: Int
    let autoMerged: Int
    let hasMore: Bool
    let affectedMonths: Set<ShiftChangeAffectedMonth>

    init(
      rowsProcessed: Int,
      cursor: Int64,
      newConflicts: Int,
      autoMerged: Int,
      hasMore: Bool,
      affectedMonths: Set<ShiftChangeAffectedMonth> = []
    ) {
      self.rowsProcessed = rowsProcessed
      self.cursor = cursor
      self.newConflicts = newConflicts
      self.autoMerged = autoMerged
      self.hasMore = hasMore
      self.affectedMonths = affectedMonths
    }
  }

  static func affectedMonths(forShiftRows rows: [SyncShiftRow])
    -> Set<ShiftChangeAffectedMonth>
  {
    Set(rows.compactMap { ShiftChangeAffectedMonth(dateISO: $0.shift_date) })
  }

  static func affectedMonths(forEventRows rows: [SyncEventRow])
    -> Set<ShiftChangeAffectedMonth>
  {
    rows.reduce(into: Set<ShiftChangeAffectedMonth>()) { result, row in
      result.formUnion(
        ShiftChangeContext.affecting(
          isoDateRangeStart: row.start_date,
          end: row.end_date
        ).affectedMonths
      )
    }
  }

  static func affectedMonths(forPayrollAdjustmentRows rows: [SyncPayrollAdjustmentRow])
    -> Set<ShiftChangeAffectedMonth>
  {
    Set(rows.compactMap { ShiftChangeAffectedMonth(dateISO: $0.payout_date) })
  }

  // MARK: - Jobs Pull

  private func pullJobsPage(userId: String, cursor: Int64) async throws -> PagePullResult {
    let page: SyncPullPage<SyncJobRow> = try await SyncConvex.pull(
      .jobs, after: cursor, limit: pageSize)
    let rows = page.rows

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        cursor: page.cursor,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    var newConflicts = 0
    var autoMerged = 0
    let pageStartTime = Date()

    for (index, row) in rows.enumerated() {
      let result = try await applyIsolated(table: .jobs, id: row.id) {
        try await self.applyJobRow(row, storeActor: storeActor)
      }
      if result == .conflict { newConflicts += 1 }
      if result == .autoMerged { autoMerged += 1 }

      let rowNumber = index + 1
      if rowNumber.isMultiple(of: pullSaveBatchSize) {
        try await storeActor.save()
        syncCoordinatorLogger.debug("jobs: saved batch at row \(rowNumber)/\(rows.count)")
      }
    }

    try await storeActor.save()

    let duration = Date().timeIntervalSince(pageStartTime)
    syncCoordinatorLogger.info("jobs: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

    return PagePullResult(
      rowsProcessed: rows.count,
      cursor: page.cursor,
      newConflicts: newConflicts,
      autoMerged: autoMerged,
      hasMore: !page.done
    )
  }

  private func applyJobRow(_ serverRow: SyncJobRow, storeActor: LocalStoreActor) async throws
    -> ApplyResult
  {
    let serverUpdatedAt = try requireISO8601(serverRow.updated_at, table: .jobs, id: serverRow.id)
    let serverArchivedAt = serverRow.archived_at.flatMap { parseISO8601($0) }
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if let existing = try await storeActor.jobCopy(id: serverRow.id) {
      return await applyJobToExisting(
        existing: existing,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverArchivedAt: serverArchivedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )
    }
    let localJob = LocalJob.from(serverRow: serverRow, serverUpdatedAt: serverUpdatedAt)
    try await storeActor.upsertJob(localJob)
    return .inserted
  }

  private func applyJobToExisting(
    existing: LocalJob,
    serverRow: SyncJobRow,
    serverUpdatedAt: Date,
    serverArchivedAt: Date?,
    serverDeletedAt: Date?,
    storeActor: LocalStoreActor
  ) async -> ApplyResult {
    let serverSnapshot = JobServerSnapshot.from(row: serverRow, updatedAt: serverUpdatedAt)

    switch existing.syncStatus {
    case .clean:
      if await storeActor.updateJobFromServer(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        archivedAt: serverArchivedAt,
        deletedAt: serverDeletedAt,
        snapshot: serverSnapshot
      ) {
        return .updated
      }
      // The row stopped being clean after it was read. Read it again and take the merge path.
      guard let fresh = try? await storeActor.jobCopy(id: serverRow.id), fresh.syncStatus != .clean else {
        return .noChange
      }
      return await applyJobToExisting(
        existing: fresh,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverArchivedAt: serverArchivedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )

    case .dirty, .pendingDelete:
      if serverRow.revision == existing.serverRevision {
        return .noChange
      }

      await storeActor.autoMergeJob(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        archivedAt: serverArchivedAt,
        deletedAt: serverDeletedAt,
        newSnapshot: serverSnapshot
      )
      return .autoMerged

    case .conflict:
      await storeActor.updateJobConflictSnapshot(id: serverRow.id, serverSnapshot: serverSnapshot)
      return .noChange
    }
  }

  // MARK: - User Shifts Pull

  private func pullUserShiftsPage(userId: String, cursor: Int64) async throws -> PagePullResult
  {
    let page: SyncPullPage<SyncShiftRow> = try await SyncConvex.pull(
      .userShifts, after: cursor, limit: pageSize)
    let rows = page.rows

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        cursor: page.cursor,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    var newConflicts = 0
    var autoMerged = 0
    var affectedMonths = Self.affectedMonths(forShiftRows: rows)
    let pageStartTime = Date()

    for (index, row) in rows.enumerated() {
      if let existing = try await storeActor.userShiftCopy(id: row.id) {
        affectedMonths.insert(ShiftChangeAffectedMonth(date: existing.shiftDate))
      }

      let result = try await applyIsolated(table: .userShifts, id: row.id) {
        try await self.applyShiftRow(row, storeActor: storeActor)
      }
      if result == .conflict { newConflicts += 1 }
      if result == .autoMerged { autoMerged += 1 }

      // Batch save for durability: persist partial progress every N rows
      // Cursor is NOT advanced here - only after full page success
      let rowNumber = index + 1
      if rowNumber.isMultiple(of: pullSaveBatchSize) {
        try await storeActor.save()
        syncCoordinatorLogger.debug("user_shifts: saved batch at row \(rowNumber)/\(rows.count)")
      }
    }

    // Final save for any remaining rows
    try await savePulledPage(storeActor: storeActor, table: .userShifts)

    let duration = Date().timeIntervalSince(pageStartTime)
    syncCoordinatorLogger.info(
      "user_shifts: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

    return PagePullResult(
      rowsProcessed: rows.count,
      cursor: page.cursor,
      newConflicts: newConflicts,
      autoMerged: autoMerged,
      hasMore: !page.done,
      affectedMonths: affectedMonths
    )
  }

  /// Apply a server shift row to local storage
  private func applyShiftRow(_ serverRow: SyncShiftRow, storeActor: LocalStoreActor) async throws
    -> ApplyResult
  {
    // SAFETY: Throw on parse failure to prevent data corruption
    let serverUpdatedAt = try requireISO8601(
      serverRow.updated_at, table: .userShifts, id: serverRow.id)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    // Check if exists locally
    if let existing = try await storeActor.userShiftCopy(id: serverRow.id) {
      return await applyShiftToExisting(
        existing: existing,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )
    }
    // Insert as new clean row
    try await insertNewShift(
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverDeletedAt: serverDeletedAt,
      storeActor: storeActor
    )
    return .inserted
  }

  private func applyShiftToExisting(
    existing: LocalUserShift,
    serverRow: SyncShiftRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    storeActor: LocalStoreActor
  ) async -> ApplyResult {
    let serverSnapshot = UserShiftServerSnapshot.from(
      jobId: serverRow.job_id,
      shiftDate: serverRow.shift_date,
      startTime: serverRow.start_time,
      endTime: serverRow.end_time,
      note: serverRow.note,
      customPauseWindows: serverRow.custom_pause_windows,
      customSupplements: serverRow.custom_supplements,
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision,
      deletedAt: serverDeletedAt
    )

    switch existing.syncStatus {
    case .clean:
      // Overwrite with server data
      if await storeActor.updateShiftFromServer(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        snapshot: serverSnapshot
      ) {
        return .updated
      }
      // The row stopped being clean after it was read. Read it again and take the merge path.
      guard let fresh = try? await storeActor.userShiftCopy(id: serverRow.id), fresh.syncStatus != .clean else {
        return .noChange
      }
      return await applyShiftToExisting(
        existing: fresh,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )

    case .dirty, .pendingDelete:
      if serverRow.revision == existing.serverRevision {
        // Server unchanged, keep local edits
        return .noChange
      }

      // Keep unacknowledged local values. A delayed push can have a newer server timestamp.
      await storeActor.autoMergeShift(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        newSnapshot: serverSnapshot
      )
      return .autoMerged

    case .conflict:
      // Already in conflict, update conflict snapshot
      await storeActor.updateShiftConflictSnapshot(id: serverRow.id, serverSnapshot: serverSnapshot)
      return .noChange
    }
  }

  private func insertNewShift(
    serverRow: SyncShiftRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    storeActor: LocalStoreActor
  ) async throws {
    let dateFormatter = FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone)

    guard let shiftDate = dateFormatter.date(from: serverRow.shift_date) else {
      syncCoordinatorLogger.error("Failed to parse shift_date '\(serverRow.shift_date)' for shift \(serverRow.id)")
      throw SyncError.dateParsingFailed(
        table: .userShifts, id: serverRow.id, rawValue: serverRow.shift_date)
    }
    let supplementsData = serverRow.custom_supplements.flatMap {
      try? kCanonicalJSONEncoder.encode($0)
    }
    let pauseWindowsData = PauseWindowSupport.normalize(serverRow.custom_pause_windows).flatMap {
      try? kCanonicalJSONEncoder.encode($0)
    }

    let snapshot = UserShiftServerSnapshot.from(
      jobId: serverRow.job_id,
      shiftDate: serverRow.shift_date,
      startTime: serverRow.start_time,
      endTime: serverRow.end_time,
      note: serverRow.note,
      customPauseWindows: serverRow.custom_pause_windows,
      customSupplements: serverRow.custom_supplements,
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision,
      deletedAt: serverDeletedAt
    )

    let localShift = LocalUserShift(
      id: serverRow.id,
      userId: serverRow.user_id,
      jobId: serverRow.job_id,
      shiftDate: shiftDate,
      startTime: serverRow.start_time,
      endTime: serverRow.end_time,
      note: serverRow.note,
      customPauseWindows: pauseWindowsData,
      customSupplements: supplementsData,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRow.revision,
      serverDeletedAt: serverDeletedAt,
      syncStatus: .clean,
      dirtyFields: LocalUserShift.emptyDirtyFields(),
      lastSyncedSnapshot: try snapshot.encodedOrThrow(),
      localUpdatedAt: Date(),
      conflictServerSnapshot: nil
    )

    try await storeActor.upsertUserShift(localShift)
  }

  // MARK: - Events Pull

  private func pullEventsPage(userId: String, cursor: Int64) async throws -> PagePullResult {
    let page: SyncPullPage<SyncEventRow> = try await SyncConvex.pull(
      .events, after: cursor, limit: pageSize)
    let rows = page.rows

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        cursor: page.cursor,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    var newConflicts = 0
    var autoMerged = 0
    var affectedMonths = Self.affectedMonths(forEventRows: rows)
    let pageStartTime = Date()

    for (index, row) in rows.enumerated() {
      if let existing = try await storeActor.eventCopy(id: row.id) {
        affectedMonths.formUnion(
          ShiftChangeContext.affecting(
            dateRangeStart: existing.startDate,
            end: existing.endDate
          ).affectedMonths
        )
      }

      let result = try await applyIsolated(table: .events, id: row.id) {
        try await self.applyEventRow(row, storeActor: storeActor)
      }
      if result == .conflict { newConflicts += 1 }
      if result == .autoMerged { autoMerged += 1 }

      let rowNumber = index + 1
      if rowNumber.isMultiple(of: pullSaveBatchSize) {
        try await storeActor.save()
        syncCoordinatorLogger.debug("events: saved batch at row \(rowNumber)/\(rows.count)")
      }
    }

    try await savePulledPage(storeActor: storeActor, table: .events)

    let duration = Date().timeIntervalSince(pageStartTime)
    syncCoordinatorLogger.info(
      "events: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

    return PagePullResult(
      rowsProcessed: rows.count,
      cursor: page.cursor,
      newConflicts: newConflicts,
      autoMerged: autoMerged,
      hasMore: !page.done,
      affectedMonths: affectedMonths
    )
  }

  private func applyEventRow(_ serverRow: SyncEventRow, storeActor: LocalStoreActor) async throws
    -> ApplyResult
  {
    let serverUpdatedAt = try requireISO8601(serverRow.updated_at, table: .events, id: serverRow.id)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if let existing = try await storeActor.eventCopy(id: serverRow.id) {
      return await applyEventToExisting(
        existing: existing,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )
    }
    try await insertNewEvent(
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverDeletedAt: serverDeletedAt,
      storeActor: storeActor
    )
    return .inserted
  }

  private func applyEventToExisting(
    existing: LocalEvent,
    serverRow: SyncEventRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    storeActor: LocalStoreActor
  ) async -> ApplyResult {
    let serverSnapshot = EventServerSnapshot.from(
      serverRow: serverRow,
      updatedAt: serverUpdatedAt,
      deletedAt: serverDeletedAt
    )

    switch existing.syncStatus {
    case .clean:
      if await storeActor.updateEventFromServer(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        snapshot: serverSnapshot
      ) {
        return .updated
      }
      // The row stopped being clean after it was read. Read it again and take the merge path.
      guard let fresh = try? await storeActor.eventCopy(id: serverRow.id), fresh.syncStatus != .clean else {
        return .noChange
      }
      return await applyEventToExisting(
        existing: fresh,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )

    case .dirty, .pendingDelete:
      if serverRow.revision == existing.serverRevision {
        return .noChange
      }

      await storeActor.autoMergeEvent(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        newSnapshot: serverSnapshot
      )
      return .autoMerged

    case .conflict:
      await storeActor.updateEventConflictSnapshot(id: serverRow.id, serverSnapshot: serverSnapshot)
      return .noChange
    }
  }

  private func insertNewEvent(
    serverRow: SyncEventRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    storeActor: LocalStoreActor
  ) async throws {
    let dateFormatter = FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone)

    guard let startDate = dateFormatter.date(from: serverRow.start_date) else {
      syncCoordinatorLogger.error("Failed to parse start_date '\(serverRow.start_date)' for event \(serverRow.id)")
      throw SyncError.dateParsingFailed(
        table: .events, id: serverRow.id, rawValue: serverRow.start_date)
    }

    guard let endDate = dateFormatter.date(from: serverRow.end_date) else {
      syncCoordinatorLogger.error("Failed to parse end_date '\(serverRow.end_date)' for event \(serverRow.id)")
      throw SyncError.dateParsingFailed(
        table: .events, id: serverRow.id, rawValue: serverRow.end_date)
    }

    let snapshot = EventServerSnapshot.from(
      serverRow: serverRow,
      updatedAt: serverUpdatedAt,
      deletedAt: serverDeletedAt
    )

    let localEvent = LocalEvent(
      id: serverRow.id,
      userId: serverRow.user_id,
      startDate: startDate,
      endDate: endDate,
      isAllDay: serverRow.is_all_day,
      startTime: serverRow.start_time,
      endTime: serverRow.end_time,
      note: serverRow.note,
      notificationMinutesArray: serverRow.notification_minutes_array ?? [],
      notificationAnchorTime: serverRow.notification_anchor_time,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRow.revision,
      serverDeletedAt: serverDeletedAt,
      syncStatus: .clean,
      dirtyFields: LocalEvent.emptyDirtyFields(),
      lastSyncedSnapshot: try snapshot.encodedOrThrow(),
      localUpdatedAt: Date(),
      conflictServerSnapshot: nil
    )

    try await storeActor.upsertEvent(localEvent)
  }

  // MARK: - Recurring Shifts Pull

  private func pullRecurringShiftsPage(userId: String, cursor: Int64) async throws
    -> PagePullResult
  {
    let page: SyncPullPage<SyncRecurringShiftRow> = try await SyncConvex.pull(
      .recurringShifts, after: cursor, limit: pageSize)
    let rows = page.rows

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        cursor: page.cursor,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    var newConflicts = 0
    var autoMerged = 0
    let pageStartTime = Date()

    for (index, row) in rows.enumerated() {
      let result = try await applyIsolated(table: .recurringShifts, id: row.id) {
        try await self.applyRecurringShiftRow(row, storeActor: storeActor)
      }
      if result == .conflict { newConflicts += 1 }
      if result == .autoMerged { autoMerged += 1 }

      // Batch save for durability
      let rowNumber = index + 1
      if rowNumber.isMultiple(of: pullSaveBatchSize) {
        try await storeActor.save()
        syncCoordinatorLogger.debug("recurring_shifts: saved batch at row \(rowNumber)/\(rows.count)")
      }
    }

    // Final save for any remaining rows
    try await savePulledPage(storeActor: storeActor, table: .recurringShifts)

    let duration = Date().timeIntervalSince(pageStartTime)
    syncCoordinatorLogger.info(
      "recurring_shifts: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s"
    )

    return PagePullResult(
      rowsProcessed: rows.count,
      cursor: page.cursor,
      newConflicts: newConflicts,
      autoMerged: autoMerged,
      hasMore: !page.done
    )
  }

  private func applyRecurringShiftRow(
    _ serverRow: SyncRecurringShiftRow, storeActor: LocalStoreActor
  ) async throws -> ApplyResult {
    // SAFETY: Throw on parse failure to prevent data corruption
    let serverUpdatedAt = try requireISO8601(
      serverRow.updated_at, table: .recurringShifts, id: serverRow.id)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if let existing = try await storeActor.recurringShiftCopy(id: serverRow.id) {
      return await applyRecurringShiftToExisting(
        existing: existing,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )
    }
    try await insertNewRecurringShift(
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverDeletedAt: serverDeletedAt,
      storeActor: storeActor
    )
    return .inserted
  }

  private func applyRecurringShiftToExisting(
    existing: LocalRecurringShift,
    serverRow: SyncRecurringShiftRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    storeActor: LocalStoreActor
  ) async -> ApplyResult {
    let serverSnapshot = RecurringShiftServerSnapshot.from(
      row: serverRow.toRecurringShiftRow(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision,
      deletedAt: serverDeletedAt
    )

    switch existing.syncStatus {
    case .clean:
      if await storeActor.updateRecurringShiftFromServer(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        snapshot: serverSnapshot
      ) {
        return .updated
      }
      // The row stopped being clean after it was read. Read it again and take the merge path.
      guard let fresh = try? await storeActor.recurringShiftCopy(id: serverRow.id), fresh.syncStatus != .clean else {
        return .noChange
      }
      return await applyRecurringShiftToExisting(
        existing: fresh,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )

    case .dirty, .pendingDelete:
      if serverRow.revision == existing.serverRevision {
        return .noChange
      }

      await storeActor.autoMergeRecurringShift(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        newSnapshot: serverSnapshot
      )
      return .autoMerged

    case .conflict:
      await storeActor.updateRecurringShiftConflictSnapshot(
        id: serverRow.id, serverSnapshot: serverSnapshot)
      return .noChange
    }
  }

  private func insertNewRecurringShift(
    serverRow: SyncRecurringShiftRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    storeActor: LocalStoreActor
  ) async throws {
    let snapshot = RecurringShiftServerSnapshot.from(
      row: serverRow.toRecurringShiftRow(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision,
      deletedAt: serverDeletedAt
    )

    let localShift = LocalRecurringShift(
      id: serverRow.id,
      userId: serverRow.user_id,
      jobId: serverRow.job_id,
      startTime: serverRow.cleanStartTime,
      endTime: serverRow.cleanEndTime,
      repeatIntervalWeeks: serverRow.repeat_interval_weeks,
      selectedDays: try kCanonicalJSONEncoder.encode(serverRow.selected_days),
      endCondition: serverRow.end_condition.flatMap { try? kCanonicalJSONEncoder.encode($0) },
      exclusions: serverRow.exclusions.flatMap { try? kCanonicalJSONEncoder.encode($0) },
      dateSpecificPauseWindows: PauseWindowSupport.normalize(serverRow.date_specific_pause_windows)
        .flatMap { try? kCanonicalJSONEncoder.encode($0) },
      dateSpecificSupplements: serverRow.date_specific_supplements.flatMap {
        try? kCanonicalJSONEncoder.encode($0)
      },
      dateSpecificNotes: ShiftNoteSupport.normalizeDateSpecificNotes(serverRow.date_specific_notes)
        .flatMap { try? kCanonicalJSONEncoder.encode($0) },
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRow.revision,
      serverDeletedAt: serverDeletedAt,
      syncStatus: .clean,
      dirtyFields: LocalRecurringShift.emptyDirtyFields(),
      lastSyncedSnapshot: try snapshot.encodedOrThrow(),
      localUpdatedAt: Date(),
      conflictServerSnapshot: nil
    )

    try await storeActor.upsertRecurringShift(localShift)
  }

  // MARK: - Wage Snapshots Pull

  private func pullWageSnapshotsPage(userId: String, cursor: Int64) async throws
    -> PagePullResult
  {
    let page: SyncPullPage<SyncWageSnapshotRow> = try await SyncConvex.pull(
      .wageSnapshots, after: cursor, limit: pageSize)
    let rows = page.rows

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        cursor: page.cursor,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    var newConflicts = 0
    var autoMerged = 0
    let pageStartTime = Date()

    for (index, row) in rows.enumerated() {
      let result = try await applyIsolated(table: .wageSnapshots, id: row.id) {
        try await self.applyWageSnapshotRow(row, storeActor: storeActor)
      }
      if result == .conflict { newConflicts += 1 }
      if result == .autoMerged { autoMerged += 1 }

      // Batch save for durability
      let rowNumber = index + 1
      if rowNumber.isMultiple(of: pullSaveBatchSize) {
        try await storeActor.save()
        syncCoordinatorLogger.debug("wage_snapshots: saved batch at row \(rowNumber)/\(rows.count)")
      }
    }

    // Final save for any remaining rows
    try await savePulledPage(storeActor: storeActor, table: .wageSnapshots)

    let duration = Date().timeIntervalSince(pageStartTime)
    syncCoordinatorLogger.info(
      "wage_snapshots: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

    return PagePullResult(
      rowsProcessed: rows.count,
      cursor: page.cursor,
      newConflicts: newConflicts,
      autoMerged: autoMerged,
      hasMore: !page.done
    )
  }

  private func applyWageSnapshotRow(_ serverRow: SyncWageSnapshotRow, storeActor: LocalStoreActor)
    async throws -> ApplyResult
  {
    // SAFETY: Throw on parse failure to prevent data corruption
    let serverUpdatedAt = try requireISO8601(
      serverRow.updated_at, table: .wageSnapshots, id: serverRow.id)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if let existing = try await storeActor.wageSnapshotCopy(id: serverRow.id) {
      return await applyWageSnapshotToExisting(
        existing: existing,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )
    }
    try await insertNewWageSnapshot(
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverDeletedAt: serverDeletedAt,
      storeActor: storeActor
    )
    return .inserted
  }

  private func applyWageSnapshotToExisting(
    existing: LocalWageSnapshot,
    serverRow: SyncWageSnapshotRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    storeActor: LocalStoreActor
  ) async -> ApplyResult {
    let serverSnapshot = WageSnapshotServerSnapshot.from(
      row: serverRow.toWageSnapshot(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision,
      deletedAt: serverDeletedAt
    )

    switch existing.syncStatus {
    case .clean:
      if await storeActor.updateWageSnapshotFromServer(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        snapshot: serverSnapshot
      ) {
        return .updated
      }
      // The row stopped being clean after it was read. Read it again and take the merge path.
      guard let fresh = try? await storeActor.wageSnapshotCopy(id: serverRow.id), fresh.syncStatus != .clean else {
        return .noChange
      }
      return await applyWageSnapshotToExisting(
        existing: fresh,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )

    case .dirty, .pendingDelete:
      if serverRow.revision == existing.serverRevision {
        return .noChange
      }

      await storeActor.autoMergeWageSnapshot(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        newSnapshot: serverSnapshot
      )
      return .autoMerged

    case .conflict:
      await storeActor.updateWageSnapshotConflictSnapshot(
        id: serverRow.id, serverSnapshot: serverSnapshot)
      return .noChange
    }
  }

  private func insertNewWageSnapshot(
    serverRow: SyncWageSnapshotRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    storeActor: LocalStoreActor
  ) async throws {
    let dateFormatter = FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone)

    let fromDate = serverRow.from_date.flatMap { dateFormatter.date(from: $0) }

    let snapshot = WageSnapshotServerSnapshot.from(
      row: serverRow.toWageSnapshot(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision,
      deletedAt: serverDeletedAt
    )

    let localSnapshot = LocalWageSnapshot(
      id: serverRow.id,
      userId: serverRow.user_id,
      jobId: serverRow.job_id,
      fromDate: fromDate,
      hourlyWage: serverRow.hourly_wage,
      wageLevel: serverRow.wage_level,
      tariffTypeId: serverRow.tariff_type_id,
      supplements: (try? kCanonicalJSONEncoder.encode(serverRow.supplements)) ?? Data(),
      overtime: (try? kCanonicalJSONEncoder.encode(serverRow.overtime ?? .disabled)) ?? Data(),
      taxEnabled: serverRow.tax_enabled,
      taxPercentage: serverRow.tax_percentage,
      breakEnabled: serverRow.break_enabled,
      breakMethod: serverRow.break_method,
      breakThresholdHours: serverRow.break_threshold_hours,
      breakDeductionMinutes: serverRow.break_deduction_minutes,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRow.revision,
      serverDeletedAt: serverDeletedAt,
      syncStatus: .clean,
      dirtyFields: LocalWageSnapshot.emptyDirtyFields(),
      lastSyncedSnapshot: try snapshot.encodedOrThrow(),
      localUpdatedAt: Date(),
      conflictServerSnapshot: nil
    )

    try await storeActor.upsertWageSnapshot(localSnapshot)
  }

  // MARK: - User Settings Pull

  private func pullUserSettingsPage(userId: String, cursor: Int64) async throws
    -> PagePullResult
  {
    let page: SyncPullPage<SyncUserSettingsRow> = try await SyncConvex.pull(
      .userSettings, after: cursor, limit: pageSize)
    let rows = page.rows

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        cursor: page.cursor,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    var newConflicts = 0
    var autoMerged = 0
    let pageStartTime = Date()

    for (index, row) in rows.enumerated() {
      let result = try await applyIsolated(table: .userSettings, id: row.user_id) {
        try await self.applyUserSettingsRow(row, storeActor: storeActor)
      }
      if result == .conflict { newConflicts += 1 }
      if result == .autoMerged { autoMerged += 1 }

      // Batch save for durability
      let rowNumber = index + 1
      if rowNumber.isMultiple(of: pullSaveBatchSize) {
        try await storeActor.save()
        syncCoordinatorLogger.debug("user_settings: saved batch at row \(rowNumber)/\(rows.count)")
      }
    }

    // Final save for any remaining rows
    try await savePulledPage(storeActor: storeActor, table: .userSettings)

    let duration = Date().timeIntervalSince(pageStartTime)
    syncCoordinatorLogger.info(
      "user_settings: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

    return PagePullResult(
      rowsProcessed: rows.count,
      cursor: page.cursor,
      newConflicts: newConflicts,
      autoMerged: autoMerged,
      hasMore: !page.done
    )
  }

  private func applyUserSettingsRow(_ serverRow: SyncUserSettingsRow, storeActor: LocalStoreActor)
    async throws -> ApplyResult
  {
    // SAFETY: Throw on parse failure to prevent data corruption
    let serverUpdatedAt = try requireISO8601(
      serverRow.updated_at, table: .userSettings, id: serverRow.user_id)

    if let existing = try await storeActor.userSettingsCopy(userId: serverRow.user_id) {
      return await applyUserSettingsToExisting(
        existing: existing,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        storeActor: storeActor
      )
    }
    try await insertNewUserSettings(
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      storeActor: storeActor
    )
    return .inserted
  }

  private func applyUserSettingsToExisting(
    existing: LocalUserSettings,
    serverRow: SyncUserSettingsRow,
    serverUpdatedAt: Date,
    storeActor: LocalStoreActor
  ) async -> ApplyResult {
    let serverSnapshot = UserSettingsServerSnapshot.from(
      row: serverRow.toUserSettings(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision
    )

    switch existing.syncStatus {
    case .clean:
      if await storeActor.updateUserSettingsFromServer(
        userId: serverRow.user_id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        snapshot: serverSnapshot
      ) {
        return .updated
      }
      // The row stopped being clean after it was read. Read it again and take the merge path.
      guard let fresh = try? await storeActor.userSettingsCopy(userId: serverRow.user_id),
        fresh.syncStatus != .clean
      else {
        return .noChange
      }
      return await applyUserSettingsToExisting(
        existing: fresh,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        storeActor: storeActor
      )

    case .dirty:
      if serverRow.revision == existing.serverRevision {
        return .noChange
      }

      // Take the server's profile picture instead of keeping a stale local edit of it.
      await storeActor.dropServerOwnedSettingsFields(userId: serverRow.user_id)
      await storeActor.autoMergeUserSettings(
        userId: serverRow.user_id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        newSnapshot: serverSnapshot
      )
      return .autoMerged

    case .pendingDelete, .conflict:
      // Settings don't have pendingDelete, treat as conflict
      await storeActor.updateUserSettingsConflictSnapshot(
        userId: serverRow.user_id, serverSnapshot: serverSnapshot)
      return .noChange
    }
  }

  private func insertNewUserSettings(
    serverRow: SyncUserSettingsRow,
    serverUpdatedAt: Date,
    storeActor: LocalStoreActor
  ) async throws {
    let lastActive = serverRow.last_active.flatMap { ISO8601Timestamp.date(from: $0) }
    let createdAt = serverRow.created_at.flatMap { ISO8601Timestamp.date(from: $0) }

    let snapshot = UserSettingsServerSnapshot.from(
      row: serverRow.toUserSettings(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision
    )

    let localSettings = LocalUserSettings(
      userId: serverRow.user_id,
      monthlyGoal: serverRow.monthly_goal,
      monthlyGoalsByMonthData: (try? kCanonicalJSONEncoder.encode(
        serverRow.monthly_goals_by_month ?? [:]))
        ?? Data(),
      defaultShiftsView: serverRow.default_shifts_view,
      profilePictureUrl: serverRow.profile_picture_url,
      payrollDay: serverRow.payroll_day,
      theme: serverRow.theme,
      calendarContentColorStyle: serverRow.calendar_content_color_style ?? "workplace",
      showDashboardClockButtons: serverRow.show_dashboard_clock_buttons ?? true,
      halfTaxMonth: serverRow.half_tax_month,
      currency: serverRow.currency,
      defaultStartupTab: serverRow.default_startup_tab,
      lastActive: lastActive,
      createdAt: createdAt,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRow.revision,
      syncStatus: .clean,
      dirtyFields: LocalUserSettings.emptyDirtyFields(),
      lastSyncedSnapshot: try snapshot.encodedOrThrow(),
      localUpdatedAt: Date(),
      conflictServerSnapshot: nil
    )

    try await storeActor.upsertUserSettings(localSettings)
  }
}
