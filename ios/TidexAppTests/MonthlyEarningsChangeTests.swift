import XCTest

@testable import Tidex

/// Home and Stats both show `MonthlyEarningsChange`. These tests pin the number and the text,
/// so the two screens can't drift apart again (Home used to show +17% and Stats +16% for the same month).
final class MonthlyEarningsChangeTests: XCTestCase {
  private let english = Locale(identifier: "en_US")

  func testComparesGrossShiftPayBetweenMonths() throws {
    let change = try XCTUnwrap(percent(current: [14_000], previous: [6_000, 6_000]))

    XCTAssertEqual(change, 16.667, accuracy: 0.001)
    // Stats used to truncate this to +16% while Home rounded it to +17%.
    XCTAssertEqual(MonthlyEarningsChange.percentText(change, locale: english), "+17%")
  }

  func testNoComparisonWhenPreviousMonthHasNoPay() {
    // Home used to show "∞" here while Stats showed nothing.
    XCTAssertNil(percent(current: [1_000], previous: []))
    XCTAssertNil(percent(current: [], previous: []))
  }

  func testDropIsNegative() throws {
    let change = try XCTUnwrap(percent(current: [930], previous: [1_000]))

    XCTAssertEqual(change, -7, accuracy: 0.001)
    XCTAssertEqual(MonthlyEarningsChange.percentText(change, locale: english), "-7%")
  }

  func testConflictingShiftDoesNotPickTheComparisonCurrency() throws {
    let jobs = [
      TestFixtures.job(id: "job-kr", isDefault: true, currency: "kr"),
      TestFixtures.job(id: "job-usd", isDefault: false, currency: "$"),
    ]
    // The default job's only shift overlaps a cheaper one, so conflict exclusion drops it.
    let current = [
      TestFixtures.computedShift(
        id: "kr", shiftDate: "2026-09-01", startTime: "08:00", endTime: "16:00",
        jobId: "job-kr", gross: 2_000),
      TestFixtures.computedShift(
        id: "usd", shiftDate: "2026-09-01", startTime: "09:00", endTime: "15:00",
        jobId: "job-usd", gross: 500),
    ]
    let previous = [
      TestFixtures.computedShift(
        id: "usd-prev", shiftDate: "2026-08-01", startTime: "08:00", endTime: "16:00",
        jobId: "job-usd", gross: 1_000)
    ]

    let change = try XCTUnwrap(
      MonthlyEarningsChange.percent(
        monthShifts: current,
        previousMonthShifts: previous,
        jobs: jobs,
        fallbackCurrency: "kr",
        halfTaxMonth: nil,
        currentMonth: 9,
        previousMonth: 8,
        now: Date()
      ))

    XCTAssertEqual(change, -50, accuracy: 0.001)
  }

  func testPercentTextRoundsToWholePercentWithoutNegativeZero() {
    XCTAssertEqual(MonthlyEarningsChange.percentText(7, locale: english), "+7%")
    XCTAssertEqual(MonthlyEarningsChange.percentText(0.3, locale: english), "0%")
    XCTAssertEqual(MonthlyEarningsChange.percentText(-0.3, locale: english), "0%")
    XCTAssertEqual(MonthlyEarningsChange.percentText(-12.6, locale: english), "-13%")
  }

  func testPayrollTotalLabelNamesTheTaxBasis() {
    XCTAssertEqual(
      String(localized: PayrollDetailsSheet.totalLabel(taxEnabledByJob: [true, true])),
      String(localized: .dashboardPayrollDetailsTotalNetAfterTax)
    )
    XCTAssertEqual(
      String(localized: PayrollDetailsSheet.totalLabel(taxEnabledByJob: [false, false])),
      String(localized: .dashboardPayrollDetailsTotalBeforeTax)
    )
    XCTAssertEqual(
      String(localized: PayrollDetailsSheet.totalLabel(taxEnabledByJob: [true, false])),
      String(localized: .dashboardPayrollDetailsTotalEstimate)
    )
  }

  private func percent(current: [Double], previous: [Double]) -> Double? {
    MonthlyEarningsChange.percent(
      currentShifts: shifts(current, month: "2026-09"),
      previousShifts: shifts(previous, month: "2026-08"),
      halfTaxMonth: nil,
      currentMonth: 9,
      previousMonth: 8,
      now: Date()
    )
  }

  private func shifts(_ grossAmounts: [Double], month: String) -> [ShiftWithComputations] {
    grossAmounts.enumerated().map { index, gross in
      TestFixtures.computedShift(
        id: "\(month)-\(index)",
        shiftDate: "\(month)-\(String(format: "%02d", index + 1))",
        startTime: "08:00",
        endTime: "16:00",
        gross: gross
      )
    }
  }
}
