import XCTest

@testable import Tidex

final class PayrollAdjustmentCalculatorTests: XCTestCase {
  func testAdjustmentsUseEachWorkplacesHalfTaxSettingIncludingExplicitOff() {
    let jobs = [
      TestFixtures.job(id: "half", isDefault: true, halfTaxMonth: 11),
      TestFixtures.job(id: "full", isDefault: false, halfTaxMonth: nil),
    ]
    let totals = PayrollAdjustmentCalculator.totals(
      adjustments: [
        makeAdjustment(amount: 1000, taxTreatment: .grossTaxable, jobId: "half"),
        makeAdjustment(amount: 1000, taxTreatment: .grossTaxable, jobId: "full"),
      ],
      taxSettings: { _ in PayoutTaxSettings(enabled: true, percentage: 20) },
      halfTaxMonth: 11, payoutMonth: 11, jobs: jobs
    )
    XCTAssertEqual(totals.net, 1700, accuracy: 0.001)
  }

  func testPayoutBreakdownRecalculatesTaxWhenAnAdjustmentIsAddedChangedOrRemoved() throws {
    let start = try XCTUnwrap(Date.fromISODateString("2026-05-01"))
    let breakdown = PayrollCardJobBreakdown(
      id: "job", title: "Work", colorHex: nil, currency: "kr", basePay: 1000,
      supplementPay: 0, supplementBreakdowns: [], postDeductions: 0, postDeductionParts: [],
      payoutDate: try XCTUnwrap(Date.fromISODateString("2026-06-15")),
      gross: 1000, net: 800, tax: 200, taxEnabled: true, adjustments: [],
      earningsPeriodStart: start,
      payoutTaxSettings: PayoutTaxSettings(enabled: true, percentage: 20))

    let added = breakdown.withAdjustments([
      makeAdjustment(amount: 1000, taxTreatment: .grossTaxable)
    ])
    XCTAssertEqual(added.gross, 2000, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(added.net), 1600, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(added.tax), 400, accuracy: 0.001)
    XCTAssertEqual(added.earningsPeriodStart, start)

    let edited = added.withAdjustments([makeAdjustment(amount: 500, taxTreatment: .grossTaxable)])
    XCTAssertEqual(try XCTUnwrap(edited.net), 1200, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(edited.tax), 300, accuracy: 0.001)
    let removed = edited.withAdjustments([])
    XCTAssertEqual(removed, breakdown)
  }

  func testGrossTaxableAdjustmentUsesPayoutMonthTax() {
    let adjustment: PayrollAdjustment = makeAdjustment(amount: 1_000, taxTreatment: .grossTaxable)

    let totals = PayrollAdjustmentCalculator.totals(
      adjustments: [adjustment],
      taxEnabled: true,
      taxPercentage: 20,
      halfTaxMonth: nil,
      payoutMonth: 6
    )

    XCTAssertLessThan(abs(totals.gross - 1_000), 0.01)
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
    let adjustment: PayrollAdjustment = makeAdjustment(amount: 1_000, taxTreatment: .grossTaxable)

    let totals = PayrollAdjustmentCalculator.totals(
      adjustments: [adjustment],
      taxEnabled: true,
      taxPercentage: 40,
      halfTaxMonth: 6,
      payoutMonth: 6
    )

    XCTAssertLessThan(abs(totals.gross - 1_000), 0.01)
    XCTAssertEqual(totals.net, 800, accuracy: 0.01)
    XCTAssertTrue(totals.taxEnabled)
  }

  func testDeletedAdjustmentIsIgnored() {
    let adjustment = makeAdjustment(
      amount: 1_000,
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
    deletedAt: String? = nil,
    jobId: String? = nil
  ) -> PayrollAdjustment {
    PayrollAdjustment(
      id: "a1",
      user_id: "user-1",
      job_id: jobId,
      amount: amount,
      currency: "kr",
      category: category,
      tax_treatment: taxTreatment,
      description: "Etterbetaling for manglende timer.",
      note: nil,
      curated_note: nil,
      curated_description: nil,
      curated_link: nil,
      curated_link_title: nil,
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
