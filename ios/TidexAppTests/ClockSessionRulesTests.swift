import XCTest

@testable import Tidex

internal final class ClockSessionRulesTests: XCTestCase {
  internal func testTimeStringUsesHHmmFormat() {
    let date: Date = Date.fromDateAndTime("2026-03-02", time: "09:07") ?? Date()

    XCTAssertEqual(ClockSessionRules.timeString(from: date), "09:07")
  }

  internal func testNightSessionSurvivesMidnightUntilMaxDuration() {
    let startedAt: Date = Date.fromDateAndTime("2026-03-02", time: "22:00") ?? Date()
    let session: TemporaryClockSession = TemporaryClockSession(
      id: "clock-1",
      userId: "user-1",
      jobId: nil,
      startedAt: startedAt,
      createdAt: startedAt
    )

    let afterMidnight: Date = Date.fromDateAndTime("2026-03-03", time: "03:00") ?? Date()
    let justBeforeLimit: Date = Date.fromDateAndTime("2026-03-03", time: "21:59") ?? Date()
    let atLimit: Date = Date.fromDateAndTime("2026-03-03", time: "22:00") ?? Date()

    XCTAssertEqual(ClockSessionRules.hasExceededMaxDuration(session, at: afterMidnight), false)
    XCTAssertEqual(ClockSessionRules.hasExceededMaxDuration(session, at: justBeforeLimit), false)
    XCTAssertEqual(ClockSessionRules.hasExceededMaxDuration(session, at: atLimit), true)
  }

  internal func testIsShiftOngoingForSameDayShift() {
    let shift: ShiftRow = TestFixtures.shift(
      shiftDate: "2026-03-02",
      startTime: "09:00",
      endTime: "17:00"
    )
    let withinShift: Date = Date.fromDateAndTime("2026-03-02", time: "12:00") ?? Date()
    let afterShift: Date = Date.fromDateAndTime("2026-03-02", time: "17:00") ?? Date()

    XCTAssertEqual(ClockSessionRules.isShiftOngoing(shift, at: withinShift), true)
    XCTAssertEqual(ClockSessionRules.isShiftOngoing(shift, at: afterShift), false)
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

    XCTAssertEqual(ClockSessionRules.isShiftOngoing(shift, at: beforeMidnight), true)
    XCTAssertEqual(ClockSessionRules.isShiftOngoing(shift, at: afterMidnight), true)
    XCTAssertEqual(ClockSessionRules.isShiftOngoing(shift, at: ended), false)
  }

  internal func testIsShiftOngoingReturnsFalseForInvalidDate() {
    let shift: ShiftRow = TestFixtures.shift(
      shiftDate: "bad-date",
      startTime: "09:00",
      endTime: "17:00"
    )

    let reference: Date = Date.fromDateAndTime("2026-03-02", time: "12:00") ?? Date()

    XCTAssertEqual(ClockSessionRules.isShiftOngoing(shift, at: reference), false)
  }

  internal func testIsShiftOngoingReturnsFalseForInvalidTimes() {
    let shift: ShiftRow = TestFixtures.shift(
      shiftDate: "2026-03-02",
      startTime: "invalid",
      endTime: "17:00"
    )

    let reference: Date = Date.fromDateAndTime("2026-03-02", time: "12:00") ?? Date()

    XCTAssertEqual(ClockSessionRules.isShiftOngoing(shift, at: reference), false)
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
