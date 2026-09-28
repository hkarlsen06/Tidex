// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface no_magic_numbers
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable prefer_condition_list
import Foundation

/// Payroll Date Adjustment Utility
///
/// Adjusts payroll dates backwards to the last valid weekday (Tuesday-Friday)
/// if the original date falls on a weekend, Monday, or public holiday.
///
/// This ensures employees receive payment on or before the expected date,
/// accounting for bank processing restrictions on weekends, Mondays, and holidays.
///
/// Matches the Next.js implementation in `lib/payroll/adjust-payroll-date.ts`.
enum PayrollDateAdjuster {

  /// Gregorian calendar for all payroll date math. `year`/`month`/`day` here are always
  /// Gregorian, so resolving them with `Calendar.current` would misread them as, say,
  /// Hijri or Buddhist components on a device set to one of those calendars and land on
  /// a wildly wrong date (payouts hundreds of years away).
  private static var calendar: Calendar { .gregorianCurrent }

  /// Adjusts a payroll date backwards to the last valid weekday (Tuesday-Friday)
  /// if the original date falls on a weekend, Monday, or public holiday.
  ///
  /// - Parameters:
  ///   - payrollDay: Day of month (1-31)
  ///   - month: Month (1-12)
  ///   - year: Full year (e.g., 2025)
  /// - Returns: Adjusted Date guaranteed to be a valid payroll day (Tue-Fri, non-holiday)
  ///
  /// - Example:
  ///   ```swift
  ///   // Payroll day 15 falls on Saturday, Jan 15, 2025
  ///   adjustPayrollDate(payrollDay: 15, month: 1, year: 2025) // Returns Friday, Jan 14, 2025
  ///
  ///   // Payroll day 17 falls on Monday, Feb 17, 2025
  ///   adjustPayrollDate(payrollDay: 17, month: 2, year: 2025) // Returns Friday, Feb 14, 2025
  ///   ```
  static func adjustPayrollDate(payrollDay: Int, month: Int, year: Int) -> Date {
    let daysInMonth = Date.daysInMonth(year: year, month: month)
    let effectivePayrollDay = min(max(payrollDay, 1), daysInMonth)

    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = effectivePayrollDay

    guard var date = calendar.date(from: components) else {
      return Date()
    }

    // Maximum iterations to prevent infinite loops (should never need more than 7 days)
    let maxIterations = 10
    var iterations = 0

    // Move backward until we find a valid payroll day (Tuesday-Friday, non-holiday)
    while isInvalidPayrollDay(date), iterations < maxIterations {
      date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
      iterations += 1
    }

    return date
  }

  /// Check if a date is invalid for payroll purposes
  /// Invalid = weekend, Monday, or public holiday
  static func isInvalidPayrollDay(_ date: Date) -> Bool {
    return isWeekend(date) || isMonday(date) || NorwegianHolidays.isPublicHoliday(date)
  }

  /// Check if a date is a weekend (Saturday or Sunday)
  static func isWeekend(_ date: Date) -> Bool {
    let weekday = calendar.component(.weekday, from: date)
    // 1 = Sunday, 7 = Saturday
    return weekday == 1 || weekday == 7
  }

  /// Check if a date is a Monday
  static func isMonday(_ date: Date) -> Bool {
    let weekday = calendar.component(.weekday, from: date)
    // 2 = Monday
    return weekday == 2
  }
}
