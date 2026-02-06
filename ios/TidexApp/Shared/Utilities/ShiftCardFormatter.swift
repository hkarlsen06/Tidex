import Foundation

struct ShiftCardDateParts {
  let dayName: String
  let dayNumber: String
  let monthName: String
}

/// Shared formatting helpers for shift cards to avoid duplicated logic.
enum ShiftCardFormatter {
  private static let formatterCache = ShiftCardFormatterCache()

  static func dateParts(for isoDate: String, locale: Locale) -> ShiftCardDateParts {
    guard let date = Date.fromISODateString(isoDate) else {
      return ShiftCardDateParts(dayName: "", dayNumber: "", monthName: "")
    }

    let dayNameFormatter = formatterCache.formatter(locale: locale, format: "EEEE")
    let dayName = dayNameFormatter.string(from: date).capitalized

    let dayNumberFormatter = formatterCache.formatter(locale: locale, format: "d")
    let dayNumber = dayNumberFormatter.string(from: date) + String(localized: .commonDaySuffix)

    let monthFormatter = formatterCache.formatter(locale: locale, format: "MMM")
    let monthName = monthFormatter.string(from: date).lowercased()

    return ShiftCardDateParts(dayName: dayName, dayNumber: dayNumber, monthName: monthName)
  }

  static func formattedHours(_ hours: Double, locale: Locale) -> String {
    let hoursLabel = String(localized: .commonHoursShort)
    let formatter = FormatterCache.numberFormatter(includeDecimals: true, locale: locale)
    let formattedHours =
      formatter.string(from: NSNumber(value: hours)) ?? String(format: "%.2f", hours)
    return "\(formattedHours) \(hoursLabel)"
  }

  static func localizedTime(_ time: String, locale: Locale, format: String = "HH:mm") -> String {
    let hhmm = String(time.prefix(5))
    let parts = hhmm.split(separator: ":")
    guard parts.count >= 2,
      let hour = Int(parts[0]),
      let minute = Int(parts[1])
    else {
      return hhmm
    }
    if hour == 24 && minute == 0 {
      return localizedTimeComponents(hours: 24, minutes: 0, locale: locale)
    }

    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.hour = hour
    components.minute = minute

    let date = components.date ?? Date()
    let formatter = formatterCache.formatter(locale: locale, format: format)
    return formatter.string(from: date)
  }

  static func localizedTimeRange(
    start: String,
    end: String,
    locale: Locale,
    separator: String = "–",
    format: String = "HH:mm"
  ) -> String {
    return
      "\(localizedTime(start, locale: locale, format: format))\(separator)\(localizedTime(end, locale: locale, format: format))"
  }

  private static func localizedTimeComponents(hours: Int, minutes: Int, locale: Locale) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumIntegerDigits = 2
    formatter.maximumIntegerDigits = 2
    let hoursString =
      formatter.string(from: NSNumber(value: hours)) ?? String(format: "%02d", hours)
    let minutesString =
      formatter.string(from: NSNumber(value: minutes)) ?? String(format: "%02d", minutes)
    return "\(hoursString):\(minutesString)"
  }
}

private final class ShiftCardFormatterCache {
  private var formatters: [String: DateFormatter] = [:]
  private let lock = NSLock()

  func formatter(locale: Locale, format: String) -> DateFormatter {
    let key = "\(locale.identifier)|\(format)"

    lock.lock()
    defer { lock.unlock() }

    if let cached = formatters[key] {
      return cached
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: locale.identifier)
    formatter.calendar = Calendar.autoupdatingCurrent
    formatter.dateFormat = format
    formatters[key] = formatter
    return formatter
  }
}
