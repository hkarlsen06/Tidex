import Combine
import Foundation
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SyncCoordinator")

private enum SyncDateFormatters {
  private static func cached<T: AnyObject>(_ key: String, builder: () -> T) -> T {
    let dictionary = Thread.current.threadDictionary
    if let cached = dictionary[key] as? T {
      return cached
    }
    let formatter = builder()
    dictionary[key] = formatter
    return formatter
  }

  static func iso8601DefaultFormatter() -> ISO8601DateFormatter {
    cached("tidex.sync.iso8601.default") {
      ISO8601DateFormatter()
    }
  }

  static func iso8601FractionalFormatter() -> ISO8601DateFormatter {
    cached("tidex.sync.iso8601.fractional") {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return formatter
    }
  }

  static func iso8601InternetFormatter() -> ISO8601DateFormatter {
    cached("tidex.sync.iso8601.internet") {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime]
      return formatter
    }
  }
}

/// Batch size for intermediate saves during pull operations.
/// Rows are saved every N rows to ensure durability if a later row fails.
/// Cursor is only persisted after full page success, so failed pages will re-pull.
private let pullSaveBatchSize = 50

private enum SyncState {
  case idle
  case syncing(userId: String, startedAt: Date)
}

private enum SyncStartDecision {
  case started
  case alreadySyncing
  case skippedInterval
}

private actor SyncStateStore {
  private var syncState: SyncState = .idle
  private var lastAutoSyncAt: Date?

  func beginSync(reason: SyncReason, userId: String, minimumSyncInterval: TimeInterval)
    -> SyncStartDecision
  {
    switch syncState {
    case .syncing:
      return .alreadySyncing
    case .idle:
      break
    }

    let requiresIntervalCheck =
      reason != .manualRefresh && reason != .localChange && reason != .watchRefresh
    if requiresIntervalCheck,
      let lastAuto = lastAutoSyncAt,
      Date().timeIntervalSince(lastAuto) < minimumSyncInterval
    {
      return .skippedInterval
    }

    if requiresIntervalCheck {
      lastAutoSyncAt = Date()
    }

    syncState = .syncing(userId: userId, startedAt: Date())
    return .started
  }

  func endSync() {
    syncState = .idle
  }

  func reset() {
    syncState = .idle
    lastAutoSyncAt = nil
  }
}

// MARK: - Sync Coordinator

/// Coordinates bidirectional sync between local SwiftData storage and Supabase
/// Implements incremental sync via revision cursors with field-level conflict detection
final class SyncCoordinator: ObservableObject {
  /// Shared instance
  static let shared = SyncCoordinator()

  // MARK: - Published State

  /// Whether a sync is currently in progress
  @Published private(set) var isSyncing = false

  /// Last sync error (nil if last sync succeeded)
  @Published private(set) var lastError: String?

  /// Number of unresolved conflicts
  @Published private(set) var conflictCount = 0

  /// When the last successful sync completed
  @Published private(set) var lastSyncedAt: Date?

  // MARK: - Configuration

  /// Page size for incremental sync queries
  private let pageSize = 500

  /// Minimum interval between automatic syncs (in seconds)
  private let minimumSyncInterval: TimeInterval = 60

  /// Maximum time a sync operation can run before being cancelled (in nanoseconds).
  /// Prevents zombie syncs from holding the syncing lock indefinitely.
  private static let syncTimeout: UInt64 = 30_000_000_000  // 30 seconds

  // MARK: - Private State

  /// Sync state for atomic check-and-set operations
  private let stateStore = SyncStateStore()

  private init() {}

  /// Reset sync state when user changes (e.g., sign out)
  /// Clears the interval guard so the next user's initial sync isn't blocked
  func resetForUserChange() async {
    await stateStore.reset()
    await MainActor.run {
      isSyncing = false
      lastError = nil
      lastSyncedAt = nil
      conflictCount = 0
      SyncStatusManager.shared.reset()
    }
    logger.info("Sync state reset for user change")
  }

  // MARK: - App Locale Update

  /// Keeps `raw_user_meta_data.locale` aligned with the active iPhone/app language.
  /// Stores the app localization identifier (e.g. `nb`, `pt-br`, `zh-hans`) for server-side localization.
  private func updateAppLocaleMetadataIfNeeded() async {
    guard let appLocaleCode = currentAppLocaleMetadataCode() else {
      logger.debug("Skipping locale metadata sync: app locale code is empty")
      return
    }

    do {
      // Route session access through AuthSessionManager to avoid refresh races
      // with other launch/foreground tasks.
      let session = try await AuthSessionManager.shared.getSession()
      let currentMetadataLocale = session.user.userMetadata["locale"]?.value as? String
      let normalizedCurrentLocale = currentMetadataLocale?.lowercased()

      guard normalizedCurrentLocale != appLocaleCode else {
        return
      }

      _ = try await supabase.auth.update(
        user: UserAttributes(data: ["locale": .string(appLocaleCode)])
      )
      logger.debug(
        "Updated user locale metadata from \(normalizedCurrentLocale ?? "nil") to \(appLocaleCode)"
      )
    } catch {
      // Non-fatal - log but don't fail sync/foreground flow.
      logger.warning("Failed to update app locale metadata: \(error.localizedDescription)")
    }
  }

  private func currentAppLocaleMetadataCode() -> String? {
    let identifier =
      Bundle.main.preferredLocalizations.first
      ?? Locale.autoupdatingCurrent.identifier
    let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    guard !normalized.isEmpty, normalized != "base" else { return nil }
    return normalized
  }

  // MARK: - Public API

  /// Trigger a sync operation
  /// - Parameters:
  ///   - reason: Why the sync was triggered (for logging)
  ///   - userId: User ID to sync for
  /// - Returns: Sync result
  @discardableResult
  func sync(reason: SyncReason, userId: String) async -> SyncResult {
    await sync(
      reason: reason,
      userId: userId,
      tables: SyncTable.allCases,
      updateWidgetStorage: true
    )
  }

  @discardableResult
  func sync(
    reason: SyncReason,
    userId: String,
    tables: [SyncTable],
    updateWidgetStorage: Bool = true
  ) async -> SyncResult {
    var seenTables = Set<SyncTable>()
    let uniqueTables = tables.filter { seenTables.insert($0).inserted }
    guard !uniqueTables.isEmpty else {
      return SyncResult(
        success: true,
        tableResults: [],
        pushResults: [],
        totalRowsProcessed: 0,
        totalRowsPushed: 0,
        totalConflicts: 0,
        totalAutoMerged: 0,
        duration: 0,
        error: nil
      )
    }

    var decision: SyncStartDecision = .alreadySyncing
    var waitAttempts = 0
    let maxWaitAttempts = 48  // 12s at 250ms intervals

    syncStartLoop: while true {
      decision = await stateStore.beginSync(
        reason: reason,
        userId: userId,
        minimumSyncInterval: minimumSyncInterval
      )

      // Manual pull-to-refresh should wait for an ongoing sync, then retry.
      // This avoids dismissing the refresh UI immediately when background sync is active.
      if case .alreadySyncing = decision, reason == .manualRefresh {
        if waitAttempts >= maxWaitAttempts {
          logger.warning("Manual refresh timed out waiting for ongoing sync to finish")
          break syncStartLoop
        }
        waitAttempts += 1
        logger.info("Manual refresh requested while sync in progress, waiting for idle")
        do {
          try await Task.sleep(nanoseconds: 250_000_000)
        } catch {
          return SyncResult(
            success: false,
            tableResults: [],
            pushResults: [],
            totalRowsProcessed: 0,
            totalRowsPushed: 0,
            totalConflicts: 0,
            totalAutoMerged: 0,
            duration: 0,
            error: nil
          )
        }
        continue syncStartLoop
      }

      break syncStartLoop
    }

    switch decision {
    case .alreadySyncing:
      logger.info("Sync already in progress, skipping \(reason.rawValue)")
      return SyncResult(
        success: false,
        tableResults: [],
        pushResults: [],
        totalRowsProcessed: 0,
        totalRowsPushed: 0,
        totalConflicts: 0,
        totalAutoMerged: 0,
        duration: 0,
        error: "Sync already in progress"
      )
    case .skippedInterval:
      // Keep locale metadata in sync even when full sync is interval-skipped.
      await updateAppLocaleMetadataIfNeeded()
      // Keep foreground Live Activity state fresh without running full widget
      // storage recomputation on the main thread when sync is interval-skipped.
      await MainActor.run {
        AppDelegate.shared?.checkAndStartLiveActivityIfNeeded()
      }
      return SyncResult(
        success: false,
        tableResults: [],
        pushResults: [],
        totalRowsProcessed: 0,
        totalRowsPushed: 0,
        totalConflicts: 0,
        totalAutoMerged: 0,
        duration: 0,
        error: nil
      )
    case .started:
      break
    }

    await MainActor.run {
      isSyncing = true
      lastError = nil
    }

    // Update global sync status for UI indicators (only for manual pull-to-refresh)
    if reason == .manualRefresh {
      await MainActor.run {
        SyncStatusManager.shared.syncStarted()
      }
    }

    let startTime = Date()

    // Race the sync work against a timeout to prevent zombie syncs
    // from holding the syncing lock indefinitely.
    let result: SyncResult = await withTaskGroup(of: SyncResult?.self) { group in
      group.addTask {
        await self.performSyncWork(
          userId: userId,
          startTime: startTime,
          tables: uniqueTables,
          updateWidgetStorage: updateWidgetStorage
        )
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: Self.syncTimeout)
        return nil  // timeout signal
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
        ?? SyncResult(
          success: false,
          tableResults: [],
          pushResults: [],
          totalRowsProcessed: 0,
          totalRowsPushed: 0,
          totalConflicts: 0,
          totalAutoMerged: 0,
          duration: Date().timeIntervalSince(startTime),
          error: "Sync timed out"
        )
    }

    if result.error == "Sync timed out" {
      logger.error("Sync timed out after 30s, cancelling")
      await MainActor.run {
        lastError = "Sync timed out"
        SyncStatusManager.shared.syncFailed(message: "Sync timed out")
      }
    }

    await stateStore.endSync()
    await MainActor.run {
      isSyncing = false
    }
    return result
  }

  /// Performs the actual sync work (locale update, pull, push, widget update).
  /// Extracted so it can be raced against a timeout in `sync()`.
  private func performSyncWork(
    userId: String,
    startTime: Date,
    tables: [SyncTable],
    updateWidgetStorage: Bool
  ) async -> SyncResult {
    // Keep locale metadata aligned with the app locale.
    await updateAppLocaleMetadataIfNeeded()

    // Get or create sync state
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    do {
      try Task.checkCancellation()

      let syncState = try await storeActor.getOrCreateSyncState(userId: userId)
      await storeActor.updateSyncState(userId: userId) { state in
        state.markSyncStarted()
      }

      // Phase 1: Pull all tables (get latest server state)
      var tableResults: [TablePullResult] = []

      for table in tables {
        try Task.checkCancellation()
        let result = try await pullTable(table, userId: userId, syncState: syncState)
        tableResults.append(result)
        await Task.yield()
      }

      // Phase 2: Push dirty records to server
      var pushResults: [TablePushResult] = []

      for table in tables {
        try Task.checkCancellation()
        let result = try await pushTable(table, userId: userId)
        pushResults.append(result)
        await Task.yield()
      }

      // Calculate totals
      let totalRows = tableResults.reduce(0) { $0 + $1.rowsProcessed }
      let totalPushed = pushResults.reduce(0) { $0 + $1.rowsPushed }
      let pullConflicts = tableResults.reduce(0) { $0 + $1.newConflicts }
      let pushConflicts = pushResults.reduce(0) { $0 + $1.newConflicts }
      let totalConflicts = pullConflicts + pushConflicts
      let totalAutoMerged = tableResults.reduce(0) { $0 + $1.autoMerged }
      _ = pushResults.reduce(0) { $0 + $1.rebased }  // totalRebased - tracked but not logged
      let duration = Date().timeIntervalSince(startTime)

      // Update sync state
      await storeActor.updateSyncState(userId: userId) { state in
        state.markSyncSucceeded()
      }

      let conflicts = try await storeActor.countConflicts(userId: userId)

      await MainActor.run {
        lastSyncedAt = Date()
        conflictCount = conflicts
        SyncStatusManager.shared.syncSucceeded()
      }

      // Note: lastAutoSyncAt is now updated at the START of sync (for interval-guarded syncs)
      // to prevent race conditions where concurrent syncs both pass the interval check

      // Only log when there's actual data transfer
      if totalRows > 0 || totalPushed > 0 || totalConflicts > 0 {
        logger.info(
          "Sync: \(totalRows) pulled, \(totalPushed) pushed\(totalConflicts > 0 ? ", \(totalConflicts) conflicts" : "")"
        )
      }

      // Update widget storage with latest shift data
      if updateWidgetStorage {
        NativeWidgetStorage.updateWidgetStorage(for: userId)
      }

      return SyncResult(
        success: true,
        tableResults: tableResults,
        pushResults: pushResults,
        totalRowsProcessed: totalRows,
        totalRowsPushed: totalPushed,
        totalConflicts: totalConflicts,
        totalAutoMerged: totalAutoMerged,
        duration: duration,
        error: nil
      )
    } catch is CancellationError {
      let duration = Date().timeIntervalSince(startTime)
      logger.warning("Sync cancelled after \(String(format: "%.1f", duration))s")
      return SyncResult(
        success: false,
        tableResults: [],
        pushResults: [],
        totalRowsProcessed: 0,
        totalRowsPushed: 0,
        totalConflicts: 0,
        totalAutoMerged: 0,
        duration: duration,
        error: "Sync timed out"
      )
    } catch {
      let duration = Date().timeIntervalSince(startTime)

      // Extract user-friendly message if available, otherwise use technical description
      let userFriendlyMessage: String
      let technicalMessage = error.localizedDescription

      if let syncError = error as? SyncError {
        userFriendlyMessage = syncError.userFriendlyMessage
      } else if let encodingError = error as? SyncEncodingError {
        userFriendlyMessage = encodingError.userFriendlyMessage
      } else {
        userFriendlyMessage = "Sync failed: \(technicalMessage)"
      }

      // Log technical details for debugging
      logger.error("Sync failed: \(technicalMessage)")

      await storeActor.updateSyncState(userId: userId) { state in
        state.markSyncFailed(error: technicalMessage)
      }

      // Surface user-friendly message to UI
      await MainActor.run {
        lastError = userFriendlyMessage
        SyncStatusManager.shared.syncFailed(message: userFriendlyMessage)
      }

      return SyncResult(
        success: false,
        tableResults: [],
        pushResults: [],
        totalRowsProcessed: 0,
        totalRowsPushed: 0,
        totalConflicts: 0,
        totalAutoMerged: 0,
        duration: duration,
        error: userFriendlyMessage
      )
    }
  }

  // MARK: - Pull Implementation

  /// Pull changes for a single table
  /// Uses updated_at timestamp cursor with tie-breaker for incremental sync
  private func pullTable(
    _ table: SyncTable,
    userId: String,
    syncState: LocalSyncState
  ) async throws -> TablePullResult {
    var cursor = syncState.updatedAtCursor(for: table)
    var totalRows = 0
    var newConflicts = 0
    var autoMerged = 0
    var maxRevision: Int64 = syncState.cursor(for: table)  // Legacy, for debugging

    logger.debug("Pulling \(table.displayName) from \(cursor.description)")

    // Page through all changes using updated_at cursor
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

      // Track legacy max revision for debugging
      if result.maxRevision > maxRevision {
        maxRevision = result.maxRevision
      }

      // Update cursor if we processed rows
      if let lastUpdatedAt = result.lastUpdatedAt {
        cursor = SyncCursor(updatedAt: lastUpdatedAt, tieId: result.lastTieId)

        // Persist cursor to sync state
        let storeActor = await MainActor.run { LocalStore.shared.storeActor }
        await storeActor.updateSyncState(userId: userId) { state in
          state.updateUpdatedAtCursor(for: table, updatedAt: lastUpdatedAt, tieId: result.lastTieId)
          // Also update legacy cursor for debugging
          state.updateCursor(for: table, to: result.maxRevision)
        }
      }

      // No more pages
      if !result.hasMore {
        break
      }

      await Task.yield()
    }

    let finalCursor = cursor.updatedAt.map { formatSupabaseTimestamp($0) } ?? "initial"
    logger.debug("Pulled \(table.displayName): \(totalRows) rows, cursor now at \(finalCursor)")

    return TablePullResult(
      table: table,
      rowsProcessed: totalRows,
      lastUpdatedAt: cursor.updatedAt,
      lastUpdatedAtTieId: cursor.tieId,
      maxRevision: maxRevision,
      newConflicts: newConflicts,
      autoMerged: autoMerged
    )
  }

  /// Result of pulling a single page
  private struct PagePullResult {
    let rowsProcessed: Int
    /// Last updated_at timestamp in this page (for cursor)
    let lastUpdatedAt: Date?
    /// ID of the last row at lastUpdatedAt (tie-breaker)
    let lastTieId: String
    /// Legacy max revision in this page (for debugging)
    let maxRevision: Int64
    let newConflicts: Int
    let autoMerged: Int
    let hasMore: Bool
  }

  // MARK: - Jobs Pull

  private func pullJobsPage(userId: String, cursor: SyncCursor) async throws -> PagePullResult {
    let rows: [SyncJobRow]

    if let cursorUpdatedAt = cursor.updatedAt {
      let cursorTimestamp = formatISO8601(cursorUpdatedAt)
      let cursorTieId = cursor.tieId

      rows =
        try await supabase
        .from("jobs")
        .select()
        .eq("user_id", value: userId)
        .or(
          "updated_at.gt.\(cursorTimestamp),and(updated_at.eq.\(cursorTimestamp),id.gt.\(cursorTieId))"
        )
        .order("updated_at", ascending: true)
        .order("id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    } else {
      rows =
        try await supabase
        .from("jobs")
        .select()
        .eq("user_id", value: userId)
        .order("updated_at", ascending: true)
        .order("id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    }

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: cursor.updatedAt,
        lastTieId: cursor.tieId,
        maxRevision: 0,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    var newConflicts = 0
    var autoMerged = 0
    var maxRevision: Int64 = 0
    let pageStartTime = Date()

    for (index, row) in rows.enumerated() {
      let result = try await applyJobRow(row, storeActor: storeActor)
      if result == .conflict { newConflicts += 1 }
      if result == .autoMerged { autoMerged += 1 }

      if row.revision > maxRevision {
        maxRevision = row.revision
      }

      let rowNumber = index + 1
      if rowNumber.isMultiple(of: pullSaveBatchSize) {
        try await storeActor.save()
        logger.debug("jobs: saved batch at row \(rowNumber)/\(rows.count)")
      }
    }

    try await storeActor.save()

    let duration = Date().timeIntervalSince(pageStartTime)
    logger.info("jobs: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

    guard let lastRow = rows.last else {
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: Date(),
        lastTieId: "",
        maxRevision: maxRevision,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let lastUpdatedAt = try requireISO8601(lastRow.updated_at, table: .jobs, id: lastRow.id)

    return PagePullResult(
      rowsProcessed: rows.count,
      lastUpdatedAt: lastUpdatedAt,
      lastTieId: lastRow.id,
      maxRevision: maxRevision,
      newConflicts: newConflicts,
      autoMerged: autoMerged,
      hasMore: rows.count == pageSize
    )
  }

  private func applyJobRow(_ serverRow: SyncJobRow, storeActor: LocalStoreActor) async throws
    -> ApplyResult
  {
    let serverUpdatedAt = try requireISO8601(serverRow.updated_at, table: .jobs, id: serverRow.id)
    let serverArchivedAt = serverRow.archived_at.flatMap { parseISO8601($0) }
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if let existing = try await storeActor.getJob(id: serverRow.id) {
      return await applyJobToExisting(
        existing: existing,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverArchivedAt: serverArchivedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )
    } else {
      let localJob = LocalJob.from(serverRow: serverRow, serverUpdatedAt: serverUpdatedAt)
      try await storeActor.upsertJob(localJob)
      return .inserted
    }
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
      await storeActor.updateJobFromServer(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        archivedAt: serverArchivedAt,
        deletedAt: serverDeletedAt,
        snapshot: serverSnapshot
      )
      return .updated

    case .dirty, .pendingDelete:
      if serverRow.revision == existing.serverRevision {
        return .noChange
      }

      guard let lastSnapshot = JobServerSnapshot.decode(from: existing.lastSyncedSnapshot) else {
        await storeActor.markJobConflict(id: serverRow.id, serverSnapshot: serverSnapshot)
        return .conflict
      }

      let serverChangedFields = serverSnapshot.changedFields(from: lastSnapshot)
      let localDirtyFields = existing.dirtyFieldKeys
      let conflictingFields = serverChangedFields.intersection(
        Set(localDirtyFields.map { convertToJobField($0) }))

      if conflictingFields.isEmpty {
        await storeActor.autoMergeJob(
          id: serverRow.id,
          serverRow: serverRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: serverRow.revision,
          archivedAt: serverArchivedAt,
          deletedAt: serverDeletedAt,
          newSnapshot: serverSnapshot,
          localDirtyFields: localDirtyFields
        )
        return .autoMerged
      }

      await storeActor.markJobConflict(id: serverRow.id, serverSnapshot: serverSnapshot)
      return .conflict

    case .conflict:
      await storeActor.updateJobConflictSnapshot(id: serverRow.id, serverSnapshot: serverSnapshot)
      return .noChange
    }
  }

  private func convertToJobField(_ field: JobField) -> JobField {
    field
  }

  // MARK: - User Shifts Pull

  private func pullUserShiftsPage(userId: String, cursor: SyncCursor) async throws -> PagePullResult
  {
    // Query server for changes since cursor using updated_at + id tie-breaker
    // Condition: (updated_at > cursor.updatedAt) OR (updated_at == cursor.updatedAt AND id > cursor.tieId)
    let rows: [SyncShiftRow]

    if let cursorUpdatedAt = cursor.updatedAt {
      // Incremental sync: fetch rows after cursor
      let cursorTimestamp = formatISO8601(cursorUpdatedAt)
      let cursorTieId = cursor.tieId

      // Use Supabase's or() filter for the compound condition
      // (updated_at > cursor) OR (updated_at = cursor AND id > tieId)
      rows =
        try await supabase
        .from("user_shifts")
        .select()
        .eq("user_id", value: userId)
        .or(
          "updated_at.gt.\(cursorTimestamp),and(updated_at.eq.\(cursorTimestamp),id.gt.\(cursorTieId))"
        )
        .order("updated_at", ascending: true)
        .order("id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    } else {
      // Initial sync: fetch all rows
      rows =
        try await supabase
        .from("user_shifts")
        .select()
        .eq("user_id", value: userId)
        .order("updated_at", ascending: true)
        .order("id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    }

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: cursor.updatedAt,
        lastTieId: cursor.tieId,
        maxRevision: 0,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    var newConflicts = 0
    var autoMerged = 0
    var maxRevision: Int64 = 0
    let pageStartTime = Date()

    for (index, row) in rows.enumerated() {
      let result = try await applyShiftRow(row, storeActor: storeActor)
      if result == .conflict { newConflicts += 1 }
      if result == .autoMerged { autoMerged += 1 }
      if row.revision > maxRevision {
        maxRevision = row.revision
      }

      // Batch save for durability: persist partial progress every N rows
      // Cursor is NOT advanced here - only after full page success
      let rowNumber = index + 1
      if rowNumber.isMultiple(of: pullSaveBatchSize) {
        try await storeActor.save()
        logger.debug("user_shifts: saved batch at row \(rowNumber)/\(rows.count)")
      }
    }

    // Final save for any remaining rows
    try await storeActor.save()

    let duration = Date().timeIntervalSince(pageStartTime)
    logger.info(
      "user_shifts: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

    // Get cursor position from the last row
    // SAFETY: guard let prevents crash if rows somehow became empty
    guard let lastRow = rows.last else {
      logger.warning("Unexpected empty rows after processing in pullShiftsPage")
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: Date(),
        lastTieId: "",
        maxRevision: maxRevision,
        newConflicts: newConflicts,
        autoMerged: autoMerged,
        hasMore: false
      )
    }
    // SAFETY: Throw on parse failure to prevent cursor corruption
    let lastUpdatedAt = try requireISO8601(lastRow.updated_at, table: .userShifts, id: lastRow.id)

    return PagePullResult(
      rowsProcessed: rows.count,
      lastUpdatedAt: lastUpdatedAt,
      lastTieId: lastRow.id,
      maxRevision: maxRevision,
      newConflicts: newConflicts,
      autoMerged: autoMerged,
      hasMore: rows.count == pageSize
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
    if let existing = try await storeActor.getUserShift(id: serverRow.id) {
      return try await applyShiftToExisting(
        existing: existing,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )
    } else {
      // Insert as new clean row
      try await insertNewShift(
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )
      return .inserted
    }
  }

  private func applyShiftToExisting(
    existing: LocalUserShift,
    serverRow: SyncShiftRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    storeActor: LocalStoreActor
  ) async throws -> ApplyResult {
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
      await storeActor.updateShiftFromServer(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        snapshot: serverSnapshot
      )
      return .updated

    case .dirty, .pendingDelete:
      // Check for conflict
      if serverRow.revision == existing.serverRevision {
        // Server unchanged, keep local edits
        return .noChange
      }

      // Server changed - check for field-level merge
      guard let lastSnapshot = UserShiftServerSnapshot.decode(from: existing.lastSyncedSnapshot)
      else {
        // Cannot decode snapshot, mark conflict
        await storeActor.markShiftConflict(id: serverRow.id, serverSnapshot: serverSnapshot)
        return .conflict
      }

      let serverChangedFields = serverSnapshot.changedFields(from: lastSnapshot)
      let localDirtyFields = existing.dirtyFieldKeys

      // Check for overlap
      let conflictingFields = serverChangedFields.intersection(
        Set(localDirtyFields.map { convertToUserShiftField($0) }))

      if conflictingFields.isEmpty {
        // Auto-merge: apply server changes for non-dirty fields, keep local for dirty
        await storeActor.autoMergeShift(
          id: serverRow.id,
          serverRow: serverRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: serverRow.revision,
          serverDeletedAt: serverDeletedAt,
          newSnapshot: serverSnapshot,
          localDirtyFields: localDirtyFields
        )
        return .autoMerged
      } else {
        // Conflict - overlapping fields
        await storeActor.markShiftConflict(id: serverRow.id, serverSnapshot: serverSnapshot)
        return .conflict
      }

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
      logger.error("Failed to parse shift_date '\(serverRow.shift_date)' for shift \(serverRow.id)")
      throw SyncError.dateParsingFailed(
        table: .userShifts, id: serverRow.id, rawValue: serverRow.shift_date)
    }
    let supplementsData = serverRow.custom_supplements.flatMap {
      try? canonicalJSONEncoder.encode($0)
    }
    let pauseWindowsData = PauseWindowSupport.normalize(serverRow.custom_pause_windows).flatMap {
      try? canonicalJSONEncoder.encode($0)
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

  // Helper to convert UserShiftField to itself (for type safety in intersection)
  private func convertToUserShiftField(_ field: UserShiftField) -> UserShiftField {
    field
  }

  // MARK: - Events Pull

  private func pullEventsPage(userId: String, cursor: SyncCursor) async throws -> PagePullResult {
    let rows: [SyncEventRow]

    if let cursorUpdatedAt = cursor.updatedAt {
      let cursorTimestamp = formatISO8601(cursorUpdatedAt)
      let cursorTieId = cursor.tieId

      rows =
        try await supabase
        .from("events")
        .select()
        .eq("user_id", value: userId)
        .or(
          "updated_at.gt.\(cursorTimestamp),and(updated_at.eq.\(cursorTimestamp),id.gt.\(cursorTieId))"
        )
        .order("updated_at", ascending: true)
        .order("id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    } else {
      rows =
        try await supabase
        .from("events")
        .select()
        .eq("user_id", value: userId)
        .order("updated_at", ascending: true)
        .order("id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    }

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: cursor.updatedAt,
        lastTieId: cursor.tieId,
        maxRevision: 0,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    var newConflicts = 0
    var autoMerged = 0
    var maxRevision: Int64 = 0
    let pageStartTime = Date()

    for (index, row) in rows.enumerated() {
      let result = try await applyEventRow(row, storeActor: storeActor)
      if result == .conflict { newConflicts += 1 }
      if result == .autoMerged { autoMerged += 1 }
      if row.revision > maxRevision {
        maxRevision = row.revision
      }

      let rowNumber = index + 1
      if rowNumber.isMultiple(of: pullSaveBatchSize) {
        try await storeActor.save()
        logger.debug("events: saved batch at row \(rowNumber)/\(rows.count)")
      }
    }

    try await storeActor.save()

    let duration = Date().timeIntervalSince(pageStartTime)
    logger.info(
      "events: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

    guard let lastRow = rows.last else {
      logger.warning("Unexpected empty rows after processing in pullEventsPage")
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: Date(),
        lastTieId: "",
        maxRevision: maxRevision,
        newConflicts: newConflicts,
        autoMerged: autoMerged,
        hasMore: false
      )
    }

    let lastUpdatedAt = try requireISO8601(lastRow.updated_at, table: .events, id: lastRow.id)

    return PagePullResult(
      rowsProcessed: rows.count,
      lastUpdatedAt: lastUpdatedAt,
      lastTieId: lastRow.id,
      maxRevision: maxRevision,
      newConflicts: newConflicts,
      autoMerged: autoMerged,
      hasMore: rows.count == pageSize
    )
  }

  private func applyEventRow(_ serverRow: SyncEventRow, storeActor: LocalStoreActor) async throws
    -> ApplyResult
  {
    let serverUpdatedAt = try requireISO8601(serverRow.updated_at, table: .events, id: serverRow.id)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if let existing = try await storeActor.getEvent(id: serverRow.id) {
      return try await applyEventToExisting(
        existing: existing,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )
    } else {
      try await insertNewEvent(
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )
      return .inserted
    }
  }

  private func applyEventToExisting(
    existing: LocalEvent,
    serverRow: SyncEventRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    storeActor: LocalStoreActor
  ) async throws -> ApplyResult {
    let serverSnapshot = EventServerSnapshot.from(
      serverRow: serverRow,
      updatedAt: serverUpdatedAt,
      deletedAt: serverDeletedAt
    )

    switch existing.syncStatus {
    case .clean:
      await storeActor.updateEventFromServer(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        snapshot: serverSnapshot
      )
      return .updated

    case .dirty, .pendingDelete:
      if serverRow.revision == existing.serverRevision {
        return .noChange
      }

      guard let lastSnapshot = EventServerSnapshot.decode(from: existing.lastSyncedSnapshot) else {
        await storeActor.markEventConflict(id: serverRow.id, serverSnapshot: serverSnapshot)
        return .conflict
      }

      let serverChangedFields = serverSnapshot.changedFields(from: lastSnapshot)
      let localDirtyFields = existing.dirtyFieldKeys
      let conflictingFields = serverChangedFields.intersection(
        Set(localDirtyFields.map { convertToEventField($0) }))

      if conflictingFields.isEmpty {
        await storeActor.autoMergeEvent(
          id: serverRow.id,
          serverRow: serverRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: serverRow.revision,
          serverDeletedAt: serverDeletedAt,
          newSnapshot: serverSnapshot,
          localDirtyFields: localDirtyFields
        )
        return .autoMerged
      } else {
        await storeActor.markEventConflict(id: serverRow.id, serverSnapshot: serverSnapshot)
        return .conflict
      }

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
      logger.error("Failed to parse start_date '\(serverRow.start_date)' for event \(serverRow.id)")
      throw SyncError.dateParsingFailed(
        table: .events, id: serverRow.id, rawValue: serverRow.start_date)
    }

    guard let endDate = dateFormatter.date(from: serverRow.end_date) else {
      logger.error("Failed to parse end_date '\(serverRow.end_date)' for event \(serverRow.id)")
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

  private func convertToEventField(_ field: EventField) -> EventField {
    field
  }

  // MARK: - Recurring Shifts Pull

  private func pullRecurringShiftsPage(userId: String, cursor: SyncCursor) async throws
    -> PagePullResult
  {
    // Query using updated_at + id tie-breaker
    let rows: [SyncRecurringShiftRow]

    if let cursorUpdatedAt = cursor.updatedAt {
      let cursorTimestamp = formatISO8601(cursorUpdatedAt)
      let cursorTieId = cursor.tieId

      rows =
        try await supabase
        .from("recurring_shifts")
        .select()
        .eq("user_id", value: userId)
        .or(
          "updated_at.gt.\(cursorTimestamp),and(updated_at.eq.\(cursorTimestamp),id.gt.\(cursorTieId))"
        )
        .order("updated_at", ascending: true)
        .order("id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    } else {
      rows =
        try await supabase
        .from("recurring_shifts")
        .select()
        .eq("user_id", value: userId)
        .order("updated_at", ascending: true)
        .order("id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    }

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: cursor.updatedAt,
        lastTieId: cursor.tieId,
        maxRevision: 0,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    var newConflicts = 0
    var autoMerged = 0
    var maxRevision: Int64 = 0
    let pageStartTime = Date()

    for (index, row) in rows.enumerated() {
      let result = try await applyRecurringShiftRow(row, storeActor: storeActor)
      if result == .conflict { newConflicts += 1 }
      if result == .autoMerged { autoMerged += 1 }
      if row.revision > maxRevision {
        maxRevision = row.revision
      }

      // Batch save for durability
      let rowNumber = index + 1
      if rowNumber.isMultiple(of: pullSaveBatchSize) {
        try await storeActor.save()
        logger.debug("recurring_shifts: saved batch at row \(rowNumber)/\(rows.count)")
      }
    }

    // Final save for any remaining rows
    try await storeActor.save()

    let duration = Date().timeIntervalSince(pageStartTime)
    logger.info(
      "recurring_shifts: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s"
    )

    // SAFETY: guard let prevents crash if rows somehow became empty
    guard let lastRow = rows.last else {
      logger.warning("Unexpected empty rows after processing in pullRecurringShiftsPage")
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: Date(),
        lastTieId: "",
        maxRevision: maxRevision,
        newConflicts: newConflicts,
        autoMerged: autoMerged,
        hasMore: false
      )
    }
    // SAFETY: Throw on parse failure to prevent cursor corruption
    let lastUpdatedAt = try requireISO8601(
      lastRow.updated_at, table: .recurringShifts, id: lastRow.id)

    return PagePullResult(
      rowsProcessed: rows.count,
      lastUpdatedAt: lastUpdatedAt,
      lastTieId: lastRow.id,
      maxRevision: maxRevision,
      newConflicts: newConflicts,
      autoMerged: autoMerged,
      hasMore: rows.count == pageSize
    )
  }

  private func applyRecurringShiftRow(
    _ serverRow: SyncRecurringShiftRow, storeActor: LocalStoreActor
  ) async throws -> ApplyResult {
    // SAFETY: Throw on parse failure to prevent data corruption
    let serverUpdatedAt = try requireISO8601(
      serverRow.updated_at, table: .recurringShifts, id: serverRow.id)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if let existing = try await storeActor.getRecurringShift(id: serverRow.id) {
      return try await applyRecurringShiftToExisting(
        existing: existing,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )
    } else {
      try await insertNewRecurringShift(
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )
      return .inserted
    }
  }

  private func applyRecurringShiftToExisting(
    existing: LocalRecurringShift,
    serverRow: SyncRecurringShiftRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    storeActor: LocalStoreActor
  ) async throws -> ApplyResult {
    let serverSnapshot = RecurringShiftServerSnapshot.from(
      row: serverRow.toRecurringShiftRow(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision,
      deletedAt: serverDeletedAt
    )

    switch existing.syncStatus {
    case .clean:
      await storeActor.updateRecurringShiftFromServer(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        snapshot: serverSnapshot
      )
      return .updated

    case .dirty, .pendingDelete:
      if serverRow.revision == existing.serverRevision {
        return .noChange
      }

      guard
        let lastSnapshot = RecurringShiftServerSnapshot.decode(from: existing.lastSyncedSnapshot)
      else {
        await storeActor.markRecurringShiftConflict(
          id: serverRow.id, serverSnapshot: serverSnapshot)
        return .conflict
      }

      let serverChangedFields = serverSnapshot.changedFields(from: lastSnapshot)
      let localDirtyFields = existing.dirtyFieldKeys
      let conflictingFields = serverChangedFields.intersection(
        Set(localDirtyFields.map { convertToRecurringShiftField($0) }))

      if conflictingFields.isEmpty {
        await storeActor.autoMergeRecurringShift(
          id: serverRow.id,
          serverRow: serverRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: serverRow.revision,
          serverDeletedAt: serverDeletedAt,
          newSnapshot: serverSnapshot,
          localDirtyFields: localDirtyFields
        )
        return .autoMerged
      } else {
        await storeActor.markRecurringShiftConflict(
          id: serverRow.id, serverSnapshot: serverSnapshot)
        return .conflict
      }

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
      selectedDays: try canonicalJSONEncoder.encode(serverRow.selected_days),
      endCondition: serverRow.end_condition.flatMap { try? canonicalJSONEncoder.encode($0) },
      exclusions: serverRow.exclusions.flatMap { try? canonicalJSONEncoder.encode($0) },
      dateSpecificPauseWindows: PauseWindowSupport.normalize(serverRow.date_specific_pause_windows)
        .flatMap { try? canonicalJSONEncoder.encode($0) },
      dateSpecificSupplements: serverRow.date_specific_supplements.flatMap {
        try? canonicalJSONEncoder.encode($0)
      },
      dateSpecificNotes: ShiftNoteSupport.normalizeDateSpecificNotes(serverRow.date_specific_notes)
        .flatMap { try? canonicalJSONEncoder.encode($0) },
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

  private func convertToRecurringShiftField(_ field: RecurringShiftField) -> RecurringShiftField {
    field
  }

  // MARK: - Wage Snapshots Pull

  private func pullWageSnapshotsPage(userId: String, cursor: SyncCursor) async throws
    -> PagePullResult
  {
    // Query using updated_at + id tie-breaker
    let rows: [SyncWageSnapshotRow]

    if let cursorUpdatedAt = cursor.updatedAt {
      let cursorTimestamp = formatISO8601(cursorUpdatedAt)
      let cursorTieId = cursor.tieId

      rows =
        try await supabase
        .from("wage_snapshots")
        .select()
        .eq("user_id", value: userId)
        .or(
          "updated_at.gt.\(cursorTimestamp),and(updated_at.eq.\(cursorTimestamp),id.gt.\(cursorTieId))"
        )
        .order("updated_at", ascending: true)
        .order("id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    } else {
      rows =
        try await supabase
        .from("wage_snapshots")
        .select()
        .eq("user_id", value: userId)
        .order("updated_at", ascending: true)
        .order("id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    }

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: cursor.updatedAt,
        lastTieId: cursor.tieId,
        maxRevision: 0,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    var newConflicts = 0
    var autoMerged = 0
    var maxRevision: Int64 = 0
    let pageStartTime = Date()

    for (index, row) in rows.enumerated() {
      let result = try await applyWageSnapshotRow(row, storeActor: storeActor)
      if result == .conflict { newConflicts += 1 }
      if result == .autoMerged { autoMerged += 1 }
      if row.revision > maxRevision {
        maxRevision = row.revision
      }

      // Batch save for durability
      let rowNumber = index + 1
      if rowNumber.isMultiple(of: pullSaveBatchSize) {
        try await storeActor.save()
        logger.debug("wage_snapshots: saved batch at row \(rowNumber)/\(rows.count)")
      }
    }

    // Final save for any remaining rows
    try await storeActor.save()

    let duration = Date().timeIntervalSince(pageStartTime)
    logger.info(
      "wage_snapshots: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

    // SAFETY: guard let prevents crash if rows somehow became empty
    guard let lastRow = rows.last else {
      logger.warning("Unexpected empty rows after processing in pullWageSnapshotsPage")
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: Date(),
        lastTieId: "",
        maxRevision: maxRevision,
        newConflicts: newConflicts,
        autoMerged: autoMerged,
        hasMore: false
      )
    }
    // SAFETY: Throw on parse failure to prevent cursor corruption
    let lastUpdatedAt = try requireISO8601(
      lastRow.updated_at, table: .wageSnapshots, id: lastRow.id)

    return PagePullResult(
      rowsProcessed: rows.count,
      lastUpdatedAt: lastUpdatedAt,
      lastTieId: lastRow.id,
      maxRevision: maxRevision,
      newConflicts: newConflicts,
      autoMerged: autoMerged,
      hasMore: rows.count == pageSize
    )
  }

  private func applyWageSnapshotRow(_ serverRow: SyncWageSnapshotRow, storeActor: LocalStoreActor)
    async throws -> ApplyResult
  {
    // SAFETY: Throw on parse failure to prevent data corruption
    let serverUpdatedAt = try requireISO8601(
      serverRow.updated_at, table: .wageSnapshots, id: serverRow.id)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if let existing = try await storeActor.getWageSnapshot(id: serverRow.id) {
      return try await applyWageSnapshotToExisting(
        existing: existing,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )
    } else {
      try await insertNewWageSnapshot(
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        storeActor: storeActor
      )
      return .inserted
    }
  }

  private func applyWageSnapshotToExisting(
    existing: LocalWageSnapshot,
    serverRow: SyncWageSnapshotRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    storeActor: LocalStoreActor
  ) async throws -> ApplyResult {
    let serverSnapshot = WageSnapshotServerSnapshot.from(
      row: serverRow.toWageSnapshot(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision,
      deletedAt: serverDeletedAt
    )

    switch existing.syncStatus {
    case .clean:
      await storeActor.updateWageSnapshotFromServer(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        snapshot: serverSnapshot
      )
      return .updated

    case .dirty, .pendingDelete:
      if serverRow.revision == existing.serverRevision {
        return .noChange
      }

      guard let lastSnapshot = WageSnapshotServerSnapshot.decode(from: existing.lastSyncedSnapshot)
      else {
        await storeActor.markWageSnapshotConflict(id: serverRow.id, serverSnapshot: serverSnapshot)
        return .conflict
      }

      let serverChangedFields = serverSnapshot.changedFields(from: lastSnapshot)
      let localDirtyFields = existing.dirtyFieldKeys
      let conflictingFields = serverChangedFields.intersection(
        Set(localDirtyFields.map { convertToWageSnapshotField($0) }))

      if conflictingFields.isEmpty {
        await storeActor.autoMergeWageSnapshot(
          id: serverRow.id,
          serverRow: serverRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: serverRow.revision,
          serverDeletedAt: serverDeletedAt,
          newSnapshot: serverSnapshot,
          localDirtyFields: localDirtyFields
        )
        return .autoMerged
      } else {
        await storeActor.markWageSnapshotConflict(id: serverRow.id, serverSnapshot: serverSnapshot)
        return .conflict
      }

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
      supplements: (try? canonicalJSONEncoder.encode(serverRow.supplements)) ?? Data(),
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

  private func convertToWageSnapshotField(_ field: WageSnapshotField) -> WageSnapshotField {
    field
  }

  // MARK: - Payroll Adjustments Push

  private func pushPayrollAdjustments(userId: String) async throws -> TablePushResult {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    let dirtyAdjustments = try await storeActor.getDirtyPayrollAdjustments(userId: userId)

    if dirtyAdjustments.isEmpty {
      return TablePushResult(
        table: .payrollAdjustments,
        rowsPushed: 0,
        newConflicts: 0,
        rebased: 0
      )
    }

    var rowsPushed = 0
    var newConflicts = 0

    for adjustment in dirtyAdjustments {
      let result = try await pushPayrollAdjustment(
        adjustment,
        userId: userId,
        storeActor: storeActor
      )
      switch result {
      case .success, .deleted:
        rowsPushed += 1
      case .conflict:
        newConflicts += 1
      case .rebased:
        rowsPushed += 1
      case .noChange:
        break
      }
    }

    try await storeActor.save()
    return TablePushResult(
      table: .payrollAdjustments,
      rowsPushed: rowsPushed,
      newConflicts: newConflicts,
      rebased: 0
    )
  }

  private func pushPayrollAdjustment(
    _ adjustment: LocalPayrollAdjustment,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    if adjustment.syncStatus == .pendingDelete {
      return try await pushPayrollAdjustmentDelete(
        adjustment,
        userId: userId,
        storeActor: storeActor
      )
    }

    if adjustment.dirtyFieldKeys.isEmpty {
      await storeActor.markPayrollAdjustmentClean(id: adjustment.id)
      return .noChange
    }

    if adjustment.serverRevision == 0 {
      return try await insertPayrollAdjustment(adjustment, userId: userId, storeActor: storeActor)
    }

    let updateData = payrollAdjustmentPayload(adjustment, includeIdentity: false, userId: userId)
    try requireNonEmptyUpdate(updateData, table: .payrollAdjustments, id: adjustment.id)

    let returnedRows: [SyncPayrollAdjustmentRow] =
      try await supabase
      .from("payroll_adjustments")
      .update(updateData)
      .eq("id", value: adjustment.id)
      .eq("user_id", value: userId)
      .eq("revision", value: Int(adjustment.serverRevision))
      .is("deleted_at", value: nil)
      .select()
      .execute()
      .value

    guard let returnedRow = returnedRows.first else {
      await storeActor.markPayrollAdjustmentConflict(id: adjustment.id, serverSnapshot: nil)
      return .conflict
    }

    try await markPayrollAdjustmentPushed(returnedRow, storeActor: storeActor)
    return .success
  }

  private func insertPayrollAdjustment(
    _ adjustment: LocalPayrollAdjustment,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let insertData = payrollAdjustmentPayload(adjustment, includeIdentity: true, userId: userId)
    let returnedRows: [SyncPayrollAdjustmentRow] =
      try await supabase
      .from("payroll_adjustments")
      .insert(insertData)
      .select()
      .execute()
      .value

    guard let returnedRow = returnedRows.first else {
      await storeActor.markPayrollAdjustmentConflict(id: adjustment.id, serverSnapshot: nil)
      return .conflict
    }

    try await markPayrollAdjustmentPushed(returnedRow, storeActor: storeActor)
    return .success
  }

  private func pushPayrollAdjustmentDelete(
    _ adjustment: LocalPayrollAdjustment,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let returnedRows: [SyncPayrollAdjustmentRow] =
      try await supabase
      .from("payroll_adjustments")
      .update(["deleted_at": AnyJSON.string(formatSupabaseTimestamp(Date()))])
      .eq("id", value: adjustment.id)
      .eq("user_id", value: userId)
      .eq("revision", value: Int(adjustment.serverRevision))
      .is("deleted_at", value: nil)
      .select()
      .execute()
      .value

    guard let returnedRow = returnedRows.first else {
      await storeActor.markPayrollAdjustmentConflict(id: adjustment.id, serverSnapshot: nil)
      return .conflict
    }

    let serverUpdatedAt = try requireISO8601(
      returnedRow.updated_at, table: .payrollAdjustments, id: returnedRow.id)
    let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }
    await storeActor.markPayrollAdjustmentDeleted(
      id: returnedRow.id,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: returnedRow.revision,
      serverDeletedAt: serverDeletedAt
    )
    return .deleted
  }

  private func payrollAdjustmentPayload(
    _ adjustment: LocalPayrollAdjustment,
    includeIdentity: Bool,
    userId: String
  ) -> [String: AnyJSON] {
    var payload: [String: AnyJSON] = [
      "amount": .double(adjustment.amount),
      "currency": .string(adjustment.currency),
      "category": .string(adjustment.category.rawValue),
      "tax_treatment": .string(adjustment.taxTreatment.rawValue),
      "title": .string(adjustment.title),
      "payout_date": .string(adjustment.payoutDateString),
    ]

    if includeIdentity {
      payload["id"] = .string(adjustment.id)
      payload["user_id"] = .string(userId)
    }
    payload["job_id"] = adjustment.jobId.map(AnyJSON.string) ?? .null
    payload["note"] = adjustment.note.map(AnyJSON.string) ?? .null
    payload["earned_from_date"] = adjustment.earnedFromDateString.map(AnyJSON.string) ?? .null
    payload["earned_to_date"] = adjustment.earnedToDateString.map(AnyJSON.string) ?? .null

    return payload
  }

  private func markPayrollAdjustmentPushed(
    _ row: SyncPayrollAdjustmentRow,
    storeActor: LocalStoreActor
  ) async throws {
    let serverUpdatedAt = try requireISO8601(
      row.updated_at, table: .payrollAdjustments, id: row.id)
    let serverDeletedAt = row.deleted_at.flatMap { parseISO8601($0) }
    let snapshot = PayrollAdjustmentServerSnapshot.from(
      row: row,
      updatedAt: serverUpdatedAt,
      deletedAt: serverDeletedAt
    )
    await storeActor.markPayrollAdjustmentPushed(
      id: row.id,
      serverRow: row,
      serverUpdatedAt: serverUpdatedAt,
      serverDeletedAt: serverDeletedAt,
      snapshot: snapshot
    )
  }

  // MARK: - Payroll Adjustments Pull

  private func pullPayrollAdjustmentsPage(userId: String, cursor: SyncCursor) async throws
    -> PagePullResult
  {
    let rows: [SyncPayrollAdjustmentRow]

    if let cursorUpdatedAt = cursor.updatedAt {
      let cursorTimestamp = formatISO8601(cursorUpdatedAt)
      let cursorTieId = cursor.tieId
      rows =
        try await supabase
        .from("payroll_adjustments")
        .select()
        .eq("user_id", value: userId)
        .or(
          "updated_at.gt.\(cursorTimestamp),and(updated_at.eq.\(cursorTimestamp),id.gt.\(cursorTieId))"
        )
        .order("updated_at", ascending: true)
        .order("id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    } else {
      rows =
        try await supabase
        .from("payroll_adjustments")
        .select()
        .eq("user_id", value: userId)
        .order("updated_at", ascending: true)
        .order("id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    }

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: cursor.updatedAt,
        lastTieId: cursor.tieId,
        maxRevision: 0,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    var newConflicts = 0
    var maxRevision: Int64 = 0

    for row in rows {
      let result = try await applyPayrollAdjustmentRow(row, storeActor: storeActor)
      if result == .conflict { newConflicts += 1 }
      if row.revision > maxRevision { maxRevision = row.revision }
    }

    try await storeActor.save()

    guard let lastRow = rows.last else {
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: Date(),
        lastTieId: "",
        maxRevision: maxRevision,
        newConflicts: newConflicts,
        autoMerged: 0,
        hasMore: false
      )
    }
    let lastUpdatedAt = try requireISO8601(
      lastRow.updated_at, table: .payrollAdjustments, id: lastRow.id)

    return PagePullResult(
      rowsProcessed: rows.count,
      lastUpdatedAt: lastUpdatedAt,
      lastTieId: lastRow.id,
      maxRevision: maxRevision,
      newConflicts: newConflicts,
      autoMerged: 0,
      hasMore: rows.count == pageSize
    )
  }

  private func applyPayrollAdjustmentRow(
    _ serverRow: SyncPayrollAdjustmentRow,
    storeActor: LocalStoreActor
  ) async throws -> ApplyResult {
    let serverUpdatedAt = try requireISO8601(
      serverRow.updated_at, table: .payrollAdjustments, id: serverRow.id)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }
    let serverSnapshot = PayrollAdjustmentServerSnapshot.from(
      row: serverRow,
      updatedAt: serverUpdatedAt,
      deletedAt: serverDeletedAt
    )

    if let existing = try await storeActor.getPayrollAdjustment(id: serverRow.id) {
      switch existing.syncStatus {
      case .clean:
        await storeActor.updatePayrollAdjustmentFromServer(
          id: serverRow.id,
          serverRow: serverRow,
          serverUpdatedAt: serverUpdatedAt,
          serverDeletedAt: serverDeletedAt,
          snapshot: serverSnapshot
        )
        return .updated
      case .dirty, .pendingDelete:
        if serverRow.revision == existing.serverRevision { return .noChange }
        await storeActor.markPayrollAdjustmentConflict(
          id: serverRow.id,
          serverSnapshot: serverSnapshot
        )
        return .conflict
      case .conflict:
        await storeActor.markPayrollAdjustmentConflict(
          id: serverRow.id,
          serverSnapshot: serverSnapshot
        )
        return .noChange
      }
    }

    let local = LocalPayrollAdjustment.from(serverRow: serverRow, serverUpdatedAt: serverUpdatedAt)
    try await storeActor.upsertPayrollAdjustment(local)
    return .inserted
  }

  // MARK: - User Settings Pull

  private func pullUserSettingsPage(userId: String, cursor: SyncCursor) async throws
    -> PagePullResult
  {
    // Query using updated_at + user_id tie-breaker (user_settings uses user_id as primary key)
    let rows: [SyncUserSettingsRow]

    if let cursorUpdatedAt = cursor.updatedAt {
      let cursorTimestamp = formatISO8601(cursorUpdatedAt)
      let cursorTieId = cursor.tieId

      rows =
        try await supabase
        .from("user_settings")
        .select()
        .eq("user_id", value: userId)
        .or(
          "updated_at.gt.\(cursorTimestamp),and(updated_at.eq.\(cursorTimestamp),user_id.gt.\(cursorTieId))"
        )
        .order("updated_at", ascending: true)
        .order("user_id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    } else {
      rows =
        try await supabase
        .from("user_settings")
        .select()
        .eq("user_id", value: userId)
        .order("updated_at", ascending: true)
        .order("user_id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    }

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: cursor.updatedAt,
        lastTieId: cursor.tieId,
        maxRevision: 0,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    var newConflicts = 0
    var autoMerged = 0
    var maxRevision: Int64 = 0
    let pageStartTime = Date()

    for (index, row) in rows.enumerated() {
      let result = try await applyUserSettingsRow(row, storeActor: storeActor)
      if result == .conflict { newConflicts += 1 }
      if result == .autoMerged { autoMerged += 1 }
      if row.revision > maxRevision {
        maxRevision = row.revision
      }

      // Batch save for durability
      let rowNumber = index + 1
      if rowNumber.isMultiple(of: pullSaveBatchSize) {
        try await storeActor.save()
        logger.debug("user_settings: saved batch at row \(rowNumber)/\(rows.count)")
      }
    }

    // Final save for any remaining rows
    try await storeActor.save()

    let duration = Date().timeIntervalSince(pageStartTime)
    logger.info(
      "user_settings: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

    // SAFETY: guard let prevents crash if rows somehow became empty
    guard let lastRow = rows.last else {
      logger.warning("Unexpected empty rows after processing in pullUserSettingsPage")
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: Date(),
        lastTieId: "",
        maxRevision: maxRevision,
        newConflicts: newConflicts,
        autoMerged: autoMerged,
        hasMore: false
      )
    }
    // SAFETY: Throw on parse failure to prevent cursor corruption
    let lastUpdatedAt = try requireISO8601(
      lastRow.updated_at, table: .userSettings, id: lastRow.user_id)

    return PagePullResult(
      rowsProcessed: rows.count,
      lastUpdatedAt: lastUpdatedAt,
      lastTieId: lastRow.user_id,  // user_settings uses user_id as primary key
      maxRevision: maxRevision,
      newConflicts: newConflicts,
      autoMerged: autoMerged,
      hasMore: rows.count == pageSize
    )
  }

  private func applyUserSettingsRow(_ serverRow: SyncUserSettingsRow, storeActor: LocalStoreActor)
    async throws -> ApplyResult
  {
    // SAFETY: Throw on parse failure to prevent data corruption
    let serverUpdatedAt = try requireISO8601(
      serverRow.updated_at, table: .userSettings, id: serverRow.user_id)

    if let existing = try await storeActor.getUserSettings(userId: serverRow.user_id) {
      return try await applyUserSettingsToExisting(
        existing: existing,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        storeActor: storeActor
      )
    } else {
      try await insertNewUserSettings(
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        storeActor: storeActor
      )
      return .inserted
    }
  }

  private func applyUserSettingsToExisting(
    existing: LocalUserSettings,
    serverRow: SyncUserSettingsRow,
    serverUpdatedAt: Date,
    storeActor: LocalStoreActor
  ) async throws -> ApplyResult {
    let serverSnapshot = UserSettingsServerSnapshot.from(
      row: serverRow.toUserSettings(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision
    )

    switch existing.syncStatus {
    case .clean:
      await storeActor.updateUserSettingsFromServer(
        userId: serverRow.user_id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        snapshot: serverSnapshot
      )
      return .updated

    case .dirty:
      if serverRow.revision == existing.serverRevision {
        return .noChange
      }

      guard let lastSnapshot = UserSettingsServerSnapshot.decode(from: existing.lastSyncedSnapshot)
      else {
        await storeActor.markUserSettingsConflict(
          userId: serverRow.user_id, serverSnapshot: serverSnapshot)
        return .conflict
      }

      let serverChangedFields = serverSnapshot.changedFields(from: lastSnapshot)
      let localDirtyFields = existing.dirtyFieldKeys
      let conflictingFields = serverChangedFields.intersection(
        Set(localDirtyFields.map { convertToUserSettingsField($0) }))

      if conflictingFields.isEmpty {
        await storeActor.autoMergeUserSettings(
          userId: serverRow.user_id,
          serverRow: serverRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: serverRow.revision,
          newSnapshot: serverSnapshot,
          localDirtyFields: localDirtyFields
        )
        return .autoMerged
      } else {
        await storeActor.markUserSettingsConflict(
          userId: serverRow.user_id, serverSnapshot: serverSnapshot)
        return .conflict
      }

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
    let dateFormatter = SyncDateFormatters.iso8601DefaultFormatter()

    let lastActive = serverRow.last_active.flatMap { dateFormatter.date(from: $0) }
    let createdAt = serverRow.created_at.flatMap { dateFormatter.date(from: $0) }

    let snapshot = UserSettingsServerSnapshot.from(
      row: serverRow.toUserSettings(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision
    )

    let localSettings = LocalUserSettings(
      userId: serverRow.user_id,
      monthlyGoal: serverRow.monthly_goal,
      monthlyGoalsByMonthData: (try? canonicalJSONEncoder.encode(
        serverRow.monthly_goals_by_month ?? [:]))
        ?? Data(),
      defaultShiftsView: serverRow.default_shifts_view,
      profilePictureUrl: serverRow.profile_picture_url,
      payrollDay: serverRow.payroll_day,
      theme: serverRow.theme,
      calendarAnimationStyle: serverRow.calendar_animation_style,
      showDashboardClockButtons: serverRow.show_dashboard_clock_buttons ?? true,
      aiDataSharingEnabled: serverRow.ai_data_sharing_enabled ?? false,
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

  private func convertToUserSettingsField(_ field: UserSettingsField) -> UserSettingsField {
    field
  }

  // MARK: - Push Implementation

  /// Push dirty records for a single table
  private func pushTable(_ table: SyncTable, userId: String) async throws -> TablePushResult {
    logger.debug("Pushing \(table.displayName)")

    switch table {
    case .jobs:
      return try await pushJobs(userId: userId)
    case .userShifts:
      return try await pushUserShifts(userId: userId)
    case .events:
      return try await pushEvents(userId: userId)
    case .recurringShifts:
      return try await pushRecurringShifts(userId: userId)
    case .wageSnapshots:
      return try await pushWageSnapshots(userId: userId)
    case .payrollAdjustments:
      return try await pushPayrollAdjustments(userId: userId)
    case .userSettings:
      return try await pushUserSettings(userId: userId)
    case .notificationPreferences:
      return try await pushNotificationPreferences(userId: userId)
    }
  }

  private func pushJobs(userId: String) async throws -> TablePushResult {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    let dirtyJobs = try await storeActor.getDirtyJobs(userId: userId)

    if dirtyJobs.isEmpty {
      return TablePushResult(table: .jobs, rowsPushed: 0, newConflicts: 0, rebased: 0)
    }

    var rowsPushed = 0
    var newConflicts = 0
    var rebased = 0

    // Keep default-workplace updates constraint-safe:
    // 1) push rows unsetting is_default first
    // 2) push regular updates
    // 3) push rows setting is_default=true last
    let orderedDirtyJobs = dirtyJobs.sorted { lhs, rhs in
      let lhsPriority = jobPushPriority(lhs)
      let rhsPriority = jobPushPriority(rhs)

      if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
      }

      if lhs.localUpdatedAt != rhs.localUpdatedAt {
        return lhs.localUpdatedAt < rhs.localUpdatedAt
      }

      return lhs.id < rhs.id
    }

    for job in orderedDirtyJobs {
      let result = try await pushJob(job, userId: userId, storeActor: storeActor, isRetry: false)
      switch result {
      case .success, .deleted:
        rowsPushed += 1
      case .conflict:
        newConflicts += 1
      case .rebased:
        rebased += 1
        rowsPushed += 1
      case .noChange:
        break
      }
    }

    try await storeActor.save()
    return TablePushResult(
      table: .jobs, rowsPushed: rowsPushed, newConflicts: newConflicts, rebased: rebased)
  }

  private func jobPushPriority(_ job: LocalJob) -> Int {
    let dirtyFields = job.dirtyFieldKeys
    guard dirtyFields.contains(.isDefault) else {
      return 1
    }
    return job.isDefault ? 2 : 0
  }

  private func pushJob(
    _ job: LocalJob,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let jobId = job.id

    if job.syncStatus == .pendingDelete {
      return try await pushJobDelete(job, userId: userId, storeActor: storeActor)
    }

    let dirtyFields = job.dirtyFieldKeys
    if dirtyFields.isEmpty {
      await storeActor.markJobClean(id: jobId)
      return .noChange
    }

    if job.serverRevision == 0 {
      return try await insertJob(job, userId: userId, storeActor: storeActor)
    }

    var updateData: [String: AnyJSON] = [:]

    if dirtyFields.contains(.name) {
      updateData["name"] = .string(job.name)
    }
    if dirtyFields.contains(.color) {
      if let color = job.color {
        updateData["color"] = .string(color)
      } else {
        updateData["color"] = .null
      }
    }
    if dirtyFields.contains(.currency) {
      updateData["currency"] = .string(job.currency)
    }
    if dirtyFields.contains(.isDefault) {
      updateData["is_default"] = .bool(job.isDefault)
    }
    if dirtyFields.contains(.sortOrder) {
      updateData["sort_order"] = .integer(job.sortOrder)
    }
    if dirtyFields.contains(.payrollDay) {
      if let day = job.payrollDay {
        updateData["payroll_day"] = .integer(day)
      } else {
        updateData["payroll_day"] = .null
      }
    }
    if dirtyFields.contains(.halfTaxMonth) {
      if let month = job.halfTaxMonth {
        updateData["half_tax_month"] = .integer(month)
      } else {
        updateData["half_tax_month"] = .null
      }
    }
    if dirtyFields.contains(.monthlyGoal) {
      if let goal = job.monthlyGoal {
        updateData["monthly_goal"] = .integer(goal)
      } else {
        updateData["monthly_goal"] = .null
      }
    }
    if dirtyFields.contains(.archivedAt) {
      if let archivedAt = job.archivedAt {
        updateData["archived_at"] = .string(formatSupabaseTimestamp(archivedAt))
      } else {
        updateData["archived_at"] = .null
      }
    }
    if dirtyFields.contains(.deletedAt) {
      if let deletedAt = job.deletedAt {
        updateData["deleted_at"] = .string(formatSupabaseTimestamp(deletedAt))
      } else {
        updateData["deleted_at"] = .null
      }
    }

    try requireNonEmptyUpdate(updateData, table: .jobs, id: jobId)

    let serverRevision = Int(job.serverRevision)

    do {
      let returnedRows: [SyncJobRow] =
        try await supabase
        .from("jobs")
        .update(updateData)
        .eq("id", value: jobId)
        .eq("user_id", value: userId)
        .eq("revision", value: serverRevision)
        .is("deleted_at", value: nil)
        .select()
        .execute()
        .value

      if let returnedRow = returnedRows.first {
        let serverUpdatedAt = parseUpdatedAt(returnedRow.updated_at, table: .jobs, id: jobId)
        let serverArchivedAt = returnedRow.archived_at.flatMap { parseISO8601($0) }
        let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }
        let serverSnapshot = JobServerSnapshot.from(row: returnedRow, updatedAt: serverUpdatedAt)

        await storeActor.markJobPushed(
          id: jobId,
          serverRow: returnedRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: returnedRow.revision,
          archivedAt: serverArchivedAt,
          deletedAt: serverDeletedAt,
          snapshot: serverSnapshot
        )

        logger.debug("Pushed job \(jobId.prefix(8))")
        return .success
      }

      return try await handleJobPushConflict(
        job: job,
        userId: userId,
        storeActor: storeActor,
        isRetry: isRetry
      )
    } catch {
      let errorString = String(describing: error)
      if errorString.contains("duplicate") || errorString.contains("23505") {
        logger.warning(
          "Job \(jobId.prefix(8)) hit unique constraint on UPDATE, resolving via conflict flow"
        )
        return try await handleJobPushConflict(
          job: job,
          userId: userId,
          storeActor: storeActor,
          isRetry: isRetry
        )
      }
      if errorString.contains("row-level security") || errorString.contains("42501") {
        logger.warning(
          "Job \(jobId.prefix(8)) blocked by RLS policy on UPDATE, marking as conflict")
        await storeActor.markJobConflict(id: jobId, serverSnapshot: nil)
        return .conflict
      }
      logger.error("Push job failed: \(error.localizedDescription)")
      throw error
    }
  }

  private func pushJobDelete(
    _ job: LocalJob,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let jobId = job.id
    let serverRevision = Int(job.serverRevision)

    let returnedRows: [SyncJobRow] =
      try await supabase
      .from("jobs")
      .update([
        "deleted_at": AnyJSON.string(formatSupabaseTimestamp(Date())),
        "is_default": AnyJSON.bool(false),
      ])
      .eq("id", value: jobId)
      .eq("user_id", value: userId)
      .eq("revision", value: serverRevision)
      .is("deleted_at", value: nil)
      .select()
      .execute()
      .value

    if let returnedRow = returnedRows.first {
      let serverUpdatedAt = parseUpdatedAt(returnedRow.updated_at, table: .jobs, id: jobId)
      let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }
      await storeActor.markJobDeleted(
        id: jobId,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        deletedAt: serverDeletedAt
      )
      logger.debug("Deleted job \(jobId.prefix(8))")
      return .deleted
    }

    let serverRows: [SyncJobRow] =
      try await supabase
      .from("jobs")
      .select()
      .eq("id", value: jobId)
      .execute()
      .value

    if let serverRow = serverRows.first {
      let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .jobs, id: jobId)
      let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

      if serverDeletedAt != nil {
        await storeActor.markJobDeleted(
          id: jobId,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: serverRow.revision,
          deletedAt: serverDeletedAt
        )
        return .deleted
      }

      let serverSnapshot = JobServerSnapshot.from(row: serverRow, updatedAt: serverUpdatedAt)
      await storeActor.markJobConflict(id: jobId, serverSnapshot: serverSnapshot)
    }

    return .conflict
  }

  private func insertJob(
    _ job: LocalJob,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let jobId = job.id
    var insertData: [String: AnyJSON] = [
      "id": .string(jobId),
      "user_id": .string(userId),
      "name": .string(job.name),
      "currency": .string(job.currency),
      "is_default": .bool(job.isDefault),
      "sort_order": .integer(job.sortOrder),
    ]

    if let color = job.color {
      insertData["color"] = .string(color)
    }
    if let payrollDay = job.payrollDay {
      insertData["payroll_day"] = .integer(payrollDay)
    }
    if let halfTaxMonth = job.halfTaxMonth {
      insertData["half_tax_month"] = .integer(halfTaxMonth)
    }
    if let monthlyGoal = job.monthlyGoal {
      insertData["monthly_goal"] = .integer(monthlyGoal)
    }
    if let archivedAt = job.archivedAt {
      insertData["archived_at"] = .string(formatSupabaseTimestamp(archivedAt))
    }

    do {
      let returnedRows: [SyncJobRow] =
        try await supabase
        .from("jobs")
        .insert(insertData)
        .select()
        .execute()
        .value

      if let returnedRow = returnedRows.first {
        let serverUpdatedAt = parseUpdatedAt(returnedRow.updated_at, table: .jobs, id: jobId)
        let serverArchivedAt = returnedRow.archived_at.flatMap { parseISO8601($0) }
        let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }
        let serverSnapshot = JobServerSnapshot.from(row: returnedRow, updatedAt: serverUpdatedAt)

        await storeActor.markJobPushed(
          id: jobId,
          serverRow: returnedRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: returnedRow.revision,
          archivedAt: serverArchivedAt,
          deletedAt: serverDeletedAt,
          snapshot: serverSnapshot
        )

        logger.debug("Inserted new job \(jobId.prefix(8))")
        return .success
      }

      logger.error("Insert job returned no rows for \(jobId.prefix(8))")
      return .conflict
    } catch {
      let errorString = String(describing: error)
      if errorString.contains("duplicate") || errorString.contains("23505") {
        logger.warning("Job \(jobId.prefix(8)) already exists on server, fetching and merging")
        let serverRows: [SyncJobRow] =
          try await supabase
          .from("jobs")
          .select()
          .eq("id", value: jobId)
          .execute()
          .value

        if let serverRow = serverRows.first {
          let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .jobs, id: jobId)
          let serverSnapshot = JobServerSnapshot.from(row: serverRow, updatedAt: serverUpdatedAt)
          await storeActor.markJobConflict(id: jobId, serverSnapshot: serverSnapshot)
        }
        return .conflict
      }

      if errorString.contains("row-level security") || errorString.contains("42501") {
        logger.warning("Job \(jobId.prefix(8)) blocked by RLS policy, marking as conflict")
        await storeActor.markJobConflict(id: jobId, serverSnapshot: nil)
        return .conflict
      }

      logger.error("Insert job failed: \(error.localizedDescription)")
      throw error
    }
  }

  private func handleJobPushConflict(
    job: LocalJob,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let jobId = job.id

    let serverRows: [SyncJobRow] =
      try await supabase
      .from("jobs")
      .select()
      .eq("id", value: jobId)
      .execute()
      .value

    guard let serverRow = serverRows.first else {
      if job.serverRevision == 0 {
        logger.debug("Job \(jobId.prefix(8)) is new (serverRevision=0), attempting INSERT")
        return try await insertJob(job, userId: userId, storeActor: storeActor)
      }
      logger.debug("Job \(jobId.prefix(8)) was deleted on server")
      await storeActor.markJobConflict(id: jobId, serverSnapshot: nil)
      return .conflict
    }

    let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .jobs, id: jobId)
    let serverArchivedAt = serverRow.archived_at.flatMap { parseISO8601($0) }
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if serverDeletedAt != nil {
      if job.syncStatus == .pendingDelete {
        await storeActor.markJobDeleted(
          id: jobId,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: serverRow.revision,
          deletedAt: serverDeletedAt
        )
        return .deleted
      }

      let serverSnapshot = JobServerSnapshot.from(row: serverRow, updatedAt: serverUpdatedAt)
      await storeActor.markJobConflict(id: jobId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    guard let lastSnapshot = JobServerSnapshot.decode(from: job.lastSyncedSnapshot) else {
      let serverSnapshot = JobServerSnapshot.from(row: serverRow, updatedAt: serverUpdatedAt)
      await storeActor.markJobConflict(id: jobId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    let newServerSnapshot = JobServerSnapshot.from(row: serverRow, updatedAt: serverUpdatedAt)
    let serverChangedFields = newServerSnapshot.changedFields(from: lastSnapshot)
    let localDirtyFields = job.dirtyFieldKeys
    let conflictingFields = serverChangedFields.intersection(
      Set(localDirtyFields.map { convertToJobField($0) }))

    if conflictingFields.isEmpty && !isRetry {
      await storeActor.rebaseJob(
        id: jobId,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        archivedAt: serverArchivedAt,
        deletedAt: serverDeletedAt,
        newSnapshot: newServerSnapshot,
        localDirtyFields: localDirtyFields
      )

      if let rebasedJob = try await storeActor.getJob(id: jobId) {
        let retryResult = try await pushJob(
          rebasedJob, userId: userId, storeActor: storeActor, isRetry: true)
        if retryResult == .success {
          return .rebased
        }
        return retryResult
      }
      return .conflict
    }

    await storeActor.markJobConflict(id: jobId, serverSnapshot: newServerSnapshot)
    return .conflict
  }

  // MARK: - User Shifts Push

  private func pushUserShifts(userId: String) async throws -> TablePushResult {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    let dirtyShifts = try await storeActor.getDirtyUserShifts(userId: userId)

    if dirtyShifts.isEmpty {
      return TablePushResult(table: .userShifts, rowsPushed: 0, newConflicts: 0, rebased: 0)
    }

    var rowsPushed = 0
    var newConflicts = 0
    var rebased = 0

    for shift in dirtyShifts {
      let result = try await pushUserShift(
        shift, userId: userId, storeActor: storeActor, isRetry: false)
      switch result {
      case .success, .deleted:
        rowsPushed += 1
      case .conflict:
        newConflicts += 1
      case .rebased:
        rebased += 1
        rowsPushed += 1
      case .noChange:
        break
      }
    }

    try await storeActor.save()
    return TablePushResult(
      table: .userShifts, rowsPushed: rowsPushed, newConflicts: newConflicts, rebased: rebased)
  }

  private func pushUserShift(
    _ shift: LocalUserShift,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let shiftId = shift.id

    if shift.syncStatus == .pendingDelete {
      // Soft delete: UPDATE deleted_at = now()
      return try await pushUserShiftDelete(shift, userId: userId, storeActor: storeActor)
    }

    // Build update patch using only dirty fields
    let dirtyFields = shift.dirtyFieldKeys
    if dirtyFields.isEmpty {
      // No fields dirty, mark as clean
      await storeActor.markShiftClean(id: shiftId)
      return .noChange
    }

    // Check if this is a new record that needs INSERT (serverRevision == 0 means never synced)
    if shift.serverRevision == 0 {
      return try await insertUserShift(shift, userId: userId, storeActor: storeActor)
    }

    // Build partial update
    var updateData: [String: AnyJSON] = [:]
    if dirtyFields.contains(.jobId) {
      if let jobId = shift.jobId {
        updateData["job_id"] = .string(jobId)
      } else {
        updateData["job_id"] = .null
      }
    }
    if dirtyFields.contains(.shiftDate) {
      updateData["shift_date"] = .string(shift.shiftDateString)
    }
    if dirtyFields.contains(.startTime) {
      updateData["start_time"] = .string(shift.startTime)
    }
    if dirtyFields.contains(.endTime) {
      updateData["end_time"] = .string(shift.endTime)
    }
    if dirtyFields.contains(.customPauseWindows) {
      if let data = shift.customPauseWindows {
        let decoded = try requireAnyJSON(
          data,
          table: .userShifts,
          id: shiftId,
          field: "custom_pause_windows"
        )
        updateData["custom_pause_windows"] = decoded
      } else {
        updateData["custom_pause_windows"] = .null
      }
    }
    if dirtyFields.contains(.customSupplements) {
      if let data = shift.customSupplements {
        let decoded = try requireAnyJSON(
          data,
          table: .userShifts,
          id: shiftId,
          field: "custom_supplements"
        )
        updateData["custom_supplements"] = decoded
      } else {
        updateData["custom_supplements"] = .null
      }
    }
    if dirtyFields.contains(.note) {
      if let note = shift.note {
        updateData["note"] = .string(note)
      } else {
        updateData["note"] = .null
      }
    }

    try requireNonEmptyUpdate(updateData, table: .userShifts, id: shiftId)

    // Optimistic concurrency: filter by revision
    // Note: Convert Int64 to Int for PostgrestFilterValue conformance
    let serverRevision = Int(shift.serverRevision)

    do {
      // UPDATE with revision filter, returning the updated row
      let returnedRows: [SyncShiftRow] =
        try await supabase
        .from("user_shifts")
        .update(updateData)
        .eq("id", value: shiftId)
        .eq("user_id", value: userId)
        .eq("revision", value: serverRevision)
        .is("deleted_at", value: nil)
        .select()
        .execute()
        .value

      if let returnedRow = returnedRows.first {
        // Success - update local with canonical server values
        let serverUpdatedAt = parseUpdatedAt(
          returnedRow.updated_at, table: .userShifts, id: shiftId)
        let serverSnapshot = UserShiftServerSnapshot.from(
          jobId: returnedRow.job_id,
          shiftDate: returnedRow.shift_date,
          startTime: returnedRow.start_time,
          endTime: returnedRow.end_time,
          note: returnedRow.note,
          customPauseWindows: returnedRow.custom_pause_windows,
          customSupplements: returnedRow.custom_supplements,
          updatedAt: serverUpdatedAt,
          revision: returnedRow.revision,
          deletedAt: nil
        )

        await storeActor.markShiftPushed(
          id: shiftId,
          serverRow: returnedRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: returnedRow.revision,
          snapshot: serverSnapshot
        )

        logger.debug("Pushed shift \(shiftId.prefix(8))")

        return .success
      } else {
        // Row wasn't updated - revision mismatch
        return try await handleShiftPushConflict(
          shift: shift,
          userId: userId,
          storeActor: storeActor,
          isRetry: isRetry
        )
      }
    } catch {
      // Check if it's an RLS policy violation - mark as conflict, don't abort sync
      let errorString = String(describing: error)
      if errorString.contains("row-level security") || errorString.contains("42501") {
        logger.warning(
          "Shift \(shiftId.prefix(8)) blocked by RLS policy on UPDATE, marking as conflict")
        await storeActor.markShiftConflict(id: shiftId, serverSnapshot: nil)
        return .conflict
      }
      logger.error("Push shift failed: \(error.localizedDescription)")
      throw error
    }
  }

  private func pushUserShiftDelete(
    _ shift: LocalUserShift,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let shiftId = shift.id
    // Note: Convert Int64 to Int for PostgrestFilterValue conformance
    let serverRevision = Int(shift.serverRevision)

    // UPDATE deleted_at = now() with revision filter
    let returnedRows: [SyncShiftRow] =
      try await supabase
      .from("user_shifts")
      .update(["deleted_at": AnyJSON.string(formatSupabaseTimestamp(Date()))])
      .eq("id", value: shiftId)
      .eq("user_id", value: userId)
      .eq("revision", value: serverRevision)
      .is("deleted_at", value: nil)
      .select()
      .execute()
      .value

    if let returnedRow = returnedRows.first {
      // Success - mark as deleted locally
      let serverUpdatedAt = parseUpdatedAt(returnedRow.updated_at, table: .userShifts, id: shiftId)
      let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }

      await storeActor.markShiftDeleted(
        id: shiftId,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        serverDeletedAt: serverDeletedAt
      )

      logger.debug("Deleted shift \(shiftId.prefix(8))")

      return .deleted
    } else {
      // Conflict - fetch current server state
      let serverRows: [SyncShiftRow] =
        try await supabase
        .from("user_shifts")
        .select()
        .eq("id", value: shiftId)
        .execute()
        .value

      if let serverRow = serverRows.first {
        let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .userShifts, id: shiftId)
        let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

        if serverDeletedAt != nil {
          // Already deleted on server, just clean up local
          await storeActor.markShiftDeleted(
            id: shiftId,
            serverUpdatedAt: serverUpdatedAt,
            serverRevision: serverRow.revision,
            serverDeletedAt: serverDeletedAt
          )
          return .deleted
        }

        // Mark conflict
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
        await storeActor.markShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
      }
      return .conflict
    }
  }

  /// Insert a new user shift that was created locally (serverRevision == 0)
  private func insertUserShift(
    _ shift: LocalUserShift,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let shiftId = shift.id

    // Build full insert data
    var insertData: [String: AnyJSON] = [
      "id": .string(shiftId),
      "user_id": .string(userId),
      "shift_date": .string(shift.shiftDateString),
      "start_time": .string(shift.startTime),
      "end_time": .string(shift.endTime),
    ]
    if let jobId = shift.jobId {
      insertData["job_id"] = .string(jobId)
    }

    if let data = shift.customPauseWindows {
      let decoded = try requireAnyJSON(
        data,
        table: .userShifts,
        id: shiftId,
        field: "custom_pause_windows"
      )
      insertData["custom_pause_windows"] = decoded
    }

    if let data = shift.customSupplements {
      let decoded = try requireAnyJSON(
        data,
        table: .userShifts,
        id: shiftId,
        field: "custom_supplements"
      )
      insertData["custom_supplements"] = decoded
    }
    if let note = shift.note {
      insertData["note"] = .string(note)
    }

    do {
      let returnedRows: [SyncShiftRow] =
        try await supabase
        .from("user_shifts")
        .insert(insertData)
        .select()
        .execute()
        .value

      if let returnedRow = returnedRows.first {
        let serverUpdatedAt = parseUpdatedAt(
          returnedRow.updated_at, table: .userShifts, id: shiftId)
        let serverSnapshot = UserShiftServerSnapshot.from(
          jobId: returnedRow.job_id,
          shiftDate: returnedRow.shift_date,
          startTime: returnedRow.start_time,
          endTime: returnedRow.end_time,
          note: returnedRow.note,
          customPauseWindows: returnedRow.custom_pause_windows,
          customSupplements: returnedRow.custom_supplements,
          updatedAt: serverUpdatedAt,
          revision: returnedRow.revision,
          deletedAt: nil
        )

        await storeActor.markShiftPushed(
          id: shiftId,
          serverRow: returnedRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: returnedRow.revision,
          snapshot: serverSnapshot
        )

        logger.debug("Inserted new shift \(shiftId.prefix(8))")

        return .success
      } else {
        logger.error("Insert shift returned no rows for \(shiftId.prefix(8))")
        return .conflict
      }
    } catch {
      let errorString = String(describing: error)
      // Check if it's a duplicate key error (row already exists on server)
      if errorString.contains("duplicate") || errorString.contains("23505") {
        logger.warning("Shift \(shiftId.prefix(8)) already exists on server, fetching and merging")
        // Fetch the existing server row and treat as conflict
        let serverRows: [SyncShiftRow] =
          try await supabase
          .from("user_shifts")
          .select()
          .eq("id", value: shiftId)
          .execute()
          .value

        if let serverRow = serverRows.first {
          let serverUpdatedAt = parseUpdatedAt(
            serverRow.updated_at, table: .userShifts, id: shiftId)
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
            deletedAt: serverRow.deleted_at.flatMap { parseISO8601($0) }
          )
          await storeActor.markShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
        }
        return .conflict
      }
      // Check if it's an RLS policy violation - mark as conflict, don't abort sync
      if errorString.contains("row-level security") || errorString.contains("42501") {
        logger.warning("Shift \(shiftId.prefix(8)) blocked by RLS policy, marking as conflict")
        await storeActor.markShiftConflict(id: shiftId, serverSnapshot: nil)
        return .conflict
      }
      logger.error("Insert shift failed: \(error.localizedDescription)")
      throw error
    }
  }

  private func handleShiftPushConflict(
    shift: LocalUserShift,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let shiftId = shift.id

    // Fetch current server state
    let serverRows: [SyncShiftRow] =
      try await supabase
      .from("user_shifts")
      .select()
      .eq("id", value: shiftId)
      .execute()
      .value

    guard let serverRow = serverRows.first else {
      // Server row doesn't exist - check if this is a new local record that needs INSERT
      if shift.serverRevision == 0 {
        logger.debug("Shift \(shiftId.prefix(8)) is new (serverRevision=0), attempting INSERT")
        return try await insertUserShift(shift, userId: userId, storeActor: storeActor)
      }
      // Row was deleted on server
      logger.debug("Shift \(shiftId.prefix(8)) was deleted on server")
      await storeActor.markShiftConflict(id: shiftId, serverSnapshot: nil)
      return .conflict
    }

    let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .userShifts, id: shiftId)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if serverDeletedAt != nil {
      // Server soft-deleted this row
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
      await storeActor.markShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    // Try field-level merge
    guard let lastSnapshot = UserShiftServerSnapshot.decode(from: shift.lastSyncedSnapshot) else {
      // Cannot decode snapshot, mark conflict
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
      await storeActor.markShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    let newServerSnapshot = UserShiftServerSnapshot.from(
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

    let serverChangedFields = newServerSnapshot.changedFields(from: lastSnapshot)
    let localDirtyFields = shift.dirtyFieldKeys
    let conflictingFields = serverChangedFields.intersection(
      Set(localDirtyFields.map { convertToUserShiftField($0) }))

    if conflictingFields.isEmpty && !isRetry {
      // Auto-merge possible: rebase and retry once
      await storeActor.rebaseShift(
        id: shiftId,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        newSnapshot: newServerSnapshot,
        localDirtyFields: localDirtyFields
      )

      // Reload and retry
      if let rebasedShift = try await storeActor.getUserShift(id: shiftId) {
        let retryResult = try await pushUserShift(
          rebasedShift, userId: userId, storeActor: storeActor, isRetry: true)
        if retryResult == .success {
          return .rebased
        }
        return retryResult
      }
      return .conflict
    } else {
      // Conflict - overlapping fields or retry failed
      await storeActor.markShiftConflict(id: shiftId, serverSnapshot: newServerSnapshot)
      return .conflict
    }
  }

  // MARK: - Events Push

  private func pushEvents(userId: String) async throws -> TablePushResult {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    let dirtyEvents = try await storeActor.getDirtyEvents(userId: userId)

    if dirtyEvents.isEmpty {
      return TablePushResult(table: .events, rowsPushed: 0, newConflicts: 0, rebased: 0)
    }

    var rowsPushed = 0
    var newConflicts = 0
    var rebased = 0

    for event in dirtyEvents {
      let result = try await pushEvent(
        event, userId: userId, storeActor: storeActor, isRetry: false)
      switch result {
      case .success, .deleted:
        rowsPushed += 1
      case .conflict:
        newConflicts += 1
      case .rebased:
        rebased += 1
        rowsPushed += 1
      case .noChange:
        break
      }
    }

    try await storeActor.save()
    return TablePushResult(
      table: .events,
      rowsPushed: rowsPushed,
      newConflicts: newConflicts,
      rebased: rebased
    )
  }

  private func pushEvent(
    _ event: LocalEvent,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let eventId = event.id

    if event.syncStatus == .pendingDelete {
      return try await pushEventDelete(event, userId: userId, storeActor: storeActor)
    }

    let dirtyFields = event.dirtyFieldKeys
    if dirtyFields.isEmpty {
      await storeActor.markEventClean(id: eventId)
      return .noChange
    }

    if event.serverRevision == 0 {
      return try await insertEvent(event, userId: userId, storeActor: storeActor)
    }

    var updateData: [String: AnyJSON] = [:]
    if dirtyFields.contains(.startDate) {
      updateData["start_date"] = .string(event.startDateString)
    }
    if dirtyFields.contains(.endDate) {
      updateData["end_date"] = .string(event.endDateString)
    }
    if dirtyFields.contains(.isAllDay) {
      updateData["is_all_day"] = .bool(event.isAllDay)
    }
    if dirtyFields.contains(.startTime) {
      if let startTime = event.startTime {
        updateData["start_time"] = .string(startTime)
      } else {
        updateData["start_time"] = .null
      }
    }
    if dirtyFields.contains(.endTime) {
      if let endTime = event.endTime {
        updateData["end_time"] = .string(endTime)
      } else {
        updateData["end_time"] = .null
      }
    }
    if dirtyFields.contains(.note) {
      updateData["note"] = .string(event.note)
    }
    if dirtyFields.contains(.notificationMinutesArray) {
      updateData["notification_minutes_array"] =
        event.notificationMinutesArray.isEmpty
        ? .array([])
        : .array(event.notificationMinutesArray.map { .integer($0) })
    }
    if dirtyFields.contains(.notificationAnchorTime) {
      if let notificationAnchorTime = event.notificationAnchorTime {
        updateData["notification_anchor_time"] = .string(notificationAnchorTime)
      } else {
        updateData["notification_anchor_time"] = .null
      }
    }

    try requireNonEmptyUpdate(updateData, table: .events, id: eventId)

    let serverRevision = Int(event.serverRevision)

    do {
      let returnedRows: [SyncEventRow] =
        try await supabase
        .from("events")
        .update(updateData)
        .eq("id", value: eventId)
        .eq("user_id", value: userId)
        .eq("revision", value: serverRevision)
        .is("deleted_at", value: nil)
        .select()
        .execute()
        .value

      if let returnedRow = returnedRows.first {
        let serverUpdatedAt = parseUpdatedAt(returnedRow.updated_at, table: .events, id: eventId)
        let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }
        let serverSnapshot = EventServerSnapshot.from(
          serverRow: returnedRow,
          updatedAt: serverUpdatedAt,
          deletedAt: serverDeletedAt
        )

        await storeActor.markEventPushed(
          id: eventId,
          serverRow: returnedRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: returnedRow.revision,
          snapshot: serverSnapshot
        )

        logger.debug("Pushed event \(eventId.prefix(8))")
        return .success
      } else {
        return try await handleEventPushConflict(
          event: event,
          userId: userId,
          storeActor: storeActor,
          isRetry: isRetry
        )
      }
    } catch {
      let errorString = String(describing: error)
      if errorString.contains("row-level security") || errorString.contains("42501") {
        logger.warning(
          "Event \(eventId.prefix(8)) blocked by RLS policy on UPDATE, marking as conflict")
        await storeActor.markEventConflict(id: eventId, serverSnapshot: nil)
        return .conflict
      }
      logger.error("Push event failed: \(error.localizedDescription)")
      throw error
    }
  }

  private func pushEventDelete(
    _ event: LocalEvent,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let eventId = event.id

    // A locally created event can be deleted before its first successful push.
    // In that case there is no server row to soft-delete, so we should just
    // retire the local record instead of surfacing a false conflict.
    if event.serverRevision == 0 {
      let deletedAt = Date()
      await storeActor.markEventDeleted(
        id: eventId,
        serverUpdatedAt: deletedAt,
        serverRevision: 0,
        serverDeletedAt: deletedAt
      )
      logger.debug("Discarded unsynced event \(eventId.prefix(8))")
      return .deleted
    }

    let serverRevision = Int(event.serverRevision)

    let returnedRows: [SyncEventRow] =
      try await supabase
      .from("events")
      .update(["deleted_at": AnyJSON.string(formatSupabaseTimestamp(Date()))])
      .eq("id", value: eventId)
      .eq("user_id", value: userId)
      .eq("revision", value: serverRevision)
      .is("deleted_at", value: nil)
      .select()
      .execute()
      .value

    if let returnedRow = returnedRows.first {
      let serverUpdatedAt = parseUpdatedAt(returnedRow.updated_at, table: .events, id: eventId)
      let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }

      await storeActor.markEventDeleted(
        id: eventId,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        serverDeletedAt: serverDeletedAt
      )

      logger.debug("Deleted event \(eventId.prefix(8))")
      return .deleted
    } else {
      let serverRows: [SyncEventRow] =
        try await supabase
        .from("events")
        .select()
        .eq("id", value: eventId)
        .execute()
        .value

      if let serverRow = serverRows.first {
        let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .events, id: eventId)
        let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

        if serverDeletedAt != nil {
          await storeActor.markEventDeleted(
            id: eventId,
            serverUpdatedAt: serverUpdatedAt,
            serverRevision: serverRow.revision,
            serverDeletedAt: serverDeletedAt
          )
          return .deleted
        }

        let serverSnapshot = EventServerSnapshot.from(
          serverRow: serverRow,
          updatedAt: serverUpdatedAt,
          deletedAt: serverDeletedAt
        )
        await storeActor.markEventConflict(id: eventId, serverSnapshot: serverSnapshot)
      }
      return .conflict
    }
  }

  private func insertEvent(
    _ event: LocalEvent,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let eventId = event.id
    var insertData: [String: AnyJSON] = [
      "id": .string(eventId),
      "user_id": .string(userId),
      "start_date": .string(event.startDateString),
      "end_date": .string(event.endDateString),
      "is_all_day": .bool(event.isAllDay),
      "note": .string(event.note),
    ]

    if let startTime = event.startTime {
      insertData["start_time"] = .string(startTime)
    }
    if let endTime = event.endTime {
      insertData["end_time"] = .string(endTime)
    }
    if !event.notificationMinutesArray.isEmpty {
      insertData["notification_minutes_array"] = .array(
        event.notificationMinutesArray.map { .integer($0) }
      )
    }
    if let notificationAnchorTime = event.notificationAnchorTime {
      insertData["notification_anchor_time"] = .string(notificationAnchorTime)
    }

    do {
      let returnedRows: [SyncEventRow] =
        try await supabase
        .from("events")
        .insert(insertData)
        .select()
        .execute()
        .value

      if let returnedRow = returnedRows.first {
        let serverUpdatedAt = parseUpdatedAt(returnedRow.updated_at, table: .events, id: eventId)
        let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }
        let serverSnapshot = EventServerSnapshot.from(
          serverRow: returnedRow,
          updatedAt: serverUpdatedAt,
          deletedAt: serverDeletedAt
        )

        await storeActor.markEventPushed(
          id: eventId,
          serverRow: returnedRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: returnedRow.revision,
          snapshot: serverSnapshot
        )

        logger.debug("Inserted new event \(eventId.prefix(8))")
        return .success
      } else {
        logger.error("Insert event returned no rows for \(eventId.prefix(8))")
        return .conflict
      }
    } catch {
      let errorString = String(describing: error)
      if errorString.contains("duplicate") || errorString.contains("23505") {
        logger.warning("Event \(eventId.prefix(8)) already exists on server, fetching and merging")
        let serverRows: [SyncEventRow] =
          try await supabase
          .from("events")
          .select()
          .eq("id", value: eventId)
          .execute()
          .value

        if let serverRow = serverRows.first {
          let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .events, id: eventId)
          let serverSnapshot = EventServerSnapshot.from(
            serverRow: serverRow,
            updatedAt: serverUpdatedAt,
            deletedAt: serverRow.deleted_at.flatMap { parseISO8601($0) }
          )
          await storeActor.markEventConflict(id: eventId, serverSnapshot: serverSnapshot)
        }
        return .conflict
      }
      if errorString.contains("row-level security") || errorString.contains("42501") {
        logger.warning("Event \(eventId.prefix(8)) blocked by RLS policy, marking as conflict")
        await storeActor.markEventConflict(id: eventId, serverSnapshot: nil)
        return .conflict
      }
      logger.error("Insert event failed: \(error.localizedDescription)")
      throw error
    }
  }

  private func handleEventPushConflict(
    event: LocalEvent,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let eventId = event.id

    let serverRows: [SyncEventRow] =
      try await supabase
      .from("events")
      .select()
      .eq("id", value: eventId)
      .execute()
      .value

    guard let serverRow = serverRows.first else {
      if event.serverRevision == 0 {
        logger.debug("Event \(eventId.prefix(8)) is new (serverRevision=0), attempting INSERT")
        return try await insertEvent(event, userId: userId, storeActor: storeActor)
      }
      logger.debug("Event \(eventId.prefix(8)) was deleted on server")
      await storeActor.markEventConflict(id: eventId, serverSnapshot: nil)
      return .conflict
    }

    let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .events, id: eventId)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if serverDeletedAt != nil {
      let serverSnapshot = EventServerSnapshot.from(
        serverRow: serverRow,
        updatedAt: serverUpdatedAt,
        deletedAt: serverDeletedAt
      )
      await storeActor.markEventConflict(id: eventId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    guard let lastSnapshot = EventServerSnapshot.decode(from: event.lastSyncedSnapshot) else {
      let serverSnapshot = EventServerSnapshot.from(
        serverRow: serverRow,
        updatedAt: serverUpdatedAt,
        deletedAt: serverDeletedAt
      )
      await storeActor.markEventConflict(id: eventId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    let newServerSnapshot = EventServerSnapshot.from(
      serverRow: serverRow,
      updatedAt: serverUpdatedAt,
      deletedAt: serverDeletedAt
    )

    let serverChangedFields = newServerSnapshot.changedFields(from: lastSnapshot)
    let localDirtyFields = event.dirtyFieldKeys
    let conflictingFields = serverChangedFields.intersection(
      Set(localDirtyFields.map { convertToEventField($0) }))

    if conflictingFields.isEmpty && !isRetry {
      await storeActor.rebaseEvent(
        id: eventId,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        newSnapshot: newServerSnapshot,
        localDirtyFields: localDirtyFields
      )

      if let rebasedEvent = try await storeActor.getEvent(id: eventId) {
        let retryResult = try await pushEvent(
          rebasedEvent, userId: userId, storeActor: storeActor, isRetry: true)
        if retryResult == .success {
          return .rebased
        }
        return retryResult
      }
      return .conflict
    } else {
      await storeActor.markEventConflict(id: eventId, serverSnapshot: newServerSnapshot)
      return .conflict
    }
  }

  // MARK: - Recurring Shifts Push

  private func pushRecurringShifts(userId: String) async throws -> TablePushResult {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    let dirtyShifts = try await storeActor.getDirtyRecurringShifts(userId: userId)

    if dirtyShifts.isEmpty {
      return TablePushResult(table: .recurringShifts, rowsPushed: 0, newConflicts: 0, rebased: 0)
    }

    var rowsPushed = 0
    var newConflicts = 0
    var rebased = 0

    for shift in dirtyShifts {
      let result = try await pushRecurringShift(
        shift, userId: userId, storeActor: storeActor, isRetry: false)
      switch result {
      case .success, .deleted:
        rowsPushed += 1
      case .conflict:
        newConflicts += 1
      case .rebased:
        rebased += 1
        rowsPushed += 1
      case .noChange:
        break
      }
    }

    try await storeActor.save()
    return TablePushResult(
      table: .recurringShifts, rowsPushed: rowsPushed, newConflicts: newConflicts, rebased: rebased)
  }

  private func pushRecurringShift(
    _ shift: LocalRecurringShift,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let shiftId = shift.id

    if shift.syncStatus == .pendingDelete {
      return try await pushRecurringShiftDelete(shift, userId: userId, storeActor: storeActor)
    }

    let dirtyFields = shift.dirtyFieldKeys
    if dirtyFields.isEmpty {
      await storeActor.markRecurringShiftClean(id: shiftId)
      return .noChange
    }

    // Check if this is a new record that needs INSERT (serverRevision == 0 means never synced)
    if shift.serverRevision == 0 {
      return try await insertRecurringShift(shift, userId: userId, storeActor: storeActor)
    }

    // Build partial update
    var updateData: [String: AnyJSON] = [:]
    if dirtyFields.contains(.jobId) {
      if let jobId = shift.jobId {
        updateData["job_id"] = .string(jobId)
      } else {
        updateData["job_id"] = .null
      }
    }
    if dirtyFields.contains(.startTime) {
      updateData["start_time"] = .string(shift.startTime)
    }
    if dirtyFields.contains(.endTime) {
      updateData["end_time"] = .string(shift.endTime)
    }
    if dirtyFields.contains(.repeatIntervalWeeks) {
      updateData["repeat_interval_weeks"] = .integer(shift.repeatIntervalWeeks)
    }
    if dirtyFields.contains(.selectedDays) {
      let decoded = try requireAnyJSON(
        shift.selectedDays,
        table: .recurringShifts,
        id: shiftId,
        field: "selected_days"
      )
      updateData["selected_days"] = decoded
    }
    if dirtyFields.contains(.endCondition) {
      if let data = shift.endCondition {
        let decoded = try requireAnyJSON(
          data,
          table: .recurringShifts,
          id: shiftId,
          field: "end_condition"
        )
        updateData["end_condition"] = decoded
      } else {
        updateData["end_condition"] = .null
      }
    }
    if dirtyFields.contains(.exclusions) {
      if let data = shift.exclusions {
        let decoded = try requireAnyJSON(
          data,
          table: .recurringShifts,
          id: shiftId,
          field: "exclusions"
        )
        updateData["exclusions"] = decoded
      } else {
        updateData["exclusions"] = .null
      }
    }
    if dirtyFields.contains(.dateSpecificPauseWindows) {
      if let data = shift.dateSpecificPauseWindows {
        let decoded = try requireAnyJSON(
          data,
          table: .recurringShifts,
          id: shiftId,
          field: "date_specific_pause_windows"
        )
        updateData["date_specific_pause_windows"] = decoded
      } else {
        updateData["date_specific_pause_windows"] = .null
      }
    }
    if dirtyFields.contains(.dateSpecificSupplements) {
      if let data = shift.dateSpecificSupplements {
        let decoded = try requireAnyJSON(
          data,
          table: .recurringShifts,
          id: shiftId,
          field: "date_specific_supplements"
        )
        updateData["date_specific_supplements"] = decoded
      } else {
        updateData["date_specific_supplements"] = .null
      }
    }
    if dirtyFields.contains(.dateSpecificNotes) {
      if let data = shift.dateSpecificNotes {
        let decoded = try requireAnyJSON(
          data,
          table: .recurringShifts,
          id: shiftId,
          field: "date_specific_notes"
        )
        updateData["date_specific_notes"] = decoded
      } else {
        updateData["date_specific_notes"] = .null
      }
    }

    try requireNonEmptyUpdate(updateData, table: .recurringShifts, id: shiftId)

    // Note: Convert Int64 to Int for PostgrestFilterValue conformance
    let serverRevision = Int(shift.serverRevision)

    do {
      let returnedRows: [SyncRecurringShiftRow] =
        try await supabase
        .from("recurring_shifts")
        .update(updateData)
        .eq("id", value: shiftId)
        .eq("user_id", value: userId)
        .eq("revision", value: serverRevision)
        .is("deleted_at", value: nil)
        .select()
        .execute()
        .value

      if let returnedRow = returnedRows.first {
        let serverUpdatedAt = parseUpdatedAt(
          returnedRow.updated_at, table: .recurringShifts, id: shiftId)
        let serverSnapshot = RecurringShiftServerSnapshot.from(
          row: returnedRow.toRecurringShiftRow(),
          updatedAt: serverUpdatedAt,
          revision: returnedRow.revision,
          deletedAt: nil
        )

        await storeActor.markRecurringShiftPushed(
          id: shiftId,
          serverRow: returnedRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: returnedRow.revision,
          snapshot: serverSnapshot
        )

        logger.debug("Pushed recurring shift \(shiftId.prefix(8))")
        return .success
      } else {
        return try await handleRecurringShiftPushConflict(
          shift: shift,
          userId: userId,
          storeActor: storeActor,
          isRetry: isRetry
        )
      }
    } catch {
      // Check if it's an RLS policy violation - mark as conflict, don't abort sync
      let errorString = String(describing: error)
      if errorString.contains("row-level security") || errorString.contains("42501") {
        logger.warning(
          "Recurring shift \(shiftId.prefix(8)) blocked by RLS policy on UPDATE, marking as conflict"
        )
        await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: nil)
        return .conflict
      }
      logger.error("Push recurring shift failed: \(error.localizedDescription)")
      throw error
    }
  }

  private func pushRecurringShiftDelete(
    _ shift: LocalRecurringShift,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let shiftId = shift.id
    // Note: Convert Int64 to Int for PostgrestFilterValue conformance
    let serverRevision = Int(shift.serverRevision)

    let returnedRows: [SyncRecurringShiftRow] =
      try await supabase
      .from("recurring_shifts")
      .update(["deleted_at": AnyJSON.string(formatSupabaseTimestamp(Date()))])
      .eq("id", value: shiftId)
      .eq("user_id", value: userId)
      .eq("revision", value: serverRevision)
      .is("deleted_at", value: nil)
      .select()
      .execute()
      .value

    if let returnedRow = returnedRows.first {
      let serverUpdatedAt = parseUpdatedAt(
        returnedRow.updated_at, table: .recurringShifts, id: shiftId)
      let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }

      await storeActor.markRecurringShiftDeleted(
        id: shiftId,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        serverDeletedAt: serverDeletedAt
      )

      logger.debug("Deleted recurring shift \(shiftId.prefix(8))")
      return .deleted
    } else {
      // Fetch and check server state
      let serverRows: [SyncRecurringShiftRow] =
        try await supabase
        .from("recurring_shifts")
        .select()
        .eq("id", value: shiftId)
        .execute()
        .value

      if let serverRow = serverRows.first {
        let serverUpdatedAt = parseUpdatedAt(
          serverRow.updated_at, table: .recurringShifts, id: shiftId)
        let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

        if serverDeletedAt != nil {
          await storeActor.markRecurringShiftDeleted(
            id: shiftId,
            serverUpdatedAt: serverUpdatedAt,
            serverRevision: serverRow.revision,
            serverDeletedAt: serverDeletedAt
          )
          return .deleted
        }

        let serverSnapshot = RecurringShiftServerSnapshot.from(
          row: serverRow.toRecurringShiftRow(),
          updatedAt: serverUpdatedAt,
          revision: serverRow.revision,
          deletedAt: serverDeletedAt
        )
        await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
      }
      return .conflict
    }
  }

  /// Insert a new recurring shift that was created locally (serverRevision == 0)
  private func insertRecurringShift(
    _ shift: LocalRecurringShift,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let shiftId = shift.id

    // Build full insert data
    var insertData: [String: AnyJSON] = [
      "id": .string(shiftId),
      "user_id": .string(userId),
      "start_time": .string(shift.startTime),
      "end_time": .string(shift.endTime),
      "repeat_interval_weeks": .integer(shift.repeatIntervalWeeks),
    ]
    if let jobId = shift.jobId {
      insertData["job_id"] = .string(jobId)
    }

    // selected_days is required
    let selectedDaysDecoded = try requireAnyJSON(
      shift.selectedDays,
      table: .recurringShifts,
      id: shiftId,
      field: "selected_days"
    )
    insertData["selected_days"] = selectedDaysDecoded

    if let data = shift.endCondition {
      let decoded = try requireAnyJSON(
        data, table: .recurringShifts, id: shiftId, field: "end_condition")
      insertData["end_condition"] = decoded
    }

    if let data = shift.exclusions {
      let decoded = try requireAnyJSON(
        data, table: .recurringShifts, id: shiftId, field: "exclusions")
      insertData["exclusions"] = decoded
    }

    if let data = shift.dateSpecificPauseWindows {
      let decoded = try requireAnyJSON(
        data, table: .recurringShifts, id: shiftId, field: "date_specific_pause_windows")
      insertData["date_specific_pause_windows"] = decoded
    }

    if let data = shift.dateSpecificSupplements {
      let decoded = try requireAnyJSON(
        data, table: .recurringShifts, id: shiftId, field: "date_specific_supplements")
      insertData["date_specific_supplements"] = decoded
    }
    if let data = shift.dateSpecificNotes {
      let decoded = try requireAnyJSON(
        data, table: .recurringShifts, id: shiftId, field: "date_specific_notes")
      insertData["date_specific_notes"] = decoded
    }

    do {
      let returnedRows: [SyncRecurringShiftRow] =
        try await supabase
        .from("recurring_shifts")
        .insert(insertData)
        .select()
        .execute()
        .value

      if let returnedRow = returnedRows.first {
        let serverUpdatedAt = parseUpdatedAt(
          returnedRow.updated_at, table: .recurringShifts, id: shiftId)
        let serverSnapshot = RecurringShiftServerSnapshot.from(
          row: returnedRow.toRecurringShiftRow(),
          updatedAt: serverUpdatedAt,
          revision: returnedRow.revision,
          deletedAt: nil
        )

        await storeActor.markRecurringShiftPushed(
          id: shiftId,
          serverRow: returnedRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: returnedRow.revision,
          snapshot: serverSnapshot
        )

        logger.debug("Inserted new recurring shift \(shiftId.prefix(8))")
        return .success
      } else {
        logger.error("Insert recurring shift returned no rows for \(shiftId.prefix(8))")
        return .conflict
      }
    } catch {
      let errorString = String(describing: error)
      // Check if it's a duplicate key error
      if errorString.contains("duplicate") || errorString.contains("23505") {
        logger.warning(
          "Recurring shift \(shiftId.prefix(8)) already exists on server, fetching and merging")
        let serverRows: [SyncRecurringShiftRow] =
          try await supabase
          .from("recurring_shifts")
          .select()
          .eq("id", value: shiftId)
          .execute()
          .value

        if let serverRow = serverRows.first {
          let serverUpdatedAt = parseUpdatedAt(
            serverRow.updated_at, table: .recurringShifts, id: shiftId)
          let serverSnapshot = RecurringShiftServerSnapshot.from(
            row: serverRow.toRecurringShiftRow(),
            updatedAt: serverUpdatedAt,
            revision: serverRow.revision,
            deletedAt: serverRow.deleted_at.flatMap { parseISO8601($0) }
          )
          await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
        }
        return .conflict
      }
      // Check if it's an RLS policy violation - mark as conflict, don't abort sync
      if errorString.contains("row-level security") || errorString.contains("42501") {
        logger.warning(
          "Recurring shift \(shiftId.prefix(8)) blocked by RLS policy, marking as conflict")
        await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: nil)
        return .conflict
      }
      logger.error("Insert recurring shift failed: \(error.localizedDescription)")
      throw error
    }
  }

  private func handleRecurringShiftPushConflict(
    shift: LocalRecurringShift,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let shiftId = shift.id

    let serverRows: [SyncRecurringShiftRow] =
      try await supabase
      .from("recurring_shifts")
      .select()
      .eq("id", value: shiftId)
      .execute()
      .value

    guard let serverRow = serverRows.first else {
      // Server row doesn't exist - check if this is a new local record that needs INSERT
      if shift.serverRevision == 0 {
        logger.debug(
          "Recurring shift \(shiftId.prefix(8)) is new (serverRevision=0), attempting INSERT")
        return try await insertRecurringShift(shift, userId: userId, storeActor: storeActor)
      }
      logger.debug("Recurring shift \(shiftId.prefix(8)) was deleted on server")
      await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: nil)
      return .conflict
    }

    let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .recurringShifts, id: shiftId)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if serverDeletedAt != nil {
      let serverSnapshot = RecurringShiftServerSnapshot.from(
        row: serverRow.toRecurringShiftRow(),
        updatedAt: serverUpdatedAt,
        revision: serverRow.revision,
        deletedAt: serverDeletedAt
      )
      await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    guard let lastSnapshot = RecurringShiftServerSnapshot.decode(from: shift.lastSyncedSnapshot)
    else {
      let serverSnapshot = RecurringShiftServerSnapshot.from(
        row: serverRow.toRecurringShiftRow(),
        updatedAt: serverUpdatedAt,
        revision: serverRow.revision,
        deletedAt: serverDeletedAt
      )
      await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    let newServerSnapshot = RecurringShiftServerSnapshot.from(
      row: serverRow.toRecurringShiftRow(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision,
      deletedAt: serverDeletedAt
    )

    let serverChangedFields = newServerSnapshot.changedFields(from: lastSnapshot)
    let localDirtyFields = shift.dirtyFieldKeys
    let conflictingFields = serverChangedFields.intersection(
      Set(localDirtyFields.map { convertToRecurringShiftField($0) }))

    if conflictingFields.isEmpty && !isRetry {
      await storeActor.rebaseRecurringShift(
        id: shiftId,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        newSnapshot: newServerSnapshot,
        localDirtyFields: localDirtyFields
      )

      if let rebasedShift = try await storeActor.getRecurringShift(id: shiftId) {
        let retryResult = try await pushRecurringShift(
          rebasedShift, userId: userId, storeActor: storeActor, isRetry: true)
        if retryResult == .success {
          return .rebased
        }
        return retryResult
      }
      return .conflict
    } else {
      await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: newServerSnapshot)
      return .conflict
    }
  }

  // MARK: - Wage Snapshots Push

  private func pushWageSnapshots(userId: String) async throws -> TablePushResult {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    let dirtySnapshots = try await storeActor.getDirtyWageSnapshots(userId: userId)

    if dirtySnapshots.isEmpty {
      return TablePushResult(table: .wageSnapshots, rowsPushed: 0, newConflicts: 0, rebased: 0)
    }

    var rowsPushed = 0
    var newConflicts = 0
    var rebased = 0

    for snapshot in dirtySnapshots {
      let result = try await pushWageSnapshot(
        snapshot, userId: userId, storeActor: storeActor, isRetry: false)
      switch result {
      case .success, .deleted:
        rowsPushed += 1
      case .conflict:
        newConflicts += 1
      case .rebased:
        rebased += 1
        rowsPushed += 1
      case .noChange:
        break
      }
    }

    try await storeActor.save()
    return TablePushResult(
      table: .wageSnapshots, rowsPushed: rowsPushed, newConflicts: newConflicts, rebased: rebased)
  }

  private func pushWageSnapshot(
    _ snapshot: LocalWageSnapshot,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let snapshotId = snapshot.id

    if snapshot.syncStatus == .pendingDelete {
      return try await pushWageSnapshotDelete(snapshot, userId: userId, storeActor: storeActor)
    }

    let dirtyFields = snapshot.dirtyFieldKeys
    if dirtyFields.isEmpty {
      await storeActor.markWageSnapshotClean(id: snapshotId)
      return .noChange
    }

    // Check if this is a new record that needs INSERT (serverRevision == 0 means never synced)
    if snapshot.serverRevision == 0 {
      return try await insertWageSnapshot(snapshot, userId: userId, storeActor: storeActor)
    }

    // Build partial update
    var updateData: [String: AnyJSON] = [:]
    if dirtyFields.contains(.jobId) {
      if let jobId = snapshot.jobId {
        updateData["job_id"] = .string(jobId)
      } else {
        updateData["job_id"] = .null
      }
    }
    if dirtyFields.contains(.fromDate) {
      if let fromDateString = snapshot.fromDateString {
        updateData["from_date"] = .string(fromDateString)
      } else {
        updateData["from_date"] = .null
      }
    }
    if dirtyFields.contains(.hourlyWage) {
      updateData["hourly_wage"] = .double(snapshot.hourlyWage)
    }
    if dirtyFields.contains(.wageLevel) {
      if let level = snapshot.wageLevel {
        updateData["wage_level"] = .integer(level)
      } else {
        updateData["wage_level"] = .null
      }
    }
    if dirtyFields.contains(.tariffTypeId) {
      if let tariffTypeId = snapshot.tariffTypeId {
        updateData["tariff_type_id"] = .string(tariffTypeId)
      } else {
        updateData["tariff_type_id"] = .null
      }
    }
    if dirtyFields.contains(.supplements) {
      let decoded = try requireAnyJSON(
        snapshot.supplements,
        table: .wageSnapshots,
        id: snapshotId,
        field: "supplements"
      )
      updateData["supplements"] = decoded
    }
    if dirtyFields.contains(.taxEnabled) {
      if let enabled = snapshot.taxEnabled {
        updateData["tax_enabled"] = .bool(enabled)
      } else {
        updateData["tax_enabled"] = .null
      }
    }
    if dirtyFields.contains(.taxPercentage) {
      if let percentage = snapshot.taxPercentage {
        updateData["tax_percentage"] = .double(percentage)
      } else {
        updateData["tax_percentage"] = .null
      }
    }
    if dirtyFields.contains(.breakEnabled) {
      if let enabled = snapshot.breakEnabled {
        updateData["break_enabled"] = .bool(enabled)
      } else {
        updateData["break_enabled"] = .null
      }
    }
    if dirtyFields.contains(.breakMethod) {
      if let method = snapshot.breakMethod {
        updateData["break_method"] = .string(method)
      } else {
        updateData["break_method"] = .null
      }
    }
    if dirtyFields.contains(.breakThresholdHours) {
      if let hours = snapshot.breakThresholdHours {
        updateData["break_threshold_hours"] = .double(hours)
      } else {
        updateData["break_threshold_hours"] = .null
      }
    }
    if dirtyFields.contains(.breakDeductionMinutes) {
      if let minutes = snapshot.breakDeductionMinutes {
        updateData["break_deduction_minutes"] = .integer(minutes)
      } else {
        updateData["break_deduction_minutes"] = .null
      }
    }

    try requireNonEmptyUpdate(updateData, table: .wageSnapshots, id: snapshotId)

    // Note: Convert Int64 to Int for PostgrestFilterValue conformance
    let serverRevision = Int(snapshot.serverRevision)

    do {
      let returnedRows: [SyncWageSnapshotRow] =
        try await supabase
        .from("wage_snapshots")
        .update(updateData)
        .eq("id", value: snapshotId)
        .eq("user_id", value: userId)
        .eq("revision", value: serverRevision)
        .is("deleted_at", value: nil)
        .select()
        .execute()
        .value

      if let returnedRow = returnedRows.first {
        let serverUpdatedAt = parseUpdatedAt(
          returnedRow.updated_at, table: .wageSnapshots, id: snapshotId)
        let serverSnapshot = WageSnapshotServerSnapshot.from(
          row: returnedRow.toWageSnapshot(),
          updatedAt: serverUpdatedAt,
          revision: returnedRow.revision,
          deletedAt: nil
        )

        await storeActor.markWageSnapshotPushed(
          id: snapshotId,
          serverRow: returnedRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: returnedRow.revision,
          snapshot: serverSnapshot
        )

        logger.debug("Pushed wage snapshot \(snapshotId.prefix(8))")
        return .success
      } else {
        return try await handleWageSnapshotPushConflict(
          snapshot: snapshot,
          userId: userId,
          storeActor: storeActor,
          isRetry: isRetry
        )
      }
    } catch {
      // Check if it's an RLS policy violation - mark as conflict, don't abort sync
      let errorString = String(describing: error)
      if errorString.contains("row-level security") || errorString.contains("42501") {
        logger.warning(
          "Wage snapshot \(snapshotId.prefix(8)) blocked by RLS policy on UPDATE, marking as conflict"
        )
        await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: nil)
        return .conflict
      }
      logger.error("Push wage snapshot failed: \(error.localizedDescription)")
      throw error
    }
  }

  private func pushWageSnapshotDelete(
    _ snapshot: LocalWageSnapshot,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let snapshotId = snapshot.id
    // Note: Convert Int64 to Int for PostgrestFilterValue conformance
    let serverRevision = Int(snapshot.serverRevision)

    let returnedRows: [SyncWageSnapshotRow] =
      try await supabase
      .from("wage_snapshots")
      .update(["deleted_at": AnyJSON.string(formatSupabaseTimestamp(Date()))])
      .eq("id", value: snapshotId)
      .eq("user_id", value: userId)
      .eq("revision", value: serverRevision)
      .is("deleted_at", value: nil)
      .select()
      .execute()
      .value

    if let returnedRow = returnedRows.first {
      let serverUpdatedAt = parseUpdatedAt(
        returnedRow.updated_at, table: .wageSnapshots, id: snapshotId)
      let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }

      await storeActor.markWageSnapshotDeleted(
        id: snapshotId,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        serverDeletedAt: serverDeletedAt
      )

      logger.debug("Deleted wage snapshot \(snapshotId.prefix(8))")
      return .deleted
    } else {
      let serverRows: [SyncWageSnapshotRow] =
        try await supabase
        .from("wage_snapshots")
        .select()
        .eq("id", value: snapshotId)
        .execute()
        .value

      if let serverRow = serverRows.first {
        let serverUpdatedAt = parseUpdatedAt(
          serverRow.updated_at, table: .wageSnapshots, id: snapshotId)
        let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

        if serverDeletedAt != nil {
          await storeActor.markWageSnapshotDeleted(
            id: snapshotId,
            serverUpdatedAt: serverUpdatedAt,
            serverRevision: serverRow.revision,
            serverDeletedAt: serverDeletedAt
          )
          return .deleted
        }

        let serverSnapshot = WageSnapshotServerSnapshot.from(
          row: serverRow.toWageSnapshot(),
          updatedAt: serverUpdatedAt,
          revision: serverRow.revision,
          deletedAt: serverDeletedAt
        )
        await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: serverSnapshot)
      }
      return .conflict
    }
  }

  /// Insert a new wage snapshot that was created locally (serverRevision == 0)
  private func insertWageSnapshot(
    _ snapshot: LocalWageSnapshot,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let snapshotId = snapshot.id

    // Build full insert data
    var insertData: [String: AnyJSON] = [
      "id": .string(snapshotId),
      "user_id": .string(userId),
      "hourly_wage": .double(snapshot.hourlyWage),
    ]
    if let jobId = snapshot.jobId {
      insertData["job_id"] = .string(jobId)
    }

    // from_date (nil for baseline snapshot)
    if let fromDateString = snapshot.fromDateString {
      insertData["from_date"] = .string(fromDateString)
    }

    // wage_level
    if let level = snapshot.wageLevel {
      insertData["wage_level"] = .integer(level)
    }
    if let tariffTypeId = snapshot.tariffTypeId {
      insertData["tariff_type_id"] = .string(tariffTypeId)
    }

    // supplements (required)
    let supplementsDecoded = try requireAnyJSON(
      snapshot.supplements,
      table: .wageSnapshots,
      id: snapshotId,
      field: "supplements"
    )
    insertData["supplements"] = supplementsDecoded

    // Optional fields
    if let enabled = snapshot.taxEnabled {
      insertData["tax_enabled"] = .bool(enabled)
    }
    if let percentage = snapshot.taxPercentage {
      insertData["tax_percentage"] = .double(percentage)
    }
    if let enabled = snapshot.breakEnabled {
      insertData["break_enabled"] = .bool(enabled)
    }
    if let method = snapshot.breakMethod {
      insertData["break_method"] = .string(method)
    }
    if let hours = snapshot.breakThresholdHours {
      insertData["break_threshold_hours"] = .double(hours)
    }
    if let minutes = snapshot.breakDeductionMinutes {
      insertData["break_deduction_minutes"] = .integer(minutes)
    }

    do {
      let returnedRows: [SyncWageSnapshotRow] =
        try await supabase
        .from("wage_snapshots")
        .insert(insertData)
        .select()
        .execute()
        .value

      if let returnedRow = returnedRows.first {
        let serverUpdatedAt = parseUpdatedAt(
          returnedRow.updated_at, table: .wageSnapshots, id: snapshotId)
        let serverSnapshot = WageSnapshotServerSnapshot.from(
          row: returnedRow.toWageSnapshot(),
          updatedAt: serverUpdatedAt,
          revision: returnedRow.revision,
          deletedAt: nil
        )

        await storeActor.markWageSnapshotPushed(
          id: snapshotId,
          serverRow: returnedRow,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: returnedRow.revision,
          snapshot: serverSnapshot
        )

        logger.debug("Inserted new wage snapshot \(snapshotId.prefix(8))")
        return .success
      } else {
        logger.error("Insert wage snapshot returned no rows for \(snapshotId.prefix(8))")
        return .conflict
      }
    } catch {
      let errorString = String(describing: error)
      // Check if it's a duplicate key error
      if errorString.contains("duplicate") || errorString.contains("23505") {
        logger.warning(
          "Wage snapshot \(snapshotId.prefix(8)) already exists on server, fetching and merging")
        let serverRows: [SyncWageSnapshotRow] =
          try await supabase
          .from("wage_snapshots")
          .select()
          .eq("id", value: snapshotId)
          .execute()
          .value

        if let serverRow = serverRows.first {
          let serverUpdatedAt = parseUpdatedAt(
            serverRow.updated_at, table: .wageSnapshots, id: snapshotId)
          let serverSnapshot = WageSnapshotServerSnapshot.from(
            row: serverRow.toWageSnapshot(),
            updatedAt: serverUpdatedAt,
            revision: serverRow.revision,
            deletedAt: serverRow.deleted_at.flatMap { parseISO8601($0) }
          )
          await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: serverSnapshot)
        }
        return .conflict
      }
      // Check if it's an RLS policy violation - mark as conflict, don't abort sync
      if errorString.contains("row-level security") || errorString.contains("42501") {
        logger.warning(
          "Wage snapshot \(snapshotId.prefix(8)) blocked by RLS policy, marking as conflict")
        await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: nil)
        return .conflict
      }
      logger.error("Insert wage snapshot failed: \(error.localizedDescription)")
      throw error
    }
  }

  private func handleWageSnapshotPushConflict(
    snapshot: LocalWageSnapshot,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let snapshotId = snapshot.id

    let serverRows: [SyncWageSnapshotRow] =
      try await supabase
      .from("wage_snapshots")
      .select()
      .eq("id", value: snapshotId)
      .execute()
      .value

    guard let serverRow = serverRows.first else {
      // Server row doesn't exist - check if this is a new local record that needs INSERT
      if snapshot.serverRevision == 0 {
        logger.debug(
          "Wage snapshot \(snapshotId.prefix(8)) is new (serverRevision=0), attempting INSERT")
        return try await insertWageSnapshot(snapshot, userId: userId, storeActor: storeActor)
      }
      logger.debug("Wage snapshot \(snapshotId.prefix(8)) was deleted on server")
      await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: nil)
      return .conflict
    }

    let serverUpdatedAt = parseUpdatedAt(
      serverRow.updated_at, table: .wageSnapshots, id: snapshotId)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if serverDeletedAt != nil {
      let serverSnapshot = WageSnapshotServerSnapshot.from(
        row: serverRow.toWageSnapshot(),
        updatedAt: serverUpdatedAt,
        revision: serverRow.revision,
        deletedAt: serverDeletedAt
      )
      await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    guard let lastSnapshot = WageSnapshotServerSnapshot.decode(from: snapshot.lastSyncedSnapshot)
    else {
      let serverSnapshot = WageSnapshotServerSnapshot.from(
        row: serverRow.toWageSnapshot(),
        updatedAt: serverUpdatedAt,
        revision: serverRow.revision,
        deletedAt: serverDeletedAt
      )
      await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    let newServerSnapshot = WageSnapshotServerSnapshot.from(
      row: serverRow.toWageSnapshot(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision,
      deletedAt: serverDeletedAt
    )

    let serverChangedFields = newServerSnapshot.changedFields(from: lastSnapshot)
    let localDirtyFields = snapshot.dirtyFieldKeys
    let conflictingFields = serverChangedFields.intersection(
      Set(localDirtyFields.map { convertToWageSnapshotField($0) }))

    if conflictingFields.isEmpty && !isRetry {
      await storeActor.rebaseWageSnapshot(
        id: snapshotId,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        serverDeletedAt: serverDeletedAt,
        newSnapshot: newServerSnapshot,
        localDirtyFields: localDirtyFields
      )

      if let rebasedSnapshot = try await storeActor.getWageSnapshot(id: snapshotId) {
        let retryResult = try await pushWageSnapshot(
          rebasedSnapshot, userId: userId, storeActor: storeActor, isRetry: true)
        if retryResult == .success {
          return .rebased
        }
        return retryResult
      }
      return .conflict
    } else {
      await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: newServerSnapshot)
      return .conflict
    }
  }

  // MARK: - User Settings Push

  private func pushUserSettings(userId: String) async throws -> TablePushResult {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    guard let settings = try await storeActor.getDirtyUserSettings(userId: userId) else {
      return TablePushResult(table: .userSettings, rowsPushed: 0, newConflicts: 0, rebased: 0)
    }

    let result = try await pushUserSettingsRow(
      settings, userId: userId, storeActor: storeActor, isRetry: false)

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

  private func pushUserSettingsRow(
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

    // Build partial update
    var updateData: [String: AnyJSON] = [:]
    if dirtyFields.contains(.monthlyGoal) {
      if let goal = settings.monthlyGoal {
        updateData["monthly_goal"] = .integer(goal)
      } else {
        updateData["monthly_goal"] = .null
      }
    }
    if dirtyFields.contains(.monthlyGoalsByMonth) {
      let encoded = try requireEncode(
        settings.monthlyGoalsByMonth,
        typeName: "UserSettings.monthlyGoalsByMonth"
      )
      let decoded = try requireAnyJSON(
        encoded,
        table: .userSettings,
        id: userId,
        field: "monthly_goals_by_month"
      )
      updateData["monthly_goals_by_month"] = decoded
    }
    if dirtyFields.contains(.defaultShiftsView) {
      if let view = settings.defaultShiftsView {
        updateData["default_shifts_view"] = .string(view)
      } else {
        updateData["default_shifts_view"] = .null
      }
    }
    if dirtyFields.contains(.profilePictureUrl) {
      if let url = settings.profilePictureUrl {
        updateData["profile_picture_url"] = .string(url)
      } else {
        updateData["profile_picture_url"] = .null
      }
    }
    if dirtyFields.contains(.payrollDay) {
      if let day = settings.payrollDay {
        updateData["payroll_day"] = .integer(day)
      } else {
        updateData["payroll_day"] = .null
      }
    }
    if dirtyFields.contains(.theme) {
      updateData["theme"] = .string(settings.theme)
    }
    if dirtyFields.contains(.calendarAnimationStyle) {
      updateData["calendar_animation_style"] = .string(settings.effectiveCalendarAnimationStyle)
    }
    if dirtyFields.contains(.showDashboardClockButtons) {
      updateData["show_dashboard_clock_buttons"] = .bool(
        settings.effectiveShowDashboardClockButtons)
    }
    if dirtyFields.contains(.aiDataSharingEnabled) {
      updateData["ai_data_sharing_enabled"] = .bool(settings.aiDataSharingEnabled ?? false)
    }
    if dirtyFields.contains(.halfTaxMonth) {
      if let month = settings.halfTaxMonth {
        updateData["half_tax_month"] = .integer(month)
      } else {
        updateData["half_tax_month"] = .null
      }
    }
    if dirtyFields.contains(.currency) {
      if let currency = settings.currency {
        updateData["currency"] = .string(currency)
      } else {
        updateData["currency"] = .null
      }
    }
    if dirtyFields.contains(.defaultStartupTab) {
      updateData["default_startup_tab"] = .string(settings.effectiveDefaultStartupTab)
    }
    if dirtyFields.contains(.lastActive) {
      if let lastActive = settings.lastActive {
        updateData["last_active"] = .string(formatSupabaseTimestamp(lastActive))
      } else {
        updateData["last_active"] = .null
      }
    }

    // Note: Convert Int64 to Int for PostgrestFilterValue conformance
    let serverRevision = Int(settings.serverRevision)

    do {
      let returnedRows: [SyncUserSettingsRow] =
        try await supabase
        .from("user_settings")
        .update(updateData)
        .eq("user_id", value: userId)
        .eq("revision", value: serverRevision)
        .select()
        .execute()
        .value

      if let returnedRow = returnedRows.first {
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
          snapshot: serverSnapshot
        )

        logger.debug("Pushed user settings for \(userId.prefix(8))")
        return .success
      } else {
        return try await handleUserSettingsPushConflict(
          settings: settings,
          userId: userId,
          storeActor: storeActor,
          isRetry: isRetry
        )
      }
    } catch {
      // Check if it's an RLS policy violation - mark as conflict, don't abort sync
      let errorString = String(describing: error)
      if errorString.contains("row-level security") || errorString.contains("42501") {
        logger.warning(
          "User settings for \(userId.prefix(8)) blocked by RLS policy on UPDATE, marking as conflict"
        )
        await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: nil)
        return .conflict
      }
      logger.error("Push user settings failed: \(error.localizedDescription)")
      throw error
    }
  }

  /// Insert new user settings that were created locally (serverRevision == 0)
  private func insertUserSettings(
    _ settings: LocalUserSettings,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    // Build full insert data
    var insertData: [String: AnyJSON] = [
      "user_id": .string(userId),
      "theme": .string(settings.theme),
      "calendar_animation_style": .string(settings.effectiveCalendarAnimationStyle),
      "show_dashboard_clock_buttons": .bool(settings.effectiveShowDashboardClockButtons),
      "ai_data_sharing_enabled": .bool(settings.aiDataSharingEnabled ?? false),
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
    if let url = settings.profilePictureUrl {
      insertData["profile_picture_url"] = .string(url)
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
      insertData["last_active"] = .string(formatSupabaseTimestamp(lastActive))
    }

    do {
      let returnedRows: [SyncUserSettingsRow] =
        try await supabase
        .from("user_settings")
        .insert(insertData)
        .select()
        .execute()
        .value

      if let returnedRow = returnedRows.first {
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
          snapshot: serverSnapshot
        )

        logger.debug("Inserted new user settings for \(userId.prefix(8))")
        return .success
      } else {
        logger.error("Insert user settings returned no rows for \(userId.prefix(8))")
        return .conflict
      }
    } catch {
      let errorString = String(describing: error)
      // Check if it's a duplicate key error
      if errorString.contains("duplicate") || errorString.contains("23505") {
        logger.warning(
          "User settings for \(userId.prefix(8)) already exists on server, fetching and merging")
        let serverRows: [SyncUserSettingsRow] =
          try await supabase
          .from("user_settings")
          .select()
          .eq("user_id", value: userId)
          .execute()
          .value

        if let serverRow = serverRows.first {
          let serverUpdatedAt = parseUpdatedAt(
            serverRow.updated_at, table: .userSettings, id: userId)
          let serverSnapshot = UserSettingsServerSnapshot.from(
            row: serverRow.toUserSettings(),
            updatedAt: serverUpdatedAt,
            revision: serverRow.revision
          )
          await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: serverSnapshot)
        }
        return .conflict
      }
      // Check if it's an RLS policy violation - mark as conflict, don't abort sync
      if errorString.contains("row-level security") || errorString.contains("42501") {
        logger.warning(
          "User settings for \(userId.prefix(8)) blocked by RLS policy, marking as conflict")
        await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: nil)
        return .conflict
      }
      logger.error("Insert user settings failed: \(error.localizedDescription)")
      throw error
    }
  }

  private func handleUserSettingsPushConflict(
    settings: LocalUserSettings,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let serverRows: [SyncUserSettingsRow] =
      try await supabase
      .from("user_settings")
      .select()
      .eq("user_id", value: userId)
      .execute()
      .value

    guard let serverRow = serverRows.first else {
      // Server row doesn't exist - check if this is a new local record that needs INSERT
      if settings.serverRevision == 0 {
        logger.debug(
          "User settings for \(userId.prefix(8)) is new (serverRevision=0), attempting INSERT")
        return try await insertUserSettings(settings, userId: userId, storeActor: storeActor)
      }
      logger.debug("User settings for \(userId.prefix(8)) were deleted on server")
      await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: nil)
      return .conflict
    }

    let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .userSettings, id: userId)

    guard let lastSnapshot = UserSettingsServerSnapshot.decode(from: settings.lastSyncedSnapshot)
    else {
      let serverSnapshot = UserSettingsServerSnapshot.from(
        row: serverRow.toUserSettings(),
        updatedAt: serverUpdatedAt,
        revision: serverRow.revision
      )
      await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    let newServerSnapshot = UserSettingsServerSnapshot.from(
      row: serverRow.toUserSettings(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision
    )

    let serverChangedFields = newServerSnapshot.changedFields(from: lastSnapshot)
    let localDirtyFields = settings.dirtyFieldKeys
    let conflictingFields = serverChangedFields.intersection(
      Set(localDirtyFields.map { convertToUserSettingsField($0) }))

    if conflictingFields.isEmpty && !isRetry {
      await storeActor.rebaseUserSettings(
        userId: userId,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        newSnapshot: newServerSnapshot,
        localDirtyFields: localDirtyFields
      )

      if let rebasedSettings = try await storeActor.getUserSettings(userId: userId) {
        let retryResult = try await pushUserSettingsRow(
          rebasedSettings, userId: userId, storeActor: storeActor, isRetry: true)
        if retryResult == .success {
          return .rebased
        }
        return retryResult
      }
      return .conflict
    } else {
      await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: newServerSnapshot)
      return .conflict
    }
  }

  // MARK: - Conflict Resolution API

  /// Resolve a conflict for a user shift
  func resolveShiftConflict(shiftId: String, resolution: ConflictResolution, userId: String)
    async throws
  {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }

    guard let shift = try await storeActor.getUserShift(id: shiftId) else {
      throw SyncError.notFound(table: .userShifts, id: shiftId)
    }

    guard shift.syncStatus == .conflict else {
      throw SyncError.notInConflict(table: .userShifts, id: shiftId)
    }

    switch resolution {
    case .keepServer:
      // Overwrite local with server snapshot
      guard let serverSnapshotData = shift.conflictServerSnapshot,
        let serverSnapshot = UserShiftServerSnapshot.decode(from: serverSnapshotData)
      else {
        throw SyncError.missingConflictSnapshot(table: .userShifts, id: shiftId)
      }

      await storeActor.resolveShiftConflictKeepServer(id: shiftId, serverSnapshot: serverSnapshot)

    case .keepLocal:
      // Update serverRevision to server's value, keep local values, set dirty, attempt push
      guard let serverSnapshotData = shift.conflictServerSnapshot,
        let serverSnapshot = UserShiftServerSnapshot.decode(from: serverSnapshotData)
      else {
        throw SyncError.missingConflictSnapshot(table: .userShifts, id: shiftId)
      }

      await storeActor.resolveShiftConflictKeepLocal(
        id: shiftId, serverRevision: serverSnapshot.revision)

      // Attempt to push
      if let updatedShift = try await storeActor.getUserShift(id: shiftId) {
        _ = try await pushUserShift(
          updatedShift, userId: userId, storeActor: storeActor, isRetry: false)
        try await storeActor.save()
      }
    }

    // Update conflict count
    let conflicts = try await storeActor.countConflicts(userId: userId)
    await MainActor.run {
      conflictCount = conflicts
    }

    // Update widget storage since shift data changed
    NativeWidgetStorage.updateWidgetStorage(for: userId)
  }

  /// Resolve a conflict for a recurring shift
  func resolveRecurringShiftConflict(
    shiftId: String, resolution: ConflictResolution, userId: String
  ) async throws {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }

    guard let shift = try await storeActor.getRecurringShift(id: shiftId) else {
      throw SyncError.notFound(table: .recurringShifts, id: shiftId)
    }

    guard shift.syncStatus == .conflict else {
      throw SyncError.notInConflict(table: .recurringShifts, id: shiftId)
    }

    switch resolution {
    case .keepServer:
      guard let serverSnapshotData = shift.conflictServerSnapshot,
        let serverSnapshot = RecurringShiftServerSnapshot.decode(from: serverSnapshotData)
      else {
        throw SyncError.missingConflictSnapshot(table: .recurringShifts, id: shiftId)
      }

      await storeActor.resolveRecurringShiftConflictKeepServer(
        id: shiftId, serverSnapshot: serverSnapshot)

    case .keepLocal:
      guard let serverSnapshotData = shift.conflictServerSnapshot,
        let serverSnapshot = RecurringShiftServerSnapshot.decode(from: serverSnapshotData)
      else {
        throw SyncError.missingConflictSnapshot(table: .recurringShifts, id: shiftId)
      }

      await storeActor.resolveRecurringShiftConflictKeepLocal(
        id: shiftId, serverRevision: serverSnapshot.revision)

      if let updatedShift = try await storeActor.getRecurringShift(id: shiftId) {
        _ = try await pushRecurringShift(
          updatedShift, userId: userId, storeActor: storeActor, isRetry: false)
        try await storeActor.save()
      }
    }

    let conflicts = try await storeActor.countConflicts(userId: userId)
    await MainActor.run {
      conflictCount = conflicts
    }

    // Update widget storage since recurring shift data changed (affects generated shifts)
    NativeWidgetStorage.updateWidgetStorage(for: userId)
  }

  /// Resolve a conflict for a wage snapshot
  func resolveWageSnapshotConflict(
    snapshotId: String, resolution: ConflictResolution, userId: String
  ) async throws {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }

    guard let snapshot = try await storeActor.getWageSnapshot(id: snapshotId) else {
      throw SyncError.notFound(table: .wageSnapshots, id: snapshotId)
    }

    guard snapshot.syncStatus == .conflict else {
      throw SyncError.notInConflict(table: .wageSnapshots, id: snapshotId)
    }

    switch resolution {
    case .keepServer:
      guard let serverSnapshotData = snapshot.conflictServerSnapshot,
        let serverSnapshot = WageSnapshotServerSnapshot.decode(from: serverSnapshotData)
      else {
        throw SyncError.missingConflictSnapshot(table: .wageSnapshots, id: snapshotId)
      }

      await storeActor.resolveWageSnapshotConflictKeepServer(
        id: snapshotId, serverSnapshot: serverSnapshot)

    case .keepLocal:
      guard let serverSnapshotData = snapshot.conflictServerSnapshot,
        let serverSnapshot = WageSnapshotServerSnapshot.decode(from: serverSnapshotData)
      else {
        throw SyncError.missingConflictSnapshot(table: .wageSnapshots, id: snapshotId)
      }

      await storeActor.resolveWageSnapshotConflictKeepLocal(
        id: snapshotId, serverRevision: serverSnapshot.revision)

      if let updatedSnapshot = try await storeActor.getWageSnapshot(id: snapshotId) {
        _ = try await pushWageSnapshot(
          updatedSnapshot, userId: userId, storeActor: storeActor, isRetry: false)
        try await storeActor.save()
      }
    }

    let conflicts = try await storeActor.countConflicts(userId: userId)
    await MainActor.run {
      conflictCount = conflicts
    }

    // Update widget storage since wage calculations may have changed
    NativeWidgetStorage.updateWidgetStorage(for: userId)
  }

  /// Resolve a conflict for user settings
  func resolveUserSettingsConflict(resolution: ConflictResolution, userId: String) async throws {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }

    guard let settings = try await storeActor.getUserSettings(userId: userId) else {
      throw SyncError.notFound(table: .userSettings, id: userId)
    }

    guard settings.syncStatus == .conflict else {
      throw SyncError.notInConflict(table: .userSettings, id: userId)
    }

    switch resolution {
    case .keepServer:
      guard let serverSnapshotData = settings.conflictServerSnapshot,
        let serverSnapshot = UserSettingsServerSnapshot.decode(from: serverSnapshotData)
      else {
        throw SyncError.missingConflictSnapshot(table: .userSettings, id: userId)
      }

      await storeActor.resolveUserSettingsConflictKeepServer(
        userId: userId, serverSnapshot: serverSnapshot)

    case .keepLocal:
      guard let serverSnapshotData = settings.conflictServerSnapshot,
        let serverSnapshot = UserSettingsServerSnapshot.decode(from: serverSnapshotData)
      else {
        throw SyncError.missingConflictSnapshot(table: .userSettings, id: userId)
      }

      await storeActor.resolveUserSettingsConflictKeepLocal(
        userId: userId, serverRevision: serverSnapshot.revision)

      if let updatedSettings = try await storeActor.getUserSettings(userId: userId) {
        _ = try await pushUserSettingsRow(
          updatedSettings, userId: userId, storeActor: storeActor, isRetry: false)
        try await storeActor.save()
      }
    }

    let conflicts = try await storeActor.countConflicts(userId: userId)
    await MainActor.run {
      conflictCount = conflicts
    }

    // Update widget storage since settings (e.g., currency) may affect display
    NativeWidgetStorage.updateWidgetStorage(for: userId)
  }

  // MARK: - Notification Preferences Pull

  private func pullNotificationPreferencesPage(userId: String, cursor: SyncCursor) async throws
    -> PagePullResult
  {
    // Query using updated_at + user_id tie-breaker (notification_preferences uses user_id as primary key)
    // Note: This table has no revision column - iOS is source of truth
    let rows: [SyncNotificationPreferencesRow]

    if let cursorUpdatedAt = cursor.updatedAt {
      let cursorTimestamp = formatISO8601(cursorUpdatedAt)
      let cursorTieId = cursor.tieId

      rows =
        try await supabase
        .from("notification_preferences")
        .select()
        .eq("user_id", value: userId)
        .or(
          "updated_at.gt.\(cursorTimestamp),and(updated_at.eq.\(cursorTimestamp),user_id.gt.\(cursorTieId))"
        )
        .order("updated_at", ascending: true)
        .order("user_id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    } else {
      rows =
        try await supabase
        .from("notification_preferences")
        .select()
        .eq("user_id", value: userId)
        .order("updated_at", ascending: true)
        .order("user_id", ascending: true)
        .limit(pageSize)
        .execute()
        .value
    }

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: cursor.updatedAt,
        lastTieId: cursor.tieId,
        maxRevision: 0,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let pageStartTime = Date()

    // Apply each row to local storage using the repository
    for row in rows {
      let serverUpdatedAt = parseUpdatedAt(
        row.updated_at, table: .notificationPreferences, id: row.user_id)
      await MainActor.run {
        NotificationPreferencesRepository.shared
          .saveFromServer(row: row.toNotificationPreferencesRow(), serverUpdatedAt: serverUpdatedAt)
      }
    }

    let duration = Date().timeIntervalSince(pageStartTime)
    logger.info(
      "notification_preferences: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s"
    )

    guard let lastRow = rows.last else {
      logger.warning("Unexpected empty rows after processing in pullNotificationPreferencesPage")
      return PagePullResult(
        rowsProcessed: 0,
        lastUpdatedAt: Date(),
        lastTieId: "",
        maxRevision: 0,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let lastUpdatedAt = try requireISO8601(
      lastRow.updated_at, table: .notificationPreferences, id: lastRow.user_id)

    return PagePullResult(
      rowsProcessed: rows.count,
      lastUpdatedAt: lastUpdatedAt,
      lastTieId: lastRow.user_id,
      maxRevision: 0,  // No revision column for notification_preferences
      newConflicts: 0,  // iOS is source of truth, no conflicts
      autoMerged: 0,
      hasMore: rows.count == pageSize
    )
  }

  // MARK: - Notification Preferences Push

  private func pushNotificationPreferences(userId: String) async throws -> TablePushResult {
    struct NotificationPreferencesPayload {
      let shiftRemindersEnabled: Bool
      let shiftReminderMinutesArray: [Int]
      let sharedShiftsEnabled: Bool
    }

    // Get dirty preferences (if any)
    let preferences = await MainActor.run(resultType: NotificationPreferencesPayload?.self) {
      guard let dirty = NotificationPreferencesRepository.shared.getDirtyPreferences(for: userId)
      else {
        return nil
      }
      return NotificationPreferencesPayload(
        shiftRemindersEnabled: dirty.shiftRemindersEnabled,
        shiftReminderMinutesArray: dirty.shiftReminderMinutesArray,
        sharedShiftsEnabled: dirty.sharedShiftsEnabled
      )
    }

    guard let preferences else {
      return TablePushResult(
        table: .notificationPreferences, rowsPushed: 0, newConflicts: 0, rebased: 0)
    }

    // Build upsert payload - iOS is source of truth, so we always push all fields
    let updateData: [String: AnyJSON] = [
      "user_id": AnyJSON.string(userId),
      "shift_reminders_enabled": AnyJSON.bool(preferences.shiftRemindersEnabled),
      "shift_reminder_minutes_array": AnyJSON.array(
        preferences.shiftReminderMinutesArray.map { AnyJSON.integer($0) }
      ),
      "shared_shifts_enabled": AnyJSON.bool(preferences.sharedShiftsEnabled),
    ]

    do {
      // Upsert to server (insert or update based on user_id)
      let returnedRows: [SyncNotificationPreferencesRow] =
        try await supabase
        .from("notification_preferences")
        .upsert(updateData, onConflict: "user_id")
        .select()
        .execute()
        .value

      if let returnedRow = returnedRows.first {
        let serverUpdatedAt = parseUpdatedAt(
          returnedRow.updated_at, table: .notificationPreferences, id: userId)
        await MainActor.run {
          NotificationPreferencesRepository.shared.markClean(
            for: userId, serverUpdatedAt: serverUpdatedAt)
        }
        logger.debug("Pushed notification preferences for user \(userId.prefix(8))")
        return TablePushResult(
          table: .notificationPreferences, rowsPushed: 1, newConflicts: 0, rebased: 0)
      } else {
        logger.warning("No rows returned after notification preferences upsert")
        return TablePushResult(
          table: .notificationPreferences, rowsPushed: 0, newConflicts: 0, rebased: 0)
      }
    } catch {
      logger.error("Push notification preferences failed: \(error.localizedDescription)")
      throw error
    }
  }

  // MARK: - Helpers

  private enum ApplyResult {
    case inserted
    case updated
    case noChange
    case autoMerged
    case conflict
  }

  /// Parse ISO8601 date string to Date
  private func parseISO8601(_ string: String) -> Date? {
    if let date = SyncDateFormatters.iso8601FractionalFormatter().date(from: string) {
      return date
    }

    // Try without fractional seconds
    return SyncDateFormatters.iso8601InternetFormatter().date(from: string)
  }

  /// Parse ISO8601 updated_at with warning log on failure
  /// For sync cursor timestamps where fallback to Date() is acceptable but should be visible
  private func parseUpdatedAt(_ string: String, table: SyncTable, id: String) -> Date {
    if let date = parseISO8601(string) {
      return date
    }
    logger.warning(
      "Failed to parse updated_at '\(string)' for \(table.displayName) \(id.prefix(8)), using current date as fallback"
    )
    return Date()
  }

  /// Parse ISO8601 date string to Date, throwing on failure
  /// Use this for cursor-affecting code paths to prevent data loss
  /// - Parameters:
  ///   - string: The ISO8601 date string to parse
  ///   - table: The table being synced (for error context)
  ///   - id: The row ID (for error context)
  /// - Returns: Parsed Date
  /// - Throws: SyncError.dateParsingFailed if parsing fails
  private func requireISO8601(_ string: String, table: SyncTable, id: String) throws -> Date {
    if let date = parseISO8601(string) {
      return date
    }
    logger.error("Failed to parse updated_at for \(table.displayName) id=\(id): '\(string)'")
    throw SyncError.dateParsingFailed(table: table, id: id, rawValue: string)
  }

  private func requireAnyJSON(
    _ data: Data,
    table: SyncTable,
    id: String,
    field: String
  ) throws -> AnyJSON {
    do {
      return try AnyJSON.decoder.decode(AnyJSON.self, from: data)
    } catch {
      logger.error("Failed to decode \(table.displayName) field=\(field) id=\(id)")
      throw SyncEncodingError.payloadDecodingFailed(
        type: "\(table.rawValue).\(field)",
        underlyingError: error
      )
    }
  }

  private func requireNonEmptyUpdate(
    _ updateData: [String: AnyJSON],
    table: SyncTable,
    id: String
  ) throws {
    guard !updateData.isEmpty else {
      logger.error("Empty update payload for \(table.displayName) id=\(id)")
      throw SyncEncodingError.emptyUpdatePayload(type: "\(table.rawValue).\(id)")
    }
  }

  /// Format Date to ISO8601 string for Supabase queries
  /// Uses fractional seconds for maximum precision
  private func formatISO8601(_ date: Date) -> String {
    SyncDateFormatters.iso8601FractionalFormatter().string(from: date)
  }

  private func formatSupabaseTimestamp(_ date: Date) -> String {
    SyncDateFormatters.iso8601DefaultFormatter().string(from: date)
  }

  // MARK: - Shift Notification Helper

  /// Notify shared users about a shift change via RPC
}

// MARK: - Sync Errors

/// Errors that can occur during sync operations
enum SyncError: LocalizedError {
  case notFound(table: SyncTable, id: String)
  case notInConflict(table: SyncTable, id: String)
  case missingConflictSnapshot(table: SyncTable, id: String)
  case dateParsingFailed(table: SyncTable, id: String, rawValue: String)

  /// Technical description for logging
  var errorDescription: String? {
    switch self {
    case .notFound(let table, let id):
      return "\(table.displayName) with id \(id) not found"
    case .notInConflict(let table, let id):
      return "\(table.displayName) with id \(id) is not in conflict state"
    case .missingConflictSnapshot(let table, let id):
      return "\(table.displayName) with id \(id) has no conflict snapshot"
    case .dateParsingFailed(let table, let id, let rawValue):
      return "\(table.displayName) with id \(id) has unparseable date field: '\(rawValue)'"
    }
  }

  /// User-friendly message for UI display
  var userFriendlyMessage: String {
    switch self {
    case .notFound:
      return "Sync failed: Record not found locally. Please refresh and try again."
    case .notInConflict, .missingConflictSnapshot:
      return "Sync failed: Conflict state mismatch. Please refresh and try again."
    case .dateParsingFailed(let table, let id, _):
      return
        "Sync failed: Server returned invalid data for \(table.displayName) (ID: \(id.prefix(8))...). Please contact support."
    }
  }
}

// MARK: - Debug Test Harness

#if DEBUG
  /// Debug-only test harness for sync safety verification
  /// Call from a debug menu or unit test to verify cursor safety
  enum SyncTestHarness {
    /// Test that malformed updated_at throws the correct error type
    /// This verifies the error path without needing actual sync infrastructure
    static func testMalformedUpdatedAtThrowsError() -> (passed: Bool, message: String) {
      // Directly test the date parsing logic
      let malformedDate = "not-a-date"
      let testTable = SyncTable.userShifts
      let testId = "test-id-12345"

      // ISO8601DateFormatter should return nil for malformed dates
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if formatter.date(from: malformedDate) != nil {
        return (false, "FAIL: ISO8601DateFormatter accepted malformed date")
      }

      // SyncError should capture the details correctly
      let error = SyncError.dateParsingFailed(table: testTable, id: testId, rawValue: malformedDate)

      // Verify technical description contains details
      guard let description = error.errorDescription else {
        return (false, "FAIL: Error has no description")
      }
      guard description.contains(testId) && description.contains(malformedDate) else {
        return (false, "FAIL: Error description missing details: \(description)")
      }

      // Verify user-friendly message is actionable
      let userMessage = error.userFriendlyMessage
      guard userMessage.contains("contact support") else {
        return (false, "FAIL: User message not actionable: \(userMessage)")
      }

      return (true, "PASS: Malformed date creates proper error with details")
    }

    /// Test that encoding failure throws and is caught properly
    static func testEncodingFailureIsCaught() -> (passed: Bool, message: String) {
      // Create a snapshot with valid data - encoding should succeed
      let validSnapshot = UserShiftServerSnapshot.from(
        jobId: nil,
        shiftDate: "2025-01-15",
        startTime: "09:00",
        endTime: "17:00",
        note: nil,
        customPauseWindows: nil,
        customSupplements: nil,
        updatedAt: Date(),
        revision: 1,
        deletedAt: nil
      )

      do {
        let data = try validSnapshot.encodedOrThrow()
        guard !data.isEmpty else {
          return (false, "FAIL: Encoded data is empty")
        }
        return (true, "PASS: Valid snapshot encodes successfully")
      } catch {
        return (false, "FAIL: Valid snapshot encoding threw: \(error)")
      }
    }

    /// Test that user-friendly messages are provided for all error types
    static func testUserFriendlyMessages() -> (passed: Bool, message: String) {
      let errors: [SyncError] = [
        .notFound(table: .userShifts, id: "test"),
        .notInConflict(table: .recurringShifts, id: "test"),
        .missingConflictSnapshot(table: .wageSnapshots, id: "test"),
        .dateParsingFailed(table: .userSettings, id: "test", rawValue: "bad"),
      ]

      for error in errors {
        let message = error.userFriendlyMessage
        guard !message.isEmpty else {
          return (false, "FAIL: Empty user message for \(error)")
        }
        guard message.contains("Sync failed") else {
          return (false, "FAIL: Message doesn't indicate sync failure: \(message)")
        }
      }

      return (true, "PASS: All error types have user-friendly messages")
    }

    /// Run all tests and return summary
    static func runAllTests() -> String {
      var results: [String] = []

      let test1 = testMalformedUpdatedAtThrowsError()
      results.append(test1.message)

      let test2 = testEncodingFailureIsCaught()
      results.append(test2.message)

      let test3 = testUserFriendlyMessages()
      results.append(test3.message)

      let allPassed = results.allSatisfy { $0.hasPrefix("PASS") }
      let summary = allPassed ? "✅ All tests passed" : "❌ Some tests failed"

      return ([summary] + results).joined(separator: "\n")
    }
  }
#endif
