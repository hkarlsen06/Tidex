import XCTest

@testable import Tidex

final class StatsLatticeTests: XCTestCase {
  func testFourWeekFebruaryKeepsSixRows() throws {
    // 1 February 2021 is a Monday, so its 28 days fill exactly four rows.
    let lattice = try lattice(year: 2_021, month: 2, pay: [:], now: date(2_026, 11, 12))
    let rows = lattice.weeks.rows

    XCTAssertEqual(rows.count, 6)
    XCTAssertEqual(rows.map { $0.cells.count }, Array(repeating: 7, count: 6))
    XCTAssertEqual(rows.map(hasDays), [true, true, true, true, false, false])
    XCTAssertEqual(rows[0].cells[0].dayStats?.day, 1)
    XCTAssertEqual(rows[3].cells[6].dayStats?.day, 28)
    XCTAssertEqual(lattice.pace.dayCount, 28)
    XCTAssertEqual(lattice.pace.focus.values.count, 31)
    XCTAssertEqual(lattice.year.months.count, 12)
  }

  func testMonthStartingOnSundayUsesAllSixRows() throws {
    // 1 March 2026 is a Sunday, so days 30 and 31 land in the sixth row.
    let lattice = try lattice(year: 2_026, month: 3, pay: [:], now: date(2_026, 11, 12))
    let rows = lattice.weeks.rows

    XCTAssertEqual(rows.map(hasDays), Array(repeating: true, count: 6))
    XCTAssertEqual(rows[0].cells.map(\.dayStats?.day), [nil, nil, nil, nil, nil, nil, 1])
    XCTAssertEqual(rows[5].cells.map(\.dayStats?.day), [30, 31, nil, nil, nil, nil, nil])
  }

  func testJanuary2027StartsInISOWeek53() throws {
    // 1 January 2027 is a Friday, so its first days belong to week 53 of 2026.
    let lattice = try lattice(year: 2_027, month: 1, pay: [:], now: date(2_026, 11, 12))

    XCTAssertEqual(lattice.weeks.rows.map(\.isoWeek), [53, 1, 2, 3, 4, 5])
  }

  func testWeekTotalsAddUpToTheMonth() throws {
    // November 2026 starts on a Sunday, so the first and last rows are partial.
    let pay: [Int: Double] = [1: 2_310, 3: 1_480, 9: 1_480, 14: 2_240, 22: 2_310, 30: 1_480]
    let lattice = try lattice(year: 2_026, month: 11, pay: pay, now: date(2_026, 12, 3))

    let total = lattice.weeks.rows.reduce(0) { $0 + $1.total }
    XCTAssertEqual(total, pay.values.reduce(0, +), accuracy: 0.001)
    XCTAssertEqual(lattice.weeks.rows[0].total, 2_310, accuracy: 0.001)
    XCTAssertEqual(lattice.weeks.rows[5].total, 1_480, accuracy: 0.001)
  }

  func testBestWeekNeedsTwoPaidWeeksAndOneAboveTheRest() throws {
    let now = try date(2_026, 11, 12)
    let clear = try lattice(year: 2_026, month: 9, pay: [1: 500, 9: 900], now: now)
    let tied = try lattice(year: 2_026, month: 9, pay: [1: 900, 9: 900], now: now)
    let single = try lattice(year: 2_026, month: 9, pay: [9: 900, 10: 400], now: now)
    let unpaid = try lattice(year: 2_026, month: 9, pay: [:], shiftCount: 2, now: now)

    XCTAssertEqual(clear.weeks.rows.map(\.isBest), [false, true, false, false, false, false])
    XCTAssertEqual(clear.weeks.headline, .best(week: 37, amount: 900))
    XCTAssertFalse(tied.weeks.rows.contains(where: \.isBest))
    XCTAssertEqual(tied.weeks.headline, .total(amount: 1_800))
    // One week with work is not praised as the best week.
    XCTAssertFalse(single.weeks.rows.contains(where: \.isBest))
    XCTAssertEqual(single.weeks.headline, .total(amount: 1_300))
    XCTAssertFalse(unpaid.weeks.rows.contains(where: \.isBest))
    XCTAssertEqual(unpaid.weeks.headline, .noPay(FocusMonth(year: 2_026, month: 9)))
  }

  func testBestDayNeedsOneDayAboveTheRest() throws {
    let now = try date(2_026, 11, 12)
    let clear = try lattice(year: 2_026, month: 9, pay: [1: 500, 9: 900], now: now)
    let tied = try lattice(year: 2_026, month: 9, pay: [1: 900, 9: 900], now: now)
    let ahead = try lattice(year: 2_026, month: 12, pay: [5: 900, 19: 900], now: now)

    XCTAssertEqual(clear.weeks.readout.bestDay?.day, 9)
    XCTAssertEqual(tied.weeks.readout, .hint)
    XCTAssertEqual(ahead.weeks.readout, .hint)
  }

  func testFutureMonthIsAllScheduled() throws {
    let lattice = try lattice(
      year: 2_026, month: 12, pay: [5: 1_000, 19: 1_500], now: date(2_026, 11, 12))
    let marks = lattice.weeks.rows.flatMap(\.cells).compactMap { cell -> StatsLattice.DayMark? in
      guard case .day(let day, let mark, _) = cell, day.shifts > 0 else { return nil }
      return mark
    }

    XCTAssertEqual(lattice.phase, .future)
    XCTAssertEqual(marks, [.scheduled(1_000 / 1_500), .scheduled(1)])
    XCTAssertEqual(lattice.pace.focus.solidThrough, 0)
    XCTAssertEqual(lattice.pace.reference, .monthEnd(31))
    XCTAssertEqual(lattice.pace.headline, .alone)
    XCTAssertEqual(lattice.weeks.headline, .busiestAhead(week: 51))
    XCTAssertFalse(lattice.weeks.rows.contains(where: \.isCurrent))
    XCTAssertEqual(
      lattice.weeks.rows.map(\.isPlannedOnly), [true, false, true, false, false, false])
  }

  func testEmptyMonthSaysWhetherItHasStarted() throws {
    let now = try date(2_026, 11, 12)
    let ahead = try lattice(year: 2_027, month: 1, pay: [:], now: now)
    let past = try lattice(year: 2_026, month: 3, pay: [:], now: now)

    XCTAssertEqual(ahead.hero.qualifier, .noShifts(isAhead: true))
    XCTAssertEqual(ahead.year.standing, .nothingPlanned)
    XCTAssertEqual(past.hero.qualifier, .noShifts(isAhead: false))
    XCTAssertEqual(past.year.standing, .noPayInYear)
  }

  func testPaceComparesOnlyWhenThePreviousMonthHasPay() throws {
    let now = try date(2_026, 11, 12)
    let versus = try lattice(year: 2_026, month: 11, pay: [3: 1_480], previousPay: 900, now: now)
    let alone = try lattice(year: 2_026, month: 11, pay: [3: 1_480], now: now)

    XCTAssertEqual(versus.pace.headline, .versus(previous: FocusMonth(year: 2_026, month: 10)))
    XCTAssertEqual(alone.pace.headline, .alone)
  }

  func testCurrentWeekCountsItsWorkedDaysSoFar() throws {
    // 12 November 2026 is the Thursday of ISO week 46. The Saturday shift is still scheduled.
    let pay: [Int: Double] = [3: 1_480, 9: 1_480, 11: 1_620, 12: 1_480, 14: 2_240]
    let lattice = try lattice(year: 2_026, month: 11, pay: pay, now: date(2_026, 11, 12))
    let current = try XCTUnwrap(lattice.weeks.rows.first(where: \.isCurrent))
    let today = try XCTUnwrap(current.cells.first(where: \.isToday)?.dayStats)

    XCTAssertEqual(lattice.weeks.rows.filter(\.isCurrent).map(\.isoWeek), [46])
    XCTAssertEqual(today.day, 12)
    XCTAssertEqual(current.total, 6_820, accuracy: 0.001)
    XCTAssertEqual(lattice.weeks.headline, .soFar(amount: 4_580, week: 46))
    XCTAssertEqual(lattice.weeks.readout, .day(today))
    XCTAssertEqual(lattice.pace.reference, .today(12))
    XCTAssertEqual(lattice.pace.focus.solidThrough, 12)
    guard case .day(_, let saturday, _) = current.cells[5] else {
      return XCTFail("Saturday 14 November is in the current week")
    }
    XCTAssertEqual(saturday, .scheduled(1))
    XCTAssertFalse(current.isPlannedOnly)
  }

  func testMonthStandsAgainstTheYearsAveragePaidMonth() throws {
    // Three paid months average 20 000. December is only scheduled.
    let income: [Int: Double] = [3: 10_000, 9: 30_000, 11: 20_000, 12: 0]
    let now = try date(2_026, 11, 12)
    func standing(_ month: Int, income: [Int: Double] = income) throws -> StatsLattice.Standing {
      try lattice(year: 2_026, month: month, pay: [:], yearlyIncome: income, now: now).year.standing
    }

    XCTAssertEqual(try standing(9), .best)
    XCTAssertEqual(try standing(3), .againstAverage(-10_000))
    XCTAssertEqual(try standing(11), .againstAverage(0))
    XCTAssertEqual(try standing(5), .noPayInMonth)
    XCTAssertEqual(try standing(5, income: [:]), .noPayInYear)
    XCTAssertEqual(try standing(12, income: [3: 10_000]), .nothingPlanned)
    // A scheduled month with the year's highest pay is compared, not called the best.
    XCTAssertEqual(
      try standing(12, income: [3: 10_000, 12: 30_000]), .againstAverage(10_000))
  }

  private func hasDays(_ row: StatsLattice.WeekRow) -> Bool {
    row.cells.contains { $0.dayStats != nil }
  }

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Oslo") ?? .current
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
    try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
  }

  private func lattice(
    year: Int, month: Int, pay: [Int: Double], shiftCount: Int? = nil, previousPay: Double = 0,
    yearlyIncome: [Int: Double]? = nil, now: Date
  ) throws -> StatsLattice {
    let days = (1...Date.daysInMonth(year: year, month: month)).map { day in
      DayStats(
        day: day, earnings: pay[day] ?? 0, hours: pay[day] == nil ? 0 : 7.5,
        shifts: pay[day] == nil ? 0 : 1, otherCurrencyShifts: 0)
    }
    var running = 0.0
    let cumulative = days.map { day in
      running += day.earnings
      return DailyCumulativeData(
        day: day.day, currentMonth: running, lastMonth: 0, isToday: false, isFuture: false)
    }
    let gross = pay.values.reduce(0, +)
    let stats = StatsData(
      focusMonth: FocusMonth(year: year, month: month),
      tax: TaxSettings(enabled: false, percentage: 0),
      currentMonth: MonthStats(
        totalEarnings: gross, totalEarningsNet: gross, totalHours: Double(pay.count) * 7.5,
        shiftCount: shiftCount ?? pay.count),
      earnedSoFar: nil,
      currentMonthCurrencyAggregate: nil,
      lastMonth: MonthStats(
        totalEarnings: previousPay, totalEarningsNet: previousPay, totalHours: 0,
        shiftCount: previousPay > 0 ? 1 : 0),
      percentageChange: nil,
      thisMonthCumulative: cumulative,
      days: days,
      employment: nil,
      yearlyIncome: yearlyIncome?.map { month, earnings in
        MonthlyIncomeData(
          month: "", fullMonth: "", year: year, monthNumber: month, earnings: earnings, hours: 0,
          shifts: earnings > 0 ? 1 : 0)
      }
    )
    return StatsLattice(stats: stats, now: now, calendar: calendar)
  }
}

extension StatsLattice.DayReadout {
  fileprivate var bestDay: DayStats? {
    if case .bestDay(let day) = self { day } else { nil }
  }
}
