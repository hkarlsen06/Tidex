import Foundation

extension PayWindow {
  /// Payday moved back to the last valid banking day.
  var adjustedPayoutDate: Date {
    guard let parts = PayPeriodCalendar.components(payoutDate) else { return Date() }
    return PayrollDateAdjuster.adjustPayrollDate(
      payrollDay: parts.day, month: parts.month, year: parts.year)
  }
}

extension PayoutSchedule {
  init(job: Job?, fallbackPayrollDay: Int) {
    self.init(
      period: job?.pay_period ?? .calendarMonth,
      payrollDay: job?.payroll_day ?? fallbackPayrollDay
    )
  }
}
