import Nimble
import XCTest

@testable import Tidex

final class PayrollTotalsTests: XCTestCase {
  func testSummarizeShiftTotalsAppliesHalfTaxOnPayoutMonth() {
    let taxedOne = TestFixtures.computedShift(
      id: "s1",
      shiftDate: "2026-10-01",
      startTime: "08:00",
      endTime: "16:00",
      gross: 1_000,
      taxEnabled: true,
      taxPercentage: 20
    )
    let taxedTwo = TestFixtures.computedShift(
      id: "s2",
      shiftDate: "2026-10-02",
      startTime: "08:00",
      endTime: "16:00",
      gross: 1_000,
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

    expect(totals.gross).to(beCloseTo(2_000, within: 0.01))
    expect(totals.net).to(beCloseTo(1_800, within: 0.01))
    expect(totals.completedGross).to(beCloseTo(2_000, within: 0.01))
    expect(totals.completedNet).to(beCloseTo(1_800, within: 0.01))
  }

  func testSummarizeShiftTotalsRespectsExcludedShiftIds() {
    let first = TestFixtures.computedShift(
      id: "keep",
      shiftDate: "2026-10-01",
      startTime: "08:00",
      endTime: "16:00",
      gross: 1_000,
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

    expect(totals.gross).to(beCloseTo(1_000, within: 0.01))
    expect(totals.net).to(beCloseTo(1_000, within: 0.01))
  }

  func testSummarizeShiftTotalsClampsInvalidTaxPercentages() {
    let overTaxed = TestFixtures.computedShift(
      id: "over-taxed",
      shiftDate: "2026-10-01",
      startTime: "08:00",
      endTime: "16:00",
      gross: 1_000,
      taxEnabled: true,
      taxPercentage: 150
    )
    let negativeTaxed = TestFixtures.computedShift(
      id: "negative-taxed",
      shiftDate: "2026-10-02",
      startTime: "08:00",
      endTime: "16:00",
      gross: 1_000,
      taxEnabled: true,
      taxPercentage: -20
    )

    let now = Date.fromDateAndTime("2026-10-31", time: "12:00") ?? Date()

    let totals = PayrollEngine.summarizeShiftTotals(
      shifts: [overTaxed, negativeTaxed],
      halfTaxMonth: nil,
      earningsMonth: 10,
      now: now
    )

    expect(totals.gross).to(beCloseTo(2_000, within: 0.01))
    expect(totals.net).to(beCloseTo(1_000, within: 0.01))
  }
}
