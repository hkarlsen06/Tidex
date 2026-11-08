// swiftlint:disable:next line_length
// swiftlint:disable explicit_type_interface file_length function_body_length multiline_arguments_brackets no_magic_numbers sorted_imports type_body_length
// swiftlint:disable:previous blanket_disable_command
import Foundation
import Observation
import Synchronization
import os.log

let syncCoordinatorLogger = Logger(subsystem: "com.tidex.app", category: "SyncCoordinator")

/// Batch size for intermediate saves during pull operations.
/// Rows are saved every N rows to ensure durability if a later row fails.
/// Cursor is only persisted after full page success, so failed pages will re-pull.
let pullSaveBatchSize = 50

// MARK: - Sync Coordinator

/// Coordinates bidirectional sync between local SwiftData storage and Convex
/// Implements incremental sync via revision cursors with field-level conflict detection
/// UI status is main-actor isolated. Network, merge and encoding work runs outside it.
final class SyncCoordinator: Sendable {
  static let shared = SyncCoordinator()

  @MainActor @Observable
  fileprivate final class Status {
    var isSyncing = false
    var lastError: String?
    var conflictCount = 0
    var lastSyncedAt: Date?
    var lastSyncAttemptedAt: Date?

    nonisolated init() {}
  }

  private let status = Status()

  @MainActor private(set) var isSyncing: Bool {
    get { status.isSyncing }
    set { status.isSyncing = newValue }
  }

  @MainActor private(set) var lastError: String? {
    get { status.lastError }
    set { status.lastError = newValue }
  }

  @MainActor var conflictCount: Int {
    get { status.conflictCount }
    set { status.conflictCount = newValue }
  }

  @MainActor private(set) var lastSyncedAt: Date? {
    get { status.lastSyncedAt }
    set { status.lastSyncedAt = newValue }
  }

  @MainActor internal private(set) var lastSyncAttemptedAt: Date? {
    get { status.lastSyncAttemptedAt }
    set { status.lastSyncAttemptedAt = newValue }
  }

  // MARK: - Configuration

  /// Page size for incremental sync queries
  let pageSize = 500

  /// Minimum interval between automatic syncs (in seconds)
  let minimumSyncInterval: TimeInterval = 60

  /// Maximum time a sync operation can run before being cancelled (in nanoseconds).
  /// Prevents zombie syncs from holding the syncing lock indefinitely.
  private static let syncTimeout: UInt64 = 30_000_000_000  // 30 seconds

  // MARK: - Private State

  /// Sync state for atomic check-and-set operations
  private let stateStore = SyncStateStore()

  private let isSendingLocale = Mutex(false)

  /// Cancelling an account's work prevents its rows using the next account's token.
  private let runningWork = Mutex<Task<SyncResult, Never>?>(nil)

  init() {}

  /// Reset sync state when user changes (e.g., sign out)
  /// Clears the interval guard so the next user's initial sync isn't blocked
  @MainActor
  func resetForUserChange() async {
    runningWork.withLock { $0 }?.cancel()
    await stateStore.reset()
    isSyncing = false
    lastError = nil
    lastSyncedAt = nil
    lastSyncAttemptedAt = nil
    conflictCount = 0
    SyncStatusManager.shared.reset()
    syncCoordinatorLogger.info("Sync state reset for user change")
  }

  // MARK: - App Locale Update

  /// Tells the server the active iPhone/app language, for push text. Sends the app localization
  /// identifier (e.g. `nb`, `pt-br`, `zh-hans`). The last value the server accepted is kept per
  /// user in UserDefaults, so a sync only calls the server when the language changed.
  private func updateAppLocaleIfNeeded(userId: String) async {
    guard let appLocaleCode = currentAppLocaleMetadataCode() else {
      syncCoordinatorLogger.debug("Skipping locale update: app locale code is empty")
      return
    }
    let defaultsKey = "sync.sentAppLocale.\(userId)"
    guard UserDefaults.standard.string(forKey: defaultsKey) != appLocaleCode else { return }

    // Concurrent syncs would each send the same value before the first reply arrives.
    guard beginLocaleSend() else { return }
    defer { endLocaleSend() }

    struct Args: Encodable, Sendable {
      let locale: String
    }
    do {
      let _: ConvexAPI.Ignored = try await ConvexAPI.app.mutation(
        "users:setLocale", Args(locale: appLocaleCode))
      UserDefaults.standard.set(appLocaleCode, forKey: defaultsKey)
      syncCoordinatorLogger.debug("Sent app locale \(appLocaleCode)")
    } catch {
      // Non-fatal - log but don't fail sync/foreground flow.
      syncCoordinatorLogger.warning("Failed to send app locale: \(error.localizedDescription)")
    }
  }

  private func beginLocaleSend() -> Bool {
    isSendingLocale.withLock { sending in
      guard !sending else { return false }
      sending = true
      return true
    }
  }

  private func endLocaleSend() {
    isSendingLocale.withLock { $0 = false }
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

  // Load persisted sync tracking state for display/debugging.
  // swiftlint:disable:next type_contents_order
  @MainActor
  internal func loadTrackingState(userId: String) async {
    let storeActor = LocalStore.shared.storeActor
    let state = try? await storeActor.syncStateCopy(userId: userId)
    let conflicts = (try? await storeActor.countConflicts(userId: userId)) ?? 0
    let lastSuccessfulSyncAt = state?.lastSuccessfulSyncAt
    let lastSyncAttemptAt = state?.lastSyncAttemptAt
    let lastSyncError = state?.lastSyncError

    lastSyncedAt = lastSuccessfulSyncAt
    lastSyncAttemptedAt = lastSyncAttemptAt
    lastError = lastSyncError
    conflictCount = conflicts
  }

  /// Waits for the sync already in progress. Resetting the account cancels the wait.
  func waitForIdle() async -> Bool {
    let updates = await stateStore.idleUpdates()
    var ready = false
    for await value in updates { ready = value }
    return ready && !Task.isCancelled
  }

  /// Trigger a sync operation
  /// - Parameters:
  ///   - reason: Why the sync was triggered (for logging)
  ///   - userId: User ID to sync for
  /// - Returns: Sync result
  @discardableResult
  @concurrent
  func sync(reason: SyncReason, userId: String) async -> SyncResult {
    await sync(
      reason: reason,
      userId: userId,
      tables: SyncTable.allCases,
      updateWidgetStorage: true
    )
  }

  @discardableResult
  @concurrent
  // swiftlint:disable:next cyclomatic_complexity
  func sync(
    reason: SyncReason,
    userId: String,
    tables: [SyncTable],
    updateWidgetStorage: Bool = true
  ) async -> SyncResult {
    guard await MainActor.run(body: { !LocalStore.shared.isStorageUnavailable }) else {
      return SyncResult(
        success: false,
        tableResults: [],
        pushResults: [],
        totalRowsProcessed: 0,
        totalRowsPushed: 0,
        totalConflicts: 0,
        totalAutoMerged: 0,
        duration: 0,
        error: String(localized: .storageUnavailableMessage)
      )
    }

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

    var decision: SyncStartDecision = .alreadySyncing(generation: 0)

    syncStartLoop: while true {
      decision = await stateStore.beginSync(
        reason: reason,
        userId: userId,
        minimumSyncInterval: minimumSyncInterval
      )

      // Manual pull-to-refresh should wait for an ongoing sync, then retry.
      // This avoids dismissing the refresh UI immediately when background sync is active.
      if case .alreadySyncing(let waitingGeneration) = decision, reason == .manualRefresh {
        syncCoordinatorLogger.info("Manual refresh requested while sync in progress, waiting for idle")
        let updates = await stateStore.idleUpdates(generation: waitingGeneration)
        var finished = false
        for await ready in updates { finished = ready }
        guard finished, !Task.isCancelled else {
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

    let generation: Int
    switch decision {
    case .alreadySyncing:
      syncCoordinatorLogger.info("Sync already in progress, skipping \(reason.rawValue)")
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
      // Keep the server's copy of the app locale current even when full sync is interval-skipped.
      // Fire and forget so a slow request cannot delay the foreground path.
      Task { await self.updateAppLocaleIfNeeded(userId: userId) }
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

    case .started(let started):
      generation = started
    }

    let startTime = Date()

    await MainActor.run {
      isSyncing = true
      lastError = nil
      lastSyncAttemptedAt = startTime
    }
    // Fire and forget. The call can take up to the request timeout, and the sync must not hold
    // the syncing lock for that long.
    Task { await self.updateRemoteLastSyncedAt(userId: userId, syncedAt: startTime) }

    // Update global sync status for UI indicators (only for manual pull-to-refresh)
    if reason == .manualRefresh {
      await MainActor.run {
        SyncStatusManager.shared.syncStarted()
      }
    }

    // Race the sync work against a timeout to prevent zombie syncs
    // from holding the syncing lock indefinitely.
    // swiftlint:disable:next closure_body_length
    let result: SyncResult = await withTaskGroup(of: SyncResult?.self) { group in
      group.addTask {
        let work = Task {
          await self.performSyncWork(
            reason: reason,
            userId: userId,
            startTime: startTime,
            tables: uniqueTables,
            updateWidgetStorage: updateWidgetStorage
          )
        }
        self.runningWork.withLock { $0 = work }
        defer {
          self.runningWork.withLock { running in
            if running == work { running = nil }
          }
        }
        return await withTaskCancellationHandler {
          await work.value
        } onCancel: {
          work.cancel()
        }
      }
      group.addTask {
        try? await Task.sleep(for: .nanoseconds(Int64(Self.syncTimeout)))
        return nil  // timeout signal
      }
      guard let first = await group.next() else {
        group.cancelAll()
        return SyncResult(
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

    // resetForUserChange ran during this sync, so it belongs to the previous user. The state and
    // the status shown now are the next user's.
    guard
      let needsFollowUpSync = await stateStore.endSync(
        success: result.success, generation: generation)
    else { return result }

    if result.error == "Sync timed out" {
      syncCoordinatorLogger.error("Sync timed out after 30s, cancelling")
      await MainActor.run {
        lastError = "Sync timed out"
        SyncStatusManager.shared.syncFailed(message: "Sync timed out")
      }
    }

    await MainActor.run {
      isSyncing = false
    }
    await notifyWorkSetupDataChangedIfNeeded(for: result, reason: reason, userId: userId)

    if needsFollowUpSync {
      syncCoordinatorLogger.info("Running coalesced follow-up sync after concurrent local changes")
      Task {
        _ = await self.sync(reason: .localChange, userId: userId)
      }
    }

    return result
  }

  private func notifyWorkSetupDataChangedIfNeeded(
    for result: SyncResult,
    reason: SyncReason,
    userId: String
  ) async {
    // A partly failed sync can still have changed work setup data, so this does not check success.
    let workSetupTables: Set<SyncTable> = [.jobs, .wageSnapshots]
    let pulledWorkSetupData = result.tableResults.contains { tableResult in
      workSetupTables.contains(tableResult.table)
        && (tableResult.rowsProcessed > 0
          || tableResult.newConflicts > 0
          || tableResult.autoMerged > 0)
    }
    let pushedWorkSetupData = result.pushResults.contains { tableResult in
      workSetupTables.contains(tableResult.table)
        && (tableResult.rowsPushed > 0
          || tableResult.newConflicts > 0
          || tableResult.rebased > 0)
    }

    guard pulledWorkSetupData || pushedWorkSetupData else { return }

    await MainActor.run {
      NotificationCenter.default.post(
        name: .workSetupDataDidChange,
        object: nil,
        userInfo: [
          "syncReason": reason.rawValue,
          "userId": userId,
        ]
      )
    }
  }

  // swiftlint:disable:next type_contents_order
  private func updateRemoteLastSyncedAt(userId: String, syncedAt: Date) async {
    struct Args: Encodable, Sendable {
      let lastSyncedAt: String
      enum CodingKeys: String, CodingKey { case lastSyncedAt = "last_synced_at" }
    }

    do {
      let _: ConvexAPI.Ignored = try await ConvexAPI.app.mutation(
        "sharing:setLastSyncedAt", Args(lastSyncedAt: formatTimestamp(syncedAt)))
      syncCoordinatorLogger.debug("Updated remote last_synced_at for \(userId.prefix(8))")
    } catch {
      syncCoordinatorLogger.warning("Failed to update remote last_synced_at: \(error.localizedDescription)")
    }
  }

  /// Keeps completed pull results available when the timeout cancels the remaining tables.
  private actor PullPhase {
    private var tableResults: [TablePullResult] = []
    private var error: Error?

    func append(_ result: TablePullResult) { tableResults.append(result) }
    func record(_ error: Error) {
      if self.error == nil { self.error = error }
    }
    func snapshot(timedOut: Bool) -> (tableResults: [TablePullResult], error: Error?) {
      (tableResults, timedOut ? SyncError.pullTimedOut : error)
    }
  }

  /// Time the pull phase gets. The rest of `syncTimeout` is left for the push phase.
  private static let pullTimeout: UInt64 = 20_000_000_000  // 20 seconds

  /// Runs `operation` and cancels it after `nanoseconds`. Returns nil when it timed out.
  private static func withTimeout<T: Sendable>(
    nanoseconds: UInt64,
    operation: @escaping @Sendable () async -> T
  ) async -> T? {
    await withTaskGroup(of: T?.self) { group in
      group.addTask { await operation() }
      group.addTask {
        try? await Task.sleep(for: .nanoseconds(Int64(nanoseconds)))
        return nil
      }
      guard let first = await group.next() else { return nil }
      group.cancelAll()
      return first
    }
  }

  /// Whether the error means the device has no usable connection, so more requests would fail.
  private static func isNetworkError(_ error: Error) async -> Bool {
    await MainActor.run { AuthSessionManager.shared.isTransientNetworkError(error) }
  }

  /// Whether the error comes from cancelling the sync, including a cancelled URL request.
  static func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
  }

  /// Pulls every table and records failures in `phase` instead of throwing. A network error or
  /// cancellation stops the phase, since the remaining requests would fail too.
  private func pullAllTables(
    into phase: PullPhase,
    tables: [SyncTable],
    userId: String,
    startCursors: [SyncTable: Int64]
  ) async {
    for table in tables {
      if Task.isCancelled { return }
      guard let start = startCursors[table] else { continue }
      do {
        await phase.append(try await pullTable(table, userId: userId, after: start))
      } catch {
        syncCoordinatorLogger.error("Pull of \(table.displayName) failed: \(error.localizedDescription)")
        await phase.record(error)
        if Self.isCancellation(error) { return }
        if await Self.isNetworkError(error) { return }
      }
      await Task.yield()
    }
  }

  /// Handles a push error that is not a row rejection. It rethrows errors that stop the sync,
  /// which are network errors and cancellation. For any other error the row is skipped and stays
  /// dirty, so the next sync retries it.
  func skipRowUnlessFatal(_ error: Error, table: SyncTable, id: String) async throws {
    if Self.isCancellation(error) || Self.isWrongUser(error) { throw error }
    if await Self.isNetworkError(error) { throw error }
    syncCoordinatorLogger.error(
      "Skipping push of \(table.displayName) row \(id.prefix(8)): \(error.localizedDescription)")
  }

  // Performs the actual sync work (pull, push, widget update).
  // Extracted so it can be raced against a timeout in `sync()`.
  @concurrent
  // swiftlint:disable:next cyclomatic_complexity
  private func performSyncWork(
    reason: SyncReason,
    userId: String,
    startTime: Date,
    tables: [SyncTable],
    updateWidgetStorage: Bool
  ) async -> SyncResult {
    // Keep the server's copy of the app locale current. The sync does not depend on it.
    Task { await self.updateAppLocaleIfNeeded(userId: userId) }

    // Get or create sync state
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    do {
      try Task.checkCancellation()

      var syncState = try await storeActor.syncStateCopyCreatingIfNeeded(userId: userId)
      if syncState.convexCursorsResetAt == nil {
        // The cursors come from Postgres. Start over once, so the pull returns every row and
        // the merge moves unsent local edits onto the Convex revisions before they push.
        await storeActor.updateSyncState(userId: userId) { state in
          state.resetCursorsForConvex()
        }
        syncState = try await storeActor.syncStateCopyCreatingIfNeeded(userId: userId)
        syncCoordinatorLogger.info("Reset the pull cursors for Convex")
      }
      // Read the cursors here so the pull task does not capture the SwiftData model.
      let startCursors = Dictionary(
        uniqueKeysWithValues: tables.map { ($0, syncState.cursor(for: $0)) })
      await storeActor.updateSyncState(userId: userId) { state in
        state.markSyncStarted(at: startTime)
      }

      // Phase 1: Pull all tables (get latest server state).
      // A failed pull does not skip the push phase, so local edits still reach the server.
      // Push handles a stale revision by rebasing onto the server row the conflict reply returns.
      let pullPhase = PullPhase()
      let pullFinished: Void? = await Self.withTimeout(nanoseconds: Self.pullTimeout) {
        await self.pullAllTables(
          into: pullPhase, tables: tables, userId: userId, startCursors: startCursors)
      }
      try Task.checkCancellation()
      if pullFinished == nil {
        syncCoordinatorLogger.error("Pull timed out, continuing with push")
      }
      let pullOutcome = await pullPhase.snapshot(timedOut: pullFinished == nil)
      let tableResults = pullOutcome.tableResults

      // Phase 2: Push dirty records to server.
      // Skipped when the pull failed because the device is offline.
      var pushResults: [TablePushResult] = []
      var pushError: Error?
      var isOffline = false
      if let pullError = pullOutcome.error {
        isOffline = await Self.isNetworkError(pullError)
      }

      if !isOffline {
        for table in tables {
          try Task.checkCancellation()
          do {
            let result = try await pushTable(table, userId: userId)
            pushResults.append(result)
          } catch {
            if Self.isCancellation(error) { throw error }
            syncCoordinatorLogger.error("Push of \(table.displayName) failed: \(error.localizedDescription)")
            if pushError == nil { pushError = error }
            if Self.isWrongUser(error) { break }
            if await Self.isNetworkError(error) { break }
          }
          await Task.yield()
        }
        // A push that stopped early can leave finished rows unsaved.
        try? await storeActor.save()
      }

      // Calculate totals
      let totalRows = tableResults.reduce(0) { $0 + $1.rowsProcessed }
      let totalPushed = pushResults.reduce(0) { $0 + $1.rowsPushed }
      let pullConflicts = tableResults.reduce(0) { $0 + $1.newConflicts }
      let pushConflicts = pushResults.reduce(0) { $0 + $1.newConflicts }
      let totalConflicts = pullConflicts + pushConflicts
      let totalAutoMerged = tableResults.reduce(0) { $0 + $1.autoMerged }
      _ = pushResults.reduce(0) { $0 + $1.rebased }  // totalRebased - tracked but not logged
      let skippedPushRows = pushResults.reduce(0) { $0 + $1.failedRows }
      let duration = Date().timeIntervalSince(startTime)

      let conflicts = try await storeActor.countConflicts(userId: userId)
      let completionSummary = SyncCompletionSummary(
        reason: reason,
        userId: userId,
        tableResults: tableResults,
        pushResults: pushResults
      )

      // Only log when there's actual data transfer
      if totalRows > 0 || totalPushed > 0 || totalConflicts > 0 {
        syncCoordinatorLogger.info(
          "Sync: \(totalRows) pulled, \(totalPushed) pushed\(totalConflicts > 0 ? ", \(totalConflicts) conflicts" : "")"
        )
      }

      // Update widget storage with latest shift data
      if updateWidgetStorage {
        NativeWidgetStorage.updateWidgetStorage(for: userId)
      }

      var failure: Error? = pullOutcome.error ?? pushError
      if failure == nil, skippedPushRows > 0 {
        failure = SyncError.rowsNotPushed(count: skippedPushRows)
      }
      if let failure {
        return await recordSyncFailure(
          failure,
          userId: userId,
          startTime: startTime,
          storeActor: storeActor,
          tableResults: tableResults,
          pushResults: pushResults,
          summary: completionSummary
        )
      }

      // Update sync state
      await storeActor.updateSyncState(userId: userId) { state in
        state.markSyncSucceeded()
      }

      await MainActor.run {
        lastSyncedAt = Date()
        conflictCount = conflicts
        SyncStatusManager.shared.syncSucceeded(summary: completionSummary)
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
    } catch let error where Self.isCancellation(error) {
      // Rows pushed before the cancellation are marked clean only in memory. Save them, or a
      // restart replays those pushes against revisions the server has moved past.
      try? await storeActor.save()
      let duration = Date().timeIntervalSince(startTime)
      syncCoordinatorLogger.warning("Sync cancelled after \(String(format: "%.1f", duration))s")
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
      return await recordSyncFailure(
        error, userId: userId, startTime: startTime, storeActor: storeActor)
    }
  }

  /// Records a failed sync in the sync state and the status indicator and builds the result.
  /// A network error shows the offline status. Any other error shows the failed status.
  /// A partly failed sync passes what it pulled and pushed, so the UI still refreshes from it.
  private func recordSyncFailure(
    _ error: Error,
    userId: String,
    startTime: Date,
    storeActor: LocalStoreActor,
    tableResults: [TablePullResult] = [],
    pushResults: [TablePushResult] = [],
    summary: SyncCompletionSummary? = nil
  ) async -> SyncResult {
    let duration = Date().timeIntervalSince(startTime)
    let technicalMessage = error.localizedDescription
    let isOffline = await Self.isNetworkError(error)

    // Extract user-friendly message if available, otherwise use the localized generic message
    let userFriendlyMessage: String
    if let syncError = error as? SyncError {
      userFriendlyMessage = syncError.userFriendlyMessage
    } else if let encodingError = error as? SyncEncodingError {
      userFriendlyMessage = encodingError.userFriendlyMessage
    } else {
      userFriendlyMessage = String(localized: .syncSyncFailed)
    }

    // Log technical details for debugging
    syncCoordinatorLogger.error("Sync failed: \(technicalMessage)")

    await storeActor.updateSyncState(userId: userId) { state in
      state.markSyncFailed(error: technicalMessage)
    }
    let conflicts = try? await storeActor.countConflicts(userId: userId)

    // Surface the failure to the UI
    await MainActor.run {
      lastError = userFriendlyMessage
      if let conflicts { conflictCount = conflicts }
      if let summary, summary.hasLocalReadModelChanges {
        SyncStatusManager.shared.syncSucceeded(summary: summary)
      }
      if isOffline {
        SyncStatusManager.shared.setOffline()
      } else {
        SyncStatusManager.shared.syncFailed(message: userFriendlyMessage)
      }
    }

    return SyncResult(
      success: false,
      tableResults: tableResults,
      pushResults: pushResults,
      totalRowsProcessed: tableResults.reduce(0) { $0 + $1.rowsProcessed },
      totalRowsPushed: pushResults.reduce(0) { $0 + $1.rowsPushed },
      totalConflicts: tableResults.reduce(0) { $0 + $1.newConflicts }
        + pushResults.reduce(0) { $0 + $1.newConflicts },
      totalAutoMerged: tableResults.reduce(0) { $0 + $1.autoMerged },
      duration: duration,
      error: userFriendlyMessage
    )
  }

  /// `ConvexError` code of a second live default job (`idx_jobs_default` in Postgres).
  static let defaultJobExistsCode = "default_job_exists"

}
