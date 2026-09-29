import Foundation

// MARK: - Sync Result Types

/// Result of pulling a single table
internal struct TablePullResult {
  internal let table: SyncTable
  internal let rowsProcessed: Int
  /// Last updated_at timestamp processed (for cursor)
  internal let lastUpdatedAt: Date?
  /// ID of the last row at the lastUpdatedAt timestamp (tie-breaker)
  internal let lastUpdatedAtTieId: String?
  /// Legacy max revision (kept for debugging only)
  internal let maxRevision: Int64
  internal let newConflicts: Int, autoMerged: Int
  internal let affectedMonths: Set<ShiftChangeAffectedMonth>
}

/// Overall sync result
internal struct SyncResult {
  internal let success: Bool
  internal let tableResults: [TablePullResult]
  internal let pushResults: [TablePushResult]
  internal let totalRowsProcessed: Int
  internal let totalRowsPushed: Int
  internal let totalConflicts: Int
  internal let totalAutoMerged: Int
  internal let duration: TimeInterval
  internal let error: String?

  internal var hasConflicts: Bool {
    totalConflicts > 0
  }
}

// MARK: - Push Result Types

/// Result of pushing a single table
internal struct TablePushResult {
  internal let table: SyncTable
  internal let rowsPushed: Int, newConflicts: Int, rebased: Int
  internal let affectedMonths: Set<ShiftChangeAffectedMonth> = []
}

// MARK: - Sync Completion Summary

internal struct SyncTableChange: Equatable {
  internal let table: SyncTable
  internal let pulledRows: Int, pushedRows: Int, newConflicts: Int, autoMerged: Int, rebased: Int
  internal let affectedMonths: Set<ShiftChangeAffectedMonth>

  internal var changesLocalReadModels: Bool {
    pulledRows > 0 || newConflicts > 0 || autoMerged > 0 || rebased > 0
  }
}

internal struct SyncCompletionSummary: Equatable {
  internal let reason: SyncReason
  internal let userId: String
  internal let completedAt: Date
  internal let tableChanges: [SyncTableChange]

  internal init(
    reason: SyncReason,
    userId: String,
    tableResults: [TablePullResult],
    pushResults: [TablePushResult],
    completedAt: Date = Date()
  ) {
    self.reason = reason
    self.userId = userId
    self.completedAt = completedAt

    let pullResultsByTable: [SyncTable: TablePullResult] =
      Dictionary(uniqueKeysWithValues: tableResults.map { ($0.table, $0) })
    let pushResultsByTable: [SyncTable: TablePushResult] =
      Dictionary(uniqueKeysWithValues: pushResults.map { ($0.table, $0) })
    let tables: Set<SyncTable> = Set(pullResultsByTable.keys).union(pushResultsByTable.keys)

    self.tableChanges = tables.sorted { $0.rawValue < $1.rawValue }.map { table in
      let pullResult: TablePullResult? = pullResultsByTable[table]
      let pushResult: TablePushResult? = pushResultsByTable[table]
      return SyncTableChange(
        table: table,
        pulledRows: pullResult?.rowsProcessed ?? 0,
        pushedRows: pushResult?.rowsPushed ?? 0,
        newConflicts: (pullResult?.newConflicts ?? 0) + (pushResult?.newConflicts ?? 0),
        autoMerged: pullResult?.autoMerged ?? 0,
        rebased: pushResult?.rebased ?? 0,
        affectedMonths: (pullResult?.affectedMonths ?? []).union(pushResult?.affectedMonths ?? [])
      )
    }
  }

  internal var localReadModelChanges: [SyncTableChange] {
    tableChanges.filter(\.changesLocalReadModels)
  }

  internal var hasLocalReadModelChanges: Bool {
    !localReadModelChanges.isEmpty
  }
}

/// Result of pushing a single record
internal enum PushResult {
  case conflict
  case deleted
  case noChange
  case rebased
  case success
}

// MARK: - Conflict Resolution

/// Resolution choice for a conflict
internal enum ConflictResolution {
  /// Keep the local (iPhone) version and push to server
  case keepLocal
  /// Keep the server (Web) version and discard local changes
  case keepServer
}
