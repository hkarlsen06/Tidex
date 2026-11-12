import Foundation

/// The Stats screen for one year, padded to exactly 12 month slots. Like `StatsLattice`, views
/// fill the slots and never branch on whether data exists, so a year change swaps values in
/// place.
struct StatsYearLattice: Equatable {
  struct MonthRow: Equatable, Identifiable {
    /// The month, 1...12.
    let id: Int
    let earnings: Double
    let hours: Double
    let shifts: Int
    /// The same month a year earlier, in the same currency.
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
    year = stats.year
    hero = Self.makeHero(stats: stats, months: months, previousMonths: previousMonths, today: today)
    metrics = StatsLattice.Metrics(
      hours: months.reduce(0) { $0 + $1.hours },
      shifts: months.reduce(0) { $0 + $1.shifts },
      perHour: Self.perHour(months)
    )
    self.months = Self.makeMonths(
      year: stats.year, months: months, previousMonths: previousMonths, today: today)
    employment = StatsLattice.makeEmploymentYear(
      year: stats.year, data: stats.employment, now: now, calendar: calendar)
    currentMonth = stats.year == today.year ? today.month : nil
  }

  private static func padded(_ months: [YearMonthStats]) -> [YearMonthStats] {
    let byMonth = Dictionary(months.map { ($0.month, $0) }, uniquingKeysWith: { first, _ in first })
    return (1...StatsLattice.monthSlots).map { byMonth[$0] ?? .empty(month: $0) }
  }

  /// Pay per paid hour in the primary currency, the rule the month page uses.
  private static func perHour(_ months: [YearMonthStats]) -> Double? {
    let pay = months.reduce(0) { $0 + $1.earnings }
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
    func shown(_ months: [YearMonthStats]) -> Double {
      months.reduce(0) { $0 + (isAfterTax ? $1.earningsNet : $1.earnings) }
    }
    let gross = months.reduce(0) { $0 + $1.earnings }
    let qualifier: StatsLattice.Qualifier
    if months.allSatisfy({ $0.shifts == 0 }) {
      qualifier = .noShifts
    } else if isAfterTax {
      qualifier = .taxed(gross: gross, taxPercent: nil)
    } else {
      qualifier = .untaxed
    }
    let secondary = StatsLattice.otherCurrencyEntries(stats.currencyAggregate)
    return StatsLattice.Hero(
      period: .year(stats.year),
      isAfterTax: isAfterTax,
      amount: shown(months),
      qualifier: qualifier,
      change: change(
        year: stats.year, total: shown(months), previousTotal: shown(previousMonths),
        toDate: stats.toDate, today: today),
      otherCurrencies: StatsLattice.otherCurrencies(secondary),
      breakdown: secondary
    )
  }

  /// A finished year compares whole years, and the running year compares the same date in both.
  private static func change(
    year: Int, total: Double, previousTotal: Double, toDate: YearToDate?, today: StatsLattice.Today
  ) -> StatsLattice.Change {
    if year > today.year { return .noPreviousPay }
    if year == today.year {
      guard let toDate, toDate.previous > 0 else { return .noPreviousPay }
      return .percentSameTime((toDate.focus - toDate.previous) / toDate.previous * 100)
    }
    guard previousTotal > 0 else { return .noPreviousPay }
    return .percent((total - previousTotal) / previousTotal * 100)
  }

  private static func makeMonths(
    year: Int,
    months: [YearMonthStats],
    previousMonths: [YearMonthStats],
    today: StatsLattice.Today
  ) -> Months {
    let best = StatsLattice.bestIndex(months.map(\.earnings))
    let rows = months.indices.map { index in
      let month = months[index]
      let monthIndex = FocusMonth(year: year, month: month.month).monthIndex
      return MonthRow(
        id: month.month,
        earnings: month.earnings,
        hours: month.hours,
        shifts: month.shifts,
        previousEarnings: previousMonths[index].earnings,
        isAhead: monthIndex > today.monthIndex,
        isCurrent: monthIndex == today.monthIndex,
        isBest: index == best
      )
    }
    let peak = (months + previousMonths).map(\.earnings).max() ?? 0
    return Months(
      year: year,
      rows: rows,
      yMax: StatsLattice.niceCeiling(peak),
      headline: headline(year: year, rows: rows)
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
