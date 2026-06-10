import XCTest

@testable import Tidex

final class RecurringShiftProjectorTests: XCTestCase {
  func testGenerateDatesReturnsEmptyForCorruptNegativeRepeatInterval() {
    let dates = RecurringShiftProjector.generateDates(
      selectedDays: ["1": "2026-03-02"],
      repeatInterval: -1,
      endCondition: .months(value: 1)
    )

    XCTAssertTrue(dates.isEmpty)
  }

  func testCalendarDisplayReturnsEmptyForCorruptNegativeRepeatInterval() throws {
    let displayMonth = try XCTUnwrap(Date.fromISODateString("2026-03-01"))

    let dates = RecurringShiftProjector.generateDatesForCalendarDisplay(
      selectedDays: ["1": "2026-03-02"],
      repeatInterval: -1,
      displayMonth: displayMonth,
      endCondition: .months(value: 1)
    )

    XCTAssertTrue(dates.isEmpty)
  }

  func testEndDateConditionIncludesEndDateAndStopsAfterIt() {
    let recurring = RecurringShiftRow(
      id: "recurring-1",
      user_id: "user-1",
      start_time: "09:00",
      end_time: "17:00",
      repeat_interval_weeks: 0,
      selected_days: ["1": "2026-03-02"],
      end_condition: .endDate(date: "2026-03-16"),
      exclusions: nil
    )

    let dates =
      RecurringShiftGenerator
      .generateVirtualShiftsForMonth(year: 2_026, month: 3, recurring: recurring)
      .map(\.date)

    XCTAssertEqual(dates, ["2026-03-02", "2026-03-09", "2026-03-16"])
  }
}
