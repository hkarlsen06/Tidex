import Foundation
import Supabase

/// Service for fetching and resolving wage snapshots from Supabase
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
      let response: [WageSnapshot] =
        try await supabase
        .from("wage_snapshots")
        .select()
        .eq("user_id", value: userId)
        .order("from_date", ascending: false, nullsFirst: false)
        .execute()
        .value

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
    var baseline: WageSnapshot?
    var result: WageSnapshot?
    var latestDate = ""

    for snapshot in snapshots {
      guard let fromDate = snapshot.from_date else {
        if baseline == nil {
          baseline = snapshot
        }
        continue
      }

      // Equal dates keep the last input entry, matching the previous stable sort
      // followed by a search for the rightmost applicable snapshot.
      if fromDate <= date, fromDate >= latestDate {
        result = snapshot
        latestDate = fromDate
      }
    }

    // Use dated snapshot if found, otherwise fall back to baseline
    return result ?? baseline
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

  /// Get the snapshot for a payout date (used for tax calculations)
  /// Tax settings are based on when you receive the money (payout month)
  /// - Parameters:
  ///   - earningsYear: Year of the earnings month
  ///   - earningsMonth: Month of earnings (1-12)
  ///   - payrollDay: Day of month for payroll
  ///   - snapshots: Array of snapshots to search
  /// - Returns: Tax settings for the payout
  func payoutTaxSettings(
    earningsYear: Int,
    earningsMonth: Int,
    payrollDay: Int,
    from snapshots: [WageSnapshot]
  ) -> PayoutTaxSettings? {
    let payoutDate = calculatePayoutDate(
      earningsYear: earningsYear,
      earningsMonth: earningsMonth,
      payrollDay: payrollDay
    )

    guard let snapshot = snapshotForDate(payoutDate, from: snapshots) else {
      return nil
    }

    return PayoutTaxSettings(
      enabled: snapshot.effectiveTaxEnabled,
      percentage: snapshot.effectiveTaxPercentage
    )
  }

  // MARK: - Private Helpers

  /// Calculate the payout date for earnings from a given month
  /// Payout is in the month after earnings, on the user's payroll_day
  private func calculatePayoutDate(
    earningsYear: Int,
    earningsMonth: Int,
    payrollDay: Int
  ) -> String {
    var payoutYear = earningsYear
    var payoutMonth = earningsMonth + 1

    if payoutMonth > 12 {
      payoutMonth = 1
      payoutYear += 1
    }

    // Handle edge case: payroll_day exceeds days in payout month
    let daysInPayoutMonth = Date.daysInMonth(year: payoutYear, month: payoutMonth)
    let effectivePayrollDay = min(payrollDay, daysInPayoutMonth)

    return String(format: "%04d-%02d-%02d", payoutYear, payoutMonth, effectivePayrollDay)
  }
}
