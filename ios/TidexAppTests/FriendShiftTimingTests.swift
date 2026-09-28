import XCTest

@testable import Tidex

final class FriendShiftTimingTests: XCTestCase {
  private let calendar = Calendar.current

  func testOvernightShiftEndsOnNextDay() throws {
    let timing = try XCTUnwrap(FriendShiftTiming(shift: makeShift(start: "22:00", end: "06:00")))

    XCTAssertEqual(timing.end.timeIntervalSince(timing.start), 8 * 3_600)
    XCTAssertEqual(calendar.component(.hour, from: timing.end), 6)
  }

  func testStatusAndProgressAcrossTheShift() throws {
    let timing = try XCTUnwrap(FriendShiftTiming(shift: makeShift(start: "08:00", end: "16:00")))

    let before = timing.start.addingTimeInterval(-60)
    let midway = timing.start.addingTimeInterval(4 * 3_600)
    let after = timing.end.addingTimeInterval(60)

    XCTAssertEqual(timing.status(at: before), .upcoming)
    XCTAssertEqual(timing.status(at: timing.start), .active)
    XCTAssertEqual(timing.status(at: midway), .active)
    XCTAssertEqual(timing.status(at: timing.end), .active)
    XCTAssertEqual(timing.status(at: after), .past)

    XCTAssertEqual(timing.progress(at: before), 0)
    XCTAssertEqual(timing.progress(at: midway), 0.5, accuracy: 0.0001)
    XCTAssertEqual(timing.progress(at: after), 1)
  }

  func testActiveShiftUsesActiveStatusText() throws {
    let timing = try XCTUnwrap(FriendShiftTiming(shift: makeShift(start: "08:00", end: "16:00")))

    XCTAssertEqual(
      timing.statusText(at: timing.start.addingTimeInterval(60)),
      String(localized: .sharingStatusActive)
    )
  }

  func testCompactStatusTextKeepsOnlyTheLargestUnit() throws {
    let timing = try XCTUnwrap(FriendShiftTiming(shift: makeShift(start: "16:00", end: "21:00")))
    let hours = String(localized: .commonHoursShort)
    let minutes = String(localized: .commonMinShort)

    XCTAssertEqual(
      timing.statusText(at: timing.start.addingTimeInterval(-(12 * 3_600 + 42 * 60 + 5)), compact: true),
      String(localized: .commonInTime("12\(hours)"))
    )
    XCTAssertEqual(
      timing.statusText(at: timing.start.addingTimeInterval(-(42 * 60 + 5)), compact: true),
      String(localized: .commonInTime("42\(minutes)"))
    )
  }

  func testMalformedTimesProduceNoTiming() {
    XCTAssertNil(FriendShiftTiming(shift: makeShift(start: "8", end: "16:00")))
    XCTAssertNil(FriendShiftTiming(shift: makeShift(date: "not-a-date")))
  }

  private func makeShift(
    date: String = "2026-03-12",
    start: String = "08:00",
    end: String = "16:00"
  ) -> SharedShiftData {
    SharedShiftData(
      id: "shift",
      user_id: "friend",
      job_id: nil,
      job_name: nil,
      job_color: nil,
      shift_date: date,
      start_time: start,
      end_time: end,
      computed: SharedShiftComputed(
        id: "shift",
        durationHours: 8,
        paidHours: 8,
        basePay: 1_000,
        supplementPay: 0,
        gross: 1_000,
        breakAudit: SharedBreakAudit(
          method: .none,
          thresholdHours: 0,
          deductedHours: 0,
          source: .none,
          appliedPauseWindows: nil,
          notes: []
        )
      ),
      tax_enabled: nil,
      tax_percentage: nil,
      custom_pause_windows: nil,
      custom_supplements: nil,
      recurring_id: nil,
      recurring_anchor_weekday: nil
    )
  }
}
