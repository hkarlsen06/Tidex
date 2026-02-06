import Foundation

enum FormatterCache {
  private static func cached<T: AnyObject>(_ key: String, builder: () -> T) -> T {
    let dict = Thread.current.threadDictionary
    if let cached = dict[key] as? T {
      return cached
    }
    let value = builder()
    dict[key] = value
    return value
  }

  static func isoDateFormatter(timeZone: TimeZone = Date.localTimeZone) -> DateFormatter {
    cached("tidex.isoDateFormatter.\(timeZone.identifier)") {
      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = timeZone
      formatter.dateFormat = "yyyy-MM-dd"
      return formatter
    }
  }

  static func iso8601Formatter() -> ISO8601DateFormatter {
    cached("tidex.iso8601Formatter") {
      ISO8601DateFormatter()
    }
  }

  static func iso8601DateOnlyUTCFormatter() -> ISO8601DateFormatter {
    cached("tidex.iso8601DateOnlyUTCFormatter") {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withFullDate]
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      return formatter
    }
  }

  static func numberFormatter(includeDecimals: Bool, locale: Locale) -> NumberFormatter {
    let key =
      "tidex.numberFormatter.\(includeDecimals ? "decimals" : "no-decimals").\(locale.identifier)"
    return cached(key) {
      let formatter = NumberFormatter()
      formatter.numberStyle = .decimal
      formatter.minimumFractionDigits = includeDecimals ? 2 : 0
      formatter.maximumFractionDigits = includeDecimals ? 2 : 0
      formatter.locale = locale
      return formatter
    }
  }

  static func monthNameFormatter(locale: Locale = .current) -> DateFormatter {
    cached("tidex.monthNameFormatter.\(locale.identifier)") {
      let formatter = DateFormatter()
      formatter.locale = locale
      formatter.calendar = Calendar.autoupdatingCurrent
      formatter.dateFormat = "MMMM"
      return formatter
    }
  }

  static func dayFormatter(locale: Locale = .current) -> DateFormatter {
    cached("tidex.dayFormatter.\(locale.identifier)") {
      let formatter = DateFormatter()
      formatter.locale = locale
      formatter.calendar = Calendar.autoupdatingCurrent
      formatter.dateFormat = "d"
      return formatter
    }
  }

  static func dayMonthFormatter(locale: Locale = .current) -> DateFormatter {
    cached("tidex.dayMonthFormatter.\(locale.identifier)") {
      let formatter = DateFormatter()
      formatter.locale = locale
      formatter.calendar = Calendar.autoupdatingCurrent
      formatter.dateFormat = "d MMMM"
      return formatter
    }
  }

  static func shiftDateTimeFormatter(timeZone: TimeZone = .current) -> DateFormatter {
    cached("tidex.shiftDateTimeFormatter.\(timeZone.identifier)") {
      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = timeZone
      formatter.dateFormat = "yyyy-MM-dd HH:mm"
      return formatter
    }
  }

  static func weekdayFormatter(locale: Locale = .current) -> DateFormatter {
    cached("tidex.weekdayFormatter.\(locale.identifier)") {
      let formatter = DateFormatter()
      formatter.locale = locale
      formatter.calendar = Calendar.autoupdatingCurrent
      formatter.dateFormat = "EEEE"
      return formatter
    }
  }

  static func shortMonthFormatter(locale: Locale = .current) -> DateFormatter {
    cached("tidex.shortMonthFormatter.\(locale.identifier)") {
      let formatter = DateFormatter()
      formatter.locale = locale
      formatter.calendar = Calendar.autoupdatingCurrent
      formatter.dateFormat = "MMM"
      return formatter
    }
  }

  static func compactCurrencyFormatter(locale: Locale = .current) -> NumberFormatter {
    cached("tidex.compactCurrencyFormatter.\(locale.identifier)") {
      let formatter = NumberFormatter()
      formatter.numberStyle = .decimal
      formatter.minimumFractionDigits = 0
      formatter.maximumFractionDigits = 0
      formatter.locale = locale
      formatter.groupingSeparator = " "
      return formatter
    }
  }
}
