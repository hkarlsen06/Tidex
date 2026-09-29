import Foundation

// MARK: - Pay Period

/// How a job groups worked days into payouts. Stored as JSON in `jobs.pay_period`.
/// A job without a stored value uses `.calendarMonth`.
enum PayPeriod: Equatable, Sendable {
  /// A month-long period starting on `startDay` (1-28). Start day 1 is the calendar month.
  /// `payoutMonthOffset` is 0 when pay comes in the month the period ends, 1 for the month after.
  case monthly(startDay: Int, payoutMonthOffset: Int)
  /// 14-day periods. `anchorEnd` is the last day (yyyy-MM-dd) of any one period.
  /// Payday is `payoutDelayDays` after each period ends.
  case biweekly(anchorEnd: String, payoutDelayDays: Int)

  static let calendarMonth = PayPeriod.monthly(startDay: 1, payoutMonthOffset: 1)

  static let startDayRange = 1...28
  static let payoutDelayRange = 0...27

  var isCalendarMonth: Bool { self == .calendarMonth }

  var isBiweekly: Bool {
    if case .biweekly = self { return true }
    return false
  }
}

extension PayPeriod: Codable {
  private enum Kind: String, Codable {
    case monthly
    case biweekly
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case startDay
    case payoutMonthOffset
    case anchorEnd
    case payoutDelayDays
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .monthly:
      let startDay = try container.decode(Int.self, forKey: .startDay)
      let offset = try container.decode(Int.self, forKey: .payoutMonthOffset)
      guard Self.startDayRange.contains(startDay), (0...1).contains(offset) else {
        throw DecodingError.dataCorruptedError(
          forKey: .startDay, in: container, debugDescription: "Invalid monthly pay period")
      }
      self = .monthly(startDay: startDay, payoutMonthOffset: offset)

    case .biweekly:
      let anchorEnd = try container.decode(String.self, forKey: .anchorEnd)
      let delay = try container.decode(Int.self, forKey: .payoutDelayDays)
      guard PayPeriodCalendar.date(anchorEnd) != nil, Self.payoutDelayRange.contains(delay) else {
        throw DecodingError.dataCorruptedError(
          forKey: .anchorEnd, in: container, debugDescription: "Invalid biweekly pay period")
      }
      self = .biweekly(anchorEnd: anchorEnd, payoutDelayDays: delay)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .monthly(let startDay, let offset):
      try container.encode(Kind.monthly, forKey: .type)
      try container.encode(startDay, forKey: .startDay)
      try container.encode(offset, forKey: .payoutMonthOffset)

    case .biweekly(let anchorEnd, let delay):
      try container.encode(Kind.biweekly, forKey: .type)
      try container.encode(anchorEnd, forKey: .anchorEnd)
      try container.encode(delay, forKey: .payoutDelayDays)
    }
  }

  /// JSON string for local storage, or nil for the calendar-month default.
  var storageJSON: String? {
    guard !isCalendarMonth, let data = try? JSONEncoder().encode(self) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Decodes a stored JSON string. Missing or invalid values fall back to the calendar month.
  static func fromStorageJSON(_ json: String?) -> PayPeriod {
    guard let data = json?.data(using: .utf8),
      let period = try? JSONDecoder().decode(PayPeriod.self, from: data)
    else {
      return .calendarMonth
    }
    return period
  }
}

// MARK: - Pay Window

/// One pay period and the payout it belongs to. Dates are yyyy-MM-dd strings.
struct PayWindow: Equatable, Sendable {
  let start: String
  let end: String
  /// Payday before weekend and holiday adjustment. Used for tax lookups.
  let payoutDate: String

  func contains(_ dateISO: String) -> Bool {
    start <= dateISO && dateISO <= end
  }

  var payoutMonth: Int {
    PayPeriodCalendar.components(payoutDate)?.month ?? 1
  }
}

// MARK: - Payout Schedule

/// A job's pay period together with its monthly payday.
struct PayoutSchedule: Equatable, Sendable {
  let period: PayPeriod
  /// Day of month for monthly payouts (1-31, clamped to the month's length).
  let payrollDay: Int

  /// The pay window that a worked day belongs to.
  func window(containing dateISO: String) -> PayWindow? {
    guard let date = PayPeriodCalendar.components(dateISO) else { return nil }

    switch period {
    case .monthly(let startDay, _):
      var start = (year: date.year, month: date.month)
      if date.day < startDay {
        start = PayPeriodCalendar.previousYearMonth(from: start)
      }
      return monthlyWindow(startYM: start, startDay: startDay)

    case .biweekly(let anchorEnd, _):
      guard let days = PayPeriodCalendar.daysBetween(anchorEnd, dateISO) else { return nil }
      // Round up to the end of the 14-day block containing the date.
      let blocks = Int((Double(days) / 14).rounded(.up))
      return biweeklyWindow(anchorEnd: anchorEnd, blockOffset: blocks)
    }
  }

  /// Nominal payout date for a worked day. Replaces "shift month + 1".
  func payoutDate(for dateISO: String) -> String {
    window(containing: dateISO)?.payoutDate ?? dateISO
  }

  /// Windows whose nominal payday falls in the given month, earliest first.
  func windows(paidInYear year: Int, month: Int) -> [PayWindow] {
    switch period {
    case .monthly(let startDay, let storedOffset):
      var endYM = (year: year, month: month)
      for _ in 0..<payoutMonthOffset(startDay: startDay, stored: storedOffset) {
        endYM = PayPeriodCalendar.previousYearMonth(from: endYM)
      }
      let startYM = startDay == 1 ? endYM : PayPeriodCalendar.previousYearMonth(from: endYM)
      return [monthlyWindow(startYM: startYM, startDay: startDay)]

    case .biweekly(let anchorEnd, let delay):
      let firstDay = String(format: "%04d-%02d-01", year, month)
      let lastDay = String(
        format: "%04d-%02d-%02d", year, month, PayPeriodCalendar.daysInMonth(year: year, month: month))
      guard let daysToMonthStart = PayPeriodCalendar.daysBetween(anchorEnd, firstDay) else {
        return []
      }
      // First block whose payday (end + delay) is on or after the 1st.
      var block = Int((Double(daysToMonthStart - delay) / 14).rounded(.up))
      var result: [PayWindow] = []
      while let window = biweeklyWindow(anchorEnd: anchorEnd, blockOffset: block),
        window.payoutDate <= lastDay
      {
        result.append(window)
        block += 1
      }
      return result
    }
  }

  /// The window paid out just before `window`.
  func previousWindow(before window: PayWindow) -> PayWindow? {
    guard let dayBefore = PayPeriodCalendar.adding(days: -1, to: window.start) else { return nil }
    return self.window(containing: dayBefore)
  }

  /// Whether a monthly period starting on `startDay` can be paid in the month it ends.
  /// Payday has to come after the period's last day, so the calendar month never can.
  static func canPayInEndMonth(startDay: Int, payrollDay: Int) -> Bool {
    startDay > 1 && payrollDay >= startDay
  }

  /// The stored offset, except that a same-month payday before the period ends moves to the
  /// next month. Otherwise work from 28 September to 27 October would be paid 10 October.
  private func payoutMonthOffset(startDay: Int, stored: Int) -> Int {
    Self.canPayInEndMonth(startDay: startDay, payrollDay: payrollDay) ? stored : 1
  }

  private func monthlyWindow(startYM: (year: Int, month: Int), startDay: Int) -> PayWindow {
    let start = String(format: "%04d-%02d-%02d", startYM.year, startYM.month, startDay)
    let nextStartYM = PayPeriodCalendar.nextYearMonth(from: startYM)
    let nextStart = String(format: "%04d-%02d-%02d", nextStartYM.year, nextStartYM.month, startDay)
    let end = PayPeriodCalendar.adding(days: -1, to: nextStart) ?? start

    guard case .monthly(_, let storedOffset) = period,
      let endParts = PayPeriodCalendar.components(end)
    else {
      return PayWindow(start: start, end: end, payoutDate: end)
    }
    var payoutYM = (year: endParts.year, month: endParts.month)
    for _ in 0..<payoutMonthOffset(startDay: startDay, stored: storedOffset) {
      payoutYM = PayPeriodCalendar.nextYearMonth(from: payoutYM)
    }
    let day = min(max(payrollDay, 1), PayPeriodCalendar.daysInMonth(year: payoutYM.year, month: payoutYM.month))
    let payout = String(format: "%04d-%02d-%02d", payoutYM.year, payoutYM.month, day)
    return PayWindow(start: start, end: end, payoutDate: payout)
  }

  private func biweeklyWindow(anchorEnd: String, blockOffset: Int) -> PayWindow? {
    guard case .biweekly(_, let delay) = period,
      let end = PayPeriodCalendar.adding(days: blockOffset * 14, to: anchorEnd),
      let start = PayPeriodCalendar.adding(days: -13, to: end),
      let payout = PayPeriodCalendar.adding(days: delay, to: end)
    else {
      return nil
    }
    return PayWindow(start: start, end: end, payoutDate: payout)
  }
}

// MARK: - Day Arithmetic

/// Day arithmetic on yyyy-MM-dd strings in UTC, so DST changes never shift a day.
enum PayPeriodCalendar {
  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }()

  static func previousYearMonth(from value: (year: Int, month: Int)) -> (year: Int, month: Int) {
    value.month == 1 ? (value.year - 1, 12) : (value.year, value.month - 1)
  }

  static func nextYearMonth(from value: (year: Int, month: Int)) -> (year: Int, month: Int) {
    value.month == 12 ? (value.year + 1, 1) : (value.year, value.month + 1)
  }

  static func daysInMonth(year: Int, month: Int) -> Int {
    guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
      return 31
    }
    return calendar.range(of: .day, in: .month, for: first)?.count ?? 31
  }

  static func date(_ iso: String) -> Date? {
    guard let parts = components(iso) else { return nil }
    return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
  }

  struct DayParts {
    let year: Int
    let month: Int
    let day: Int
  }

  static func components(_ iso: String) -> DayParts? {
    let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
      return nil
    }
    return DayParts(year: parts[0], month: parts[1], day: parts[2])
  }

  static func adding(days: Int, to iso: String) -> String? {
    guard let base = date(iso), let result = calendar.date(byAdding: .day, value: days, to: base)
    else {
      return nil
    }
    let parts = calendar.dateComponents([.year, .month, .day], from: result)
    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }

  static func daysBetween(_ fromISO: String, _ toISO: String) -> Int? {
    guard let from = date(fromISO), let to = date(toISO) else { return nil }
    return calendar.dateComponents([.day], from: from, to: to).day
  }
}
