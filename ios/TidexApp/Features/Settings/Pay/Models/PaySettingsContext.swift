import Foundation

/// Uses the same two date lookups as payroll: work settings on the shift date,
/// and tax settings on the scheduled payday in the following month.
struct PaySettingsContext {
  let workDate: String
  let taxDate: String
  let wageSnapshot: WageSnapshot?
  let taxSnapshot: WageSnapshot?
  let appliesHalfTax: Bool

  init(workDate: Date, snapshots: [WageSnapshot], payrollDay: Int, halfTaxMonth: Int?) {
    self.workDate = workDate.toISODateString()
    taxDate = PayrollEngine.calculatePayoutDate(
      shiftDate: self.workDate, payrollDay: payrollDay
    )
    wageSnapshot = SnapshotsService.snapshotForDate(self.workDate, from: snapshots)
    taxSnapshot = SnapshotsService.snapshotForDate(taxDate, from: snapshots)
    appliesHalfTax = halfTaxMonth == PayrollEngine.payoutMonth(from: self.workDate)
  }

  var effectiveTaxPercentage: Double {
    guard let taxSnapshot, taxSnapshot.effectiveTaxEnabled else { return 0 }
    let month = PayrollEngine.payoutMonth(from: workDate)
    return PayoutTaxSettings(
      enabled: taxSnapshot.effectiveTaxEnabled,
      percentage: taxSnapshot.effectiveTaxPercentage
    ).adjusted(payoutMonth: month, halfTaxMonth: appliesHalfTax ? month : nil).percentage
  }
}
