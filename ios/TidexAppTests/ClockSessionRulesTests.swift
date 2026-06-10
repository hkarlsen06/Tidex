import XCTest

@testable import Tidex

internal final class ClockSessionRulesTests: XCTestCase {
  internal func testTimeStringUsesHHmmFormat() {
    let date: Date = Date.fromDateAndTime("2026-03-02", time: "09:07") ?? Date()

    XCTAssertEqual(ClockSessionRules.timeString(from: date), "09:07")
  }

  internal func testHasExceededEndOfDayLimitOnlyAfterCutoff() {
    let startedAt: Date = Date.fromDateAndTime("2026-03-02", time: "08:00") ?? Date()
    let session: TemporaryClockSession = TemporaryClockSession(
      id: "clock-1",
      userId: "user-1",
      jobId: nil,
      startedAt: startedAt,
      createdAt: startedAt
    )

    let atCutoff: Date = Date.fromDateAndTime("2026-03-02", time: "23:59") ?? Date()
    let afterCutoff: Date = Date.fromDateAndTime("2026-03-03", time: "00:00") ?? Date()

    XCTAssertFalse(ClockSessionRules.hasExceededEndOfDayLimit(session, at: atCutoff))
    XCTAssertTrue(ClockSessionRules.hasExceededEndOfDayLimit(session, at: afterCutoff))
  }

  internal func testIsShiftOngoingForSameDayShift() {
    let shift: ShiftRow = TestFixtures.shift(
      shiftDate: "2026-03-02",
      startTime: "09:00",
      endTime: "17:00"
    )
    let withinShift: Date = Date.fromDateAndTime("2026-03-02", time: "12:00") ?? Date()
    let afterShift: Date = Date.fromDateAndTime("2026-03-02", time: "17:00") ?? Date()

    XCTAssertTrue(ClockSessionRules.isShiftOngoing(shift, at: withinShift))
    XCTAssertFalse(ClockSessionRules.isShiftOngoing(shift, at: afterShift))
  }

  internal func testIsShiftOngoingHandlesCrossMidnightShift() {
    let shift: ShiftRow = TestFixtures.shift(
      shiftDate: "2026-03-02",
      startTime: "22:00",
      endTime: "06:00"
    )

    let beforeMidnight: Date = Date.fromDateAndTime("2026-03-02", time: "23:30") ?? Date()
    let afterMidnight: Date = Date.fromDateAndTime("2026-03-03", time: "01:00") ?? Date()
    let ended: Date = Date.fromDateAndTime("2026-03-03", time: "06:00") ?? Date()

    XCTAssertTrue(ClockSessionRules.isShiftOngoing(shift, at: beforeMidnight))
    XCTAssertTrue(ClockSessionRules.isShiftOngoing(shift, at: afterMidnight))
    XCTAssertFalse(ClockSessionRules.isShiftOngoing(shift, at: ended))
  }

  internal func testIsShiftOngoingReturnsFalseForInvalidDate() {
    let shift: ShiftRow = TestFixtures.shift(
      shiftDate: "bad-date",
      startTime: "09:00",
      endTime: "17:00"
    )

    let reference: Date = Date.fromDateAndTime("2026-03-02", time: "12:00") ?? Date()

    XCTAssertFalse(ClockSessionRules.isShiftOngoing(shift, at: reference))
  }

  internal func testIsShiftOngoingReturnsFalseForInvalidTimes() {
    let shift: ShiftRow = TestFixtures.shift(
      shiftDate: "2026-03-02",
      startTime: "invalid",
      endTime: "17:00"
    )

    let reference: Date = Date.fromDateAndTime("2026-03-02", time: "12:00") ?? Date()

    XCTAssertFalse(ClockSessionRules.isShiftOngoing(shift, at: reference))
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
