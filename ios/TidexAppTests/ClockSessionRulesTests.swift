import XCTest

@testable import Tidex

internal final class ClockSessionRulesTests: XCTestCase {

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

  internal func testExtendingANightShiftCrossesMidnightButStaysUnder24Hours() throws {
    let shift: ShiftRow = TestFixtures.shift(
      shiftDate: "2026-03-02", startTime: "22:00", endTime: "06:00")

    let extended: Date = try XCTUnwrap(ClockSessionRules.extendedEnd(of: shift, byMinutes: 90))

    XCTAssertEqual(extended, Date.fromDateAndTime("2026-03-03", time: "07:30"))
    XCTAssertNotNil(ClockSessionRules.extendedEnd(of: shift, byMinutes: 16 * 60 - 1))
    XCTAssertNil(ClockSessionRules.extendedEnd(of: shift, byMinutes: 16 * 60), "24 hours fits no HH:mm")
  }

  @MainActor
  internal func testClockSessionEarnsFromItsStartMinuteToNow() throws {
    let startedAt: Date = try XCTUnwrap(Date.fromDateAndTime("2026-03-02", time: "09:00"))
    let session: TemporaryClockSession = TemporaryClockSession(
      id: "clock-1", userId: "user-1", jobId: nil, startedAt: startedAt.addingTimeInterval(30),
      createdAt: startedAt)
    let snapshot: WageSnapshot = TestFixtures.wageSnapshot(hourlyWage: 200)

    let twoHoursIn: ShiftWithComputations = ClockSessionRules.shiftSoFar(
      session, snapshot: snapshot, at: startedAt.addingTimeInterval(2 * 3_600 + 45))
    let firstMinute: ShiftWithComputations = ClockSessionRules.shiftSoFar(
      session, snapshot: snapshot, at: startedAt.addingTimeInterval(50))

    XCTAssertEqual(twoHoursIn.grossPay, 400, accuracy: 0.001)
    XCTAssertEqual(firstMinute.grossPay, 0, "a zero-length session must not read as 24 hours")
  }

  internal func testAnOpenClockSessionComesBeforeARunningShiftUntilItExpires() throws {
    let now: Date = try XCTUnwrap(Date.fromDateAndTime("2026-03-03", time: "01:00"))
    let night: ShiftWithComputations = TestFixtures.computedShift(
      id: "night", shiftDate: "2026-03-02", startTime: "22:00", endTime: "06:00", gross: 1_600)
    let later: ShiftWithComputations = TestFixtures.computedShift(
      id: "later", shiftDate: "2026-03-03", startTime: "08:00", endTime: "16:00", gross: 1_600)
    func session(startedHoursAgo hours: Double) -> TemporaryClockSession {
      let start: Date = now.addingTimeInterval(-hours * 3_600)
      return TemporaryClockSession(
        id: "clock-1", userId: "user-1", jobId: nil, startedAt: start, createdAt: start)
    }

    let clockedIn: ActiveWork? = ActiveWork.find(
      session: session(startedHoursAgo: 1), shifts: [later, night], at: now)
    let expired: ActiveWork? = ActiveWork.find(
      session: session(startedHoursAgo: 25), shifts: [later, night], at: now)
    let idle: ActiveWork? = ActiveWork.find(session: nil, shifts: [later], at: now)

    guard case .clockedIn(let open) = clockedIn else { return XCTFail("\(String(describing: clockedIn))") }
    XCTAssertEqual(open.id, "clock-1")
    guard case .onShift(let running) = expired else { return XCTFail("\(String(describing: expired))") }
    XCTAssertEqual(running.id, "night")
    XCTAssertNil(idle)
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
