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
    if now >= shiftStart && now < shiftEnd {
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

    guard now >= shiftStart && now < shiftEnd else {
      return nil
    }

    let seconds = Int(ceil(shiftEnd.timeIntervalSince(now)))
    return (1...60).contains(seconds) ? seconds : nil
  }

  // MARK: - Payroll Countdown

  /// Format countdown text for payroll date
  /// - Parameters:
  ///   - payrollDate: The payroll date
  /// - Returns: Formatted countdown text and whether it's past
  static func formatPayrollCountdown(
    payrollDate: Date
  ) -> (text: String, isPast: Bool, isToday: Bool) {
    let now = Date()
    let calendar = Calendar.current

    // Check if payroll is today
    if calendar.isDateInToday(payrollDate) {
      return (String(localized: .commonToday), false, true)
    }

    // Check if payroll has passed
    if now > payrollDate {
      let (text, _) = formatPastTime(from: payrollDate)
      return (text, true, false)
    }

    // Payroll is in the future
    let (text, _) = formatFutureTime(to: payrollDate)
    return (text, false, false)
  }

  // MARK: - Shared Relative Countdown

  /// Shared relative countdown formatting used by payroll and friend next-shift previews.
  /// Format examples: "Om 2t 30min 45sek", "I morgen", "2t siden".
  static func formatRelativeCountdown(
    referenceDate: Date,
    dayBoundaryReferenceDate: Date? = nil,
    now: Date = Date()
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
      if totalMinutes == 0 {
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
      } else {
        return String(localized: .commonTimeAgo(timeStr))
      }
    }

    if midnightDays == 1 {
      return isFuture
        ? String(localized: .commonTomorrow)
        : String(localized: .commonYesterday)
    }

    if isFuture {
      return String(localized: .commonInDaysPlural(Int(Int32(midnightDays))))
    } else {
      return String(localized: .commonDaysAgoPlural(Int(Int32(midnightDays))))
    }
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

  private static func formatFutureTime(to targetDate: Date) -> (String, Bool) {
    let now = Date()
    let calendar = Calendar.current
    let midnightDays = countMidnightCrossings(from: now, to: targetDate)

    // 1 midnight crossing = tomorrow
    if midnightDays == 1 {
      return (String(localized: .commonTomorrow), false)
    }

    // 2+ midnight crossings = "In X days"
    if midnightDays > 1 {
      return (String(localized: .commonInDays(Int32(midnightDays))), false)
    }

    // Same calendar day (0 midnight crossings) - show hours/minutes/seconds
    let components = calendar.dateComponents([.hour, .minute, .second], from: now, to: targetDate)
    let hours = components.hour ?? 0
    let minutes = components.minute ?? 0
    let seconds = components.second ?? 0
    let totalSeconds = Int(targetDate.timeIntervalSince(now))
    let totalHours = totalSeconds / 3600

    let secWord = String(localized: .commonSecondsShort)
    let minWord = String(localized: .commonMinutesShort)
    let hourWord = String(localized: .commonHoursShort)
    let inWord = String(localized: .commonIn)

    // Within 6 hours - show high precision with seconds
    if totalHours < 6 {
      // Less than 1 minute - show only seconds
      if hours == 0 && minutes == 0 {
        return ("\(inWord) \(seconds)\(secWord)", false)
      }

      // Less than 1 hour - show minutes and seconds
      if hours == 0 {
        return ("\(inWord) \(minutes)\(minWord) \(seconds)\(secWord)", false)
      }

      // Less than 6 hours - show hours, minutes and seconds
      return ("\(inWord) \(hours)\(hourWord) \(minutes)\(minWord) \(seconds)\(secWord)", false)
    }

    // 6+ hours on same day - show hours and minutes only
    if minutes == 0 {
      return ("\(inWord) \(hours)\(hourWord)", false)
    }
    return ("\(inWord) \(hours)\(hourWord) \(minutes)\(minWord)", false)
  }

  private static func formatPastTime(from pastDate: Date) -> (String, Bool) {
    let now = Date()
    let calendar = Calendar.current
    let midnightDays = countMidnightCrossings(from: pastDate, to: now)

    // 1 midnight crossing = yesterday
    if midnightDays == 1 {
      return (String(localized: .commonYesterday), false)
    }

    // 2+ midnight crossings = "X days ago"
    if midnightDays > 1 {
      return (String(localized: .commonDaysAgo(Int32(midnightDays))), false)
    }

    // Same calendar day (0 midnight crossings) - show hours/minutes/seconds
    let components = calendar.dateComponents([.hour, .minute, .second], from: pastDate, to: now)
    let hours = components.hour ?? 0
    let minutes = components.minute ?? 0
    let seconds = components.second ?? 0
    let totalSeconds = Int(now.timeIntervalSince(pastDate))
    let totalHours = totalSeconds / 3600

    let secWord = String(localized: .commonSecondsShort)
    let minWord = String(localized: .commonMinutesShort)
    let hourWord = String(localized: .commonHoursShort)
    let agoWord = String(localized: .commonAgo)

    // Within 6 hours - show high precision with seconds
    if totalHours < 6 {
      // Less than 1 minute - show only seconds
      if hours == 0 && minutes == 0 {
        return ("\(seconds)\(secWord) \(agoWord)", false)
      }

      // Less than 1 hour - show minutes and seconds
      if hours == 0 {
        return ("\(minutes)\(minWord) \(seconds)\(secWord) \(agoWord)", false)
      }

      // Less than 6 hours - show hours, minutes and seconds
      return ("\(hours)\(hourWord) \(minutes)\(minWord) \(seconds)\(secWord) \(agoWord)", false)
    }

    // 6+ hours on same day - show hours and minutes only
    if minutes == 0 {
      return ("\(hours)\(hourWord) \(agoWord)", false)
    }
    return ("\(hours)\(hourWord) \(minutes)\(minWord) \(agoWord)", false)
  }
}
