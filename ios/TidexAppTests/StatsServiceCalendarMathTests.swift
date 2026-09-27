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

    XCTAssertEqual(september.averagePercentage, (20.0 / 165 * 1_000).rounded() / 10, accuracy: 0.001)
  }

  func testBestWeekUsesISOWeekNumbers() throws {
    // 1 Jan 2027 is a Friday, so ISO week 1 starts on 4 Jan and 11 Jan is in week 2.
    let bestWeek = try XCTUnwrap(
      StatsService.buildBestWeekData(
        shifts: [shift(date: "2027-01-11", hours: 8)], focusYear: 2_027, focusMonth: 1))

    XCTAssertEqual(bestWeek.weekNumber, 2)
    XCTAssertEqual(bestWeek.weekData.first?.fullDate, "2027-01-11")
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

  private func weekdays(year: Int, month: Int) throws -> [String] {
    let calendar = Calendar(identifier: .gregorian)
    return try (1...Date.daysInMonth(year: year, month: month)).compactMap { day in
      let iso = String(format: "%04d-%02d-%02d", year, month, day)
      let weekday = calendar.component(.weekday, from: try XCTUnwrap(Date.fromISODateString(iso)))
      return (2...6).contains(weekday) ? iso : nil
    }
  }

  private func shift(date: String, hours: Double, gross: Double = 1_000) -> ShiftWithComputations {
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
      taxEnabled: false,
      taxPercentage: 0
    )
  }
}
