import Foundation

// MARK: - Stats API Response

/// Stats data from the /api/stats endpoint
/// Matches the web app's StatsData type from lib/services/stats.ts
struct StatsData: Codable, Equatable {
    let focusMonth: FocusMonth
    let tax: TaxSettings
    let currentMonth: MonthStats
    let lastMonth: MonthStats
    let percentageChange: Double?
    let monthlyGoal: MonthlyGoal
}

// MARK: - Sub-types

struct FocusMonth: Codable, Equatable {
    let year: Int
    let month: Int
}

struct TaxSettings: Codable, Equatable {
    let enabled: Bool
    let percentage: Double
}

struct MonthStats: Codable, Equatable {
    let totalEarnings: Double
    let totalEarningsNet: Double
    let totalHours: Double
    let shiftCount: Int
}

struct MonthlyGoal: Codable, Equatable {
    let enabled: Bool
    let target: Double
    let progress: Double
    let percentage: Double
    let remaining: Double
}

// MARK: - Preview Data

extension StatsData {
    /// Sample data for previews and testing
    static let preview = StatsData(
        focusMonth: FocusMonth(year: 2025, month: 1),
        tax: TaxSettings(enabled: true, percentage: 7.5),
        currentMonth: MonthStats(
            totalEarnings: 13772,
            totalEarningsNet: 12808,
            totalHours: 60.3,
            shiftCount: 9
        ),
        lastMonth: MonthStats(
            totalEarnings: 20000,
            totalEarningsNet: 18500,
            totalHours: 85,
            shiftCount: 12
        ),
        percentageChange: -32,
        monthlyGoal: MonthlyGoal(
            enabled: true,
            target: 15000,
            progress: 12808,
            percentage: 85.4,
            remaining: 2192
        )
    )

    /// Empty data for when no shifts exist
    static let empty = StatsData(
        focusMonth: FocusMonth(year: 2025, month: 1),
        tax: TaxSettings(enabled: false, percentage: 0),
        currentMonth: MonthStats(
            totalEarnings: 0,
            totalEarningsNet: 0,
            totalHours: 0,
            shiftCount: 0
        ),
        lastMonth: MonthStats(
            totalEarnings: 0,
            totalEarningsNet: 0,
            totalHours: 0,
            shiftCount: 0
        ),
        percentageChange: nil,
        monthlyGoal: MonthlyGoal(
            enabled: false,
            target: 0,
            progress: 0,
            percentage: 0,
            remaining: 0
        )
    )
}
