import XCTest

@testable import Tidex

final class PayrollAdjustmentCalculatorTests: XCTestCase {
  func testGrossTaxableAdjustmentUsesPayoutMonthTax() {
    let adjustment = PayrollAdjustment(
      id: "a1",
      user_id: "user-1",
      job_id: nil,
      amount: 1000,
      currency: "kr",
      category: .retroPay,
      tax_treatment: .grossTaxable,
      title: "Etterbetaling",
      note: nil,
      earned_from_date: "2026-04-01",
      earned_to_date: "2026-04-30",
      payout_date: "2026-06-10",
      created_at: nil,
      updated_at: nil,
      revision: nil,
      deleted_at: nil
    )

    let totals = PayrollAdjustmentCalculator.totals(
      adjustments: [adjustment],
      taxEnabled: true,
      taxPercentage: 20,
      halfTaxMonth: nil,
      payoutMonth: 6
    )

    XCTAssertEqual(totals.gross, 1000, accuracy: 0.01)
    XCTAssertEqual(totals.net, 800, accuracy: 0.01)
  }

  func testNetManualAdjustmentDoesNotApplyTaxEstimate() {
    let adjustment = PayrollAdjustment(
      id: "a1",
      user_id: "user-1",
      job_id: nil,
      amount: 750,
      currency: "kr",
      category: .correction,
      tax_treatment: .netManual,
      title: "Korrigering",
      note: nil,
      earned_from_date: nil,
      earned_to_date: nil,
      payout_date: "2026-06-10",
      created_at: nil,
      updated_at: nil,
      revision: nil,
      deleted_at: nil
    )

    let totals = PayrollAdjustmentCalculator.totals(
      adjustments: [adjustment],
      taxEnabled: true,
      taxPercentage: 50,
      halfTaxMonth: nil,
      payoutMonth: 6
    )

    XCTAssertEqual(totals.gross, 750, accuracy: 0.01)
    XCTAssertEqual(totals.net, 750, accuracy: 0.01)
  }
}
