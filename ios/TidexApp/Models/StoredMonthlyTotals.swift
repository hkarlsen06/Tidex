import Foundation

/// Represents monthly earnings totals stored in App Group UserDefaults
/// for TotalCard widget consumption.
///
/// Stores both projected (all shifts) and completed (earned to date) amounts
/// to match the main app's TotalCard display logic.
struct StoredMonthlyTotals: Codable {
    // MARK: - Projected Totals (all shifts in month)

    /// Gross earnings for all shifts in the month
    let gross: Double

    /// Net earnings for all shifts (after tax), nil if tax disabled
    let net: Double?

    // MARK: - Completed Totals (earned to date)

    /// Gross earnings from completed shifts only
    let completedGross: Double

    /// Net earnings from completed shifts, nil if tax disabled
    let completedNet: Double?

    // MARK: - Shift Counts

    /// Total number of shifts in the month
    let shiftCount: Int

    /// Number of future/planned shifts remaining
    let plannedCount: Int

    /// Total hours worked this month (all shifts)
    let totalHours: Double

    // MARK: - Comparison

    /// Percentage change compared to previous month (0-100 scale)
    /// Nil if no previous month data for comparison
    let percentageChange: Double?

    // MARK: - Settings

    /// Month identifier in "YYYY-MM" format (e.g., "2026-02")
    let yearMonth: String

    /// Whether tax calculation is enabled
    let taxEnabled: Bool

    // MARK: - Formatting

    /// Locale for widget display ("no" or "en")
    let locale: String

    /// Currency symbol (e.g., "kr", "$", "€")
    let currencySymbol: String

    // MARK: - Metadata

    /// When this data was last updated
    let updatedAt: Date
}
