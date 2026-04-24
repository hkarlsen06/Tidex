import Foundation

// MARK: - Date + Tidex Extensions

extension Date {
  private static let gregorianCalendar = Calendar(identifier: .gregorian)

  // MARK: - Timezone

  /// User-local timezone (updates dynamically if the device timezone changes)
  static var localTimeZone: TimeZone { TimeZone.current }

  // MARK: - ISO Date Formatting

  /// Format date as ISO date string (YYYY-MM-DD)
  func toISODateString(in timeZone: TimeZone = Date.localTimeZone) -> String {
    FormatterCache.isoDateFormatter(timeZone: timeZone).string(from: self)
  }

  /// Parse ISO date string (YYYY-MM-DD) to Date
  static func fromISODateString(_ string: String, in timeZone: TimeZone = Date.localTimeZone)
    -> Date?
  {
    FormatterCache.isoDateFormatter(timeZone: timeZone).date(from: string)
  }

  /// Parse ISO date string as UTC
  static func fromISODateStringUTC(_ string: String) -> Date? {
    FormatterCache.iso8601DateOnlyUTCFormatter().date(from: string)
  }

  /// Format date as HH:mm in local time.
  func toHourMinuteString(in timeZone: TimeZone = Date.localTimeZone) -> String {
    FormatterCache.hourMinuteFormatter(timeZone: timeZone).string(from: self)
  }

  /// Format date as an ISO8601 internet date-time string.
  func toISO8601String() -> String {
    FormatterCache.iso8601Formatter().string(from: self)
  }

  // MARK: - Year/Month Components

  /// Get year and month components
  func yearMonth(in timeZone: TimeZone = Date.localTimeZone) -> (year: Int, month: Int) {
    var calendar = Self.gregorianCalendar
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.year, .month], from: self)
    return (year: components.year ?? 1970, month: components.month ?? 1)
  }

  /// Get current year and month
  static func currentYearMonth(in timeZone: TimeZone = Date.localTimeZone) -> (
    year: Int, month: Int
  ) {
    Date().yearMonth(in: timeZone)
  }

  /// Get previous month (handles year rollover)
  static func previousYearMonth(from current: (year: Int, month: Int)) -> (year: Int, month: Int) {
    if current.month == 1 {
      return (year: current.year - 1, month: 12)
    }
    return (year: current.year, month: current.month - 1)
  }

  // MARK: - Month Boundaries

  /// Get first day of month as ISO date string
  static func firstDayOfMonth(year: Int, month: Int) -> String {
    String(format: "%04d-%02d-01", year, month)
  }

  /// Get last day of month as ISO date string
  static func lastDayOfMonth(year: Int, month: Int) -> String {
    let lastDay = daysInMonth(year: year, month: month)
    return String(format: "%04d-%02d-%02d", year, month, lastDay)
  }

  /// Get number of days in a month
  static func daysInMonth(year: Int, month: Int) -> Int {
    var components = DateComponents()
    components.year = year
    components.month = month + 1
    components.day = 0
    guard let date = gregorianCalendar.date(from: components) else { return 30 }
    return gregorianCalendar.component(.day, from: date)
  }

  /// Get Date object for first day of month
  static func firstDayOfMonthDate(year: Int, month: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = 1
    var calendar = gregorianCalendar
    calendar.timeZone = localTimeZone
    return calendar.date(from: components) ?? Date()
  }

  /// Get Date object for last day of month
  static func lastDayOfMonthDate(year: Int, month: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month + 1
    components.day = 0
    var calendar = gregorianCalendar
    calendar.timeZone = localTimeZone
    return calendar.date(from: components) ?? Date()
  }

  /// Get the visible date range for a calendar grid (includes out-of-month padding days)
  /// - Parameters:
  ///   - year: The year
  ///   - month: The month (1-12)
  /// - Returns: Tuple of (startDate, endDate) for the visible calendar range
  static func visibleCalendarRange(year: Int, month: Int) -> (start: Date, end: Date) {
    var calendar = gregorianCalendar
    calendar.timeZone = localTimeZone

    let firstOfMonth = firstDayOfMonthDate(year: year, month: month)
    let lastOfMonth = lastDayOfMonthDate(year: year, month: month)

    // Calendar grid starts on Monday, calculate days from previous month needed
    // weekday: 1=Sunday, 2=Monday, ..., 7=Saturday
    let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
    // Convert to Monday-start offset (0=Monday, 6=Sunday)
    let startOffset = (firstWeekday + 5) % 7

    // Calculate start date (may be in previous month)
    let startDate =
      calendar.date(byAdding: .day, value: -startOffset, to: firstOfMonth) ?? firstOfMonth

    // Calculate end date - fill to complete the last week
    let lastWeekday = calendar.component(.weekday, from: lastOfMonth)
    let lastOffset = (lastWeekday + 5) % 7  // days since Monday
    let daysToEndOfWeek = lastOffset == 6 ? 0 : (6 - lastOffset)  // days until Sunday
    let endDate =
      calendar.date(byAdding: .day, value: daysToEndOfWeek, to: lastOfMonth) ?? lastOfMonth

    return (start: startDate, end: endDate)
  }

  // MARK: - Weekday

  /// Get weekday (1-7 where 1=Monday, 7=Sunday) matching TypeScript conventions
  var tidexWeekday: Int {
    var calendar = Self.gregorianCalendar
    calendar.timeZone = Date.localTimeZone
    let weekday = calendar.component(.weekday, from: self)
    // Calendar: 1=Sunday, 2=Monday, ..., 7=Saturday
    // Tidex: 1=Monday, ..., 7=Sunday
    return weekday == 1 ? 7 : weekday - 1
  }

  /// Get weekday from ISO date string (1-7 where 1=Monday, 7=Sunday)
  static func weekdayFromISO(_ dateString: String) -> Int {
    guard let date = fromISODateString(dateString) else { return 1 }
    return date.tidexWeekday
  }

  /// Get weekday key (0-6 where 0=Sunday) for recurring shift selected_days
  var recurringWeekdayKey: Int {
    var calendar = Self.gregorianCalendar
    calendar.timeZone = Date.localTimeZone
    return calendar.component(.weekday, from: self) - 1
  }

  // MARK: - Comparison

  /// Check if this date is today (in local timezone)
  var isToday: Bool {
    let todayString = Date().toISODateString()
    return toISODateString() == todayString
  }

  /// Check if this date is in the past (before today)
  var isPast: Bool {
    let todayString = Date().toISODateString()
    return toISODateString() < todayString
  }

  /// Check if this date is in the future (after today)
  var isFuture: Bool {
    let todayString = Date().toISODateString()
    return toISODateString() > todayString
  }

  // MARK: - Days Between

  /// Calculate days between two ISO date strings
  static func daysBetween(_ from: String, _ to: String) -> Int {
    guard let fromDate = fromISODateString(from),
      let toDate = fromISODateString(to)
    else {
      return 0
    }
    var calendar = gregorianCalendar
    calendar.timeZone = localTimeZone
    let fromMidnight = calendar.startOfDay(for: fromDate)
    let toMidnight = calendar.startOfDay(for: toDate)
    return calendar.dateComponents([.day], from: fromMidnight, to: toMidnight).day ?? 0
  }
}

// MARK: - Shift Time Helpers

extension Date {
  /// Build a Date from ISO date string and HH:MM time string
  /// - Parameters:
  ///   - dateString: ISO date string (YYYY-MM-DD)
  ///   - timeString: Time string (HH:MM)
  /// - Returns: Date combining the date and time, or nil if parsing fails
  static func fromDateAndTime(_ dateString: String, time timeString: String) -> Date? {
    let parts = dateString.split(separator: "-")
    guard parts.count == 3,
      parts[0].count == 4,
      parts[1].count == 2,
      parts[2].count == 2,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2]),
      (1...12).contains(month),
      (1...31).contains(day)
    else {
      return nil
    }

    let timeParts = timeString.split(separator: ":")
    guard
      (2...3).contains(timeParts.count),
      (1...2).contains(timeParts[0].count),
      timeParts[1].count == 2,
      timeParts.count == 2 || timeParts[2].count == 2,
      let hours = Int(timeParts[0]),
      let minutes = Int(timeParts[1]),
      let seconds = timeParts.count == 3 ? Int(timeParts[2]) : 0,
      (0...24).contains(hours),
      (0...59).contains(minutes),
      (0...59).contains(seconds),
      !(hours == 24 && (minutes != 0 || seconds != 0))
    else {
      return nil
    }

    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    // Handle 24:00 as midnight of the next day
    components.hour = hours == 24 ? 0 : hours
    components.minute = minutes
    components.second = seconds
    components.timeZone = localTimeZone

    var calendar = gregorianCalendar
    calendar.timeZone = localTimeZone
    guard let date = calendar.date(from: components) else { return nil }

    let resolved = calendar.dateComponents([.year, .month, .day], from: date)
    guard
      resolved.year == year,
      resolved.month == month,
      resolved.day == day
    else {
      return nil
    }

    if hours == 24 {
      return calendar.date(byAdding: .day, value: 1, to: date)
    }
    return date
  }

  /// Check if a shift has ended based on its date and end time
  /// - Parameters:
  ///   - shiftDate: ISO date string (YYYY-MM-DD)
  ///   - startTime: Start time string (HH:MM)
  ///   - endTime: End time string (HH:MM)
  ///   - referenceDate: Date to compare against (defaults to now)
  /// - Returns: true if the shift's end time has passed
  static func hasShiftEnded(
    shiftDate: String,
    startTime: String,
    endTime: String,
    referenceDate: Date = Date()
  ) -> Bool {
    guard var endDate = fromDateAndTime(shiftDate, time: endTime),
      let startDate = fromDateAndTime(shiftDate, time: startTime)
    else {
      return false
    }

    // Handle cross-midnight shifts (e.g., 22:00-06:00)
    if endDate <= startDate {
      endDate = Self.gregorianCalendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
    }

    return endDate <= referenceDate
  }
}

// MARK: - Today ISO Helper

/// Get today's date as ISO string in local timezone
func todayISO() -> String {
  Date().toISODateString()
}
