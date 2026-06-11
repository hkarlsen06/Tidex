import Nimble
import XCTest

@testable import Tidex

// swiftlint:disable:next type_body_length
final class PayrollEngineDateLogicTests: XCTestCase {
  func testCalculatePayoutDateClampsToMonthEnd() {
    let payoutDate = PayrollEngine.calculatePayoutDate(
      shiftDate: "2026-01-15",
      payrollDay: 31
    )

    XCTAssertEqual(payoutDate, "2026-02-28")
  }

  func testPayrollDateAdjusterClampsThirtyFirstToFebruaryMonthEndBeforeWeekendAdjustment() {
    let date = PayrollDateAdjuster.adjustPayrollDate(
      payrollDay: 31,
      month: 2,
      year: 2_026
    )

    XCTAssertEqual(date.toISODateString(), "2026-02-27")
  }

  func testPayrollDateAdjusterClampsTwentyNinthToNonLeapFebruaryMonthEnd() {
    let date = PayrollDateAdjuster.adjustPayrollDate(
      payrollDay: 29,
      month: 2,
      year: 2_026
    )

    XCTAssertEqual(date.toISODateString(), "2026-02-27")
  }

  func testPayrollDateAdjusterKeepsLeapDayWhenValidPayrollDay() {
    let date = PayrollDateAdjuster.adjustPayrollDate(
      payrollDay: 29,
      month: 2,
      year: 2_028
    )

    XCTAssertEqual(date.toISODateString(), "2028-02-29")
  }

  func testCalculatePayoutDateRollsOverYearBoundary() {
    let payoutDate = PayrollEngine.calculatePayoutDate(
      shiftDate: "2026-12-10",
      payrollDay: 15
    )

    XCTAssertEqual(payoutDate, "2027-01-15")
  }

  func testCalculatePayoutDateClampsInvalidLowPayrollDayToFirst() {
    let payoutDate = PayrollEngine.calculatePayoutDate(
      shiftDate: "2026-03-10",
      payrollDay: 0
    )

    XCTAssertEqual(payoutDate, "2026-04-01")
  }

  func testCalculatePayoutDateLeavesMalformedShiftMonthUnchanged() {
    let payoutDate = PayrollEngine.calculatePayoutDate(
      shiftDate: "2026-99-10",
      payrollDay: 15
    )

    XCTAssertEqual(payoutDate, "2026-99-10")
  }

  func testPayoutMonthReturnsJanuaryForDecemberShifts() {
    XCTAssertEqual(PayrollEngine.payoutMonth(from: "2026-12-31"), 1)
  }

  func testDashboardPayrollSelectorUsesUpcomingCurrentMonthPayout() throws {
    let selection = try XCTUnwrap(
      DashboardPayrollSelector.select(
        displayYM: (year: 2_026, month: 5),
        jobs: [payrollJob(id: "job-1", payrollDay: 20)],
        fallbackPayrollDay: 15,
        isViewingCurrentMonth: true,
        now: try date("2026-05-12")
      ))

    expect(selection.payoutYear) == 2_026
    XCTAssertEqual(selection.payoutMonth, 5)
    XCTAssertEqual(selection.payoutDate.toISODateString(), "2026-05-20")
    expect(selection.earningsYear) == 2_026
    XCTAssertEqual(selection.earningsMonth, 4)
    XCTAssertEqual(selection.jobIds, ["job-1"])
  }

  func testDashboardPayrollSelectorAdvancesWhenCurrentMonthPayoutPassed() throws {
    let selection = try XCTUnwrap(
      DashboardPayrollSelector.select(
        displayYM: (year: 2_026, month: 5),
        jobs: [payrollJob(id: "job-1", payrollDay: 10)],
        fallbackPayrollDay: 15,
        isViewingCurrentMonth: true,
        now: try date("2026-05-12")
      ))

    expect(selection.payoutYear) == 2_026
    XCTAssertEqual(selection.payoutMonth, 6)
    XCTAssertEqual(selection.payoutDate.toISODateString(), "2026-06-10")
    expect(selection.earningsYear) == 2_026
    XCTAssertEqual(selection.earningsMonth, 5)
    XCTAssertEqual(selection.jobIds, ["job-1"])
  }

  func testDashboardPayrollSelectorAdvancesWhenAdjustedMonthEndPayoutPassed() throws {
    let selection = try XCTUnwrap(
      DashboardPayrollSelector.select(
        displayYM: (year: 2_026, month: 5),
        jobs: [payrollJob(id: "job-1", payrollDay: 31)],
        fallbackPayrollDay: 15,
        isViewingCurrentMonth: true,
        now: try date("2026-05-31")
      ))

    expect(selection.payoutYear) == 2_026
    XCTAssertEqual(selection.payoutMonth, 6)
    XCTAssertEqual(selection.payoutDate.toISODateString(), "2026-06-30")
    expect(selection.earningsYear) == 2_026
    XCTAssertEqual(selection.earningsMonth, 5)
    XCTAssertEqual(selection.jobIds, ["job-1"])
  }

  // swiftlint:disable:next explicit_acl
  func testDashboardPayrollPreviousPassedSelectionsReturnLatestPassedCurrentMonthPayout() throws {
    let selections: [DashboardPayrollSelection] = DashboardPayrollSelector.previousPassedSelections(
      displayYM: (year: 2_026, month: 5),
      jobs: [
        payrollJob(id: "passed", payrollDay: 10),
        payrollJob(id: "upcoming", payrollDay: 20),
      ],
      fallbackPayrollDay: 15,
      now: try date("2026-05-12")
    )

    expect(selections.map { $0.payoutDate.toISODateString() }) == ["2026-05-08"]
    expect(selections.first?.jobIds) == ["passed"]
  }

  // swiftlint:disable:next explicit_acl
  func testDashboardPayrollPreviousPassedSelectionsIgnoreTodayUntilDateHasPassed() throws {
    let selections: [DashboardPayrollSelection] = DashboardPayrollSelector.previousPassedSelections(
      displayYM: (year: 2_026, month: 5),
      jobs: [payrollJob(id: "job-1", payrollDay: 12)],
      fallbackPayrollDay: 15,
      now: try date("2026-05-12")
    )

    expect(selections).to(beEmpty())
  }

  // swiftlint:disable:next explicit_acl
  func testDashboardPayrollPreviousPassedSelectionsUseLatestWhenAllCurrentPayoutsPassed() throws {
    let selections: [DashboardPayrollSelection] = DashboardPayrollSelector.previousPassedSelections(
      displayYM: (year: 2_026, month: 5),
      jobs: [
        payrollJob(id: "passed", payrollDay: 10),
        payrollJob(id: "upcoming", payrollDay: 20),
      ],
      fallbackPayrollDay: 15,
      now: try date("2026-05-22")
    )

    expect(selections.map { $0.payoutDate.toISODateString() }) == [
      "2026-05-20", "2026-05-08",
    ]
    expect(selections.first?.jobIds) == ["upcoming"]
  }

  func testDashboardPayrollPreviousPayoutStartUsesAdjustedPriorPayrollDate() throws {
    let job = payrollJob(id: "job-1", payrollDay: 31)
    let selection = try XCTUnwrap(
      DashboardPayrollSelector.select(
        displayYM: (year: 2_026, month: 5),
        jobs: [job],
        fallbackPayrollDay: 15,
        isViewingCurrentMonth: true,
        now: try date("2026-05-31")
      ))

    let startDate = try XCTUnwrap(
      DashboardPayrollSelector.previousPayoutStartDate(
        for: selection,
        jobs: [job],
        fallbackPayrollDay: 15
      ))

    XCTAssertEqual(startDate.toISODateString(), "2026-05-29")
  }

  func testDashboardPayrollPreviousPayoutStartStillUsesPriorPayoutInPayoutMonth() throws {
    let job = payrollJob(id: "job-1", payrollDay: 10)
    let selection = try XCTUnwrap(
      DashboardPayrollSelector.select(
        displayYM: (year: 2_026, month: 6),
        jobs: [job],
        fallbackPayrollDay: 15,
        isViewingCurrentMonth: true,
        now: try date("2026-06-01")
      ))

    let startDate = try XCTUnwrap(
      DashboardPayrollSelector.previousPayoutStartDate(
        for: selection,
        jobs: [job],
        fallbackPayrollDay: 15
      ))

    XCTAssertEqual(selection.payoutDate.toISODateString(), "2026-06-10")
    XCTAssertEqual(startDate.toISODateString(), "2026-05-08")
  }

  func testDashboardPayrollSelectorUsesLaterCurrentMonthJobWhenEarlierJobPassed() throws {
    let selection = try XCTUnwrap(
      DashboardPayrollSelector.select(
        displayYM: (year: 2_026, month: 5),
        jobs: [
          payrollJob(id: "passed", payrollDay: 10),
          payrollJob(id: "upcoming", payrollDay: 20),
        ],
        fallbackPayrollDay: 15,
        isViewingCurrentMonth: true,
        now: try date("2026-05-12")
      ))

    XCTAssertEqual(selection.payoutMonth, 5)
    expect(selection.payoutDate.toISODateString()) == "2026-05-20"
    XCTAssertEqual(selection.earningsMonth, 4)
    XCTAssertEqual(selection.jobIds, ["upcoming"])
  }

  func testDashboardPayrollSelectorCombinesJobsWithSameSelectedPayoutDate() throws {
    let selection = try XCTUnwrap(
      DashboardPayrollSelector.select(
        displayYM: (year: 2_026, month: 5),
        jobs: [
          payrollJob(id: "job-1", payrollDay: 20),
          payrollJob(id: "job-2", payrollDay: 20),
        ],
        fallbackPayrollDay: 15,
        isViewingCurrentMonth: true,
        now: try date("2026-05-12")
      ))

    XCTAssertEqual(selection.payoutDate.toISODateString(), "2026-05-20")
    XCTAssertEqual(selection.jobIds, ["job-1", "job-2"])
  }

  func testDashboardPayrollSelectorKeepsNonCurrentSelectedPayoutMonth() throws {
    let selection = try XCTUnwrap(
      DashboardPayrollSelector.select(
        displayYM: (year: 2_026, month: 4),
        jobs: [payrollJob(id: "job-1", payrollDay: 10)],
        fallbackPayrollDay: 15,
        isViewingCurrentMonth: false,
        now: try date("2026-05-12")
      ))

    expect(selection.payoutYear) == 2_026
    XCTAssertEqual(selection.payoutMonth, 4)
    XCTAssertEqual(selection.payoutDate.toISODateString(), "2026-04-10")
    XCTAssertEqual(selection.earningsMonth, 3)
  }

  func testDashboardPayrollVariantPickerSkipsZeroGrossEarlierCandidateGroup() throws {
    let earlierEmptyGroup = [
      payrollVariant(
        id: "earlier-empty",
        payoutDate: try date("2026-05-10"),
        gross: 0
      )
    ]
    let laterPayableGroup = [
      payrollVariant(
        id: "later-payable",
        payoutDate: try date("2026-05-20"),
        gross: 1_200
      )
    ]

    let selected = try XCTUnwrap(
      DashboardPayrollVariantPicker.firstPayableVariants(
        in: [earlierEmptyGroup, laterPayableGroup]
      ))

    XCTAssertEqual(selected.map(\.id), ["later-payable"])
    XCTAssertEqual(selected.first?.payoutDate.toISODateString(), "2026-05-20")
  }

  func testDashboardPayrollAdjustmentFilterMatchesPayoutMonthIgnoringDay() throws {
    let earlierAdjustment = payrollAdjustment(id: "earlier", payoutDate: "2026-05-08")
    let selectedAdjustment = payrollAdjustment(id: "selected", payoutDate: "2026-05-20")
    let nextMonthAdjustment = payrollAdjustment(id: "next-month", payoutDate: "2026-06-01")
    let selectedPayoutDate = try date("2026-05-20")

    XCTAssertTrue(
      DashboardPayrollAdjustmentFilter.matches(earlierAdjustment, payoutDate: selectedPayoutDate)
    )
    XCTAssertTrue(
      DashboardPayrollAdjustmentFilter.matches(selectedAdjustment, payoutDate: selectedPayoutDate)
    )
    XCTAssertFalse(
      DashboardPayrollAdjustmentFilter.matches(
        nextMonthAdjustment,
        payoutDate: selectedPayoutDate
      )
    )
  }

  private func payrollJob(id: String, payrollDay: Int) -> Job {
    TestFixtures.job(id: id, isDefault: id == "job-1" || id == "passed", payrollDay: payrollDay)
  }

  private func payrollVariant(id: String, payoutDate: Date, gross: Double) -> PayrollCardVariant {
    PayrollCardVariant(
      id: id,
      title: id,
      colorHex: nil,
      badges: [],
      currency: "kr",
      payoutDate: payoutDate,
      gross: gross,
      net: nil,
      tax: nil,
      taxEnabled: false,
      hasPayrollAdjustments: false,
      jobBreakdowns: []
    )
  }

  private func payrollAdjustment(id: String, payoutDate: String) -> PayrollAdjustment {
    PayrollAdjustment(
      id: id,
      user_id: "user-1",
      job_id: nil,
      amount: 100,
      currency: "kr",
      category: .correction,
      tax_treatment: .grossTaxable,
      description: "Correction",
      note: nil,
      curated_note: nil,
      curated_description: nil,
      curated_link: nil,
      curated_link_title: nil,
      earned_from_date: nil,
      earned_to_date: nil,
      payout_date: payoutDate,
      created_at: nil,
      updated_at: nil,
      revision: nil,
      deleted_at: nil
    )
  }

  private func date(_ isoDate: String) throws -> Date {
    try XCTUnwrap(Date.fromISODateString(isoDate))
  }
}
