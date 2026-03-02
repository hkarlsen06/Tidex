import XCTest

@testable import Tidex

final class PayrollTotalsTests: XCTestCase {
  func testSummarizeShiftTotalsAppliesHalfTaxOnPayoutMonth() {
    let taxedOne = TestFixtures.computedShift(
      id: "s1",
      shiftDate: "2026-10-01",
      startTime: "08:00",
      endTime: "16:00",
      gross: 1000,
      taxEnabled: true,
      taxPercentage: 20
    )
    let taxedTwo = TestFixtures.computedShift(
      id: "s2",
      shiftDate: "2026-10-02",
      startTime: "08:00",
      endTime: "16:00",
      gross: 1000,
      taxEnabled: true,
      taxPercentage: 20
    )

    let now = Date.fromDateAndTime("2026-10-15", time: "12:00") ?? Date()

    let totals = PayrollEngine.summarizeShiftTotals(
      shifts: [taxedOne, taxedTwo],
      halfTaxMonth: 11,
      earningsMonth: 10,
      now: now
    )

    XCTAssertEqual(totals.gross, 2000, accuracy: 0.01)
    XCTAssertEqual(totals.net, 1800, accuracy: 0.01)
    XCTAssertEqual(totals.completedGross, 2000, accuracy: 0.01)
    XCTAssertEqual(totals.completedNet, 1800, accuracy: 0.01)
  }

  func testSummarizeShiftTotalsRespectsExcludedShiftIds() {
    let first = TestFixtures.computedShift(
      id: "keep",
      shiftDate: "2026-10-01",
      startTime: "08:00",
      endTime: "16:00",
      gross: 1000,
      taxEnabled: false
    )
    let second = TestFixtures.computedShift(
      id: "exclude",
      shiftDate: "2026-10-01",
      startTime: "12:00",
      endTime: "18:00",
      gross: 900,
      taxEnabled: false
    )

    let now = Date.fromDateAndTime("2026-10-31", time: "12:00") ?? Date()

    let totals = PayrollEngine.summarizeShiftTotals(
      shifts: [first, second],
      excludedShiftIds: ["exclude"],
      halfTaxMonth: nil,
      earningsMonth: 10,
      now: now
    )

    XCTAssertEqual(totals.gross, 1000, accuracy: 0.01)
    XCTAssertEqual(totals.net, 1000, accuracy: 0.01)
  }
}
