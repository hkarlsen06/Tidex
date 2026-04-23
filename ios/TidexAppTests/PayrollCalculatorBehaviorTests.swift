import XCTest

@testable import Tidex

final class PayrollCalculatorBehaviorTests: XCTestCase {
  func testComputeShiftWithEmptyCustomSupplementsDoesNotApplySnapshotSupplements() {
    let shift = TestFixtures.shift(
      shiftDate: "2026-02-02",
      startTime: "19:00",
      endTime: "20:00",
      customSupplements: CustomSupplementsData(rules: [])
    )

    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      supplements: [
        SupplementRule(days: [1], from: "18:00", to: "24:00", rate: 40, percent: nil)
      ]
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

    XCTAssertEqual(computed.basePay, 200, accuracy: 0.01)
    XCTAssertEqual(computed.supplementPay, 0, accuracy: 0.01)
    XCTAssertEqual(computed.gross, 200, accuracy: 0.01)
  }

  func testComputeShiftWithBreakDisabledKeepsPaidHoursEqualToDuration() {
    let shift = TestFixtures.shift(
      shiftDate: "2026-02-03",
      startTime: "08:00",
      endTime: "16:00",
      customSupplements: CustomSupplementsData(rules: [])
    )

    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      breakEnabled: false,
      breakMethod: BreakMethod.proportional.rawValue,
      breakThresholdHours: 0,
      breakDeductionMinutes: 30
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

    XCTAssertEqual(computed.durationHours, 8, accuracy: 0.01)
    XCTAssertEqual(computed.paidHours, 8, accuracy: 0.01)
    XCTAssertEqual(computed.breakAudit.deductedHours, 0, accuracy: 0.001)
  }

  func testComputeShiftWithCustomPauseWindowsUsesExactClippingInsteadOfAutomaticBreaks() {
    let shift = TestFixtures.shift(
      shiftDate: "2026-02-04",
      startTime: "08:00",
      endTime: "16:00",
      customPauseWindows: CustomPauseWindows(windows: [
        PauseWindow(start: "12:00", end: "12:30")
      ]),
      customSupplements: CustomSupplementsData(rules: [])
    )

    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      breakEnabled: true,
      breakMethod: BreakMethod.endOfShift.rawValue,
      breakThresholdHours: 5.5,
      breakDeductionMinutes: 45
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

    XCTAssertEqual(computed.durationHours, 8, accuracy: 0.01)
    XCTAssertEqual(computed.paidHours, 7.5, accuracy: 0.01)
    XCTAssertEqual(computed.breakAudit.source, .customPauseWindows)
    XCTAssertEqual(computed.breakAudit.deductedHours, 0.5, accuracy: 0.001)
    XCTAssertEqual(
      computed.breakAudit.appliedPauseWindows,
      [PauseWindow(start: "12:00", end: "12:30")]
    )
  }

  func testComputeShiftWithInvalidPersistedTimesProducesZeroPayroll() {
    let shift = TestFixtures.shift(
      shiftDate: "2026-02-05",
      startTime: "not-a-time",
      endTime: "17:00",
      customSupplements: CustomSupplementsData(rules: [])
    )

    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      breakEnabled: false
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

    XCTAssertEqual(computed.durationHours, 0, accuracy: 0.01)
    XCTAssertEqual(computed.paidHours, 0, accuracy: 0.01)
    XCTAssertEqual(computed.gross, 0, accuracy: 0.01)
  }

  func testComputeShiftIgnoresNegativePersistedBreakDeduction() {
    let shift = TestFixtures.shift(
      shiftDate: "2026-02-06",
      startTime: "08:00",
      endTime: "16:00",
      customSupplements: CustomSupplementsData(rules: [])
    )

    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      breakEnabled: true,
      breakMethod: BreakMethod.proportional.rawValue,
      breakThresholdHours: 0,
      breakDeductionMinutes: -30
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

    XCTAssertEqual(computed.durationHours, 8, accuracy: 0.01)
    XCTAssertEqual(computed.paidHours, 8, accuracy: 0.01)
    XCTAssertEqual(computed.breakAudit.deductedHours, 0, accuracy: 0.001)
  }

  func testComputeShiftFallsBackWhenPersistedHourlyWageIsNotFinite() {
    let shift = TestFixtures.shift(
      shiftDate: "2026-02-07",
      startTime: "08:00",
      endTime: "09:00",
      customSupplements: CustomSupplementsData(rules: [])
    )

    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: .infinity,
      breakEnabled: false
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

    XCTAssertEqual(computed.basePay, 184.54, accuracy: 0.01)
    XCTAssertEqual(computed.gross, 184.54, accuracy: 0.01)
  }
}
