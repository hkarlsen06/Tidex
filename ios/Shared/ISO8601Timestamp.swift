import Foundation

/// ISO 8601 timestamps as Supabase and PostgREST send them, with or without fractional seconds.
enum ISO8601Timestamp {
  private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let whole = Date.ISO8601FormatStyle()

  static func date(from string: String) -> Date? {
    (try? fractional.parse(string)) ?? (try? whole.parse(string))
  }

  /// Formats with millisecond precision, e.g. `2026-09-28T10:15:30.123Z`.
  static func string(from date: Date) -> String {
    fractional.format(date)
  }
}
