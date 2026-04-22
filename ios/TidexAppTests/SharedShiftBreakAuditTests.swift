import XCTest

@testable import Tidex

final class SharedShiftBreakAuditTests: XCTestCase {
  func testSharedShiftDataConversionPreservesBreakAudit() {
    let sharedShift = makeSharedShift()

    let converted = sharedShift.toShiftWithComputations()

    XCTAssertEqual(converted.computed.breakAudit.source, .customPauseWindows)
    XCTAssertEqual(converted.computed.breakAudit.deductedHours, 0.5, accuracy: 0.001)
    XCTAssertEqual(
      converted.computed.breakAudit.appliedPauseWindows,
      [PauseWindow(start: "12:00", end: "12:30")]
    )
  }

  func testLocalSharedShiftConversionPreservesBreakAudit() {
    let local = LocalSharedShift.from(
      apiShift: makeSharedShift(),
      ownerId: "owner-1",
      viewerId: "viewer-1",
      showEarnings: true
    )

    let converted = local.toShiftWithComputations()

    XCTAssertEqual(converted.computed.breakAudit.source, .customPauseWindows)
    XCTAssertEqual(converted.computed.breakAudit.deductedHours, 0.5, accuracy: 0.001)
    XCTAssertEqual(
      converted.computed.breakAudit.appliedPauseWindows,
      [PauseWindow(start: "12:00", end: "12:30")]
    )
  }

  private func makeSharedShift() -> SharedShiftData {
    SharedShiftData(
      id: "shared-shift-1",
      user_id: "owner-1",
      job_id: "job-1",
      job_name: "Cafe",
      job_color: "#FFAA00",
      shift_date: "2026-04-21",
      start_time: "08:00",
      end_time: "16:00",
      computed: SharedShiftComputed(
        id: "shared-shift-1",
        durationHours: 8,
        paidHours: 7.5,
        basePay: 1000,
        supplementPay: 200,
        gross: 1200,
        breakAudit: SharedBreakAudit(
          method: .none,
          thresholdHours: 0,
          deductedHours: 0.5,
          source: .customPauseWindows,
          appliedPauseWindows: [PauseWindow(start: "12:00", end: "12:30")],
          notes: ["Deducted using custom pause windows"]
        )
      ),
      tax_enabled: true,
      tax_percentage: 12.5,
      custom_pause_windows: CustomPauseWindows(windows: [
        PauseWindow(start: "12:00", end: "12:30")
      ]),
      custom_supplements: nil,
      recurring_id: nil,
      recurring_anchor_weekday: nil
    )
  }
}
