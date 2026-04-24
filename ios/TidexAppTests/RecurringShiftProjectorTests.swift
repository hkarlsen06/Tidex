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
}
