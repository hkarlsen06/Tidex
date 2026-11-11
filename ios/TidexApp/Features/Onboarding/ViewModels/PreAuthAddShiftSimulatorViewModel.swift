import Foundation
import Observation

/// The shift built in the pre-auth demo, carried to the sign-up screen.
struct PreAuthDemoShift: Equatable {
  /// Sorted `yyyy-MM-dd` dates.
  let dates: [String]
  /// `HH:mm`.
  let startTime: String
  let endTime: String
}

/// What the demo shift pays at the example rate, split the way the payroll calculator computed it.
/// The lines add up to `net`.
struct PreAuthDemoPay: Equatable {
  enum Kind: Hashable {
    case hours(Double, rate: Double)
    case supplement(PreAuthDemoSupplement)
    case unpaidBreak(minutes: Int)
    case tax(percent: Double)
  }

  struct Line: Hashable {
    let kind: Kind
    let amount: Double
  }

  let lines: [Line]
  let net: Double
}

/// The example supplements. Percentages work for every currency.
enum PreAuthDemoSupplement: CaseIterable, Hashable {
  case evening
  case saturday
  case sunday

  var percent: Double {
    switch self {
    case .evening: 20
    case .saturday: 30
    case .sunday: 50
    }
  }

  var rule: SupplementRule {
    switch self {
    case .evening: SupplementRule(days: [1, 2, 3, 4, 5], from: "18:00", to: "24:00", percent: percent)
    case .saturday: SupplementRule(days: [6], from: "13:00", to: "24:00", percent: percent)
    case .sunday: SupplementRule(days: [7], from: "00:00", to: "24:00", percent: percent)
    }
  }

  /// The supplement that pays on a weekday, 1 for Monday through 7 for Sunday.
  static func on(weekday: Int) -> Self {
    switch weekday {
    case 6: .saturday
    case 7: .sunday
    default: .evening
    }
  }
}

/// Local-only Add tab demo for pre-auth onboarding. Nothing is saved and no account is needed.
@MainActor
@Observable
final class PreAuthAddShiftSimulatorViewModel: AddShiftCalendarViewModeling {
  var startTime: Date?  // swiftlint:disable:this explicit_acl
  var endTime: Date?  // swiftlint:disable:this explicit_acl
  var selectedDates: Set<String>

  private(set) var currency: String

  let displayMonth: Date
  let displayYear: Int
  let presetTimeRanges: [TimeRangeCount] = [
    TimeRangeCount(startTime: "08:00", endTime: "16:00", count: 3),
    TimeRangeCount(startTime: "10:00", endTime: "18:00", count: 2),
    TimeRangeCount(startTime: "14:00", endTime: "22:00", count: 1),
  ]
  let navigationDirection: MonthNavigationDirection? = nil
  let conflictDates: Set<String> = []
  let existingShiftHours: [String: HoursData] = [:]

  private static let payrollDay = 15
  private static let taxPercentage = 20.0

  init(
    initialCurrency: String = OnboardingCurrencyResolver.detectDefaultCurrency(),
    now: Date = Date()
  ) {
    let calendar = Calendar.gregorianCurrent
    let month = calendar.dateInterval(of: .month, for: now)?.start ?? now
    displayMonth = month
    displayYear = calendar.component(.year, from: month)
    selectedDates = [Self.suggestedDate(now: now, calendar: calendar)]
    currency =
      OnboardingCurrencyResolver.isSupportedCurrency(initialCurrency)
      ? initialCurrency
      : OnboardingCurrencyResolver.detectDefaultCurrency()
  }

  var displayMonthName: String {
    CalendarGridHelper.monthName(from: displayMonth, locale: .appLocale)
  }

  var hourlyRate: Double {
    OnboardingCurrencyResolver.defaultHourlyWage(for: currency)
  }

  /// Set once the user has picked dates and both times.
  var shift: PreAuthDemoShift? {
    guard let startTime, let endTime, !selectedDates.isEmpty else { return nil }
    let start = startTime.toHourMinuteString()
    var end = endTime.toHourMinuteString()
    if end == "00:00", start != "00:00" { end = "24:00" }
    return PreAuthDemoShift(dates: selectedDates.sorted(), startTime: start, endTime: end)
  }

  var pay: PreAuthDemoPay? {
    guard let shift else { return nil }
    let computed = computedShifts(shift)
    var hours = 0.0
    var base = 0.0
    var supplements: [PreAuthDemoSupplement: Double] = [:]
    var breakHours = 0.0
    var gross = 0.0
    for (dateISO, result) in computed {
      hours += result.durationHours
      gross += result.gross
      breakHours += result.breakAudit.deductedHours
      let weekday = Self.weekday(of: dateISO)
      for period in result.originalWagePeriods where period.durationMinutes > 0 {
        base += period.durationHours * period.baseRate
        guard period.supplementRate > 0 else { continue }
        let dayOffset = Int((period.fromMin / 1_440).rounded(.down))
        let supplement = PreAuthDemoSupplement.on(weekday: (weekday - 1 + dayOffset) % 7 + 1)
        supplements[supplement, default: 0] += period.durationHours * period.supplementRate
      }
    }
    let preBreakGross = base + supplements.values.reduce(0, +)
    let tax = gross * Self.taxPercentage / 100

    var lines = [PreAuthDemoPay.Line(kind: .hours(hours, rate: hourlyRate), amount: base)]
    for supplement in PreAuthDemoSupplement.allCases {
      if let amount = supplements[supplement] {
        lines.append(.init(kind: .supplement(supplement), amount: amount))
      }
    }
    if breakHours > 0 {
      lines.append(
        .init(kind: .unpaidBreak(minutes: Int((breakHours * 60).rounded())), amount: gross - preBreakGross))
    }
    lines.append(.init(kind: .tax(percent: Self.taxPercentage), amount: -tax))
    return PreAuthDemoPay(lines: lines, net: gross - tax)
  }

  /// Each selected day's pay, drawn in its calendar cell as in the real Add screen.
  var previewEarnings: [String: CalendarEarningsData] {
    guard let shift else { return [:] }
    return computedShifts(shift).mapValues {
      CalendarEarningsData(
        net: $0.netPay(taxEnabled: true, taxPercentage: Self.taxPercentage),
        gross: $0.gross, hasTaxEnabled: true)
    }
  }

  func toggleDate(_ dateISO: String) {
    if selectedDates.contains(dateISO) {
      selectedDates.remove(dateISO)
    } else {
      selectedDates.insert(dateISO)
    }
    Haptics.play(.light)
  }

  func applyCurrency(_ symbol: String) {
    guard OnboardingCurrencyResolver.isSupportedCurrency(symbol) else { return }
    currency = symbol
  }

  private func computedShifts(_ shift: PreAuthDemoShift) -> [String: ShiftComputed] {
    let snapshot = Self.snapshot(hourlyWage: hourlyRate)
    var result: [String: ShiftComputed] = [:]
    for dateISO in shift.dates {
      let row = ShiftRow(
        id: "onboarding-preview-\(dateISO)", user_id: nil, shift_date: dateISO,
        start_time: shift.startTime, end_time: shift.endTime, custom_supplements: nil)
      result[dateISO] = PayrollCalculator.computeShift(row, snapshot: snapshot)
    }
    return result
  }

  /// The first Saturday after today in this month, else tomorrow, else today. The calendar
  /// shows only this month.
  private static func suggestedDate(now: Date, calendar: Calendar) -> String {
    let month = calendar.component(.month, from: now)
    let following = (1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
      .filter { calendar.component(.month, from: $0) == month }
    let saturday = following.first { calendar.component(.weekday, from: $0) == 7 }
    return (saturday ?? following.first ?? now).toISODateString()
  }

  /// 1 for Monday through 7 for Sunday.
  private static func weekday(of dateISO: String) -> Int {
    guard let date = Date.fromISODateString(dateISO) else { return 1 }
    return (Calendar.gregorianCurrent.component(.weekday, from: date) + 5) % 7 + 1
  }

  private static func snapshot(hourlyWage: Double) -> WageSnapshot {
    WageSnapshot(
      id: "onboarding-baseline",
      user_id: "onboarding-demo",
      from_date: nil,
      hourly_wage: hourlyWage,
      wage_level: nil,
      tariff_type_id: nil,
      supplements: SupplementRulesSnapshot(rules: PreAuthDemoSupplement.allCases.map(\.rule)),
      tax_enabled: true,
      tax_percentage: taxPercentage,
      break_enabled: true,
      break_method: BreakMethod.proportional.rawValue,
      break_threshold_hours: 5.5,
      break_deduction_minutes: 30,
      created_at: nil
    )
  }
}
