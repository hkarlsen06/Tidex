import XCTest

@testable import Tidex

final class ScheduleListMonthTests: XCTestCase {
  func testDecemberListExcludesCalendarGridDaysFromNovemberAndJanuary() {
    let month = ScheduleListMonth(year: 2_025, month: 12)

    XCTAssertTrue(month.contains("2025-12-01"))
    XCTAssertTrue(month.contains("2025-12-31"))
    XCTAssertFalse(month.contains("2025-11-30"))
    XCTAssertFalse(month.contains("2026-01-02"))
    XCTAssertFalse(month.contains("2024-12-01"))
  }

  func testLeapDayBelongsToFebruary() {
    let month = ScheduleListMonth(year: 2_024, month: 2)

    XCTAssertTrue(month.contains("2024-02-29"))
    XCTAssertFalse(month.contains("2024-03-01"))
  }

  func testMultiDayEventsRemainVisibleWhenTheyOverlapTheMonth() {
    let month = ScheduleListMonth(year: 2_025, month: 12)

    XCTAssertTrue(month.overlaps(start: "2025-11-30", end: "2025-12-01"))
    XCTAssertTrue(month.overlaps(start: "2025-12-31", end: "2026-01-02"))
    XCTAssertTrue(month.overlaps(start: "2025-11-01", end: "2026-01-31"))
    XCTAssertTrue(month.overlaps(start: "2025-12-15", end: "2025-12-15"))
  }

  func testEventsOnlyOnAdjacentCalendarDaysDoNotFillAnEmptyMonth() {
    let month = ScheduleListMonth(year: 2_025, month: 12)

    XCTAssertFalse(month.overlaps(start: "2025-11-28", end: "2025-11-30"))
    XCTAssertFalse(month.overlaps(start: "2026-01-01", end: "2026-01-04"))
  }
}

final class AddShiftCalendarAccessibilityTests: XCTestCase {
  func testLabelListsDetailsInReadingOrder() {
    let label = AddShiftCalendarAccessibility.label(
      dateText: "Monday 5 January",
      todayText: "Today",
      existingShiftText: "Existing shift, 08:00 to 16:00",
      earningsText: "1 200",
      conflictText: "Conflict"
    )

    XCTAssertEqual(
      label, "Monday 5 January, Today, Existing shift, 08:00 to 16:00, 1 200, Conflict")
  }

  func testLabelSkipsMissingAndEmptyDetails() {
    let label = AddShiftCalendarAccessibility.label(
      dateText: "Tuesday 6 January",
      todayText: nil,
      existingShiftText: nil,
      earningsText: "",
      conflictText: nil
    )

    XCTAssertEqual(label, "Tuesday 6 January")
  }

  func testConflictIsSpokenEvenWithoutEarnings() {
    let label = AddShiftCalendarAccessibility.label(
      dateText: "Wednesday 7 January",
      todayText: nil,
      existingShiftText: nil,
      earningsText: nil,
      conflictText: "Conflict"
    )

    XCTAssertEqual(label, "Wednesday 7 January, Conflict")
  }
}
