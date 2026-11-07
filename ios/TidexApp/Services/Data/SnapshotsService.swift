import Foundation

/// Service for fetching and resolving wage snapshots from Convex
/// Resolves snapshots in one pass without sorting or allocating a dated copy.
@MainActor
final class SnapshotsService {
  static let shared = SnapshotsService()

  private(set) var snapshots: [WageSnapshot] = []
  private(set) var isLoading = false
  private(set) var error: Error?

  private init() {}

  // MARK: - Public API

  /// Fetch all snapshots for a user, ordered by from_date DESC (nulls last)
  /// - Parameter userId: User ID to fetch snapshots for
  /// - Returns: Array of wage snapshots
  func fetchSnapshots(for userId: String) async throws -> [WageSnapshot] {
    isLoading = true
    error = nil
    defer { isLoading = false }

    do {
      let rows: [SyncWageSnapshotRow] = try await SyncConvex.pullAll(.wageSnapshots)
      let owner = userId.lowercased()
      // Newest date first, and the baseline snapshot without a date last.
      let response = rows
        .filter { $0.deleted_at == nil && $0.user_id.lowercased() == owner }
        .sorted { lhs, rhs in
          switch (lhs.from_date, rhs.from_date) {
          case (let left?, let right?): left > right
          case (_?, nil): true
          default: false
          }
        }
        .map { $0.toWageSnapshot() }

      snapshots = response
      return response
    } catch {
      self.error = error
      throw error
    }
  }

  /// Find the applicable snapshot for a specific date
  /// Instance method that delegates to the static version
  /// - Parameters:
  ///   - date: ISO date string (YYYY-MM-DD)
  ///   - snapshots: Array of snapshots to search
  /// - Returns: Applicable snapshot or nil
  nonisolated func snapshotForDate(_ date: String, from snapshots: [WageSnapshot]) -> WageSnapshot?
  {
    Self.snapshotForDate(date, from: snapshots)
  }

  /// Find the applicable snapshot for a specific date in one pass
  /// Static version for use in non-MainActor contexts (e.g., PayrollEngine)
  /// Marked nonisolated since it's a pure function with no side effects
  /// - Parameters:
  ///   - date: ISO date string (YYYY-MM-DD)
  ///   - snapshots: Array of snapshots to search
  /// - Returns: Applicable snapshot or nil
  nonisolated static func snapshotForDate(_ date: String, from snapshots: [WageSnapshot])
    -> WageSnapshot?
  {
    SharingComputeCore.snapshotForDate(date, from: snapshots, effectiveFrom: \.from_date)
  }

  /// Batch lookup for multiple dates
  /// - Parameters:
  ///   - dates: Array of ISO date strings
  ///   - snapshots: Array of snapshots to search
  /// - Returns: Dictionary mapping dates to applicable snapshots
  func snapshotsForDates(_ dates: [String], from snapshots: [WageSnapshot]) -> [String:
    WageSnapshot]
  {
    var map: [String: WageSnapshot] = [:]
    for date in dates {
      if let snapshot = snapshotForDate(date, from: snapshots) {
        map[date] = snapshot
      }
    }
    return map
  }

}
