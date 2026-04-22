import XCTest

@testable import Tidex

final class PauseWindowSupportTests: XCTestCase {
  func testIsWithinShiftRejectsPauseOutsideSameDayShift() {
    let pauseWindow = PauseWindow(start: "12:00", end: "12:30")

    let isWithinShift = PauseWindowSupport.isWithinShift(
      pauseWindow,
      shiftStartTime: "16:00",
      shiftEndTime: "23:15"
    )

    XCTAssertFalse(isWithinShift)
  }

  func testIsWithinShiftAllowsPauseInsideOvernightShift() {
    let pauseWindow = PauseWindow(start: "01:00", end: "01:30")

    let isWithinShift = PauseWindowSupport.isWithinShift(
      pauseWindow,
      shiftStartTime: "22:00",
      shiftEndTime: "06:00"
    )

    XCTAssertTrue(isWithinShift)
  }
}
