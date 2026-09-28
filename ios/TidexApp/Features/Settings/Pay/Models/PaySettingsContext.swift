import Foundation

/// Uses the same two date lookups as payroll: work settings on the shift date,
/// and tax settings on the payday of the job's pay period.
struct PaySettingsContext {
  let workDate: String
  let taxDate: String
  let wageSnapshot: WageSnapshot?
  let taxSnapshot: WageSnapshot?
  let appliesHalfTax: Bool
  private let payoutMonth: Int

  init(
    workDate: Date,
    snapshots: [WageSnapshot],
    payrollDay: Int,
    halfTaxMonth: Int?,
    payPeriod: PayPeriod = .calendarMonth
  ) {
    self.workDate = workDate.toISODateString()
    taxDate = PayoutSchedule(period: payPeriod, payrollDay: payrollDay).payoutDate(for: self.workDate)
    wageSnapshot = SnapshotsService.snapshotForDate(self.workDate, from: snapshots)
    taxSnapshot = SnapshotsService.snapshotForDate(taxDate, from: snapshots)
    payoutMonth = PayPeriodCalendar.components(taxDate)?.month ?? 1
    appliesHalfTax = halfTaxMonth == payoutMonth
  }

  var effectiveTaxPercentage: Double {
    guard let taxSnapshot, taxSnapshot.effectiveTaxEnabled else { return 0 }
    return PayoutTaxSettings(
      enabled: taxSnapshot.effectiveTaxEnabled,
      percentage: taxSnapshot.effectiveTaxPercentage
    ).adjusted(payoutMonth: payoutMonth, halfTaxMonth: appliesHalfTax ? payoutMonth : nil).percentage
  }
}
