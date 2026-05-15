import XCTest

@testable import Tidex

final class PayrollAdjustmentCalculatorTests: XCTestCase {
  func testGrossTaxableAdjustmentUsesPayoutMonthTax() {
    let adjustment = makeAdjustment(amount: 1000, taxTreatment: .grossTaxable)

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
    let adjustment = makeAdjustment(amount: 750, taxTreatment: .netManual, category: .correction)

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

  func testGrossTaxableAdjustmentUsesHalfTaxForPayoutMonth() {
    let adjustment = makeAdjustment(amount: 1000, taxTreatment: .grossTaxable)

    let totals = PayrollAdjustmentCalculator.totals(
      adjustments: [adjustment],
      taxEnabled: true,
      taxPercentage: 40,
      halfTaxMonth: 6,
      payoutMonth: 6
    )

    XCTAssertEqual(totals.gross, 1000, accuracy: 0.01)
    XCTAssertEqual(totals.net, 800, accuracy: 0.01)
    XCTAssertTrue(totals.taxEnabled)
  }

  func testDeletedAdjustmentIsIgnored() {
    let adjustment = makeAdjustment(
      amount: 1000,
      taxTreatment: .grossTaxable,
      deletedAt: "2026-06-11T10:00:00Z"
    )

    let totals = PayrollAdjustmentCalculator.totals(
      adjustments: [adjustment],
      taxEnabled: true,
      taxPercentage: 20,
      halfTaxMonth: nil,
      payoutMonth: 6
    )

    XCTAssertEqual(totals, .zero)
  }

  private func makeAdjustment(
    amount: Double,
    taxTreatment: PayrollAdjustmentTaxTreatment,
    category: PayrollAdjustmentCategory = .retroPay,
    deletedAt: String? = nil
  ) -> PayrollAdjustment {
    PayrollAdjustment(
      id: "a1",
      user_id: "user-1",
      job_id: nil,
      amount: amount,
      currency: "kr",
      category: category,
      tax_treatment: taxTreatment,
      title: "Etterbetaling",
      note: nil,
      curated_note: nil,
      curated_link: nil,
      earned_from_date: "2026-04-01",
      earned_to_date: "2026-04-30",
      payout_date: "2026-06-10",
      created_at: nil,
      updated_at: nil,
      revision: nil,
      deleted_at: deletedAt
    )
  }
}
