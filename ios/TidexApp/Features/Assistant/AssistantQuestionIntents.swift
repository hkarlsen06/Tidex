import AppIntents
import SwiftUI

enum EarningsPeriod: String, AppEnum {
  case thisWeek
  case thisMonth
  case lastMonth
  case thisYear

  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "assistant.period.type")
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .thisWeek: "assistant.period.thisWeek",
    .thisMonth: "assistant.period.thisMonth",
    .lastMonth: "assistant.period.lastMonth",
    .thisYear: "assistant.period.thisYear",
  ]

  var name: String {
    switch self {
    case .thisWeek: String(localized: .assistantPeriodThisWeek)
    case .thisMonth: String(localized: .assistantPeriodThisMonth)
    case .lastMonth: String(localized: .assistantPeriodLastMonth)
    case .thisYear: String(localized: .assistantPeriodThisYear)
    }
  }

  /// First and last day of the period, both included.
  func days(around now: Date, calendar: Calendar = .gregorianCurrent) -> (first: Date, last: Date) {
    let interval: DateInterval?
    switch self {
    case .thisWeek:
      interval = calendar.dateInterval(of: .weekOfYear, for: now)

    case .thisMonth:
      interval = calendar.dateInterval(of: .month, for: now)

    case .lastMonth:
      interval = calendar.date(byAdding: .month, value: -1, to: now)
        .flatMap { calendar.dateInterval(of: .month, for: $0) }

    case .thisYear:
      interval = calendar.dateInterval(of: .year, for: now)
    }
    let start = interval?.start ?? calendar.startOfDay(for: now)
    let end = interval?.end ?? start
    return (start, calendar.date(byAdding: .day, value: -1, to: end) ?? start)
  }
}

/// Earnings and hours for a period, added up like Home's total card.
struct PeriodEarnings: Equatable {
  let gross: Double
  let completedGross: Double
  /// Nil when tax is off.
  let net: Double?
  let currency: String
  let hours: Double
  let completedHours: Double
  let shiftCount: Int

  /// `shiftsByMonth` holds each month's computed shifts, already limited to the period.
  static func compute(
    shiftsByMonth: [(month: Int, shifts: [ShiftWithComputations])],
    jobs: [Job],
    settings: UserSettings?,
    now: Date
  ) -> Self {
    let earnings = EarningsTotals.compute(
      shiftsByMonth: shiftsByMonth,
      jobs: jobs,
      fallbackCurrency: settings?.currency ?? "kr",
      halfTaxMonth: settings?.half_tax_month,
      now: now
    )
    let counted = shiftsByMonth.flatMap { month in
      let excluded = ConflictExclusion.buildExcludedShiftIds(shifts: month.shifts)
      return month.shifts.filter { !excluded.contains($0.id) }
    }
    let completed = counted.filter {
      Date.hasShiftEnded(
        shiftDate: $0.shiftDate, startTime: $0.startTime, endTime: $0.endTime, referenceDate: now)
    }
    return Self(
      gross: earnings.totals.gross,
      completedGross: earnings.totals.completedGross,
      net: earnings.taxEnabled ? earnings.totals.net : nil,
      currency: earnings.currency,
      hours: counted.reduce(0) { $0 + $1.paidHours },
      completedHours: completed.reduce(0) { $0 + $1.paidHours },
      shiftCount: counted.count
    )
  }

  /// Reads shifts through the same services as Home.
  @MainActor
  static func load(
    _ period: EarningsPeriod,
    userId: String,
    now: Date = Date(),
    readService: MonthlyPayrollReadService = .shared
  ) async -> Self {
    let days = period.days(around: now)
    let firstISO = days.first.toISODateString()
    let lastISO = days.last.toISODateString()
    let context = await readService.loadContextUsingStoreActor(for: userId)

    var shiftsByMonth: [(month: Int, shifts: [ShiftWithComputations])] = []
    var month = days.first.yearMonth()
    let lastMonth = days.last.yearMonth()
    while (month.year, month.month) <= (lastMonth.year, lastMonth.month) {
      let raw = await readService.loadRawWindow(
        for: userId, window: .month(year: month.year, month: month.month))
      let computed = PayrollEngine.computeShiftsForMonth(
        .init(
          year: month.year, month: month.month, shifts: raw.shifts,
          recurring: context.recurringShifts, snapshots: context.snapshots,
          settings: context.settings, jobs: context.jobs))
      shiftsByMonth.append(
        (month.month, computed.filter { $0.shiftDate >= firstISO && $0.shiftDate <= lastISO }))
      month = Date.nextYearMonth(from: month)
    }
    return compute(
      shiftsByMonth: shiftsByMonth, jobs: context.jobs, settings: context.settings, now: now)
  }

  func earningsDialog(for period: EarningsPeriod) -> String {
    guard shiftCount > 0 else { return String(localized: .assistantPeriodNoShifts(period.name)) }
    let total = CurrencyConfig.format(gross, currency: currency)
    var text =
      completedGross < gross
      ? String(
        localized: .assistantEarningsTotalSoFar(
          period.name, total, CurrencyConfig.format(completedGross, currency: currency)))
      : String(localized: .assistantEarningsTotal(period.name, total))
    if let net {
      text +=
        " "
        + String(localized: .assistantEarningsNet(CurrencyConfig.format(net, currency: currency)))
    }
    return text
  }

  func hoursDialog(for period: EarningsPeriod) -> String {
    guard shiftCount > 0 else { return String(localized: .assistantPeriodNoShifts(period.name)) }
    let total = Self.formatHours(hours)
    return completedHours < hours
      ? String(
        localized: .assistantHoursTotalSoFar(period.name, total, Self.formatHours(completedHours)))
      : String(localized: .assistantHoursTotal(period.name, total))
  }

  private static func formatHours(_ hours: Double) -> String {
    Measurement(value: hours, unit: UnitDuration.hours).formatted(
      .measurement(width: .wide, numberFormatStyle: .number.precision(.fractionLength(0...1))))
  }
}

struct NextShiftIntent: AppIntent {
  static let title: LocalizedStringResource = "assistant.nextShift.title"
  static let description = IntentDescription("assistant.nextShift.description")

  @MainActor
  func perform() async throws
    -> some IntentResult & ReturnsValue<ShiftEntity?> & ProvidesDialog & ShowsSnippetView
  {
    let now = Date()
    let next = try await AssistantShifts.entities(access: .current, now: now)
      .first { $0.start > now }
    guard let next else {
      return .result(
        value: nil, dialog: IntentDialog(.assistantNextShiftNone),
        view: NextShiftSnippet(shift: nil))
    }
    let dialog = String(
      localized: .assistantNextShiftDialog(
        next.jobName,
        next.start.formatted(.dateTime.weekday(.wide).day().month(.wide)),
        next.start.formatted(date: .omitted, time: .shortened),
        next.end.formatted(date: .omitted, time: .shortened)))
    return .result(value: next, dialog: "\(dialog)", view: NextShiftSnippet(shift: next))
  }
}

struct EarningsIntent: AppIntent {
  static let title: LocalizedStringResource = "assistant.earnings.title"
  static let description = IntentDescription("assistant.earnings.description")
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @Parameter(
    title: "assistant.period.type", description: "assistant.period.description",
    default: .thisMonth)
  var period: EarningsPeriod

  init() {}

  init(period: EarningsPeriod) {
    self.period = period
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let userId = try AssistantAccess.current.requireUserId()
    let earnings = await PeriodEarnings.load(period, userId: userId)
    return .result(dialog: "\(earnings.earningsDialog(for: period))")
  }
}

struct HoursWorkedIntent: AppIntent {
  static let title: LocalizedStringResource = "assistant.hours.title"
  static let description = IntentDescription("assistant.hours.description")

  @Parameter(
    title: "assistant.period.type", description: "assistant.period.description",
    default: .thisWeek)
  var period: EarningsPeriod

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let userId = try AssistantAccess.current.requireUserId()
    let earnings = await PeriodEarnings.load(period, userId: userId)
    return .result(dialog: "\(earnings.hoursDialog(for: period))")
  }
}

private struct NextShiftSnippet: View {
  let shift: ShiftEntity?

  var body: some View {
    if let shift {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(shift.jobName)
          .font(.tidexHeadline)
          .foregroundStyle(Color.tidexTextPrimary)
        Text(shift.start.formatted(.dateTime.weekday(.wide).day().month(.wide)))
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexTextSecondary)
        Text((shift.start..<shift.end).formatted(date: .omitted, time: .shortened))
          .font(.tidexAmountMedium)
          .foregroundStyle(Color.tidexTextPrimary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.md)
      .accessibilityElement(children: .combine)
    }
  }
}
