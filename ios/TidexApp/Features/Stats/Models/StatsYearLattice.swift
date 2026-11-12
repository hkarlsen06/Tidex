import Foundation

/// The Stats screen for one year, padded to exactly 12 month slots. Like `StatsLattice`, views
/// fill the slots and never branch on whether data exists, so a year change swaps values in
/// place. Every amount is in the hero's basis, each month with its own deduction.
struct StatsYearLattice: Equatable {
  struct MonthRow: Equatable, Identifiable {
    /// The month, 1...12.
    let id: Int
    let earnings: Double
    let hours: Double
    let shifts: Int
    /// The same month a year earlier, in the same currency and basis.
    let previousEarnings: Double
    /// After the real current month, so its pay is only scheduled.
    let isAhead: Bool
    let isCurrent: Bool
    let isBest: Bool
  }

  enum MonthsHeadline: Equatable {
    case noPay(year: Int)
    case best(month: Int, amount: Double)
    /// Two or more months share the top, so the sentence gives pay per paid month instead.
    case tied(perPaidMonth: Double)
  }

  struct Months: Equatable {
    let year: Int
    let rows: [MonthRow]
    /// The scale of the bars and ticks, shared by both years.
    let yMax: Double
    let headline: MonthsHeadline
    /// False when the year before has no pay, so there are no ticks and nothing to name.
    let hasPreviousYear: Bool
  }

  let year: Int
  let hero: StatsLattice.Hero
  let metrics: StatsLattice.Metrics
  let months: Months
  let employment: StatsLattice.EmploymentYear
  /// The real current month when the year is this year.
  let currentMonth: Int?
}

extension StatsYearLattice {
  init(stats: YearStatsData, now: Date, calendar: Calendar) {
    let today = StatsLattice.Today(now, calendar: calendar)
    let months = Self.padded(stats.months)
    let previousMonths = Self.padded(stats.previousMonths)
    let afterTax = stats.tax.enabled
    year = stats.year
    hero = Self.makeHero(stats: stats, months: months, previousMonths: previousMonths, today: today)
    metrics = StatsLattice.Metrics(
      hours: months.reduce(0) { $0 + $1.hours },
      shifts: months.reduce(0) { $0 + $1.shifts },
      perHour: Self.perHour(months, afterTax: afterTax)
    )
    self.months = Self.makeMonths(
      year: stats.year, pay: months.map { $0.pay(afterTax: afterTax) },
      previousPay: previousMonths.map { $0.pay(afterTax: afterTax) }, months: months,
      today: today)
    employment = StatsLattice.makeEmploymentYear(
      year: stats.year, data: stats.employment, now: now, calendar: calendar)
    currentMonth = stats.year == today.year ? today.month : nil
  }

  private static func padded(_ months: [YearMonthStats]) -> [YearMonthStats] {
    let byMonth = Dictionary(months.map { ($0.month, $0) }, uniquingKeysWith: { first, _ in first })
    return (1...StatsLattice.monthSlots).map { byMonth[$0] ?? .empty(month: $0) }
  }

  /// Pay per paid hour in the primary currency, the rule the month page uses.
  private static func perHour(_ months: [YearMonthStats], afterTax: Bool) -> Double? {
    let pay = months.reduce(0) { $0 + $1.pay(afterTax: afterTax) }
    let paidHours = months.reduce(0) { $0 + $1.earningsHours }
    return pay > 0 && paidHours > 0 ? pay / paidHours : nil
  }

  private static func makeHero(
    stats: YearStatsData,
    months: [YearMonthStats],
    previousMonths: [YearMonthStats],
    today: StatsLattice.Today
  ) -> StatsLattice.Hero {
    let isAfterTax = stats.tax.enabled
    let gross = months.reduce(0) { $0 + $1.earnings }
    let net = months.reduce(0) { $0 + $1.earningsNet }
    let qualifier: StatsLattice.Qualifier
    if months.allSatisfy({ $0.shifts == 0 }) {
      qualifier = .noShifts(isAhead: stats.year > today.year)
    } else if isAfterTax {
      qualifier = .taxed(gross: gross)
    } else {
      qualifier = .untaxed
    }
    let secondary = StatsLattice.otherCurrencyEntries(stats.currencyAggregate)
    return StatsLattice.Hero(
      period: .year(stats.year),
      isAfterTax: isAfterTax,
      amount: isAfterTax ? net : gross,
      earnedSoFar: nil,
      qualifier: qualifier,
      change: change(
        year: stats.year, total: gross,
        previousTotal: previousMonths.reduce(0) { $0 + $1.earnings },
        toDate: stats.toDate, today: today),
      otherCurrencies: StatsLattice.otherCurrencies(secondary),
      breakdown: secondary
    )
  }

  /// Compares before-tax pay, like the month page and Home. The running year compares the same
  /// date in both years. Any other year compares whole years, which for a future year is its
  /// scheduled pay.
  private static func change(
    year: Int, total: Double, previousTotal: Double, toDate: YearToDate?, today: StatsLattice.Today
  ) -> StatsLattice.Change {
    if year == today.year {
      guard let toDate, toDate.previous > 0 else { return .noPreviousPay }
      return .percentSameTime((toDate.focus - toDate.previous) / toDate.previous * 100)
    }
    guard previousTotal > 0 else { return .noPreviousPay }
    return .percent((total - previousTotal) / previousTotal * 100)
  }

  /// `pay` and `previousPay` hold one amount per month slot in the hero's basis.
  private static func makeMonths(
    year: Int,
    pay: [Double],
    previousPay: [Double],
    months: [YearMonthStats],
    today: StatsLattice.Today
  ) -> Months {
    let best = StatsLattice.bestIndex(pay)
    let rows = months.indices.map { index in
      let month = months[index]
      let monthIndex = FocusMonth(year: year, month: month.month).monthIndex
      return MonthRow(
        id: month.month,
        earnings: pay[index],
        hours: month.hours,
        shifts: month.shifts,
        previousEarnings: previousPay[index],
        isAhead: monthIndex > today.monthIndex,
        isCurrent: monthIndex == today.monthIndex,
        isBest: index == best
      )
    }
    return Months(
      year: year,
      rows: rows,
      yMax: StatsLattice.niceCeiling((pay + previousPay).max() ?? 0),
      headline: headline(year: year, rows: rows),
      hasPreviousYear: previousPay.contains { $0 > 0 }
    )
  }

  private static func headline(year: Int, rows: [MonthRow]) -> MonthsHeadline {
    let total = rows.reduce(0) { $0 + $1.earnings }
    guard total > 0 else { return .noPay(year: year) }
    if let best = rows.first(where: \.isBest) {
      return .best(month: best.id, amount: best.earnings)
    }
    let paidMonths = rows.filter { $0.earnings > 0 }.count
    return .tied(perPaidMonth: total / Double(paidMonths))
  }
}

extension YearMonthStats {
  func pay(afterTax: Bool) -> Double {
    afterTax ? earningsNet : earnings
  }
}
