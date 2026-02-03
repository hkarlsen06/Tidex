import Foundation
import Supabase

/// Service for fetching and resolving wage snapshots from Supabase
/// Uses binary search for efficient snapshot resolution by date
@MainActor
final class SnapshotsService: ObservableObject {
    static let shared = SnapshotsService()

    @Published private(set) var snapshots: [WageSnapshot] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

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
            let response: [WageSnapshot] = try await supabase
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

    /// Find the applicable snapshot for a specific date using binary search
    /// Instance method that delegates to the static version
    /// - Parameters:
    ///   - date: ISO date string (YYYY-MM-DD)
    ///   - snapshots: Array of snapshots to search
    /// - Returns: Applicable snapshot or nil
    nonisolated func snapshotForDate(_ date: String, from snapshots: [WageSnapshot]) -> WageSnapshot? {
        Self.snapshotForDate(date, from: snapshots)
    }

    /// Find the applicable snapshot for a specific date using binary search
    /// Static version for use in non-MainActor contexts (e.g., PayrollEngine)
    /// Marked nonisolated since it's a pure function with no side effects
    /// - Parameters:
    ///   - date: ISO date string (YYYY-MM-DD)
    ///   - snapshots: Array of snapshots to search
    /// - Returns: Applicable snapshot or nil
    nonisolated static func snapshotForDate(_ date: String, from snapshots: [WageSnapshot]) -> WageSnapshot? {
        // Find baseline snapshot (from_date == nil) as fallback
        let baseline = snapshots.first { $0.from_date == nil }

        // Filter to only dated snapshots and sort ascending by from_date
        // (DB returns DESC, so we need to filter and sort)
        let dated = snapshots
            .filter { $0.from_date != nil }
            .sorted { ($0.from_date ?? "") < ($1.from_date ?? "") }

        // Binary search: find the latest snapshot where from_date <= date
        var left = 0
        var right = dated.count - 1
        var result: WageSnapshot? = nil

        while left <= right {
            let mid = (left + right) / 2
            if let midDate = dated[mid].from_date, midDate <= date {
                // This snapshot is valid, but there might be a later one
                result = dated[mid]
                left = mid + 1
            } else {
                // This snapshot starts after our target date
                right = mid - 1
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
    func snapshotsForDates(_ dates: [String], from snapshots: [WageSnapshot]) -> [String: WageSnapshot] {
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
