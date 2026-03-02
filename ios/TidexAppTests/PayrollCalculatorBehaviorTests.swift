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
}
