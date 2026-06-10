// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface function_body_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable identifier_name multiline_arguments_brackets no_magic_numbers number_separator
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable type_contents_order
import Foundation

/// Norwegian Public Holidays
///
/// Provides a lightweight implementation of Norwegian public holidays
/// matching the Next.js implementation in `lib/holidays/norwegian-holidays.ts`.
///
/// Holiday Types:
/// - Fixed: Same date every year (New Year, Labor Day, Constitution Day, Christmas)
/// - Moveable: Based on Easter (calculated via Computus algorithm)
enum NorwegianHolidays {

  // MARK: - Easter Dates

  /// Pre-computed Easter Sunday dates for 2025-2030
  private static let easterDates: [Int: (month: Int, day: Int)] = [
    2_025: (month: 4, day: 20),  // April 20, 2025
    2_026: (month: 4, day: 5),  // April 5, 2026
    2_027: (month: 3, day: 28),  // March 28, 2027
    2_028: (month: 4, day: 16),  // April 16, 2028
    2_029: (month: 4, day: 1),  // April 1, 2029
    2_030: (month: 4, day: 21),  // April 21, 2030
  ]

  // MARK: - Public API

  /// Check if a date is a Norwegian public holiday
  /// - Parameter date: The date to check
  /// - Returns: true if the date is a public holiday
  static func isPublicHoliday(_ date: Date) -> Bool {
    let dateString = formatDateISO(date)
    let year = calendar.component(.year, from: date)
    let holidays = getHolidays(for: year)
    return holidays.contains { $0.date == dateString }
  }

  /// Get the name of a holiday (if the date is a holiday)
  /// - Parameters:
  ///   - date: The date to check
  ///   - locale: The locale for the holiday name ("no" or "en")
  /// - Returns: The holiday name, or nil if not a holiday
  static func getHolidayName(_ date: Date, locale: String = "no") -> String? {
    let dateString = formatDateISO(date)
    let year = calendar.component(.year, from: date)
    let holidays = getHolidays(for: year)
    guard let holiday = holidays.first(where: { $0.date == dateString }) else {
      return nil
    }
    return locale == "en" ? holiday.nameEN : holiday.nameNO
  }

  /// Get all holidays for a specific year
  /// - Parameter year: The year to get holidays for
  /// - Returns: Array of holidays sorted by date
  static func getHolidays(for year: Int) -> [Holiday] {
    cacheLock.lock()
    defer { cacheLock.unlock() }
    if let cached = holidayCache[year] {
      return cached
    }
    let holidays = generateHolidays(for: year)
    holidayCache[year] = holidays
    return holidays
  }

  // MARK: - Holiday Model

  struct Holiday {
    let date: String  // ISO date string (YYYY-MM-DD)
    let nameNO: String
    let nameEN: String
  }

  // MARK: - Private Implementation

  private static let cacheLock = NSLock()
  private static var holidayCache: [Int: [Holiday]] = [:]

  /// Gregorian calendar used for all holiday date calculations.
  private static let calendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    return cal
  }()

  /// Generate all Norwegian public holidays for a given year
  private static func generateHolidays(for year: Int) -> [Holiday] {
    let easter = calculateEaster(year: year)
    var holidays: [Holiday] = []

    // Fixed holidays
    holidays.append(
      Holiday(
        date: "\(year)-01-01",
        nameNO: "Første nyttårsdag",
        nameEN: "New Year's Day"
      ))

    holidays.append(
      Holiday(
        date: "\(year)-05-01",
        nameNO: "Første mai",
        nameEN: "Labour Day"
      ))

    holidays.append(
      Holiday(
        date: "\(year)-05-17",
        nameNO: "Grunnlovsdag",
        nameEN: "Constitution Day"
      ))

    holidays.append(
      Holiday(
        date: "\(year)-12-25",
        nameNO: "Første juledag",
        nameEN: "Christmas Day"
      ))

    holidays.append(
      Holiday(
        date: "\(year)-12-26",
        nameNO: "Andre juledag",
        nameEN: "Boxing Day"
      ))

    // Moveable holidays (Easter-based)
    // Maundy Thursday (Skjærtorsdag) - 3 days before Easter
    holidays.append(
      Holiday(
        date: formatDateISO(addDays(to: easter, days: -3)),
        nameNO: "Skjærtorsdag",
        nameEN: "Maundy Thursday"
      ))

    // Good Friday (Langfredag) - 2 days before Easter
    holidays.append(
      Holiday(
        date: formatDateISO(addDays(to: easter, days: -2)),
        nameNO: "Langfredag",
        nameEN: "Good Friday"
      ))

    // Easter Sunday (Første påskedag)
    holidays.append(
      Holiday(
        date: formatDateISO(easter),
        nameNO: "Første påskedag",
        nameEN: "Easter Sunday"
      ))

    // Easter Monday (Andre påskedag) - 1 day after Easter
    holidays.append(
      Holiday(
        date: formatDateISO(addDays(to: easter, days: 1)),
        nameNO: "Andre påskedag",
        nameEN: "Easter Monday"
      ))

    // Ascension Day (Kristi himmelfartsdag) - 39 days after Easter
    holidays.append(
      Holiday(
        date: formatDateISO(addDays(to: easter, days: 39)),
        nameNO: "Kristi himmelfartsdag",
        nameEN: "Ascension Day"
      ))

    // Whit Sunday (Første pinsedag) - 49 days after Easter
    holidays.append(
      Holiday(
        date: formatDateISO(addDays(to: easter, days: 49)),
        nameNO: "Første pinsedag",
        nameEN: "Whit Sunday"
      ))

    // Whit Monday (Andre pinsedag) - 50 days after Easter
    holidays.append(
      Holiday(
        date: formatDateISO(addDays(to: easter, days: 50)),
        nameNO: "Andre pinsedag",
        nameEN: "Whit Monday"
      ))

    return holidays.sorted { $0.date < $1.date }
  }

  /// Calculate Easter Sunday for a given year using the Computus algorithm
  private static func calculateEaster(year: Int) -> Date {
    let month: Int
    let day: Int

    if let precomputed = easterDates[year] {
      month = precomputed.month
      day = precomputed.day
    } else {
      // Computus algorithm (Anonymous Gregorian algorithm) for years beyond precomputed range
      let a = year % 19
      let b = year / 100
      let c = year % 100
      let d = b / 4
      let e = b % 4
      let f = (b + 8) / 25
      let g = (b - f + 1) / 3
      let h = (19 * a + b - d - g + 15) % 30
      let i = c / 4
      let k = c % 4
      let l = (32 + 2 * e + 2 * i - h - k) % 7
      let m = (a + 11 * h + 22 * l) / 451
      month = (h + l - 7 * m + 114) / 31
      day = ((h + l - 7 * m + 114) % 31) + 1
    }

    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12  // Noon to avoid timezone edge cases
    // Calendar.date(from:) should never fail for valid Computus output (month 3-4, day 1-31).
    // Use distantPast instead of Date() so any failure is obviously wrong rather than silent.
    return calendar.date(from: components) ?? .distantPast
  }

  /// Add days to a date
  private static func addDays(to date: Date, days: Int) -> Date {
    calendar.date(byAdding: .day, value: days, to: date) ?? date
  }

  /// Format date as YYYY-MM-DD
  private static func formatDateISO(_ date: Date) -> String {
    let year = calendar.component(.year, from: date)
    let month = calendar.component(.month, from: date)
    let day = calendar.component(.day, from: date)
    return String(format: "%04d-%02d-%02d", year, month, day)
  }
}
