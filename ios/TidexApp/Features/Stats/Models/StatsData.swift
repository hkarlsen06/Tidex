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
  let thisWeek: [DailyData]?  // Current week (Mon-Sun) - only for current month
  let bestWeek: BestWeekData?  // Best week - only for past months
  let employment: EmploymentData?  // Employment percentage data for the focus year
  let yearlyIncome: [MonthlyIncomeData]?  // Monthly income data for the focus year
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
  let day: Int  // Day of month (1-31)
  let currentMonth: Double  // Cumulative earnings up to this day
  let lastMonth: Double  // Last month's cumulative earnings up to same day
  let isToday: Bool  // Whether this is today's date
  let isFuture: Bool  // Whether this day is in the future

  var id: Int { day }
}

/// Daily earnings data for weekly bar charts
/// Used for both "This Week" (current month) and "Best Week" (past months)
struct DailyData: Codable, Equatable, Identifiable {
  let date: String  // Short day name (e.g., "Mon", "Man") or date number (e.g., "15.")
  let fullDay: String  // Full day name (e.g., "Monday", "Mandag")
  let earnings: Double  // Gross earnings for this day
  let hours: Double  // Hours worked this day
  let shifts: Int  // Number of shifts this day
  let fullDate: String  // ISO date string (YYYY-MM-DD)

  var id: String { fullDate }
}

/// Best week data for past months
/// Contains the week with highest earnings in that month
struct BestWeekData: Codable, Equatable {
  let weekData: [DailyData]  // Daily breakdown (Mon-Sun)
  let weekNumber: Int  // ISO week number
  let totalEarnings: Double  // Total earnings for the week
  let totalHours: Double  // Total hours for the week
}

/// Monthly employment percentage data
/// Shows average employment percentage for each month of the year
struct EmploymentMonthlyData: Codable, Equatable, Identifiable {
  let month: String  // Short month name (e.g., "jan.", "feb.")
  let fullMonth: String  // Full month name (e.g., "Januar", "Februar")
  let year: Int  // Year (e.g., 2025)
  let monthNumber: Int  // Month number (1-12)
  let averagePercentage: Double  // Average employment percentage for the month
  let hasShifts: Bool  // Whether the month has any shifts

  var id: String { "\(year)-\(monthNumber)" }
}

/// Employment data containing monthly breakdown and yearly average
struct EmploymentData: Codable, Equatable {
  let monthlyData: [EmploymentMonthlyData]  // All 12 months of the focus year
  let yearlyAverage: Double?  // Yearly average (nil if no shifts)
  let fullTimeHoursPerWeek: Double  // Full-time hours used (37.5 or 40)
}

/// Monthly income data for yearly income chart
/// Shows earnings, hours, and shifts for each month
struct MonthlyIncomeData: Codable, Equatable, Identifiable {
  let month: String  // Short month name (e.g., "jan.", "feb.")
  let fullMonth: String  // Full month name (e.g., "Januar", "Februar")
  let year: Int  // Year (e.g., 2026)
  let monthNumber: Int  // Month number (1-12)
  let earnings: Double  // Gross earnings for the month
  let hours: Double  // Total hours worked
  let shifts: Int  // Number of shifts

  var id: String { "\(year)-\(monthNumber)" }
}

// MARK: - Preview Data

extension StatsData {
  /// Empty placeholder data for a specific focus month.
  static func empty(year: Int, month: Int) -> StatsData {
    StatsData(
      focusMonth: FocusMonth(year: year, month: month),
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
      thisMonthCumulative: [],
      thisWeek: nil,
      bestWeek: nil,
      employment: nil,
      yearlyIncome: nil
    )
  }

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
    thisMonthCumulative: DailyCumulativeData.previewData,
    thisWeek: DailyData.previewThisWeek,
    bestWeek: nil,
    employment: EmploymentData.preview,
    yearlyIncome: MonthlyIncomeData.previewData
  )

  /// Preview data for past month (showing best week)
  static let previewPastMonth = StatsData(
    focusMonth: FocusMonth(year: 2024, month: 12),
    tax: TaxSettings(enabled: true, percentage: 7.5),
    currentMonth: MonthStats(
      totalEarnings: 20000,
      totalEarningsNet: 18500,
      totalHours: 85,
      shiftCount: 12
    ),
    lastMonth: MonthStats(
      totalEarnings: 18000,
      totalEarningsNet: 16650,
      totalHours: 75,
      shiftCount: 10
    ),
    percentageChange: 11,
    monthlyGoal: MonthlyGoal(
      enabled: true,
      target: 20000,
      progress: 18500,
      percentage: 92.5,
      remaining: 1500
    ),
    thisMonthCumulative: DailyCumulativeData.previewData,
    thisWeek: nil,
    bestWeek: BestWeekData.preview,
    employment: EmploymentData.preview,
    yearlyIncome: MonthlyIncomeData.previewData
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
    thisMonthCumulative: [],
    thisWeek: nil,
    bestWeek: nil,
    employment: nil,
    yearlyIncome: nil
  )
}

// MARK: - DailyData Preview

extension DailyData {
  /// Preview data for "This Week" chart
  /// Simulates a typical week with work on Mon, Thu, Fri
  static var previewThisWeek: [DailyData] {
    [
      DailyData(
        date: "Man", fullDay: "Mandag", earnings: 1250, hours: 6.5, shifts: 1,
        fullDate: "2025-01-20"),
      DailyData(
        date: "Tir", fullDay: "Tirsdag", earnings: 0, hours: 0, shifts: 0, fullDate: "2025-01-21"),
      DailyData(
        date: "Ons", fullDay: "Onsdag", earnings: 0, hours: 0, shifts: 0, fullDate: "2025-01-22"),
      DailyData(
        date: "Tor", fullDay: "Torsdag", earnings: 1450, hours: 7.5, shifts: 1,
        fullDate: "2025-01-23"),
      DailyData(
        date: "Fre", fullDay: "Fredag", earnings: 1280, hours: 6.5, shifts: 1,
        fullDate: "2025-01-24"),
      DailyData(
        date: "Lør", fullDay: "Lørdag", earnings: 0, hours: 0, shifts: 0, fullDate: "2025-01-25"),
      DailyData(
        date: "Søn", fullDay: "Søndag", earnings: 0, hours: 0, shifts: 0, fullDate: "2025-01-26"),
    ]
  }
}

// MARK: - BestWeekData Preview

extension BestWeekData {
  /// Preview data for "Best Week" chart (past month)
  static var preview: BestWeekData {
    BestWeekData(
      weekData: [
        DailyData(
          date: "9.", fullDay: "Mandag", earnings: 1400, hours: 7, shifts: 1, fullDate: "2024-12-09"
        ),
        DailyData(
          date: "10.", fullDay: "Tirsdag", earnings: 1350, hours: 7, shifts: 1,
          fullDate: "2024-12-10"),
        DailyData(
          date: "11.", fullDay: "Onsdag", earnings: 0, hours: 0, shifts: 0, fullDate: "2024-12-11"),
        DailyData(
          date: "12.", fullDay: "Torsdag", earnings: 1500, hours: 8, shifts: 1,
          fullDate: "2024-12-12"),
        DailyData(
          date: "13.", fullDay: "Fredag", earnings: 1600, hours: 8, shifts: 1,
          fullDate: "2024-12-13"),
        DailyData(
          date: "14.", fullDay: "Lørdag", earnings: 1800, hours: 9, shifts: 1,
          fullDate: "2024-12-14"),
        DailyData(
          date: "15.", fullDay: "Søndag", earnings: 0, hours: 0, shifts: 0, fullDate: "2024-12-15"),
      ],
      weekNumber: 50,
      totalEarnings: 7650,
      totalHours: 39
    )
  }
}

// MARK: - DailyCumulativeData Preview

extension DailyCumulativeData {
  /// Generate sample cumulative data for previews
  /// Simulates earnings accumulating through the month
  static var previewData: [DailyCumulativeData] {
    let daysInMonth = 31
    let today = 15  // Simulate mid-month

    // Last month pattern: steady earnings with some variation
    let lastMonthDailyEarnings = [
      0, 0, 2500, 0, 0, 0, 2800, 0, 0, 3000, 0, 0, 0, 2600, 0,
      0, 2900, 0, 0, 0, 2700, 0, 0, 3100, 0, 0, 0, 2800, 0, 0, 0,
    ]

    // Current month pattern: similar earnings
    let currentMonthDailyEarnings = [
      0, 0, 0, 3200, 0, 0, 0, 2900, 0, 0, 3100, 0, 0, 0, 2800, 0,
      0, 3000, 0, 0, 0, 2700, 0, 0, 3200, 0, 0, 0, 2900, 0, 0,
    ]

    var data: [DailyCumulativeData] = []
    var lastMonthCumulative: Double = 0
    var currentMonthCumulative: Double = 0

    for day in 1...daysInMonth {
      lastMonthCumulative += Double(lastMonthDailyEarnings[day - 1])
      currentMonthCumulative += Double(currentMonthDailyEarnings[day - 1])

      data.append(
        DailyCumulativeData(
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

// MARK: - EmploymentData Preview

extension EmploymentData {
  /// Preview data showing typical employment percentages across a year
  static var preview: EmploymentData {
    let shortMonthNames = [
      "jan.", "feb.", "mar.", "apr.", "mai", "jun.",
      "jul.", "aug.", "sep.", "okt.", "nov.", "des.",
    ]
    let fullMonthNames = [
      "Januar", "Februar", "Mars", "April", "Mai", "Juni",
      "Juli", "August", "September", "Oktober", "November", "Desember",
    ]
    // Sample percentages simulating typical part-time work
    let percentages: [Double] = [
      32.5, 35.0, 50.0, 55.0, 70.0, 52.0,
      25.0, 48.0, 50.0, 42.0, 45.0, 48.0,
    ]

    let monthlyData = (0..<12).map { index in
      EmploymentMonthlyData(
        month: shortMonthNames[index],
        fullMonth: fullMonthNames[index],
        year: 2025,
        monthNumber: index + 1,
        averagePercentage: percentages[index],
        hasShifts: percentages[index] > 0
      )
    }

    // Calculate yearly average
    let withShifts = percentages.filter { $0 > 0 }
    let yearlyAvg = withShifts.isEmpty ? nil : withShifts.reduce(0, +) / Double(withShifts.count)

    return EmploymentData(
      monthlyData: monthlyData,
      yearlyAverage: yearlyAvg.map { ($0 * 10).rounded() / 10 },  // Round to 1 decimal
      fullTimeHoursPerWeek: 40
    )
  }
}

// MARK: - MonthlyIncomeData Preview

extension MonthlyIncomeData {
  /// Preview data showing monthly income for a year
  /// Simulates typical income pattern with current month highlighted
  static var previewData: [MonthlyIncomeData] {
    let shortMonthNames = [
      "jan.", "feb.", "mar.", "apr.", "mai", "jun.",
      "jul.", "aug.", "sep.", "okt.", "nov.", "des.",
    ]
    let fullMonthNames = [
      "Januar", "Februar", "Mars", "April", "Mai", "Juni",
      "Juli", "August", "September", "Oktober", "November", "Desember",
    ]

    // Sample earnings simulating varied monthly income
    let earnings: [Double] = [
      13772, 5200, 6100, 5800, 4900, 5500,
      6200, 0, 0, 0, 0, 0,
    ]
    let hours: [Double] = [
      60.3, 28, 32, 30, 25, 28,
      33, 0, 0, 0, 0, 0,
    ]
    let shifts: [Int] = [
      9, 4, 5, 4, 4, 4,
      5, 0, 0, 0, 0, 0,
    ]

    return (0..<12).map { index in
      MonthlyIncomeData(
        month: shortMonthNames[index],
        fullMonth: fullMonthNames[index],
        year: 2026,
        monthNumber: index + 1,
        earnings: earnings[index],
        hours: hours[index],
        shifts: shifts[index]
      )
    }
  }
}
