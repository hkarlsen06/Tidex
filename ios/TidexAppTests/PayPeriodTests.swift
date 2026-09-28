import XCTest

@testable import Tidex

internal final class PayPeriodTests: XCTestCase {
  // MARK: - Monthly

  internal func testCalendarMonthIsPaidTheMonthAfter() {
    let schedule = PayoutSchedule(period: .calendarMonth, payrollDay: 20)

    XCTAssertEqual(
      schedule.window(containing: "2026-09-10"),
      PayWindow(start: "2026-09-01", end: "2026-09-30", payoutDate: "2026-10-20"))
    XCTAssertEqual(schedule.payoutDate(for: "2026-12-31"), "2027-01-20")
  }

  internal func testCalendarMonthClampsPaydayToShortMonths() {
    let schedule = PayoutSchedule(period: .calendarMonth, payrollDay: 31)

    XCTAssertEqual(schedule.payoutDate(for: "2027-01-10"), "2027-02-28")
  }

  internal func testMidMonthPeriodPaidTheSameMonth() {
    let schedule = PayoutSchedule(
      period: .monthly(startDay: 16, payoutMonthOffset: 0), payrollDay: 25)

    XCTAssertEqual(
      schedule.window(containing: "2026-09-15"),
      PayWindow(start: "2026-08-16", end: "2026-09-15", payoutDate: "2026-09-25"))
    XCTAssertEqual(
      schedule.window(containing: "2026-09-16"),
      PayWindow(start: "2026-09-16", end: "2026-10-15", payoutDate: "2026-10-25"))
    XCTAssertEqual(
      schedule.window(containing: "2026-12-20"),
      PayWindow(start: "2026-12-16", end: "2027-01-15", payoutDate: "2027-01-25"))
  }

  internal func testMidMonthPeriodPaidTheMonthAfter() {
    let schedule = PayoutSchedule(
      period: .monthly(startDay: 16, payoutMonthOffset: 1), payrollDay: 12)

    XCTAssertEqual(schedule.payoutDate(for: "2026-09-10"), "2026-10-12")
    XCTAssertEqual(
      schedule.windows(paidInYear: 2_026, month: 10),
      [PayWindow(start: "2026-08-16", end: "2026-09-15", payoutDate: "2026-10-12")])
  }

  internal func testMonthlyWindowsPaidInMonthMatchWindowContainingDay() throws {
    let schedules = [
      PayoutSchedule(period: .calendarMonth, payrollDay: 20),
      PayoutSchedule(period: .monthly(startDay: 16, payoutMonthOffset: 0), payrollDay: 25),
      PayoutSchedule(period: .monthly(startDay: 21, payoutMonthOffset: 1), payrollDay: 5),
    ]
    for schedule in schedules {
      for month in 1...12 {
        let windows = schedule.windows(paidInYear: 2_026, month: month)
        XCTAssertEqual(windows.count, 1)
        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(schedule.window(containing: window.start), window)
        XCTAssertEqual(schedule.window(containing: window.end), window)
        XCTAssertEqual(window.payoutMonth, month)
      }
    }
  }

  // MARK: - Two-weekly

  internal func testBiweeklyWindowsFollowTheAnchor() {
    let schedule = PayoutSchedule(
      period: .biweekly(anchorEnd: "2026-09-13", payoutDelayDays: 5), payrollDay: 1)

    XCTAssertEqual(
      schedule.window(containing: "2026-09-13"),
      PayWindow(start: "2026-08-31", end: "2026-09-13", payoutDate: "2026-09-18"))
    XCTAssertEqual(
      schedule.window(containing: "2026-09-14"),
      PayWindow(start: "2026-09-14", end: "2026-09-27", payoutDate: "2026-10-02"))
    XCTAssertEqual(
      schedule.window(containing: "2026-08-30"),
      PayWindow(start: "2026-08-17", end: "2026-08-30", payoutDate: "2026-09-04"))
  }

  internal func testBiweeklyCanPayTwoOrThreeTimesAMonth() {
    let schedule = PayoutSchedule(
      period: .biweekly(anchorEnd: "2026-09-13", payoutDelayDays: 5), payrollDay: 1)

    XCTAssertEqual(
      schedule.windows(paidInYear: 2_026, month: 9).map(\.payoutDate),
      ["2026-09-04", "2026-09-18"])
    XCTAssertEqual(
      schedule.windows(paidInYear: 2_026, month: 10).map(\.payoutDate),
      ["2026-10-02", "2026-10-16", "2026-10-30"])
  }

  internal func testPreviousWindowIsTheOneBefore() throws {
    let biweekly = PayoutSchedule(
      period: .biweekly(anchorEnd: "2026-09-13", payoutDelayDays: 5), payrollDay: 1)
    let window = try XCTUnwrap(biweekly.window(containing: "2026-09-20"))
    XCTAssertEqual(biweekly.previousWindow(before: window)?.payoutDate, "2026-09-18")

    let monthly = PayoutSchedule(
      period: .monthly(startDay: 16, payoutMonthOffset: 0), payrollDay: 25)
    let januaryWindow = try XCTUnwrap(monthly.window(containing: "2027-01-10"))
    XCTAssertEqual(monthly.previousWindow(before: januaryWindow)?.payoutDate, "2026-12-25")
  }

  // MARK: - Storage

  internal func testStorageRoundTripAndFallback() throws {
    XCTAssertNil(PayPeriod.calendarMonth.storageJSON)

    let biweekly = PayPeriod.biweekly(anchorEnd: "2026-09-13", payoutDelayDays: 5)
    XCTAssertEqual(PayPeriod.fromStorageJSON(biweekly.storageJSON), biweekly)

    let monthly = PayPeriod.monthly(startDay: 16, payoutMonthOffset: 0)
    let json = try XCTUnwrap(monthly.storageJSON)
    XCTAssertTrue(json.contains(#""type":"monthly""#))
    XCTAssertEqual(PayPeriod.fromStorageJSON(json), monthly)

    XCTAssertEqual(PayPeriod.fromStorageJSON(nil), .calendarMonth)
    XCTAssertEqual(
      PayPeriod.fromStorageJSON(#"{"type":"monthly","startDay":31,"payoutMonthOffset":0}"#),
      .calendarMonth)
  }

  internal func testJobDecodingIgnoresInvalidPayPeriod() throws {
    let json = #"""
      {"id":"job","user_id":"user-1","name":"Job","currency":"kr","is_default":true,
       "sort_order":0,"pay_period":{"type":"weekly"}}
      """#
    let job = try JSONDecoder().decode(Job.self, from: Data(json.utf8))
    XCTAssertNil(job.pay_period)
  }

  // MARK: - Engine

  internal func testEngineUsesTheJobPayPeriodForPayoutDateAndHalfTax() throws {
    let job = TestFixtures.job(
      id: "job", isDefault: true, payrollDay: 25, halfTaxMonth: 12,
      payPeriod: .monthly(startDay: 16, payoutMonthOffset: 0))
    let snapshot = TestFixtures.wageSnapshot(
      taxEnabled: true, taxPercentage: 30, breakEnabled: false, jobId: "job")
    let shifts = [
      TestFixtures.shift(
        id: "before", shiftDate: "2026-12-10", startTime: "08:00", endTime: "16:00", jobId: "job"),
      TestFixtures.shift(
        id: "after", shiftDate: "2026-12-20", startTime: "08:00", endTime: "16:00", jobId: "job"),
    ]

    let result = PayrollEngine.computeShiftsForMonth(
      .init(
        year: 2_026, month: 12, shifts: shifts, recurring: [], snapshots: [snapshot],
        settings: nil, jobs: [job]))
    let before = try XCTUnwrap(result.first { $0.id == "before" })
    let after = try XCTUnwrap(result.first { $0.id == "after" })

    // 10 Dec is in 16 Nov-15 Dec, paid 25 Dec with half tax.
    XCTAssertEqual(before.calculationContext?.scheduledPayoutDate, "2026-12-25")
    XCTAssertEqual(before.calculationContext?.halfTaxApplied, true)
    // 20 Dec is in 16 Dec-15 Jan, paid 25 Jan with full tax.
    XCTAssertEqual(after.calculationContext?.scheduledPayoutDate, "2027-01-25")
    XCTAssertEqual(after.calculationContext?.halfTaxApplied, false)
  }

  // MARK: - Dashboard

  internal func testDashboardShowsEachTwoWeeklyPayoutSeparately() throws {
    let job = TestFixtures.job(
      id: "job", isDefault: true,
      payPeriod: .biweekly(anchorEnd: "2026-09-13", payoutDelayDays: 5))
    let now = try XCTUnwrap(Date.fromISODateString("2026-09-10"))

    let upcoming = DashboardPayrollSelector.selections(
      displayYM: (year: 2_026, month: 9), jobs: [job], fallbackPayrollDay: 25,
      isViewingCurrentMonth: true, now: now)
    XCTAssertEqual(upcoming.map { $0.payoutDate.toISODateString() }, ["2026-09-18"])
    XCTAssertEqual(
      upcoming.first?.windowsByJobId["job"],
      PayWindow(start: "2026-08-31", end: "2026-09-13", payoutDate: "2026-09-18"))

    let passed = DashboardPayrollSelector.previousPassedSelections(
      displayYM: (year: 2_026, month: 9), jobs: [job], fallbackPayrollDay: 25, now: now)
    XCTAssertEqual(passed.map { $0.payoutDate.toISODateString() }, ["2026-09-04"])

    let selection = try XCTUnwrap(upcoming.first)
    XCTAssertEqual(
      DashboardPayrollSelector.previousPayoutStartDate(
        for: selection, jobs: [job], fallbackPayrollDay: 25)?.toISODateString(),
      "2026-09-04")
  }

  internal func testAdjustmentGoesToOnePayoutWhenAMonthHasSeveral() throws {
    let paydays = try ["2026-10-02", "2026-10-16", "2026-10-30"].map {
      try XCTUnwrap(Date.fromISODateString($0))
    }
    func owner(of date: String) -> [String] {
      let adjustment = makeAdjustment(payoutDate: date)
      return paydays.filter {
        DashboardPayrollAdjustmentFilter.matches(
          adjustment, payoutDate: $0, jobPayoutDatesInMonth: paydays)
      }.map { $0.toISODateString() }
    }

    XCTAssertEqual(owner(of: "2026-10-01"), ["2026-10-02"])
    XCTAssertEqual(owner(of: "2026-10-16"), ["2026-10-16"])
    XCTAssertEqual(owner(of: "2026-10-31"), ["2026-10-30"])
    XCTAssertEqual(owner(of: "2026-11-02"), [])
  }

  private func makeAdjustment(payoutDate: String) -> PayrollAdjustment {
    PayrollAdjustment(
      id: "adjustment",
      user_id: "user-1",
      job_id: "job",
      amount: 500,
      currency: "kr",
      category: .bonus,
      tax_treatment: .grossTaxable,
      description: "Bonus",
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

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
