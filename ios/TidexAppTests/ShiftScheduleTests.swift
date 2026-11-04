import XCTest

@testable import Tidex

/// Siri adds and moves shifts with a day and two clock times, and must store them the way the
/// Add Shift screen does.
final class ShiftScheduleTests: XCTestCase {
  private func time(_ hhmm: String) throws -> Date {
    try XCTUnwrap(Date.fromDateAndTime("2026-01-01", time: hhmm))
  }

  private func day(_ iso: String) throws -> Date {
    try XCTUnwrap(Date.fromISODateString(iso))
  }

  func testAnEndBeforeTheStartIsOnTheNextDay() throws {
    let night = ShiftSchedule(day: try day("2026-11-06"), start: try time("22:00"), end: try time("06:00"))

    XCTAssertEqual(night.shiftDate, "2026-11-06")
    XCTAssertEqual(night.interval?.end, Date.fromDateAndTime("2026-11-07", time: "06:00"))
  }

  func testAnEndAtMidnightIsStoredAs2400OnTheShiftsDay() throws {
    let evening = ShiftSchedule(day: try day("2026-11-06"), start: try time("16:00"), end: try time("00:00"))

    XCTAssertEqual(evening.endTime, "24:00")
    XCTAssertEqual(evening.interval?.duration, 8 * 3_600)
  }

  func testMovingOnlyTheStartKeepsTheLengthAcrossMidnight() throws {
    let night = ShiftSchedule(shiftDate: "2026-11-06", startTime: "22:00", endTime: "06:00")

    let later = night.moved(to: nil, start: try time("23:30"), end: nil)
    let nextWeek = night.moved(to: try day("2026-11-13"), start: nil, end: nil)
    let shorter = night.moved(to: nil, start: nil, end: try time("04:00"))

    XCTAssertEqual(later, ShiftSchedule(shiftDate: "2026-11-06", startTime: "23:30", endTime: "07:30"))
    XCTAssertEqual(nextWeek, ShiftSchedule(shiftDate: "2026-11-13", startTime: "22:00", endTime: "06:00"))
    XCTAssertEqual(shorter.interval?.duration, 6 * 3_600)
  }

  func testMovingAnEveningShiftToEndAtMidnightKeepsItOnItsDay() throws {
    let evening = ShiftSchedule(shiftDate: "2026-11-06", startTime: "15:00", endTime: "23:00")

    let moved = evening.moved(to: nil, start: try time("16:00"), end: nil)

    XCTAssertEqual(moved.endTime, "24:00")
    XCTAssertEqual(moved.interval?.end, Date.fromDateAndTime("2026-11-07", time: "00:00"))
  }
}
