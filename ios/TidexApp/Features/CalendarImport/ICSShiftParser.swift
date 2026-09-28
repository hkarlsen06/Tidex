import Foundation

/// A timed event read from an employer calendar feed, in the shape Tidex stores shifts.
internal struct CalendarImportShift: Identifiable, Equatable {
  internal let start: Date
  internal let end: Date
  /// Local shift date, YYYY-MM-DD.
  internal let date: String
  /// HH:mm.
  internal let startTime: String
  /// HH:mm. "24:00" when the shift ends at midnight, like manual shifts.
  internal let endTime: String
  internal let title: String?

  internal var id: String { "\(date) \(startTime) \(endTime)" }
}

/// Reads shifts from iCalendar (.ics) text such as Planday, Quinyx, Tamigo or MinGat feeds.
/// Only timed VEVENTs become shifts. All-day, cancelled and 24 hour or longer events are skipped.
/// ponytail: RRULE is ignored (only the first occurrence is read) and DURATION is not supported.
/// Shift feeds list each shift as its own event with DTEND. Add both if a feed needs them.
internal enum ICSShiftParser {
  private struct Property {
    let name: String
    let params: [String: String]
    let value: String
  }

  /// Turns pasted text into a fetchable https URL. webcal:// and http:// become https://.
  internal static func feedURL(from input: String) -> URL? {
    var text: String = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if let separator = text.range(of: "://") {
      let scheme: String = text[..<separator.lowerBound].lowercased()
      guard ["https", "http", "webcal", "webcals"].contains(scheme) else {
        return nil
      }
      text = "https" + text[separator.lowerBound...]
    } else {
      text = "https://" + text
    }
    guard let url = URL(string: text), url.host()?.contains(".") == true else {
      return nil
    }
    return url
  }

  /// Shifts in the feed, sorted by start and without repeats of the same date and times.
  /// Floating times and unknown TZIDs are read in `timeZone`.
  internal static func shifts(
    from ics: String,
    timeZone: TimeZone = Date.localTimeZone
  ) -> [CalendarImportShift] {
    var shiftsById: [String: CalendarImportShift] = [:]
    var event: [String: Property]?
    var nestedDepth: Int = 0

    for line in unfoldedLines(ics) {
      let upper: String = line.uppercased()
      if upper == "BEGIN:VEVENT" {
        event = [:]
        nestedDepth = 0
      } else if upper == "END:VEVENT" {
        if let event, let parsed = shift(from: event, timeZone: timeZone),
          shiftsById[parsed.id] == nil
        {
          shiftsById[parsed.id] = parsed
        }
        event = nil
      } else if event != nil {
        // Skip properties of VALARM and other blocks nested in the event.
        if upper.hasPrefix("BEGIN:") {
          nestedDepth += 1
        } else if upper.hasPrefix("END:") {
          nestedDepth -= 1
        } else if nestedDepth == 0, let parsed = property(from: line),
          event?[parsed.name] == nil
        {
          event?[parsed.name] = parsed
        }
      }
    }
    return shiftsById.values.sorted { $0.start < $1.start }
  }

  /// RFC 5545 line unfolding. A line starting with a space or tab continues the previous one.
  private static func unfoldedLines(_ text: String) -> [String] {
    var lines: [String] = []
    // "\r\n" is one Character in Swift, and isNewline covers it.
    for raw in text.split(whereSeparator: \.isNewline) {
      if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
        lines[lines.count - 1] += raw.dropFirst()
      } else {
        lines.append(String(raw))
      }
    }
    return lines
  }

  private static func property(from line: String) -> Property? {
    var inQuotes: Bool = false
    let colonIndex: String.Index? = line.firstIndex { character in
      if character == "\"" {
        inQuotes.toggle()
      }
      return character == ":" && !inQuotes
    }
    guard let colonIndex else {
      return nil
    }
    let head: [Substring] = line[..<colonIndex].split(separator: ";")
    guard let name = head.first else {
      return nil
    }
    var params: [String: String] = [:]
    for param in head.dropFirst() {
      let pair: [Substring] = param.split(separator: "=", maxSplits: 1)
      if pair.count == 2 {
        params[pair[0].uppercased()] = pair[1].trimmingCharacters(
          in: CharacterSet(charactersIn: "\""))
      }
    }
    return Property(
      name: name.uppercased(),
      params: params,
      value: String(line[line.index(after: colonIndex)...])
    )
  }

  private static func shift(
    from event: [String: Property],
    timeZone: TimeZone
  ) -> CalendarImportShift? {
    guard event["STATUS"]?.value.uppercased() != "CANCELLED",
      let startProperty = event["DTSTART"],
      let endProperty = event["DTEND"],
      let start = date(from: startProperty, defaultTimeZone: timeZone),
      let end = date(from: endProperty, defaultTimeZone: timeZone)
    else {
      return nil
    }
    let duration: TimeInterval = end.timeIntervalSince(start)
    guard duration > 0, duration < 24 * 60 * 60 else {
      return nil
    }

    let startTime: String = start.toHourMinuteString(in: timeZone)
    var endTime: String = end.toHourMinuteString(in: timeZone)
    if endTime == "00:00", startTime != "00:00" {
      endTime = "24:00"
    }
    guard startTime != endTime else {
      return nil
    }

    let title: String? = event["SUMMARY"].map { unescapedText($0.value) }
    return CalendarImportShift(
      start: start,
      end: end,
      date: start.toISODateString(in: timeZone),
      startTime: startTime,
      endTime: endTime,
      title: title?.isEmpty == false ? title : nil
    )
  }

  /// Parses DATE-TIME values: UTC ("...Z"), with TZID, or floating. Returns nil for all-day DATE values.
  private static func date(from property: Property, defaultTimeZone: TimeZone) -> Date? {
    if property.params["VALUE"]?.uppercased() == "DATE" {
      return nil
    }
    var value: String = property.value.trimmingCharacters(in: .whitespaces).uppercased()
    var timeZone: TimeZone =
      property.params["TZID"].flatMap(knownTimeZone(named:)) ?? defaultTimeZone
    if value.hasSuffix("Z") {
      value.removeLast()
      timeZone = .gmt
    }

    let parts: [Substring] = value.split(separator: "T")
    guard parts.count == 2, parts[0].count == 8, parts[1].count == 4 || parts[1].count == 6 else {
      return nil
    }
    let day: [Character] = Array(parts[0])
    let time: [Character] = Array(parts[1])
    func number(_ characters: ArraySlice<Character>) -> Int? {
      Int(String(characters))
    }
    guard let year = number(day[0..<4]),
      let month = number(day[4..<6]),
      let dayOfMonth = number(day[6..<8]),
      let hour = number(time[0..<2]),
      let minute = number(time[2..<4])
    else {
      return nil
    }

    var calendar: Calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    // Seconds are dropped. Tidex stores shift times to the minute.
    return calendar.date(
      from: DateComponents(year: year, month: month, day: dayOfMonth, hour: hour, minute: minute)
    )
  }

  /// Olson names like "Europe/Oslo", also when prefixed with a vendor path.
  /// Windows names ("W. Europe Standard Time") fall back to the device time zone.
  private static func knownTimeZone(named identifier: String) -> TimeZone? {
    TimeZone(identifier: identifier)
      ?? TimeZone(identifier: identifier.split(separator: "/").suffix(2).joined(separator: "/"))
  }

  private static func unescapedText(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\n", with: " ")
      .replacingOccurrences(of: "\\N", with: " ")
      .replacingOccurrences(of: "\\,", with: ",")
      .replacingOccurrences(of: "\\;", with: ";")
      .replacingOccurrences(of: "\\\\", with: "\\")
      .trimmingCharacters(in: .whitespaces)
  }
}
