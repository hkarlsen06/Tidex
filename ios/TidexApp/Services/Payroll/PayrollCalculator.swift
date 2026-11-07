import Foundation

/// Pure payroll calculation logic
/// Port of lib/payroll/calc.ts
struct PayrollCalculator {

  /// Preset wage rates by tariff level
  static let presetWageRates: [String: Double] = [
    "-1": 129.91, "-2": 132.90, "1": 184.54, "2": 185.38,
    "3": 187.46, "4": 193.05, "5": 210.81, "6": 256.14,
  ]

  static let presetSupplementRules = SharingComputeCore.presetSupplementRules.map {
    SupplementRule(days: $0.days, from: $0.from, to: $0.to, rate: $0.rate, percent: $0.percent)
  }

  static let presetOvertimeConfig = OvertimeConfig.seededDefaults

  typealias PayTotals = PayrollPayTotals

  // MARK: - Public API

  /// Compute payroll for a single shift
  /// - Parameters:
  ///   - shift: The shift data
  ///   - snapshot: Wage snapshot containing wage, supplement, tax, and break settings
  /// - Returns: Computed payroll data including gross pay, hours, and breakdown
  static func computeShift(
    _ shift: ShiftRow,
    snapshot: WageSnapshot?
  ) -> ShiftComputed {
    PayrollEngine.appComputed(
      SharingComputeCore.computeShift(
        shift: PayrollEngine.sharingShift(shift),
        snapshot: snapshot.map(PayrollEngine.sharingSnapshot), mode: .visible),
      id: shift.id)
  }

  static func replacingWagePeriods(
    in computed: ShiftComputed,
    with periods: [WagePeriod],
    overtimeMinutes: Double
  ) -> ShiftComputed {
    let pay = payTotals(for: periods)

    return ShiftComputed(
      id: computed.id,
      durationHours: computed.durationHours,
      paidHours: computed.paidHours,
      basePay: pay.base,
      supplementPay: pay.supplement,
      gross: pay.gross,
      wagePeriods: periods,
      originalWagePeriods: computed.originalWagePeriods,
      breakAudit: computed.breakAudit,
      overtimeApplied: overtimeMinutes > 0,
      overtimeMinutes: (overtimeMinutes * 100).rounded() / 100
    )
  }

  /// Preserve minute precision and round once per pay component, independent of period splits.
  static func payTotals(for periods: [WagePeriod]) -> PayTotals {
    SharingComputeCore.payTotals(for: periods)
  }
}
