// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline cyclomatic_complexity discouraged_optional_collection explicit_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_top_level_acl explicit_type_interface file_types_order function_body_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable identifier_name legacy_objc_type multiline_arguments_brackets no_magic_numbers
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable number_separator type_contents_order unused_parameter
import Foundation
import SwiftUI

// MARK: - Calendar Grid Helper

/// Static helper functions for calendar grid computations
/// Centralizes the date calculation logic shared across all calendar views
enum CalendarGridHelper {
  private static let calendar = Calendar.current
  static let columnCount = 7
  static let cellSpacing: CGFloat = Spacing.xxs
  /// Width:height ratio for calendar cells. The cell text is sized by the cell width,
  /// so this height still fits two lines of times or earnings at full size.
  static let cellAspectRatio: CGFloat = 1 / 1.08

  // MARK: - Days in Month

  /// Generate day info array for a given month
  /// - Parameters:
  ///   - year: The year (e.g., 2025)
  ///   - month: The month number (1-12)
  ///   - selectedDates: Optional set of selected date ISO strings (for marking selection state)
  /// - Returns: Array of CalendarDayInfo for the grid (includes padding days from prev/next months)
  static func daysInMonth(
    year: Int,
    month: Int,
    selectedDates _: Set<String>? = nil
  ) -> [CalendarDayInfo] {
    var days: [CalendarDayInfo] = []

    // Get first day of month
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = 1
    guard let firstOfMonth = calendar.date(from: components) else { return days }

    // Get weekday of first day (1 = Sunday, 7 = Saturday)
    let firstWeekday = calendar.component(.weekday, from: firstOfMonth)

    // Convert to Monday-start (0 = Monday, 6 = Sunday)
    let startOffset = (firstWeekday + 5) % 7

    // Get number of days in month
    guard let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return days }

    // Get last day of previous month for "outside days"
    guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: firstOfMonth),
      let previousMonthRange = calendar.range(of: .day, in: .month, for: previousMonth)
    else { return days }
    let daysInPreviousMonth = previousMonthRange.count

    // Add days from previous month (outside days)
    for i in 0..<startOffset {
      let day = daysInPreviousMonth - startOffset + i + 1
      guard let date = calendar.date(byAdding: .day, value: i - startOffset, to: firstOfMonth)
      else { continue }
      let dateISO = date.toISODateString()
      let weekNum = calendar.component(.weekday, from: date) == 2 ? getIsoWeek(from: date) : nil

      days.append(
        .outsideMonth(
          id: -1_000 + i,
          dayNumber: day,
          dateISO: dateISO,
          weekNumber: weekNum
        ))
    }

    // Add cells for each day in current month
    for day in range {
      guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else {
        continue
      }
      let dateISO = date.toISODateString()
      let isMonday = calendar.component(.weekday, from: date) == 2
      let weekNum = isMonday ? getIsoWeek(from: date) : nil

      days.append(
        .inMonth(
          id: day,
          dayNumber: day,
          dateISO: dateISO,
          weekNumber: weekNum
        ))
    }

    // Add days from next month to fill the last row
    let totalDays = days.count
    let remainder = totalDays % 7
    if remainder > 0 {
      let daysToAdd = 7 - remainder
      for i in 0..<daysToAdd {
        guard let date = calendar.date(byAdding: .day, value: range.count + i, to: firstOfMonth)
        else { continue }
        let dateISO = date.toISODateString()
        let weekNum = calendar.component(.weekday, from: date) == 2 ? getIsoWeek(from: date) : nil

        days.append(
          .outsideMonth(
            id: 1_000 + i,
            dayNumber: i + 1,
            dateISO: dateISO,
            weekNumber: weekNum
          ))
      }
    }

    return days
  }

  /// Generate day info array for a given Date (extracts year/month automatically)
  static func daysInMonth(for date: Date, selectedDates: Set<String>? = nil) -> [CalendarDayInfo] {
    let components = calendar.dateComponents([.year, .month], from: date)
    guard let year = components.year, let month = components.month else { return [] }
    return daysInMonth(year: year, month: month, selectedDates: selectedDates)
  }

  // MARK: - ISO Week Number

  /// Get ISO week number from a date
  static func getIsoWeek(from date: Date) -> Int {
    var isoCalendar = Calendar(identifier: .iso8601)
    isoCalendar.firstWeekday = 2  // Monday
    isoCalendar.minimumDaysInFirstWeek = 4
    return isoCalendar.component(.weekOfYear, from: date)
  }

  // MARK: - Weekday Symbols

  /// Get localized weekday symbols (Monday-start)
  static func weekdaySymbols() -> [String] {
    [
      String(localized: .calendarWeekdayMonday),
      String(localized: .calendarWeekdayTuesday),
      String(localized: .calendarWeekdayWednesday),
      String(localized: .calendarWeekdayThursday),
      String(localized: .calendarWeekdayFriday),
      String(localized: .calendarWeekdaySaturday),
      String(localized: .calendarWeekdaySunday),
    ]
  }

  // MARK: - Grid Columns

  /// Standard 7-column grid for calendar
  static let columns = Array(
    repeating: GridItem(.flexible(), spacing: cellSpacing),
    count: columnCount
  )

  // MARK: - Formatting

  /// Format currency amount for calendar cells (compact, no symbol).
  /// Uses the app locale so cells group digits the same way as the totals around them.
  static func formatCompactCurrency(_ amount: Double) -> String {
    CurrencyConfig.formatPlain(amount)
  }

  /// Overnight marker appended to an end time that falls on the next day.
  static let nextDayMarker = "\u{207A}\u{00B9}"

  /// Spoken time range for a cell, e.g. "22:00 to 06:00, ends the next day".
  static func timeRangeAccessibilityText(start: String, end: String, crossesMidnight: Bool)
    -> String
  {
    let range = String(localized: .calendarAccessibilityTimeRange(start, end))
    guard crossesMidnight else { return range }
    return "\(range), \(String(localized: .calendarAccessibilityEndsNextDay))"
  }

  /// Spoken time range for a stored shift ("HH:mm:ss" times).
  static func shiftTimesAccessibilityText(startTime: String, endTime: String) -> String {
    timeRangeAccessibilityText(
      start: formatTime(startTime),
      end: formatTime(endTime),
      crossesMidnight: timeToMinutes(endTime) <= timeToMinutes(startTime)
    )
  }

  /// Spoken earnings for a cell, naming which amount is after tax and which is before.
  static func earningsAccessibilityText(_ earnings: CalendarEarningsData) -> String {
    guard earnings.hasTaxEnabled else { return formatCompactCurrency(earnings.gross) }
    return String(
      localized: .calendarAccessibilityEarningsAfterBeforeTax(
        formatCompactCurrency(earnings.net),
        formatCompactCurrency(earnings.gross)
      ))
  }

  /// Format time string for display (removes seconds, keeps leading zero)
  /// e.g., "08:30:00" -> "08:30"
  static func formatTime(_ time: String, locale: Locale = .appLocale) -> String {
    return ShiftCardFormatter.localizedTime(time, locale: locale, format: "HH:mm")
  }

  /// Convert time string to minutes since midnight
  static func timeToMinutes(_ time: String) -> Int {
    let parts = time.split(separator: ":")
    guard parts.count >= 2,
      let hours = Int(parts[0]),
      let minutes = Int(parts[1])
    else { return 0 }
    return hours * 60 + minutes
  }

  // MARK: - Month Name

  /// Get localized month name from Date
  static func monthName(from date: Date, locale: Locale) -> String {
    FormatterCache.monthNameFormatter(locale: locale)
      .string(from: date)
      .sentenceCased()
  }

  /// Get localized month name from year/month components
  static func monthName(year: Int, month: Int, locale: Locale) -> String {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = 1

    if let date = calendar.date(from: components) {
      return monthName(from: date, locale: locale)
    }
    return ""
  }
}

/// Shared month grid container that owns cell geometry.
/// Parent views provide day content, while this view enforces
/// consistent cell sizing for all calendar variants.
struct CalendarMonthGrid<DayContent: View>: View {
  let days: [CalendarDayInfo]
  var monthTransitionPhase: MonthTransitionPhase?
  var monthTransitionConfig: MonthTransitionConfig
  var spacing: CGFloat = CalendarGridHelper.cellSpacing
  let dayContent: (CalendarDayInfo) -> DayContent

  init(
    days: [CalendarDayInfo],
    monthTransitionPhase: MonthTransitionPhase? = nil,
    monthTransitionConfig: MonthTransitionConfig = .default,
    spacing: CGFloat = CalendarGridHelper.cellSpacing,
    @ViewBuilder dayContent: @escaping (CalendarDayInfo) -> DayContent
  ) {
    self.days = days
    self.monthTransitionPhase = monthTransitionPhase
    self.monthTransitionConfig = monthTransitionConfig
    self.spacing = spacing
    self.dayContent = dayContent
  }

  var body: some View {
    if let monthTransitionPhase {
      grid
        .cardTransition(phase: monthTransitionPhase, config: monthTransitionConfig)
    } else {
      grid
    }
  }

  private var grid: some View {
    LazyVGrid(columns: CalendarGridHelper.columns, spacing: spacing) {
      ForEach(days, id: \.id) { dayInfo in
        dayContent(dayInfo)
          .frame(maxWidth: .infinity)
          .aspectRatio(CalendarGridHelper.cellAspectRatio, contentMode: .fit)
      }
    }
    .id(monthGridIdentity)
  }

  private var monthGridIdentity: String {
    guard let firstDate = days.first?.dateISO, let lastDate = days.last?.dateISO else {
      return "calendar-grid-empty-\(days.count)"
    }
    return "\(firstDate)-\(lastDate)-\(days.count)"
  }
}
