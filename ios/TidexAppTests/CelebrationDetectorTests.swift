import XCTest

@testable import Tidex

final class CelebrationDetectorTests: XCTestCase {
  private func shift(_ id: String, date: String = "2026-09-10", gross: Double)
    -> ShiftWithComputations
  {
    TestFixtures.computedShift(
      id: id,
      shiftDate: date,
      startTime: "09:00",
      endTime: "17:00",
      gross: gross
    )
  }

  func testMessageIsFirstShiftWhenNothingEarlierCompleted() {
    let message = CelebrationDetector.message(
      featuredShift: shift("a", gross: 1_000),
      earlierCompleted: [],
      newlyCompletedCount: 1
    )

    XCTAssertEqual(message, .firstShiftThisMonth)
  }

  func testMessageIsBestShiftWhenFeaturedBeatsEveryEarlierShift() {
    let message = CelebrationDetector.message(
      featuredShift: shift("c", gross: 1_500),
      earlierCompleted: [shift("a", gross: 1_000), shift("b", gross: 1_200)],
      newlyCompletedCount: 1
    )

    XCTAssertEqual(message, .bestShiftThisMonth)
  }

  func testMessageIsNotBestShiftWhenItOnlyTiesTheEarlierBest() {
    let message = CelebrationDetector.message(
      featuredShift: shift("c", gross: 1_200),
      earlierCompleted: [shift("a", gross: 1_000), shift("b", gross: 1_200)],
      newlyCompletedCount: 1
    )

    XCTAssertNotEqual(message, .bestShiftThisMonth)
    XCTAssertTrue(CelebrationMessage.rotating.contains(message))
  }

  func testMessageNeedsTwoEarlierShiftsBeforeCallingARecord() {
    let message = CelebrationDetector.message(
      featuredShift: shift("b", gross: 2_000),
      earlierCompleted: [shift("a", gross: 1_000)],
      newlyCompletedCount: 1
    )

    XCTAssertNotEqual(message, .bestShiftThisMonth)
  }

  func testRotatingMessageChangesBetweenConsecutiveShifts() {
    let earlier = [shift("a", gross: 1_000), shift("b", gross: 1_000)]
    let first = CelebrationDetector.message(
      featuredShift: shift("c", gross: 900),
      earlierCompleted: earlier,
      newlyCompletedCount: 1
    )
    let second = CelebrationDetector.message(
      featuredShift: shift("d", gross: 900),
      earlierCompleted: earlier + [shift("c", gross: 900)],
      newlyCompletedCount: 1
    )

    XCTAssertNotEqual(first, second)
  }

  func testNextShiftEndSkipsEndedShiftsAndPicksTheEarliestUpcoming() throws {
    let now = try XCTUnwrap(Date.fromDateAndTime("2026-09-10", time: "12:00"))
    let shifts = [
      TestFixtures.computedShift(
        id: "ended", shiftDate: "2026-09-10", startTime: "06:00", endTime: "11:00", gross: 1),
      TestFixtures.computedShift(
        id: "later", shiftDate: "2026-09-11", startTime: "09:00", endTime: "17:00", gross: 1),
      TestFixtures.computedShift(
        id: "today", shiftDate: "2026-09-10", startTime: "10:00", endTime: "15:00", gross: 1),
    ]

    let next = CelebrationDetector.nextShiftEnd(shifts: shifts, after: now)

    XCTAssertEqual(next, Date.fromDateAndTime("2026-09-10", time: "15:00"))
  }

  func testNextShiftEndRollsCrossMidnightShiftToTheNextDay() throws {
    let now = try XCTUnwrap(Date.fromDateAndTime("2026-09-10", time: "23:00"))
    let shifts = [
      TestFixtures.computedShift(
        id: "night", shiftDate: "2026-09-10", startTime: "22:00", endTime: "06:00", gross: 1)
    ]

    let next = CelebrationDetector.nextShiftEnd(shifts: shifts, after: now)

    XCTAssertEqual(next, Date.fromDateAndTime("2026-09-11", time: "06:00"))
  }

  func testNextShiftEndIsNilWhenEveryShiftHasEnded() throws {
    let now = try XCTUnwrap(Date.fromDateAndTime("2026-09-30", time: "23:00"))

    XCTAssertNil(CelebrationDetector.nextShiftEnd(shifts: [shift("a", gross: 1)], after: now))
  }

  func testOnlyConflictMarkerShowsWithoutDifferentiateWithoutColor() {
    XCTAssertTrue(CalendarCellMarker.conflict.isVisible(differentiateWithoutColor: false))
    XCTAssertFalse(CalendarCellMarker.newlyAdded.isVisible(differentiateWithoutColor: false))
    XCTAssertFalse(CalendarCellMarker.deepLink.isVisible(differentiateWithoutColor: false))
    XCTAssertTrue(CalendarCellMarker.deepLink.isVisible(differentiateWithoutColor: true))
  }
}
