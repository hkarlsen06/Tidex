import XCTest

@testable import Tidex

final class StatsYearLatticeTests: XCTestCase {
  func testBestMonthNeedsOneMonthAboveTheRest() throws {
    let now = try date(2_026, 11, 12)
    let clear = lattice(year: 2_025, pay: [3: 9_000, 7: 12_000], now: now)
    let tied = lattice(year: 2_025, pay: [3: 12_000, 7: 12_000, 9: 6_000], now: now)
    let unpaid = lattice(year: 2_025, pay: [:], now: now)

    XCTAssertEqual(clear.months.rows.filter(\.isBest).map(\.id), [7])
    XCTAssertEqual(clear.months.headline, .best(month: 7, amount: 12_000))
    XCTAssertFalse(tied.months.rows.contains(where: \.isBest))
    XCTAssertEqual(tied.months.headline, .tied(perPaidMonth: 10_000))
    XCTAssertFalse(unpaid.months.rows.contains(where: \.isBest))
    XCTAssertEqual(unpaid.months.headline, .noPay(year: 2_025))
  }

  func testMonthsAfterTheCurrentMonthAreScheduled() throws {
    let now = try date(2_026, 11, 12)
    let running = lattice(year: 2_026, pay: [10: 9_000, 11: 4_000, 12: 6_900], now: now)
    let past = lattice(year: 2_025, pay: [12: 6_900], now: now)
    let future = lattice(year: 2_027, pay: [1: 3_000], now: now)

    XCTAssertEqual(running.months.rows.filter(\.isAhead).map(\.id), [12])
    XCTAssertEqual(running.months.rows.filter(\.isCurrent).map(\.id), [11])
    XCTAssertEqual(running.currentMonth, 11)
    XCTAssertFalse(past.months.rows.contains(where: \.isAhead))
    XCTAssertFalse(past.months.rows.contains(where: \.isCurrent))
    XCTAssertEqual(future.months.rows.filter(\.isAhead).count, 12)
  }

  func testFinishedYearComparesWholeYears() throws {
    let lattice = lattice(
      year: 2_025, pay: [3: 12_500], previousPay: [5: 10_000], now: try date(2_026, 11, 12))

    XCTAssertEqual(lattice.hero.change, .percent(25))
  }

  func testComparisonUsesPayBeforeTax() throws {
    let lattice = lattice(
      year: 2_025, pay: [3: 12_500], previousPay: [5: 10_000], netShare: 0.6,
      previousNetShare: 0.9, now: try date(2_026, 11, 12))

    XCTAssertEqual(lattice.hero.amount, 7_500, accuracy: 0.001)
    XCTAssertEqual(lattice.hero.change, .percent(25))
  }

  func testRunningYearComparesTheSameDateLastYear() throws {
    let lattice = lattice(
      year: 2_026, pay: [3: 20_000], previousPay: [3: 10_000],
      toDate: YearToDate(focus: 15_000, previous: 10_000), now: try date(2_026, 11, 12))

    XCTAssertEqual(lattice.hero.change, .percentSameTime(50))
  }

  func testNoComparisonWithoutPreviousPay() throws {
    let now = try date(2_026, 11, 12)
    let noPrevious = lattice(year: 2_025, pay: [3: 9_000], now: now)
    let runningWithoutPrevious = lattice(
      year: 2_026, pay: [3: 9_000], previousPay: [12: 4_000],
      toDate: YearToDate(focus: 9_000, previous: 0), now: now)

    XCTAssertEqual(noPrevious.hero.change, .noPreviousPay)
    XCTAssertEqual(runningWithoutPrevious.hero.change, .noPreviousPay)
  }

  func testFutureYearComparesScheduledPayWithThePreviousYear() throws {
    let future = lattice(
      year: 2_027, pay: [1: 3_000], previousPay: [1: 4_000], now: try date(2_026, 11, 12))

    XCTAssertEqual(future.hero.change, .percent(-25))
  }

  func testAlwaysTwelveMonthRows() throws {
    let stats = YearStatsData(
      year: 2_024,
      tax: TaxSettings(enabled: false, percentage: 0),
      months: [
        YearMonthStats(
          month: 4, earnings: 5_000, earningsNet: 5_000, earningsHours: 25, hours: 25, shifts: 3)
      ],
      previousMonths: [],
      currencyAggregate: nil,
      toDate: nil,
      employment: nil
    )
    let lattice = StatsYearLattice(stats: stats, now: try date(2_026, 11, 12), calendar: calendar)

    XCTAssertEqual(lattice.months.rows.map(\.id), Array(1...12))
    XCTAssertEqual(lattice.months.rows[3].earnings, 5_000, accuracy: 0.001)
    XCTAssertEqual(lattice.employment.months.count, 12)
    XCTAssertEqual(lattice.metrics.perHour ?? 0, 200, accuracy: 0.001)
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
    year: Int,
    pay: [Int: Double],
    previousPay: [Int: Double] = [:],
    netShare: Double = 1,
    previousNetShare: Double = 1,
    toDate: YearToDate? = nil,
    now: Date
  ) -> StatsYearLattice {
    func months(_ pay: [Int: Double], netShare: Double) -> [YearMonthStats] {
      (1...12).map { month in
        let earnings = pay[month] ?? 0
        let hours = earnings / 200
        return YearMonthStats(
          month: month, earnings: earnings, earningsNet: earnings * netShare,
          earningsHours: hours, hours: hours, shifts: earnings > 0 ? 1 : 0)
      }
    }
    let stats = YearStatsData(
      year: year,
      tax: TaxSettings(enabled: netShare < 1, percentage: (1 - netShare) * 100),
      months: months(pay, netShare: netShare),
      previousMonths: months(previousPay, netShare: previousNetShare),
      currencyAggregate: nil,
      toDate: toDate,
      employment: nil
    )
    return StatsYearLattice(stats: stats, now: now, calendar: calendar)
  }
}
