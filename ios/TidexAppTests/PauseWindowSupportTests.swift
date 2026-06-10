import XCTest

@testable import Tidex

internal final class PauseWindowSupportTests: XCTestCase {
  internal func testIsWithinShiftRejectsPauseOutsideSameDayShift() {
    let pauseWindow: PauseWindow = PauseWindow(start: "12:00", end: "12:30")

    let isWithinShift: Bool = PauseWindowSupport.isWithinShift(
      pauseWindow,
      shiftStartTime: "16:00",
      shiftEndTime: "23:15"
    )

    XCTAssertFalse(isWithinShift)
  }

  internal func testIsWithinShiftAllowsPauseInsideOvernightShift() {
    let pauseWindow: PauseWindow = PauseWindow(start: "01:00", end: "01:30")

    let isWithinShift: Bool = PauseWindowSupport.isWithinShift(
      pauseWindow,
      shiftStartTime: "22:00",
      shiftEndTime: "06:00"
    )

    XCTAssertTrue(isWithinShift)
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
