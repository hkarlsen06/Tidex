import XCTest

@testable import Tidex

final class ShiftsListPlaceholderPolicyTests: XCTestCase {
  func testShowsPlaceholderForCurrentMonthWhenTodayHasNoShiftOrEvent() {
    XCTAssertTrue(
      ShiftsListPlaceholderPolicy.shouldShowTodayPlaceholder(
        isCurrentMonth: true,
        filteredShifts: [],
        eventCoverageByDate: [:],
        todayISO: "2026-05-18"
      )
    )
  }

  func testHidesPlaceholderWhenTodayHasEvent() {
    let event = EventPresentation(
      event: TestFixtures.event(
        id: "event-today",
        startDate: "2026-05-18",
        endDate: "2026-05-18",
        isAllDay: false,
        startTime: "13:15",
        endTime: "14:15"
      ),
      coveredDateISO: "2026-05-18"
    )

    XCTAssertFalse(
      ShiftsListPlaceholderPolicy.shouldShowTodayPlaceholder(
        isCurrentMonth: true,
        filteredShifts: [],
        eventCoverageByDate: ["2026-05-18": [event]],
        todayISO: "2026-05-18"
      )
    )
  }

  func testHidesPlaceholderWhenTodayIsCoveredByMultiDayEvent() {
    let event = EventPresentation(
      event: TestFixtures.event(
        id: "multi-day-event",
        startDate: "2026-05-17",
        endDate: "2026-05-19",
        isAllDay: true
      ),
      coveredDateISO: "2026-05-18"
    )

    XCTAssertFalse(
      ShiftsListPlaceholderPolicy.shouldShowTodayPlaceholder(
        isCurrentMonth: true,
        filteredShifts: [],
        eventCoverageByDate: ["2026-05-18": [event]],
        todayISO: "2026-05-18"
      )
    )
  }
}
