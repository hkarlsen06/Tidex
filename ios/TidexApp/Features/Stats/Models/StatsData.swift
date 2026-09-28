import Foundation

// MARK: - Stats API Response

/// Stats data from the /api/stats endpoint
/// Matches the web app's StatsData type from lib/services/stats.ts
struct StatsData: Codable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order
  let focusMonth: FocusMonth  // swiftlint:disable:this explicit_acl
  let tax: TaxSettings  // swiftlint:disable:this explicit_acl
  let currentMonth: MonthStats  // swiftlint:disable:this explicit_acl
  let currentMonthCurrencyAggregate: JobCurrencyAggregateResolution?  // swiftlint:disable:this explicit_acl
  let lastMonth: MonthStats  // swiftlint:disable:this explicit_acl
  let percentageChange: Double?  // swiftlint:disable:this explicit_acl
  let thisMonthCumulative: [DailyCumulativeData]  // swiftlint:disable:this explicit_acl
  let thisWeek: [DailyData]?  // Current week (Mon-Sun) - only for current month // swiftlint:disable:this discouraged_optional_collection explicit_acl line_length
  let bestWeek: BestWeekData?  // Best week - only for past months // swiftlint:disable:this explicit_acl
  let employment: EmploymentData?  // Employment percentage data for the focus year // swiftlint:disable:this explicit_acl line_length
  let yearlyIncome: [MonthlyIncomeData]?  // Monthly income data for the focus year // swiftlint:disable:this discouraged_optional_collection explicit_acl line_length
}

// MARK: - Sub-types

struct FocusMonth: Codable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let year: Int  // swiftlint:disable:this explicit_acl
  let month: Int  // swiftlint:disable:this explicit_acl
}

struct TaxSettings: Codable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let enabled: Bool  // swiftlint:disable:this explicit_acl
  let percentage: Double  // swiftlint:disable:this explicit_acl
}

struct MonthStats: Codable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let totalEarnings: Double  // swiftlint:disable:this explicit_acl
  let totalEarningsNet: Double  // swiftlint:disable:this explicit_acl
  let totalHours: Double  // swiftlint:disable:this explicit_acl
  let shiftCount: Int  // swiftlint:disable:this explicit_acl
}

/// Daily cumulative earnings data for progress chart
/// Shows cumulative earnings per day for current month vs last month
struct DailyCumulativeData: Codable, Equatable, Identifiable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl line_length
  let day: Int  // Day of month (1-31) // swiftlint:disable:this explicit_acl
  let currentMonth: Double  // Cumulative earnings up to this day // swiftlint:disable:this explicit_acl
  let lastMonth: Double  // Last month's cumulative earnings up to same day // swiftlint:disable:this explicit_acl
  let isToday: Bool  // Whether this is today's date // swiftlint:disable:this explicit_acl
  let isFuture: Bool  // Whether this day is in the future // swiftlint:disable:this explicit_acl

  var id: Int { day }  // swiftlint:disable:this explicit_acl
}

/// Daily earnings data for weekly bar charts
/// Used for both "This Week" (current month) and "Best Week" (past months)
struct DailyData: Codable, Equatable, Identifiable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let date: String  // Short day name (e.g., "Mon", "Man") or date number (e.g., "15.") // swiftlint:disable:this explicit_acl line_length
  let fullDay: String  // Full day name (e.g., "Monday", "Mandag") // swiftlint:disable:this explicit_acl
  let earnings: Double  // Gross earnings for this day // swiftlint:disable:this explicit_acl
  let hours: Double  // Hours worked this day // swiftlint:disable:this explicit_acl
  let shifts: Int  // Number of shifts this day // swiftlint:disable:this explicit_acl
  let fullDate: String  // ISO date string (YYYY-MM-DD) // swiftlint:disable:this explicit_acl

  var id: String { fullDate }  // swiftlint:disable:this explicit_acl
}

/// Best week data for past months
/// Contains the week with highest earnings in that month
struct BestWeekData: Codable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let weekData: [DailyData]  // Daily breakdown (Mon-Sun) // swiftlint:disable:this explicit_acl
  let weekNumber: Int  // ISO week number // swiftlint:disable:this explicit_acl
  let totalEarnings: Double  // Total earnings for the week // swiftlint:disable:this explicit_acl
  let totalHours: Double  // Total hours for the week // swiftlint:disable:this explicit_acl
}

/// Monthly employment percentage data
/// Shows average employment percentage for each month of the year
struct EmploymentMonthlyData: Codable, Equatable, Identifiable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl line_length
  let month: String  // Short month name (e.g., "jan.", "feb.") // swiftlint:disable:this explicit_acl
  let fullMonth: String  // Full month name (e.g., "Januar", "Februar") // swiftlint:disable:this explicit_acl
  let year: Int  // Year (e.g., 2025) // swiftlint:disable:this explicit_acl
  let monthNumber: Int  // Month number (1-12) // swiftlint:disable:this explicit_acl
  let averagePercentage: Double  // Average employment percentage for the month // swiftlint:disable:this explicit_acl
  let hasShifts: Bool  // Whether the month has any shifts // swiftlint:disable:this explicit_acl

  var id: String { "\(year)-\(monthNumber)" }  // swiftlint:disable:this explicit_acl
}

/// Employment data containing monthly breakdown and yearly average
struct EmploymentData: Codable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let monthlyData: [EmploymentMonthlyData]  // All 12 months of the focus year // swiftlint:disable:this explicit_acl
  let yearlyAverage: Double?  // Yearly average (nil if no shifts) // swiftlint:disable:this explicit_acl
  let fullTimeHoursPerWeek: Double  // Full-time hours used (37.5 or 40) // swiftlint:disable:this explicit_acl

  func completedMonthsAverage(  // swiftlint:disable:this explicit_acl
    now: Date = Date(),
    calendar: Calendar = .gregorianCurrent
  ) -> Double? {
    let includedMonths = completedAverageMonthNumbers(now: now, calendar: calendar)  // swiftlint:disable:this explicit_type_interface line_length
    guard !includedMonths.isEmpty else { return nil }  // swiftlint:disable:this conditional_returns_on_newline

    let values =  // swiftlint:disable:this explicit_type_interface
      monthlyData
      .filter { includedMonths.contains($0.monthNumber) }
      .map(\.averagePercentage)

    guard !values.isEmpty else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    let average = values.reduce(0, +) / Double(values.count)  // swiftlint:disable:this explicit_type_interface
    return (average * 10).rounded() / 10  // swiftlint:disable:this no_magic_numbers
  }

  func completedAverageRangeLabel(  // swiftlint:disable:this explicit_acl
    now: Date = Date(),
    calendar: Calendar = .gregorianCurrent
  ) -> String? {
    let includedMonths = completedAverageMonthNumbers(now: now, calendar: calendar).sorted()  // swiftlint:disable:this explicit_type_interface line_length
    guard includedMonths.isContiguous else { return nil }  // swiftlint:disable:this conditional_returns_on_newline

    guard let firstMonth = includedMonths.first,
      let lastMonth = includedMonths.last,
      let firstLabel = monthlyData.first(where: { $0.monthNumber == firstMonth })?.month,
      let lastLabel = monthlyData.first(where: { $0.monthNumber == lastMonth })?.month
    else {
      return nil
    }

    return firstMonth == lastMonth ? firstLabel : "\(firstLabel)-\(lastLabel)"
  }

  func isIncludedInCompletedAverage(  // swiftlint:disable:this explicit_acl
    _ month: EmploymentMonthlyData,
    now: Date = Date(),
    calendar: Calendar = .gregorianCurrent
  ) -> Bool {
    completedAverageMonthNumbers(now: now, calendar: calendar).contains(month.monthNumber)
  }

  private func completedAverageMonthNumbers(
    now: Date,
    calendar inputCalendar: Calendar
  ) -> Set<Int> {
    guard let focusYear = monthlyData.first?.year else { return [] }  // swiftlint:disable:this conditional_returns_on_newline line_length

    var calendar = inputCalendar  // swiftlint:disable:this explicit_type_interface
    calendar.timeZone = Date.localTimeZone

    let currentYear = calendar.component(.year, from: now)  // swiftlint:disable:this explicit_type_interface
    let currentMonth = calendar.component(.month, from: now)  // swiftlint:disable:this explicit_type_interface

    let completedThroughMonth: Int
    if focusYear < currentYear {
      completedThroughMonth = 12  // swiftlint:disable:this no_magic_numbers
    } else if focusYear == currentYear {
      completedThroughMonth = max(currentMonth - 1, 0)
    } else {
      completedThroughMonth = 0
    }

    guard completedThroughMonth > 0 else { return [] }  // swiftlint:disable:this conditional_returns_on_newline
    return Set(
      monthlyData
        .filter { $0.monthNumber <= completedThroughMonth && $0.hasShifts }
        .map(\.monthNumber)
    )
  }
}

extension [Int] {  // swiftlint:disable:this extension_access_modifier file_types_order
  fileprivate var isContiguous: Bool {  // swiftlint:disable:this strict_fileprivate
    guard let first, let last else { return true }  // swiftlint:disable:this conditional_returns_on_newline
    return count == last - first + 1
  }
}

/// Monthly income data for yearly income chart
/// Shows earnings, hours, and shifts for each month
struct MonthlyIncomeData: Codable, Equatable, Identifiable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl line_length
  let month: String  // Short month name (e.g., "jan.", "feb.") // swiftlint:disable:this explicit_acl
  let fullMonth: String  // Full month name (e.g., "Januar", "Februar") // swiftlint:disable:this explicit_acl
  let year: Int  // Year (e.g., 2026) // swiftlint:disable:this explicit_acl
  let monthNumber: Int  // Month number (1-12) // swiftlint:disable:this explicit_acl
  let earnings: Double  // Gross earnings for the month // swiftlint:disable:this explicit_acl
  let hours: Double  // Total hours worked // swiftlint:disable:this explicit_acl
  let shifts: Int  // Number of shifts // swiftlint:disable:this explicit_acl

  var id: String { "\(year)-\(monthNumber)" }  // swiftlint:disable:this explicit_acl
}

// MARK: - Preview Data

extension StatsData {  // swiftlint:disable:this no_grouping_extension
  /// Empty placeholder data for a specific focus month.
  static func empty(year: Int, month: Int) -> StatsData {  // swiftlint:disable:this explicit_acl type_contents_order
    StatsData(
      focusMonth: FocusMonth(year: year, month: month),
      tax: TaxSettings(enabled: false, percentage: 0),
      currentMonth: MonthStats(
        totalEarnings: 0,
        totalEarningsNet: 0,
        totalHours: 0,
        shiftCount: 0
      ),
      currentMonthCurrencyAggregate: nil,
      lastMonth: MonthStats(
        totalEarnings: 0,
        totalEarningsNet: 0,
        totalHours: 0,
        shiftCount: 0
      ),
      percentageChange: nil,
      thisMonthCumulative: [],
      thisWeek: nil,
      bestWeek: nil,
      employment: nil,
      yearlyIncome: nil
    )
  }

  /// Sample data for previews and testing
  static let preview = StatsData(  // swiftlint:disable:this explicit_acl explicit_type_interface
    focusMonth: FocusMonth(year: 2_025, month: 1),  // swiftlint:disable:this no_magic_numbers
    tax: TaxSettings(enabled: true, percentage: 7.5),  // swiftlint:disable:this no_magic_numbers
    currentMonth: MonthStats(
      totalEarnings: 13_772,  // swiftlint:disable:this no_magic_numbers
      totalEarningsNet: 12_808,  // swiftlint:disable:this no_magic_numbers
      totalHours: 60.3,  // swiftlint:disable:this no_magic_numbers
      shiftCount: 9  // swiftlint:disable:this no_magic_numbers
    ),
    currentMonthCurrencyAggregate: nil,
    lastMonth: MonthStats(
      totalEarnings: 20_000,  // swiftlint:disable:this no_magic_numbers
      totalEarningsNet: 18_500,  // swiftlint:disable:this no_magic_numbers
      totalHours: 85,  // swiftlint:disable:this no_magic_numbers
      shiftCount: 12  // swiftlint:disable:this no_magic_numbers
    ),
    percentageChange: -32,  // swiftlint:disable:this no_magic_numbers
    thisMonthCumulative: DailyCumulativeData.previewData,
    thisWeek: DailyData.previewThisWeek,
    bestWeek: nil,
    employment: EmploymentData.preview,
    yearlyIncome: MonthlyIncomeData.previewData
  )

  /// Preview data for past month (showing best week)
  static let previewPastMonth = StatsData(  // swiftlint:disable:this explicit_acl explicit_type_interface
    focusMonth: FocusMonth(year: 2_024, month: 12),  // swiftlint:disable:this no_magic_numbers
    tax: TaxSettings(enabled: true, percentage: 7.5),  // swiftlint:disable:this no_magic_numbers
    currentMonth: MonthStats(
      totalEarnings: 20_000,  // swiftlint:disable:this no_magic_numbers
      totalEarningsNet: 18_500,  // swiftlint:disable:this no_magic_numbers
      totalHours: 85,  // swiftlint:disable:this no_magic_numbers
      shiftCount: 12  // swiftlint:disable:this no_magic_numbers
    ),
    currentMonthCurrencyAggregate: nil,
    lastMonth: MonthStats(
      totalEarnings: 18_000,  // swiftlint:disable:this no_magic_numbers
      totalEarningsNet: 16_650,  // swiftlint:disable:this no_magic_numbers
      totalHours: 75,  // swiftlint:disable:this no_magic_numbers
      shiftCount: 10  // swiftlint:disable:this no_magic_numbers
    ),
    percentageChange: 11,  // swiftlint:disable:this no_magic_numbers
    thisMonthCumulative: DailyCumulativeData.previewData,
    thisWeek: nil,
    bestWeek: BestWeekData.preview,
    employment: EmploymentData.preview,
    yearlyIncome: MonthlyIncomeData.previewData
  )

  /// Empty data for when no shifts exist
  static let empty = StatsData(  // swiftlint:disable:this explicit_acl explicit_type_interface
    focusMonth: FocusMonth(year: 2_025, month: 1),  // swiftlint:disable:this no_magic_numbers
    tax: TaxSettings(enabled: false, percentage: 0),
    currentMonth: MonthStats(
      totalEarnings: 0,
      totalEarningsNet: 0,
      totalHours: 0,
      shiftCount: 0
    ),
    currentMonthCurrencyAggregate: nil,
    lastMonth: MonthStats(
      totalEarnings: 0,
      totalEarningsNet: 0,
      totalHours: 0,
      shiftCount: 0
    ),
    percentageChange: nil,
    thisMonthCumulative: [],
    thisWeek: nil,
    bestWeek: nil,
    employment: nil,
    yearlyIncome: nil
  )
}

// MARK: - DailyData Preview

extension DailyData {  // swiftlint:disable:this no_grouping_extension
  /// Preview data for "This Week" chart
  /// Simulates a typical week with work on Mon, Thu, Fri
  static var previewThisWeek: [DailyData] {  // swiftlint:disable:this explicit_acl
    [
      DailyData(  // swiftlint:disable:this multiline_call_arguments
        date: "Man", fullDay: "Mandag", earnings: 1_250, hours: 6.5, shifts: 1,  // swiftlint:disable:this line_length no_magic_numbers
        fullDate: "2025-01-20"),  // swiftlint:disable:this multiline_arguments_brackets
      DailyData(
        date: "Tir", fullDay: "Tirsdag", earnings: 0, hours: 0, shifts: 0, fullDate: "2025-01-21"),  // swiftlint:disable:this line_length multiline_arguments_brackets
      DailyData(
        date: "Ons", fullDay: "Onsdag", earnings: 0, hours: 0, shifts: 0, fullDate: "2025-01-22"),  // swiftlint:disable:this line_length multiline_arguments_brackets
      DailyData(  // swiftlint:disable:this multiline_call_arguments
        date: "Tor", fullDay: "Torsdag", earnings: 1_450, hours: 7.5, shifts: 1,  // swiftlint:disable:this line_length no_magic_numbers
        fullDate: "2025-01-23"),  // swiftlint:disable:this multiline_arguments_brackets
      DailyData(  // swiftlint:disable:this multiline_call_arguments
        date: "Fre", fullDay: "Fredag", earnings: 1_280, hours: 6.5, shifts: 1,  // swiftlint:disable:this line_length no_magic_numbers
        fullDate: "2025-01-24"),  // swiftlint:disable:this multiline_arguments_brackets
      DailyData(
        date: "Lør", fullDay: "Lørdag", earnings: 0, hours: 0, shifts: 0, fullDate: "2025-01-25"),  // swiftlint:disable:this line_length multiline_arguments_brackets
      DailyData(
        date: "Søn", fullDay: "Søndag", earnings: 0, hours: 0, shifts: 0, fullDate: "2025-01-26"),  // swiftlint:disable:this line_length multiline_arguments_brackets
    ]
  }
}

// MARK: - BestWeekData Preview

extension BestWeekData {  // swiftlint:disable:this no_grouping_extension
  /// Preview data for "Best Week" chart (past month)
  static var preview: BestWeekData {  // swiftlint:disable:this explicit_acl
    BestWeekData(
      weekData: [
        DailyData(  // swiftlint:disable:this multiline_call_arguments
          date: "9.", fullDay: "Mandag", earnings: 1_400, hours: 7, shifts: 1,  // swiftlint:disable:this line_length no_magic_numbers
          fullDate: "2024-12-09"
        ),
        DailyData(  // swiftlint:disable:this multiline_call_arguments
          date: "10.", fullDay: "Tirsdag", earnings: 1_350, hours: 7, shifts: 1,  // swiftlint:disable:this line_length no_magic_numbers
          fullDate: "2024-12-10"),  // swiftlint:disable:this multiline_arguments_brackets
        DailyData(
          date: "11.", fullDay: "Onsdag", earnings: 0, hours: 0, shifts: 0, fullDate: "2024-12-11"),  // swiftlint:disable:this line_length multiline_arguments_brackets
        DailyData(  // swiftlint:disable:this multiline_call_arguments
          date: "12.", fullDay: "Torsdag", earnings: 1_500, hours: 8, shifts: 1,  // swiftlint:disable:this line_length no_magic_numbers
          fullDate: "2024-12-12"),  // swiftlint:disable:this multiline_arguments_brackets
        DailyData(  // swiftlint:disable:this multiline_call_arguments
          date: "13.", fullDay: "Fredag", earnings: 1_600, hours: 8, shifts: 1,  // swiftlint:disable:this line_length no_magic_numbers
          fullDate: "2024-12-13"),  // swiftlint:disable:this multiline_arguments_brackets
        DailyData(  // swiftlint:disable:this multiline_call_arguments
          date: "14.", fullDay: "Lørdag", earnings: 1_800, hours: 9, shifts: 1,  // swiftlint:disable:this line_length no_magic_numbers
          fullDate: "2024-12-14"),  // swiftlint:disable:this multiline_arguments_brackets
        DailyData(
          date: "15.", fullDay: "Søndag", earnings: 0, hours: 0, shifts: 0, fullDate: "2024-12-15"),  // swiftlint:disable:this line_length multiline_arguments_brackets
      ],
      weekNumber: 50,  // swiftlint:disable:this no_magic_numbers
      totalEarnings: 7_650,  // swiftlint:disable:this no_magic_numbers
      totalHours: 39  // swiftlint:disable:this no_magic_numbers
    )
  }
}

// MARK: - DailyCumulativeData Preview

extension DailyCumulativeData {  // swiftlint:disable:this no_grouping_extension
  /// Generate sample cumulative data for previews
  /// Simulates earnings accumulating through the month
  static var previewData: [DailyCumulativeData] {  // swiftlint:disable:this explicit_acl
    let daysInMonth = 31  // swiftlint:disable:this explicit_type_interface
    let today = 15  // Simulate mid-month // swiftlint:disable:this explicit_type_interface

    // Last month pattern: steady earnings with some variation
    let lastMonthDailyEarnings = [  // swiftlint:disable:this explicit_type_interface
      0, 0, 2_500, 0, 0, 0, 2_800, 0, 0, 3_000, 0, 0, 0, 2_600, 0,  // swiftlint:disable:this no_magic_numbers
      0, 2_900, 0, 0, 0, 2_700, 0, 0, 3_100, 0, 0, 0, 2_800, 0, 0, 0,  // swiftlint:disable:this no_magic_numbers
    ]

    // Current month pattern: similar earnings
    let currentMonthDailyEarnings = [  // swiftlint:disable:this explicit_type_interface
      0, 0, 0, 3_200, 0, 0, 0, 2_900, 0, 0, 3_100, 0, 0, 0, 2_800, 0,  // swiftlint:disable:this no_magic_numbers
      0, 3_000, 0, 0, 0, 2_700, 0, 0, 3_200, 0, 0, 0, 2_900, 0, 0,  // swiftlint:disable:this no_magic_numbers
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
        ))  // swiftlint:disable:this multiline_arguments_brackets
    }

    return data
  }
}

// MARK: - EmploymentData Preview

extension EmploymentData {  // swiftlint:disable:this no_grouping_extension
  /// Preview data showing typical employment percentages across a year
  static var preview: EmploymentData {  // swiftlint:disable:this explicit_acl
    let shortMonthNames = [  // swiftlint:disable:this explicit_type_interface
      "jan.", "feb.", "mar.", "apr.", "mai", "jun.",
      "jul.", "aug.", "sep.", "okt.", "nov.", "des.",
    ]
    let fullMonthNames = [  // swiftlint:disable:this explicit_type_interface
      "Januar", "Februar", "Mars", "April", "Mai", "Juni",
      "Juli", "August", "September", "Oktober", "November", "Desember",
    ]
    // Sample percentages simulating typical part-time work
    let percentages: [Double] = [
      32.5, 35.0, 50.0, 55.0, 70.0, 52.0,  // swiftlint:disable:this no_magic_numbers
      25.0, 48.0, 50.0, 42.0, 45.0, 48.0,  // swiftlint:disable:this no_magic_numbers
    ]

    let monthlyData = (0..<12).map { index in  // swiftlint:disable:this explicit_type_interface no_magic_numbers
      EmploymentMonthlyData(
        month: shortMonthNames[index],
        fullMonth: fullMonthNames[index],
        year: 2_025,  // swiftlint:disable:this no_magic_numbers
        monthNumber: index + 1,
        averagePercentage: percentages[index],
        hasShifts: percentages[index] > 0
      )
    }

    // Calculate yearly average
    let withShifts = percentages.filter { $0 > 0 }  // swiftlint:disable:this explicit_type_interface
    let yearlyAvg = withShifts.isEmpty ? nil : withShifts.reduce(0, +) / Double(withShifts.count)  // swiftlint:disable:this explicit_type_interface line_length

    return EmploymentData(
      monthlyData: monthlyData,
      yearlyAverage: yearlyAvg.map { ($0 * 10).rounded() / 10 },  // Round to 1 decimal // swiftlint:disable:this line_length no_magic_numbers
      fullTimeHoursPerWeek: 40  // swiftlint:disable:this no_magic_numbers
    )
  }
}

// MARK: - MonthlyIncomeData Preview

extension MonthlyIncomeData {  // swiftlint:disable:this no_grouping_extension
  /// Preview data showing monthly income for a year
  /// Simulates typical income pattern with current month highlighted
  static var previewData: [MonthlyIncomeData] {  // swiftlint:disable:this explicit_acl
    let shortMonthNames = [  // swiftlint:disable:this explicit_type_interface
      "jan.", "feb.", "mar.", "apr.", "mai", "jun.",
      "jul.", "aug.", "sep.", "okt.", "nov.", "des.",
    ]
    let fullMonthNames = [  // swiftlint:disable:this explicit_type_interface
      "Januar", "Februar", "Mars", "April", "Mai", "Juni",
      "Juli", "August", "September", "Oktober", "November", "Desember",
    ]

    // Sample earnings simulating varied monthly income
    let earnings: [Double] = [
      13_772, 5_200, 6_100, 5_800, 4_900, 5_500,  // swiftlint:disable:this no_magic_numbers
      6_200, 0, 0, 0, 0, 0,  // swiftlint:disable:this no_magic_numbers
    ]
    let hours: [Double] = [
      60.3, 28, 32, 30, 25, 28,  // swiftlint:disable:this no_magic_numbers
      33, 0, 0, 0, 0, 0,  // swiftlint:disable:this no_magic_numbers
    ]
    let shifts: [Int] = [
      9, 4, 5, 4, 4, 4,  // swiftlint:disable:this no_magic_numbers
      5, 0, 0, 0, 0, 0,  // swiftlint:disable:this no_magic_numbers
    ]

    return (0..<12).map { index in  // swiftlint:disable:this no_magic_numbers
      MonthlyIncomeData(
        month: shortMonthNames[index],
        fullMonth: fullMonthNames[index],
        year: 2_026,  // swiftlint:disable:this no_magic_numbers
        monthNumber: index + 1,
        earnings: earnings[index],
        hours: hours[index],
        shifts: shifts[index]
      )
    }
  }
}
