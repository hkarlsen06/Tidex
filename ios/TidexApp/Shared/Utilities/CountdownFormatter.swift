// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline convenience_type cyclomatic_complexity explicit_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_top_level_acl explicit_type_interface function_body_length identifier_name
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable large_tuple multiline_arguments_brackets no_magic_numbers number_separator
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable prefer_condition_list superfluous_else
import Foundation

/// Utility for formatting countdown text for shifts and payroll
/// Matches the behavior of useCountdown and usePayrollCountdown hooks in Next.js
struct CountdownFormatter {

  // MARK: - Shift Countdown

  /// Format countdown text for a shift
  /// - Parameters:
  ///   - shiftDate: ISO date string (YYYY-MM-DD)
  ///   - startTime: Start time (HH:mm)
  ///   - endTime: End time (HH:mm)
  /// - Returns: Formatted countdown text, whether shift is active, and progress (0-100) if active
  static func formatShiftCountdown(
    shiftDate: String,
    startTime: String,
    endTime: String,
    now: Date = Date()
  ) -> (text: String, isActive: Bool, progress: Double) {
    guard let shiftStart = parseShiftDateTime(date: shiftDate, time: startTime),
      let shiftEnd = parseShiftDateTime(
        date: shiftDate, time: endTime, crossesMidnight: endTime <= startTime)
    else {
      return ("---", false, 0)
    }

    // Check if shift is active
    if now >= shiftStart, now < shiftEnd {
      // Calculate progress through the shift (0-100)
      let totalDuration = shiftEnd.timeIntervalSince(shiftStart)
      let elapsed = now.timeIntervalSince(shiftStart)
      let progress = totalDuration > 0 ? min(100, max(0, (elapsed / totalDuration) * 100)) : 0
      return (String(localized: .commonInProgress), true, progress)
    }

    // Check if shift is in the past
    if now >= shiftEnd {
      return (
        formatRelativeCountdown(
          referenceDate: shiftEnd,
          dayBoundaryReferenceDate: shiftStart,
          now: now
        ),
        false,
        0
      )
    }

    // Shift is in the future
    return (
      formatRelativeCountdown(
        referenceDate: shiftStart,
        dayBoundaryReferenceDate: shiftStart,
        now: now
      ),
      false,
      0
    )
  }

  /// Returns remaining seconds in the final 60-second window of an active shift.
  /// Returns `nil` when the shift is not active or not in its final minute.
  static func finalCountdownSecondsForShift(
    shiftDate: String,
    startTime: String,
    endTime: String,
    now: Date = Date()
  ) -> Int? {
    guard let shiftStart = parseShiftDateTime(date: shiftDate, time: startTime),
      let shiftEnd = parseShiftDateTime(
        date: shiftDate, time: endTime, crossesMidnight: endTime <= startTime)
    else {
      return nil
    }

    guard now >= shiftStart, now < shiftEnd else {
      return nil
    }

    let seconds = Int(ceil(shiftEnd.timeIntervalSince(now)))
    return (1...60).contains(seconds) ? seconds : nil
  }

  // MARK: - Shared Relative Countdown

  /// Shared relative countdown formatting used by payroll and friend next-shift previews.
  /// Format examples: "Om 2t 30min 45sek", "I morgen", "2t siden".
  /// `compact` keeps only the largest unit ("Om 2t", "Om 7d") for narrow columns.
  static func formatRelativeCountdown(
    referenceDate: Date,
    dayBoundaryReferenceDate: Date? = nil,
    now: Date = Date(),
    compact: Bool = false
  ) -> String {
    let diffSeconds = referenceDate.timeIntervalSince(now)
    let isFuture = diffSeconds > 0
    let absDiffSeconds = abs(diffSeconds)

    let totalSeconds = Int(absDiffSeconds)
    let totalMinutes = totalSeconds / 60
    let totalHours = totalMinutes / 60

    // Allows callers to keep day-crossing behavior tied to a different anchor date
    // (FriendCard uses shift start for this).
    let dayBoundaryDate = dayBoundaryReferenceDate ?? referenceDate
    let midnightDays = countMidnightCrossings(
      from: min(now, dayBoundaryDate),
      to: max(now, dayBoundaryDate)
    )

    let hAbbrev = String(localized: .commonHoursShort)
    let minAbbrev = String(localized: .commonMinShort)
    let secAbbrev = String(localized: .commonSecondsShort)

    if midnightDays == 0 {
      let h = totalMinutes / 60
      let m = totalMinutes % 60
      let s = totalSeconds % 60
      let includeSeconds = totalHours < 12

      let timeStr: String
      if compact {
        timeStr = h > 0 ? "\(h)\(hAbbrev)" : m > 0 ? "\(m)\(minAbbrev)" : "\(s)\(secAbbrev)"
      } else if totalMinutes == 0 {
        timeStr = "\(s)\(secAbbrev)"
      } else if h == 0 {
        if includeSeconds {
          timeStr = "\(m)\(minAbbrev) \(s)\(secAbbrev)"
        } else {
          timeStr = "\(m)\(minAbbrev)"
        }
      } else if includeSeconds {
        if m == 0 {
          timeStr = "\(h)\(hAbbrev) \(s)\(secAbbrev)"
        } else {
          timeStr = "\(h)\(hAbbrev) \(m)\(minAbbrev) \(s)\(secAbbrev)"
        }
      } else if m == 0 {
        timeStr = "\(h)\(hAbbrev)"
      } else {
        timeStr = "\(h)\(hAbbrev) \(m)\(minAbbrev)"
      }

      if isFuture {
        return String(localized: .commonInTime(timeStr))
      }
      return String(localized: .commonTimeAgo(timeStr))
    }

    if midnightDays == 1 {
      return isFuture
        ? String(localized: .commonTomorrow)
        : String(localized: .commonYesterday)
    }

    if compact,
      let days = DateComponentsFormatter.localizedString(
        from: DateComponents(day: midnightDays), unitsStyle: .abbreviated)
    {
      // "3d" rather than "3 d", matching the message times in the friends list.
      let compactDays = days.filter { !$0.isWhitespace }
      return String(localized: isFuture ? .commonInTime(compactDays) : .commonTimeAgo(compactDays))
    }

    if isFuture {
      return String(localized: .commonInDaysPlural(Int(Int32(midnightDays))))
    }
    return String(localized: .commonDaysAgoPlural(Int(Int32(midnightDays))))
  }

  // MARK: - Private Helpers

  private static func parseShiftDateTime(date: String, time: String, crossesMidnight: Bool = false)
    -> Date?
  {
    let dateFormatter = FormatterCache.shiftDateTimeFormatter(timeZone: Date.localTimeZone)
    let dateTimeString = "\(date) \(time)"
    guard var result = dateFormatter.date(from: dateTimeString) else { return nil }

    // If shift crosses midnight, add one day to the end time
    if crossesMidnight {
      result = Calendar.current.date(byAdding: .day, value: 1, to: result) ?? result
    }

    return result
  }

  /// Count midnight boundaries crossed between two dates (matching Next.js behavior)
  /// Users perceive "1 day" as "tomorrow", not "24 hours from now"
  private static func countMidnightCrossings(from: Date, to: Date) -> Int {
    let calendar = Calendar.current
    let fromMidnight = calendar.startOfDay(for: from)
    let toMidnight = calendar.startOfDay(for: to)
    let days = calendar.dateComponents([.day], from: fromMidnight, to: toMidnight).day ?? 0
    return abs(days)
  }
}
