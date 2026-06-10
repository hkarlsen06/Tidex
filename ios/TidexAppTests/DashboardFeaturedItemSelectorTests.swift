import XCTest

@testable import Tidex

final class DashboardFeaturedItemSelectorTests: XCTestCase {
  func testSelectCurrentMonthPrefersShiftOverAllDayEventOnSameDay() throws {
    let shift = TestFixtures.computedShift(
      id: "shift-1",
      shiftDate: "2026-04-16",
      startTime: "14:00",
      endTime: "22:00",
      gross: 1_200
    )
    let event = TestFixtures.event(
      id: "event-1",
      startDate: "2026-04-16",
      endDate: "2026-04-16",
      isAllDay: true,
      note: "PTO"
    )

    let selection = DashboardFeaturedItemSelector.select(
      shifts: [shift],
      events: [event],
      isViewingCurrentMonth: true,
      todayISO: "2026-04-15",
      now: try XCTUnwrap(Date.fromDateAndTime("2026-04-15", time: "09:00"))
    )

    XCTAssertEqual(selection.item, .shift(shift))
    XCTAssertFalse(selection.isToday)
    XCTAssertFalse(selection.isBestShift)
  }

  func testSelectCurrentMonthReturnsTimedEventWhenItStartsBeforeShift() throws {
    let shift = TestFixtures.computedShift(
      id: "shift-1",
      shiftDate: "2026-04-16",
      startTime: "14:00",
      endTime: "22:00",
      gross: 1_200
    )
    let event = TestFixtures.event(
      id: "event-1",
      startDate: "2026-04-16",
      endDate: "2026-04-16",
      isAllDay: false,
      startTime: "09:00",
      endTime: "10:00",
      note: "Doctor"
    )

    let selection = DashboardFeaturedItemSelector.select(
      shifts: [shift],
      events: [event],
      isViewingCurrentMonth: true,
      todayISO: "2026-04-15",
      now: try XCTUnwrap(Date.fromDateAndTime("2026-04-15", time: "09:00"))
    )

    XCTAssertEqual(selection.item, .event(event, coveredDateISO: "2026-04-16"))
    XCTAssertFalse(selection.isToday)
    XCTAssertFalse(selection.isBestShift)
  }

  func testSelectCurrentMonthUsesTodayCoveredDateForOngoingMultiDayEvent() throws {
    let event = TestFixtures.event(
      id: "event-1",
      startDate: "2026-04-14",
      endDate: "2026-04-16",
      isAllDay: true,
      note: "Trip"
    )

    let selection = DashboardFeaturedItemSelector.select(
      shifts: [],
      events: [event],
      isViewingCurrentMonth: true,
      todayISO: "2026-04-15",
      now: try XCTUnwrap(Date.fromDateAndTime("2026-04-15", time: "10:00"))
    )

    XCTAssertEqual(selection.item, .event(event, coveredDateISO: "2026-04-15"))
    XCTAssertTrue(selection.isToday)
    XCTAssertFalse(selection.isBestShift)
  }

  func testSelectCurrentMonthIgnoresShiftWithMalformedTime() throws {
    let malformedShift = TestFixtures.computedShift(
      id: "shift-invalid-time",
      shiftDate: "2026-04-16",
      startTime: "invalid",
      endTime: "22:00",
      gross: 1_200
    )

    let selection = DashboardFeaturedItemSelector.select(
      shifts: [malformedShift],
      events: [],
      isViewingCurrentMonth: true,
      todayISO: "2026-04-15",
      now: try XCTUnwrap(Date.fromDateAndTime("2026-04-15", time: "09:00"))
    )

    XCTAssertNil(selection.item)
    XCTAssertFalse(selection.isToday)
    XCTAssertFalse(selection.isBestShift)
  }

  func testSelectNonCurrentMonthKeepsBestShiftBehavior() {
    let bestShift = TestFixtures.computedShift(
      id: "shift-best",
      shiftDate: "2026-03-20",
      startTime: "10:00",
      endTime: "18:00",
      gross: 1_800
    )
    let lowerShift = TestFixtures.computedShift(
      id: "shift-lower",
      shiftDate: "2026-03-05",
      startTime: "08:00",
      endTime: "16:00",
      gross: 900
    )
    let event = TestFixtures.event(
      id: "event-1",
      startDate: "2026-03-25",
      endDate: "2026-03-25",
      isAllDay: true,
      note: "Holiday"
    )

    let selection = DashboardFeaturedItemSelector.select(
      shifts: [lowerShift, bestShift],
      events: [event],
      isViewingCurrentMonth: false,
      todayISO: "2026-04-15",
      now: Date()
    )

    XCTAssertEqual(selection.item, .shift(bestShift))
    XCTAssertFalse(selection.isToday)
    XCTAssertTrue(selection.isBestShift)
  }
}
