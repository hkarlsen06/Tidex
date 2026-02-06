#if DEBUG
  import Foundation
  import SwiftData
  import os.log

  private let logger = Logger(subsystem: "com.tidex.app", category: "SyncTestHelper")

  // MARK: - Sync Test Helper

  /// Helper utility for testing and validating offline sync functionality
  /// Provides methods to simulate scenarios, inspect state, and log sync operations
  @MainActor
  final class SyncTestHelper: ObservableObject {
    static let shared = SyncTestHelper()

    private let localStore: LocalStore
    private let syncCoordinator: SyncCoordinator

    // MARK: - Published State

    /// Test log entries for inspection
    @Published private(set) var testLogs: [TestLogEntry] = []

    /// Maximum number of log entries to keep
    private let maxLogEntries = 100

    private init(
      localStore: LocalStore? = nil,
      syncCoordinator: SyncCoordinator? = nil
    ) {
      self.localStore = localStore ?? LocalStore.shared
      self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
    }

    // MARK: - Test Log Entry

    struct TestLogEntry: Identifiable, Equatable {
      let id = UUID()
      let timestamp: Date
      let category: LogCategory
      let message: String
      let details: String?

      enum LogCategory: String, CaseIterable {
        case sync = "SYNC"
        case pull = "PULL"
        case push = "PUSH"
        case conflict = "CONFLICT"
        case merge = "MERGE"
        case validation = "VALIDATION"
        case error = "ERROR"
      }

      var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
      }
    }

    // MARK: - Logging

    /// Add a test log entry
    func log(_ category: TestLogEntry.LogCategory, _ message: String, details: String? = nil) {
      let entry = TestLogEntry(
        timestamp: Date(),
        category: category,
        message: message,
        details: details
      )
      testLogs.append(entry)

      // Trim old entries
      if testLogs.count > maxLogEntries {
        testLogs.removeFirst(testLogs.count - maxLogEntries)
      }

      // Also log to console
      logger.info("[\(category.rawValue)] \(message)")
      if let details = details {
        logger.debug("  Details: \(details)")
      }
    }

    /// Clear all test logs
    func clearLogs() {
      testLogs.removeAll()
      log(.validation, "Logs cleared")
    }

    // MARK: - State Inspection

    /// Get sync state summary for a user
    func getSyncStateSummary(userId: String) -> SyncStateSummary {
      let context = localStore.mainContext

      // Fetch sync state
      let stateDescriptor = FetchDescriptor<LocalSyncState>(
        predicate: #Predicate { $0.userId == userId }
      )
      let syncState = try? context.fetch(stateDescriptor).first

      // Count shifts by status
      let shiftsDescriptor = FetchDescriptor<LocalUserShift>(
        predicate: #Predicate { $0.userId == userId }
      )
      let shifts = (try? context.fetch(shiftsDescriptor)) ?? []

      // Count recurring shifts by status
      let recurringDescriptor = FetchDescriptor<LocalRecurringShift>(
        predicate: #Predicate { $0.userId == userId }
      )
      let recurringShifts = (try? context.fetch(recurringDescriptor)) ?? []

      // Count wage snapshots by status
      let snapshotsDescriptor = FetchDescriptor<LocalWageSnapshot>(
        predicate: #Predicate { $0.userId == userId }
      )
      let wageSnapshots = (try? context.fetch(snapshotsDescriptor)) ?? []

      // Get user settings
      let settingsDescriptor = FetchDescriptor<LocalUserSettings>(
        predicate: #Predicate { $0.userId == userId }
      )
      let userSettings = try? context.fetch(settingsDescriptor).first

      // Categorize by sync status
      let shiftsByStatus = categorizeByStatus(shifts.map { $0.syncStatus })
      let recurringByStatus = categorizeByStatus(recurringShifts.map { $0.syncStatus })
      let snapshotsByStatus = categorizeByStatus(wageSnapshots.map { $0.syncStatus })

      return SyncStateSummary(
        userId: userId,
        syncState: syncState,
        userSettings: userSettings,
        shiftCount: ShiftCounts(
          total: shifts.count,
          clean: shiftsByStatus[.clean] ?? 0,
          dirty: shiftsByStatus[.dirty] ?? 0,
          pendingDelete: shiftsByStatus[.pendingDelete] ?? 0,
          conflict: shiftsByStatus[.conflict] ?? 0,
          deleted: shifts.filter { $0.isDeleted }.count
        ),
        recurringShiftCount: ShiftCounts(
          total: recurringShifts.count,
          clean: recurringByStatus[.clean] ?? 0,
          dirty: recurringByStatus[.dirty] ?? 0,
          pendingDelete: recurringByStatus[.pendingDelete] ?? 0,
          conflict: recurringByStatus[.conflict] ?? 0,
          deleted: recurringShifts.filter { $0.serverDeletedAt != nil }.count
        ),
        wageSnapshotCount: ShiftCounts(
          total: wageSnapshots.count,
          clean: snapshotsByStatus[.clean] ?? 0,
          dirty: snapshotsByStatus[.dirty] ?? 0,
          pendingDelete: snapshotsByStatus[.pendingDelete] ?? 0,
          conflict: snapshotsByStatus[.conflict] ?? 0,
          deleted: wageSnapshots.filter { $0.serverDeletedAt != nil }.count
        ),
        settingsStatus: userSettings?.syncStatus ?? .clean
      )
    }

    private func categorizeByStatus(_ statuses: [SyncStatus]) -> [SyncStatus: Int] {
      var counts: [SyncStatus: Int] = [:]
      for status in statuses {
        counts[status, default: 0] += 1
      }
      return counts
    }

    // MARK: - Validation Tests

    /// Validate Test 8.1: Local-only UI validation
    /// Checks that local data is accessible without network
    func validateLocalOnlyUI(userId: String) async -> ValidationResult {  // swiftlint:disable:this async_without_await
      log(
        .validation, "Starting Test 8.1: Local-only UI Validation",
        details: "userId: \(userId.prefix(8))...")

      let summary = getSyncStateSummary(userId: userId)

      var issues: [String] = []

      // Check if sync has ever completed
      if summary.syncState == nil {
        issues.append("No sync state found - sync may have never completed")
      } else if summary.syncState?.lastSuccessfulSyncAt == nil {
        issues.append("No successful sync recorded")
      }

      // Check if local data exists
      if summary.shiftCount.total == 0 && summary.recurringShiftCount.total == 0 {
        issues.append("No shifts found in local store")
      }

      if summary.wageSnapshotCount.total == 0 {
        issues.append("No wage snapshots found - payroll calculation will fail")
      }

      if summary.userSettings == nil {
        issues.append("No user settings found - dashboard may not render correctly")
      }

      let result = ValidationResult(
        testName: "8.1: Local-only UI Validation",
        passed: issues.isEmpty,
        issues: issues,
        details: """
          Shifts: \(summary.shiftCount.total) (clean: \(summary.shiftCount.clean))
          Recurring: \(summary.recurringShiftCount.total)
          Snapshots: \(summary.wageSnapshotCount.total)
          Settings: \(summary.userSettings != nil ? "Present" : "Missing")
          Last sync: \(summary.syncState?.lastSuccessfulSyncAt?.description ?? "Never")
          """
      )

      log(
        result.passed ? .validation : .error,
        "Test 8.1 \(result.passed ? "PASSED" : "FAILED")",
        details: result.details
      )

      return result
    }

    /// Validate Test 8.2: Check for pending/dirty records
    /// Verifies that offline edits are properly marked
    func validatePendingChanges(userId: String) async -> ValidationResult {  // swiftlint:disable:this async_without_await
      log(
        .validation, "Starting Test 8.2: Pending Changes Validation",
        details: "userId: \(userId.prefix(8))...")

      let summary = getSyncStateSummary(userId: userId)

      let totalDirty =
        summary.shiftCount.dirty + summary.recurringShiftCount.dirty
        + summary.wageSnapshotCount.dirty + (summary.settingsStatus == .dirty ? 1 : 0)

      let totalPendingDelete =
        summary.shiftCount.pendingDelete + summary.recurringShiftCount.pendingDelete
        + summary.wageSnapshotCount.pendingDelete

      let result = ValidationResult(
        testName: "8.2: Pending Changes Detection",
        passed: true,  // This test is informational
        issues: [],
        details: """
          Dirty records: \(totalDirty)
            - Shifts: \(summary.shiftCount.dirty)
            - Recurring: \(summary.recurringShiftCount.dirty)
            - Snapshots: \(summary.wageSnapshotCount.dirty)
            - Settings: \(summary.settingsStatus == .dirty ? 1 : 0)
          Pending delete: \(totalPendingDelete)
            - Shifts: \(summary.shiftCount.pendingDelete)
            - Recurring: \(summary.recurringShiftCount.pendingDelete)
            - Snapshots: \(summary.wageSnapshotCount.pendingDelete)
          """
      )

      log(.validation, "Test 8.2 complete", details: result.details)

      return result
    }

    /// Validate Test 8.3/8.4: Check for conflicts
    /// Verifies conflict detection and resolution status
    func validateConflicts(userId: String) async -> ValidationResult {  // swiftlint:disable:this async_without_await
      log(
        .validation, "Starting Test 8.3/8.4: Conflict Validation",
        details: "userId: \(userId.prefix(8))...")

      let summary = getSyncStateSummary(userId: userId)

      let totalConflicts =
        summary.shiftCount.conflict + summary.recurringShiftCount.conflict
        + summary.wageSnapshotCount.conflict + (summary.settingsStatus == .conflict ? 1 : 0)

      var issues: [String] = []

      // If there are conflicts, they need to be resolved
      if totalConflicts > 0 {
        issues.append("Found \(totalConflicts) unresolved conflict(s) - user action required")
      }

      let result = ValidationResult(
        testName: "8.3/8.4: Conflict Detection",
        passed: totalConflicts == 0,
        issues: issues,
        details: """
          Total conflicts: \(totalConflicts)
            - Shifts: \(summary.shiftCount.conflict)
            - Recurring: \(summary.recurringShiftCount.conflict)
            - Snapshots: \(summary.wageSnapshotCount.conflict)
            - Settings: \(summary.settingsStatus == .conflict ? 1 : 0)

          Use "Resolve All" to clear conflicts or resolve individually.
          """
      )

      log(
        result.passed ? .validation : .conflict,
        "Test 8.3/8.4 \(result.passed ? "PASSED" : "REQUIRES ATTENTION")",
        details: result.details
      )

      return result
    }

    /// Validate Test 8.5: Soft delete sync
    /// Checks that deleted records are properly tracked
    func validateSoftDeleteSync(userId: String) async -> ValidationResult {  // swiftlint:disable:this async_without_await
      log(
        .validation, "Starting Test 8.5: Soft Delete Validation",
        details: "userId: \(userId.prefix(8))...")

      let summary = getSyncStateSummary(userId: userId)

      let totalDeleted =
        summary.shiftCount.deleted + summary.recurringShiftCount.deleted
        + summary.wageSnapshotCount.deleted

      let result = ValidationResult(
        testName: "8.5: Soft Delete Sync",
        passed: true,  // Informational
        issues: [],
        details: """
          Soft-deleted records tracked locally: \(totalDeleted)
            - Shifts: \(summary.shiftCount.deleted)
            - Recurring: \(summary.recurringShiftCount.deleted)
            - Snapshots: \(summary.wageSnapshotCount.deleted)

          These records are hidden from UI but retained for sync integrity.
          """
      )

      log(.validation, "Test 8.5 complete", details: result.details)

      return result
    }

    /// Run all validation tests
    func runAllValidations(userId: String) async -> [ValidationResult] {
      log(.validation, "=== Starting Full Validation Suite ===")

      var results: [ValidationResult] = []

      results.append(await validateLocalOnlyUI(userId: userId))
      results.append(await validatePendingChanges(userId: userId))
      results.append(await validateConflicts(userId: userId))
      results.append(await validateSoftDeleteSync(userId: userId))

      let passed = results.filter { $0.passed }.count
      let total = results.count

      log(.validation, "=== Validation Suite Complete ===", details: "Passed: \(passed)/\(total)")

      return results
    }

    // MARK: - Sync Operation Tracking

    /// Log a sync operation start
    func logSyncStart(reason: SyncReason, userId: String) {
      log(
        .sync, "Sync started", details: "Reason: \(reason.rawValue), User: \(userId.prefix(8))...")
    }

    /// Log a sync operation complete
    func logSyncComplete(result: SyncResult) {
      if result.success {
        log(
          .sync, "Sync completed successfully",
          details: """
            Duration: \(String(format: "%.2f", result.duration))s
            Pulled: \(result.totalRowsProcessed) rows
            Pushed: \(result.totalRowsPushed) rows
            Auto-merged: \(result.totalAutoMerged)
            Conflicts: \(result.totalConflicts)
            """)
      } else {
        log(.error, "Sync failed", details: result.error ?? "Unknown error")
      }
    }

    /// Log a pull operation
    func logPullOperation(table: SyncTable, rowsProcessed: Int, newConflicts: Int, autoMerged: Int)
    {
      log(
        .pull, "Pulled \(table.rawValue)",
        details: """
          Rows: \(rowsProcessed)
          Auto-merged: \(autoMerged)
          Conflicts: \(newConflicts)
          """)
    }

    /// Log a push operation
    func logPushOperation(table: SyncTable, rowsPushed: Int, rebased: Int, newConflicts: Int) {
      log(
        .push, "Pushed \(table.rawValue)",
        details: """
          Rows: \(rowsPushed)
          Rebased: \(rebased)
          Conflicts: \(newConflicts)
          """)
    }

    /// Log a conflict detection
    func logConflictDetected(entityType: String, entityId: String, overlappingFields: [String]) {
      log(
        .conflict, "Conflict detected",
        details: """
          Type: \(entityType)
          ID: \(entityId.prefix(8))...
          Overlapping fields: \(overlappingFields.joined(separator: ", "))
          """)
    }

    /// Log a field-level merge
    func logAutoMerge(
      entityType: String, entityId: String, serverFields: [String], localFields: [String]
    ) {
      log(
        .merge, "Auto-merged \(entityType)",
        details: """
          ID: \(entityId.prefix(8))...
          Server changed: \(serverFields.joined(separator: ", "))
          Local changed: \(localFields.joined(separator: ", "))
          No overlap - merged successfully
          """)
    }

    /// Log a conflict resolution
    func logConflictResolved(entityType: String, entityId: String, resolution: ConflictResolution) {
      let resolutionStr = resolution == .keepLocal ? "Keep iPhone" : "Keep Web"
      log(
        .conflict, "Conflict resolved",
        details: """
          Type: \(entityType)
          ID: \(entityId.prefix(8))...
          Resolution: \(resolutionStr)
          """)
    }
  }

  // MARK: - Supporting Types

  /// Summary of sync state for a user
  struct SyncStateSummary {
    let userId: String
    let syncState: LocalSyncState?
    let userSettings: LocalUserSettings?
    let shiftCount: ShiftCounts
    let recurringShiftCount: ShiftCounts
    let wageSnapshotCount: ShiftCounts
    let settingsStatus: SyncStatus
  }

  /// Count breakdown by sync status
  struct ShiftCounts {
    let total: Int
    let clean: Int
    let dirty: Int
    let pendingDelete: Int
    let conflict: Int
    let deleted: Int
  }

  /// Result of a validation test
  struct ValidationResult: Identifiable {
    let id = UUID()
    let testName: String
    let passed: Bool
    let issues: [String]
    let details: String
  }
#endif
