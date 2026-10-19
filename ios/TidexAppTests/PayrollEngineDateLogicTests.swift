import XCTest

@testable import Tidex

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

  func testPayrollDateAdjusterKeepsLeapDayWhenValidPayrollDay() {
    let date = PayrollDateAdjuster.adjustPayrollDate(
      payrollDay: 29,
      month: 2,
      year: 2_028
    )

    XCTAssertEqual(date.toISODateString(), "2028-02-29")
  }

  /// A device set to an Islamic (Hijri) calendar, reachable via a locale like
  /// `en_US@calendar=islamic`, resolves Gregorian year/month/day components to a date
  /// hundreds of years away, because AH year 2026 lands in the 26th century CE, not
  /// 2026 CE. `PayrollDateAdjuster` must always resolve payroll dates on the Gregorian
  /// calendar, never on `Calendar.current`, or the dashboard payout countdown shows
  /// something like "in 204,970 days" instead of a date days away.
  func testAdjustPayrollDateIsIndependentOfDeviceCalendar() {
    var islamicCalendar = Calendar(identifier: .islamic)
    islamicCalendar.timeZone = .current
    let buggyDate = islamicCalendar.date(from: DateComponents(year: 2_026, month: 9, day: 15))
    let buggyYear = buggyDate.flatMap { Int($0.toISODateString().prefix(4)) }
    XCTAssertNotEqual(buggyYear, 2_026)

    let date = PayrollDateAdjuster.adjustPayrollDate(
      payrollDay: 15,
      month: 9,
      year: 2_026
    )

    XCTAssertTrue(date.toISODateString().hasPrefix("2026-09"))
  }

  func testCalculatePayoutDateRollsOverYearBoundary() {
    let payoutDate = PayrollEngine.calculatePayoutDate(
      shiftDate: "2026-12-10",
      payrollDay: 15
    )

    XCTAssertEqual(payoutDate, "2027-01-15")
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

    XCTAssertEqual(selection.payoutYear, 2_026)
    XCTAssertEqual(selection.payoutMonth, 5)
    XCTAssertEqual(selection.payoutDate.toISODateString(), "2026-05-20")
    XCTAssertEqual(selection.windowsByJobId.values.first?.start, "2026-04-01")
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

    XCTAssertEqual(selection.payoutYear, 2_026)
    XCTAssertEqual(selection.payoutMonth, 6)
    XCTAssertEqual(selection.payoutDate.toISODateString(), "2026-06-10")
    XCTAssertEqual(selection.windowsByJobId.values.first?.start, "2026-05-01")
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

    XCTAssertEqual(selection.payoutYear, 2_026)
    XCTAssertEqual(selection.payoutMonth, 6)
    XCTAssertEqual(selection.payoutDate.toISODateString(), "2026-06-30")
    XCTAssertEqual(selection.windowsByJobId.values.first?.start, "2026-05-01")
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

    XCTAssertEqual(selections.map { $0.payoutDate.toISODateString() }, ["2026-05-08"])
    XCTAssertEqual(selections.first?.jobIds, ["passed"])
  }

  // swiftlint:disable:next explicit_acl
  func testDashboardPayrollPreviousPassedSelectionsIgnoreTodayUntilDateHasPassed() throws {
    let selections: [DashboardPayrollSelection] = DashboardPayrollSelector.previousPassedSelections(
      displayYM: (year: 2_026, month: 5),
      jobs: [payrollJob(id: "job-1", payrollDay: 12)],
      fallbackPayrollDay: 15,
      now: try date("2026-05-12")
    )

    XCTAssertTrue(selections.isEmpty)
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
    XCTAssertEqual(selection.payoutDate.toISODateString(), "2026-05-20")
    XCTAssertEqual(selection.windowsByJobId.values.first?.start, "2026-04-01")
    XCTAssertEqual(selection.jobIds, ["upcoming"])
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
