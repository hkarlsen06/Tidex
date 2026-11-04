import XCTest

@testable import Tidex

/// Siri must say the same amount as Home's month card, half tax and currencies included.
@MainActor
final class AssistantEarningsTests: XCTestCase {
  private let jobs = [
    TestFixtures.job(id: "cafe", isDefault: true, currency: "kr"),
    TestFixtures.job(id: "bar", isDefault: false, currency: "kr"),
    TestFixtures.job(id: "diner", isDefault: false, currency: "$"),
  ]
  private let settings = UserSettings(
    user_id: "user-1", created_at: nil, updated_at: nil, last_active: nil, monthly_goal: nil,
    monthly_goals_by_month: nil, default_shifts_view: nil, profile_picture_url: nil,
    payroll_day: 25, theme: "system", show_dashboard_clock_buttons: nil, half_tax_month: 11,
    currency: "kr", default_startup_tab: nil)

  func testMonthEarningsMatchHomesTotalCard() throws {
    let october = [
      shift("cafe-shift", "2025-10-06", job: "cafe", gross: 1_000, tax: 30),
      shift("bar-shift", "2025-10-13", job: "bar", gross: 500, tax: 30),
      shift("diner-shift", "2025-10-20", job: "diner", gross: 2_000, tax: 0),
    ]
    let now = Date()

    let home = DashboardViewModel.buildDashboardDataOffMain(
      .init(
        displayedMonthShifts: october, displayedMonthEvents: [], previousMonthShifts: [],
        previousPayrollAdjustments: [], snapshots: [], settings: settings,
        displayYM: (2_025, 10), previousYM: (2_025, 9), currency: "kr", jobs: jobs))
    let siri = PeriodEarnings.compute(
      shiftsByMonth: [(10, october)], jobs: jobs, settings: settings, now: now)

    // October is paid in November, the half-tax month: 1 500 kr at 15 %.
    XCTAssertEqual(home.currentMonthGross, 1_500, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(home.currentMonthNet), 1_275, accuracy: 0.001)
    XCTAssertEqual(home.currency, "kr")
    XCTAssertEqual(siri.gross, home.currentMonthGross, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(siri.net), 1_275, accuracy: 0.001)
    XCTAssertEqual(siri.completedGross, home.currentMonthCompletedGross, accuracy: 0.001)
    XCTAssertEqual(siri.currency, home.currency)
    XCTAssertEqual(siri.hours, 24, accuracy: 0.001, "hours count every currency")
  }

  func testAWeekAcrossTwoMonthsTaxesEachMonthByItsOwnPayout() throws {
    let now = try XCTUnwrap(Date.fromDateAndTime("2025-11-01", time: "12:00"))

    let week = PeriodEarnings.compute(
      shiftsByMonth: [
        (10, [shift("worked", "2025-10-30", job: "cafe", gross: 1_000, tax: 30)]),
        (11, [shift("planned", "2025-11-02", job: "cafe", gross: 1_000, tax: 30)]),
      ],
      jobs: jobs, settings: settings, now: now)

    // October pay arrives in November at half tax, November pay in December at full tax.
    XCTAssertEqual(week.gross, 2_000, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(week.net), 850 + 700, accuracy: 0.001)
    XCTAssertEqual(week.completedGross, 1_000, accuracy: 0.001)
    XCTAssertEqual(week.hours, 16, accuracy: 0.001)
    XCTAssertEqual(week.completedHours, 8, accuracy: 0.001)
  }

  func testNetIsLeftOutWhenTaxIsOff() {
    let earnings = PeriodEarnings.compute(
      shiftsByMonth: [(10, [shift("untaxed", "2025-10-06", job: "cafe", gross: 1_000, tax: 0)])],
      jobs: jobs, settings: settings, now: Date())

    XCTAssertNil(earnings.net)
  }

  func testLastMonthInJanuaryIsDecemberOfThePreviousYear() throws {
    let midJanuary = try XCTUnwrap(Date.fromDateAndTime("2026-01-15", time: "12:00"))

    let december = EarningsPeriod.lastMonth.days(around: midJanuary)
    let year = EarningsPeriod.thisYear.days(around: midJanuary)

    XCTAssertEqual(december.first.toISODateString(), "2025-12-01")
    XCTAssertEqual(december.last.toISODateString(), "2025-12-31")
    XCTAssertEqual(year.first.toISODateString(), "2026-01-01")
    XCTAssertEqual(year.last.toISODateString(), "2026-12-31")
  }

  private func shift(_ id: String, _ date: String, job: String, gross: Double, tax: Double)
    -> ShiftWithComputations
  {
    TestFixtures.computedShift(
      id: id, shiftDate: date, startTime: "09:00", endTime: "17:00", jobId: job, gross: gross,
      taxEnabled: tax > 0, taxPercentage: tax)
  }
}
