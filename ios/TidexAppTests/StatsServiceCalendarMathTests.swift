import XCTest

@testable import Tidex

final class StatsServiceCalendarMathTests: XCTestCase {
  func testEmploymentIsFullForEveryWeekdayWorkedRegardlessOfMonthLength() throws {
    // September 2026 has 22 weekdays and February 2026 has 20; both are full-time at 7.5 h a day.
    let shifts = try (weekdays(year: 2_026, month: 9) + weekdays(year: 2_026, month: 2))
      .map { shift(date: $0, hours: 7.5) }

    let employment = StatsService.buildEmploymentData(
      focusYear: 2_026, shifts: shifts, snapshots: [])

    for month in [2, 9] {
      let data = try XCTUnwrap(employment.monthlyData.first { $0.monthNumber == month })
      XCTAssertEqual(data.averagePercentage, 100, accuracy: 0.001, "month \(month)")
    }
    XCTAssertEqual(employment.yearlyAverage ?? 0, 100, accuracy: 0.001)
  }

  func testEmploymentCountsWeekendHoursTowardTheMonth() throws {
    // 20 h on Saturdays in September 2026 against 22 weekdays x 7.5 h = 165 h full time.
    let shifts = ["2026-09-05", "2026-09-12"].map { shift(date: $0, hours: 10) }

    let employment = StatsService.buildEmploymentData(
      focusYear: 2_026, shifts: shifts, snapshots: [])
    let september = try XCTUnwrap(employment.monthlyData.first { $0.monthNumber == 9 })

    XCTAssertEqual(
      september.averagePercentage, (20.0 / 165 * 1_000).rounded() / 10, accuracy: 0.001)
  }

  func testBestWeekUsesISOWeekNumbers() throws {
    // 1 Jan 2027 is a Friday, so ISO week 1 starts on 4 Jan and 11 Jan is in week 2.
    let worked = shift(date: "2027-01-11", hours: 8)
    let days = StatsService.buildDayStats(
      primaryShifts: [worked], includedShifts: [worked], year: 2_027, month: 1)
    let empty = StatsData.empty(year: 2_027, month: 1)
    let stats = StatsData(
      focusMonth: empty.focusMonth,
      tax: empty.tax,
      currentMonth: MonthStats(
        totalEarnings: 1_000, totalEarningsNet: 1_000, totalHours: 8, shiftCount: 1),
      currentMonthCurrencyAggregate: nil,
      lastMonth: empty.lastMonth,
      percentageChange: nil,
      thisMonthCumulative: [],
      days: days,
      employment: nil,
      yearlyIncome: nil
    )
    let now = try XCTUnwrap(Date.fromISODateString("2027-03-15"))
    let lattice = StatsLattice(stats: stats, now: now, calendar: .gregorianCurrent)
    let best = try XCTUnwrap(lattice.weeks.rows.first(where: \.isBest))

    XCTAssertEqual(days.count, 31)
    XCTAssertEqual(days[10].earnings, 1_000, accuracy: 0.001)
    XCTAssertEqual(best.isoWeek, 2)
    XCTAssertEqual(best.cells.first?.dayStats?.day, 11)
    XCTAssertEqual(lattice.weeks.headline, .best(week: 2, amount: 1_000))
  }

  func testCumulativeChartKeepsLastDaysOfLongerPreviousMonth() throws {
    let now = try XCTUnwrap(Date.fromISODateString("2026-03-15"))
    let data = StatsService.buildCumulativeData(
      currentMonthShifts: [],
      previousMonthShifts: [
        shift(date: "2026-01-10", hours: 8, gross: 300),
        shift(date: "2026-01-31", hours: 8, gross: 500),
      ],
      targetYear: 2_026,
      targetMonth: 2,
      previousYear: 2_026,
      previousMonth: 1,
      now: now
    )

    XCTAssertEqual(data.count, 28)
    XCTAssertEqual(try XCTUnwrap(data.last).lastMonth, 800, accuracy: 0.001)
  }

  func testRunningMonthComparesTheSameDayOnItsLastDay() throws {
    let now = try XCTUnwrap(Date.fromISODateString("2026-02-28"))
    let data = StatsService.buildCumulativeData(
      currentMonthShifts: [],
      previousMonthShifts: [
        shift(date: "2026-01-10", hours: 8, gross: 300),
        shift(date: "2026-01-31", hours: 8, gross: 500),
      ],
      targetYear: 2_026,
      targetMonth: 2,
      previousYear: 2_026,
      previousMonth: 1,
      now: now
    )

    XCTAssertEqual(try XCTUnwrap(data.last).lastMonth, 300, accuracy: 0.001)
  }

  func testYearToDateStopsAtTheSameDateLastYear() throws {
    let data = try yearStats(
      focus: [("2026-01-10", 1_000), ("2026-03-15", 500), ("2026-03-16", 700)],
      previous: [("2025-02-01", 400), ("2025-03-15", 300), ("2025-03-16", 900)],
      now: noon(2_026, 3, 15)
    )
    let toDate = try XCTUnwrap(data.toDate)

    XCTAssertEqual(toDate.focus, 1_500, accuracy: 0.001)
    XCTAssertEqual(toDate.previous, 700, accuracy: 0.001)
    // The scheduled shift on 16 March still counts in its month.
    XCTAssertEqual(data.months[2].earnings, 1_200, accuracy: 0.001)
    XCTAssertEqual(data.previousMonths[2].earnings, 1_200, accuracy: 0.001)
  }

  func testYearToDateCountsPayBeforeTax() throws {
    let data = try yearStats(
      focus: [("2026-01-10", 1_000), ("2026-03-15", 500)],
      previous: [("2025-02-01", 400)],
      taxPercent: 30,
      now: noon(2_026, 3, 15)
    )
    let toDate = try XCTUnwrap(data.toDate)

    XCTAssertTrue(data.tax.enabled)
    XCTAssertEqual(toDate.focus, 1_500, accuracy: 0.001)
    XCTAssertEqual(toDate.previous, 400, accuracy: 0.001)
  }

  func testLeapDayComparesWithTheLastDayOfFebruaryLastYear() throws {
    let data = try yearStats(
      focus: [("2028-02-29", 500)],
      previous: [("2027-02-28", 300), ("2027-03-01", 900)],
      now: noon(2_028, 2, 29)
    )

    XCTAssertEqual(try XCTUnwrap(data.toDate).previous, 300, accuracy: 0.001)
  }

  func testOnlyTheRunningYearHasPayToDate() throws {
    let past = try yearStats(
      focus: [("2025-03-01", 500)], previous: [], now: noon(2_026, 3, 15))

    XCTAssertNil(past.toDate)
    XCTAssertEqual(past.months.count, 12)
    XCTAssertEqual(past.previousMonths.count, 12)
  }

  private func yearStats(
    focus: [(date: String, gross: Double)],
    previous: [(date: String, gross: Double)],
    taxPercent: Double = 0,
    now: Date
  ) throws -> YearStatsData {
    func fullYear(_ shifts: [(date: String, gross: Double)], year: Int) -> FullYearComputedData {
      let computed = shifts.map {
        shift(date: $0.date, hours: 8, gross: $0.gross, taxPercent: taxPercent)
      }
      return FullYearComputedData(
        year: year, shiftsByMonth: [:], shifts: computed, includedShifts: computed)
    }
    let focusYear = try XCTUnwrap(Int(try XCTUnwrap(focus.first?.date.prefix(4))))
    return StatsService.buildYearStats(
      focus: fullYear(focus, year: focusYear),
      previous: fullYear(previous, year: focusYear - 1),
      jobs: [],
      aggregateJobs: [],
      fallbackCurrency: "kr",
      halfTaxMonth: nil,
      snapshots: [],
      now: now
    )
  }

  private func noon(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
    try XCTUnwrap(
      Calendar.gregorianCurrent.date(
        from: DateComponents(year: year, month: month, day: day, hour: 12)))
  }

  private func weekdays(year: Int, month: Int) throws -> [String] {
    let calendar = Calendar(identifier: .gregorian)
    return try (1...Date.daysInMonth(year: year, month: month)).compactMap { day in
      let iso = String(format: "%04d-%02d-%02d", year, month, day)
      let weekday = calendar.component(.weekday, from: try XCTUnwrap(Date.fromISODateString(iso)))
      return (2...6).contains(weekday) ? iso : nil
    }
  }

  private func shift(
    date: String, hours: Double, gross: Double = 1_000, taxPercent: Double = 0
  ) -> ShiftWithComputations {
    let template = TestFixtures.computedShift(
      id: date, shiftDate: date, startTime: "08:00", endTime: "16:00", gross: gross)
    return ShiftWithComputations(
      shift: template.shift,
      computed: ShiftComputed(
        id: date,
        durationHours: hours,
        paidHours: hours,
        basePay: gross,
        supplementPay: 0,
        gross: gross,
        wagePeriods: [],
        originalWagePeriods: [],
        breakAudit: template.computed.breakAudit
      ),
      taxEnabled: taxPercent > 0,
      taxPercentage: taxPercent
    )
  }
}
