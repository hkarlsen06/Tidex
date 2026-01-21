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
    let thisMonthCumulative: [DailyCumulativeData]
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

/// Daily cumulative earnings data for progress chart
/// Shows cumulative earnings per day for current month vs last month
struct DailyCumulativeData: Codable, Equatable, Identifiable {
    let day: Int           // Day of month (1-31)
    let currentMonth: Double  // Cumulative earnings up to this day
    let lastMonth: Double     // Last month's cumulative earnings up to same day
    let isToday: Bool         // Whether this is today's date
    let isFuture: Bool        // Whether this day is in the future

    var id: Int { day }
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
        ),
        thisMonthCumulative: DailyCumulativeData.previewData
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
        ),
        thisMonthCumulative: []
    )
}

// MARK: - DailyCumulativeData Preview

extension DailyCumulativeData {
    /// Generate sample cumulative data for previews
    /// Simulates earnings accumulating through the month
    static var previewData: [DailyCumulativeData] {
        let daysInMonth = 31
        let today = 15 // Simulate mid-month

        // Last month pattern: steady earnings with some variation
        let lastMonthDailyEarnings = [
            0, 0, 2500, 0, 0, 0, 2800, 0, 0, 3000, 0, 0, 0, 2600, 0,
            0, 2900, 0, 0, 0, 2700, 0, 0, 3100, 0, 0, 0, 2800, 0, 0, 0
        ]

        // Current month pattern: similar earnings
        let currentMonthDailyEarnings = [
            0, 0, 0, 3200, 0, 0, 0, 2900, 0, 0, 3100, 0, 0, 0, 2800, 0,
            0, 3000, 0, 0, 0, 2700, 0, 0, 3200, 0, 0, 0, 2900, 0, 0
        ]

        var data: [DailyCumulativeData] = []
        var lastMonthCumulative: Double = 0
        var currentMonthCumulative: Double = 0

        for day in 1...daysInMonth {
            lastMonthCumulative += Double(lastMonthDailyEarnings[day - 1])
            currentMonthCumulative += Double(currentMonthDailyEarnings[day - 1])

            data.append(DailyCumulativeData(
                day: day,
                currentMonth: currentMonthCumulative,
                lastMonth: lastMonthCumulative,
                isToday: day == today,
                isFuture: day > today
            ))
        }

        return data
    }
}
