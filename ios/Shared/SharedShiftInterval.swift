import Foundation

/// A recorded schedule date and its clock times interpreted in the schedule's fixed zone.
struct SharedShiftInterval: Equatable, Sendable {
  let start: Date
  let end: Date
  let timeZone: TimeZone

  init?(date: String, startTime: String, endTime: String, timeZoneIdentifier: String?) {
    guard let zone = Self.scheduleZone(timeZoneIdentifier),
      let startClock = Self.clock(startTime), let endClock = Self.clock(endTime)
    else { return nil }

    let parts = date.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
    else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let components = DateComponents(year: year, month: month, day: day, hour: 12)
    guard let noon = calendar.date(from: components),
      calendar.dateComponents([.year, .month, .day], from: noon).year == year,
      calendar.component(.month, from: noon) == month,
      calendar.component(.day, from: noon) == day
    else { return nil }

    let endSeconds = endClock <= startClock ? endClock + 86_400 : endClock
    func instant(_ seconds: Int) -> Date? {
      guard let anchor = calendar.date(byAdding: .day, value: seconds / 86_400, to: noon) else {
        return nil
      }
      var fields = calendar.dateComponents([.year, .month, .day], from: anchor)
      fields.hour = seconds / 3_600 % 24
      fields.minute = seconds / 60 % 60
      fields.second = seconds % 60
      return calendar.date(from: fields)
    }
    guard let start = instant(startClock), let end = instant(endSeconds), end > start else {
      return nil
    }
    self.start = start
    self.end = end
    self.timeZone = zone
  }

  func status(at now: Date) -> SharingPreviewStatus {
    if now < start { return .upcoming }
    return now < end ? .active : .past
  }

  func differs(from viewerZone: TimeZone = .current) -> Bool {
    timeZone.secondsFromGMT(for: start) != viewerZone.secondsFromGMT(for: start)
      || timeZone.secondsFromGMT(for: end) != viewerZone.secondsFromGMT(for: end)
  }

  static func scheduleZone(_ identifier: String?) -> TimeZone? {
    guard let identifier, identifier == "UTC" || identifier.contains("/") else { return nil }
    return TimeZone(identifier: identifier)
  }

  func datedTimeRange(in zone: TimeZone = .current, locale: Locale = .current) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.isDate(start, inSameDayAs: end)
      ? dateLabel(in: zone, locale: locale) + " " + timeRange(in: zone, locale: locale)
      : dateLabel(in: zone, locale: locale) + " " + clock(start, in: zone, locale: locale)
        + " – " + dateLabel(end, in: zone, locale: locale) + " "
        + clock(end, in: zone, locale: locale)
  }

  func sourceDescription(viewerZone: TimeZone = .current, locale: Locale = .current) -> String {
    timeRange(in: timeZone, datedAgainst: viewerZone, locale: locale)
  }

  /// The clock range in `zone`. It names the dates only when they differ from the dates the
  /// same instants have in `other`.
  func timeRange(in zone: TimeZone, datedAgainst other: TimeZone, locale: Locale = .current)
    -> String
  {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    var otherCalendar = calendar
    otherCalendar.timeZone = other
    let sameDates = [start, end].allSatisfy { date in
      calendar.dateComponents([.year, .month, .day], from: date)
        == otherCalendar.dateComponents([.year, .month, .day], from: date)
    }
    guard !sameDates else { return timeRange(in: zone, locale: locale) }
    var style = Date.FormatStyle().day().month(.abbreviated).locale(locale)
    style.calendar = calendar
    style.timeZone = zone
    if calendar.isDate(start, inSameDayAs: end) {
      return start.formatted(style) + " " + timeRange(in: zone, locale: locale)
    }
    return start.formatted(style) + " " + clock(start, in: zone, locale: locale)
      + " – " + end.formatted(style) + " " + clock(end, in: zone, locale: locale)
  }

  func clock(_ instant: Date, in zone: TimeZone = .current, locale: Locale = .current) -> String {
    Self.clockFormatter(zone: zone, locale: locale).string(from: instant)
  }

  private static func clockFormatter(zone: TimeZone, locale: Locale) -> DateFormatter {
    let key = "tidex.sharing.clock.\(zone.identifier).\(locale.identifier)"
    if let cached = Thread.current.threadDictionary[key] as? DateFormatter { return cached }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = zone
    formatter.dateFormat = "HH:mm"
    Thread.current.threadDictionary[key] = formatter
    return formatter
  }

  func timeRange(in zone: TimeZone = .current, locale: Locale = .current) -> String {
    clock(start, in: zone, locale: locale) + " – " + clock(end, in: zone, locale: locale)
  }

  func dateLabel(_ instant: Date? = nil, in zone: TimeZone = .current, locale: Locale = .current)
    -> String
  {
    var style = Date.FormatStyle().weekday(.wide).day().month(.abbreviated).locale(locale)
    style.timeZone = zone
    style.calendar = Calendar(identifier: .gregorian)
    let value = (instant ?? start).formatted(style)
    return value.prefix(1).uppercased(with: locale) + value.dropFirst()
  }

  func dateString(in zone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = zone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: start)
  }

  private static func clock(_ value: String) -> Int? {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard (2...3).contains(parts.count), parts[0].count == 2, parts[1].count == 2,
      let hour = Int(parts[0]), let minute = Int(parts[1]), (0...24).contains(hour),
      (0...59).contains(minute)
    else { return nil }
    let second: Int
    if parts.count == 3 {
      guard parts[2].count == 2, let parsed = Int(parts[2]), (0...59).contains(parsed) else {
        return nil
      }
      second = parsed
    } else {
      second = 0
    }
    guard hour < 24 || minute == 0 && second == 0 else { return nil }
    return hour * 3_600 + minute * 60 + second
  }
}
