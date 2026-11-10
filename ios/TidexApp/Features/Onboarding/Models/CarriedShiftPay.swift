import Foundation

/// What the carried demo shift pays with the wage the user just saved, from the payroll engine.
/// The parts add up the way the shift details sheet shows them: base and supplements before
/// the break, then the break deduction, then gross.
internal struct CarriedShiftPay: Equatable {
  internal let shift: CarriedDemoShift
  internal let currency: String
  /// Hours before the break, the hours the base pay is for.
  internal let workedHours: Double
  internal let basePay: Double
  internal let supplementPay: Double
  internal let breakDeduction: Double
  internal let gross: Double

  internal init(shift: CarriedDemoShift, snapshots: [WageSnapshot], currency: String) {
    var workedHours = 0.0
    var basePay = 0.0
    var supplementPay = 0.0
    var breakDeduction = 0.0
    var gross = 0.0

    for date in shift.dates {
      let row = ShiftRow(
        id: "carried-\(date)",
        user_id: nil,
        shift_date: date,
        start_time: shift.startTime,
        end_time: shift.endTime,
        custom_supplements: nil
      )
      let computed = PayrollCalculator.computeShift(
        row, snapshot: SnapshotsService.snapshotForDate(date, from: snapshots))
      let deduction = BreakDeductionBreakdown.make(
        originalPeriods: computed.preBreakWagePeriods,
        adjustedPeriods: computed.wagePeriods
      )
      workedHours += computed.durationHours
      gross += computed.gross
      if computed.breakAudit.deductedHours > 0, let deduction {
        basePay += BreakDeductionBreakdown.basePay(for: computed.preBreakWagePeriods)
        supplementPay += BreakDeductionBreakdown.supplementPay(for: computed.preBreakWagePeriods)
        breakDeduction += deduction.totalAmount
      } else {
        basePay += computed.basePay
        supplementPay += computed.supplementPay
      }
    }

    self.shift = shift
    self.currency = currency
    self.workedHours = workedHours
    self.basePay = basePay
    self.supplementPay = supplementPay
    self.breakDeduction = breakDeduction
    self.gross = gross
  }
}
