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

  /// Formats with microsecond precision, e.g. `2026-09-28T10:15:30.123456Z`.
  /// Postgres stores microseconds. A sync cursor needs all of them, because a millisecond cursor
  /// sorts before its own row, so `updated_at > cursor` returns that row again and every row
  /// that shares its timestamp.
  static func microsecondString(from date: Date) -> String {
    // Rounds to the nearest microsecond, since a Double holds the parsed value only to within
    // a fraction of one. The count stays below 2^53, so the Double math is exact.
    let micros = (date.timeIntervalSince1970 * 1_000_000).rounded()
    let seconds = (micros / 1_000_000).rounded(.down)
    let fraction = Int(micros - seconds * 1_000_000)
    let wholeSeconds = whole.format(Date(timeIntervalSince1970: seconds)).dropLast()  // drops "Z"
    return wholeSeconds + String(format: ".%06dZ", fraction)
  }
}
