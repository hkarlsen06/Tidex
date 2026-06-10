import XCTest

@testable import Tidex

final class EmploymentDataCompletedAverageTests: XCTestCase {
  func testCompletedMonthsAverageExcludesCurrentAndFutureMonths() {
    let data = makeEmploymentData(
      year: 2_026,
      percentages: [10, 20, 30, 40, 100, 100, 100, 100, 100, 100, 100, 100]
    )
    let now: Date = makeDate(year: 2_026, month: 5, day: 17)

    XCTAssertEqual(data.completedMonthsAverage(now: now, calendar: calendar), 25)
    XCTAssertEqual(data.completedAverageRangeLabel(now: now, calendar: calendar), "jan.-apr.")
  }

  func testCompletedMonthsAverageExcludesEmptyCompletedMonths() {
    let data = makeEmploymentData(
      year: 2_026,
      percentages: [0, 20, 0, 40, 100, 100, 100, 100, 100, 100, 100, 100]
    )
    let now: Date = makeDate(year: 2_026, month: 5, day: 17)

    XCTAssertEqual(data.completedMonthsAverage(now: now, calendar: calendar), 30)
    XCTAssertNil(data.completedAverageRangeLabel(now: now, calendar: calendar))
  }

  func testCompletedMonthsAverageExcludesLeadingEmptyMonths() {
    let data = makeEmploymentData(
      year: 2_026,
      percentages: [0, 0, 30, 40, 100, 100, 100, 100, 100, 100, 100, 100]
    )
    let now: Date = makeDate(year: 2_026, month: 5, day: 17)

    XCTAssertEqual(data.completedMonthsAverage(now: now, calendar: calendar), 35)
    XCTAssertEqual(data.completedAverageRangeLabel(now: now, calendar: calendar), "mar.-apr.")
  }

  func testCompletedMonthsAverageExcludesTrailingEmptyMonthsForPastYear() {
    let data = makeEmploymentData(
      year: 2_025,
      percentages: [10, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    )
    let now: Date = makeDate(year: 2_026, month: 5, day: 17)

    XCTAssertEqual(data.completedMonthsAverage(now: now, calendar: calendar), 15)
    XCTAssertEqual(data.completedAverageRangeLabel(now: now, calendar: calendar), "jan.-feb.")
  }

  func testCompletedMonthsAverageIsNilWhenOnlyCurrentMonthHasShifts() {
    let data = makeEmploymentData(
      year: 2_026,
      percentages: [0, 0, 0, 0, 10, 100, 100, 100, 100, 100, 100, 100]
    )
    let now: Date = makeDate(year: 2_026, month: 5, day: 17)

    XCTAssertNil(data.completedMonthsAverage(now: now, calendar: calendar))
    XCTAssertNil(data.completedAverageRangeLabel(now: now, calendar: calendar))
  }

  func testCompletedMonthsAverageUsesAllMonthsForPastYear() {
    let data = makeEmploymentData(
      year: 2_025,
      percentages: Array(repeating: 12, count: 12)
    )
    let now: Date = makeDate(year: 2_026, month: 5, day: 17)

    XCTAssertEqual(data.completedMonthsAverage(now: now, calendar: calendar), 12)
    XCTAssertEqual(data.completedAverageRangeLabel(now: now, calendar: calendar), "jan.-des.")
  }

  func testCompletedMonthsAverageIsNilBeforeAnyMonthHasCompleted() {
    let data = makeEmploymentData(
      year: 2_026,
      percentages: Array(repeating: 50, count: 12)
    )
    let now: Date = makeDate(year: 2_026, month: 1, day: 17)

    XCTAssertNil(data.completedMonthsAverage(now: now, calendar: calendar))
    XCTAssertNil(data.completedAverageRangeLabel(now: now, calendar: calendar))
  }

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Date.localTimeZone
    return calendar
  }

  private func makeDate(year: Int, month: Int, day: Int) -> Date {
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
    else {
      XCTFail("Failed to create test date for \(year)-\(month)-\(day)")
      return Date(timeIntervalSince1970: 0)
    }

    return date
  }

  private func makeEmploymentData(year: Int, percentages: [Double]) -> EmploymentData {
    let shortMonthNames = [
      "jan.", "feb.", "mar.", "apr.", "mai", "jun.",
      "jul.", "aug.", "sep.", "okt.", "nov.", "des.",
    ]
    let fullMonthNames = [
      "Januar", "Februar", "Mars", "April", "Mai", "Juni",
      "Juli", "August", "September", "Oktober", "November", "Desember",
    ]

    return EmploymentData(
      monthlyData: percentages.enumerated().map { index, percentage in
        EmploymentMonthlyData(
          month: shortMonthNames[index],
          fullMonth: fullMonthNames[index],
          year: year,
          monthNumber: index + 1,
          averagePercentage: percentage,
          hasShifts: percentage > 0
        )
      },
      yearlyAverage: nil,
      fullTimeHoursPerWeek: 40
    )
  }
}
