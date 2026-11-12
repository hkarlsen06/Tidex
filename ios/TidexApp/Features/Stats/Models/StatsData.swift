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
  /// One entry per day of the focus month, days without shifts included.
  let days: [DayStats]  // swiftlint:disable:this explicit_acl
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

/// Pay on one day of the focus month. Earnings, hours and shifts count the primary currency,
/// and `otherCurrencyShifts` counts the day's shifts paid in another currency.
struct DayStats: Codable, Equatable, Identifiable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let day: Int  // swiftlint:disable:this explicit_acl
  let earnings: Double  // swiftlint:disable:this explicit_acl
  let hours: Double  // swiftlint:disable:this explicit_acl
  let shifts: Int  // swiftlint:disable:this explicit_acl
  let otherCurrencyShifts: Int  // swiftlint:disable:this explicit_acl

  var id: Int { day }  // swiftlint:disable:this explicit_acl
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

// MARK: - Year

/// One year of Stats. Pay counts the currency that earns the most in the focus year, and the
/// previous year uses that currency too.
struct YearStatsData: Codable, Equatable {
  let year: Int
  /// `enabled` comes from the year's primary currency.
  let tax: TaxSettings
  /// Exactly 12, January first.
  let months: [YearMonthStats]
  /// The 12 months of the year before.
  let previousMonths: [YearMonthStats]
  /// Resolved over the focus year.
  let currencyAggregate: JobCurrencyAggregateResolution?
  /// Shown-basis pay through today for the running year, and through the same date a year
  /// earlier. Nil for any other year.
  let toDate: YearToDate?
  let employment: EmploymentData?

  static func empty(year: Int) -> YearStatsData {
    let months = (1...12).map(YearMonthStats.empty)
    return YearStatsData(
      year: year,
      tax: TaxSettings(enabled: false, percentage: 0),
      months: months,
      previousMonths: months,
      currencyAggregate: nil,
      toDate: nil,
      employment: nil
    )
  }
}

/// Earnings count the primary currency. Hours and shifts count every currency, like the month
/// page's metrics.
struct YearMonthStats: Codable, Equatable, Identifiable {
  /// 1...12.
  let month: Int
  let earnings: Double
  let earningsNet: Double
  /// The paid hours behind `earnings`, which per-hour pay divides by.
  let earningsHours: Double
  let hours: Double
  let shifts: Int

  var id: Int { month }

  static func empty(month: Int) -> YearMonthStats {
    YearMonthStats(month: month, earnings: 0, earningsNet: 0, earningsHours: 0, hours: 0, shifts: 0)
  }
}

/// Net pay when tax is on, else gross.
struct YearToDate: Codable, Equatable {
  let focus: Double
  let previous: Double
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
      days: [],
      employment: nil,
      yearlyIncome: nil
    )
  }
}
