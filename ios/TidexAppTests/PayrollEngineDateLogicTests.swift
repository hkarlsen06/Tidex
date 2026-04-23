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
}
