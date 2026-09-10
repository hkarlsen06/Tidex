import Foundation
import os.log

/// Pure payroll calculation logic
/// Port of lib/payroll/calc.ts
struct PayrollCalculator {

  // MARK: - Logging

  private static let logger = Logger(subsystem: "com.tidex.app", category: "PayrollCalculator")

  // MARK: - Constants

  /// Precision for currency calculations (2 decimal places)
  private static let currencyPrecision: Double = 100

  /// Weekday mapping: JS getDay() 0=Sun maps to 7, then 1-6 for Mon-Sat
  private static let weekdayMap = [7, 1, 2, 3, 4, 5, 6]

  /// Preset wage rates by tariff level
  static let presetWageRates: [String: Double] = [
    "-1": 129.91, "-2": 132.90, "1": 184.54, "2": 185.38,
    "3": 187.46, "4": 193.05, "5": 210.81, "6": 256.14,
  ]

  /// Preset supplement rules (Norwegian tariff-based)
  static let presetSupplementRules: [SupplementRule] = [
    SupplementRule(days: [1, 2, 3, 4, 5], from: "18:00", to: "21:00", rate: 22, percent: nil),
    SupplementRule(days: [1, 2, 3, 4, 5], from: "21:00", to: "24:00", rate: 45, percent: nil),
    SupplementRule(days: [6], from: "13:00", to: "15:00", rate: 45, percent: nil),
    SupplementRule(days: [6], from: "15:00", to: "18:00", rate: 55, percent: nil),
    SupplementRule(days: [6], from: "18:00", to: "24:00", rate: 110, percent: nil),
    SupplementRule(days: [7], from: "00:00", to: "24:00", rate: 115, percent: nil),
  ]

  static let presetOvertimeConfig = OvertimeConfig.seededDefaults

  /// Default break deduction settings
  private static let defaultBreakEnabled = true
  private static let defaultBreakMethod: BreakMethod = .proportional
  private static let defaultBreakThresholdHours = 5.5
  private static let defaultBreakDeductionMinutes = 30

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
    let normalizedPauseWindows = PauseWindowSupport.normalize(shift.custom_pause_windows)

    // Get weekday (1-7 where 1=Mon, 7=Sun)
    let weekday = Date.weekdayFromISO(shift.shift_date)

    // Resolve base rate from snapshot or fallback
    let baseRate = resolveBaseRate(shift: shift, snapshot: snapshot)

    // Resolve supplement rules
    let rules = resolveSupplementRules(
      snapshot: snapshot,
      customSupplements: shift.custom_supplements
    )

    // Build wage periods
    var periods = WagePeriodBuilder.buildWagePeriods(
      startTime: shift.start_time,
      endTime: shift.end_time,
      weekday: weekday,
      baseRate: baseRate,
      rules: rules
    )

    // Calculate raw duration (durationMinutes is Double for precision)
    let totalMinutes = periods.reduce(0.0) { $0 + $1.durationMinutes }
    let durationHours = totalMinutes / 60.0

    // Store original periods before break deduction (for display)
    let originalPeriods = periods

    let breakAudit: BreakAudit
    if let normalizedPauseWindows {
      let clipped = PauseWindowSupport.apply(
        customPauseWindows: normalizedPauseWindows,
        startTime: shift.start_time,
        endTime: shift.end_time,
        periods: periods.map {
          PauseClipPeriod(
            fromMin: $0.fromMin,
            toMin: $0.toMin,
            baseRate: $0.baseRate,
            supplementRate: $0.supplementRate
          )
        }
      )
      periods = clipped.periods.map {
        WagePeriod(
          fromMin: $0.fromMin,
          toMin: $0.toMin,
          baseRate: $0.baseRate,
          supplementRate: $0.supplementRate
        )
      }
      breakAudit = BreakAudit(
        method: .none,
        thresholdHours: 0,
        deductedHours: clipped.deductedHours,
        source: .customPauseWindows,
        appliedPauseWindows: clipped.appliedPauseWindows,
        notes: clipped.appliedPauseWindows?.isEmpty == false
          ? ["Deducted using custom pause windows"] : []
      )
    } else {
      // Resolve break settings from snapshot (with defaults for backward compatibility)
      let breakEnabled = snapshot?.effectiveBreakEnabled ?? defaultBreakEnabled
      let method = snapshot?.breakMethod ?? defaultBreakMethod
      let threshold = sanitizedHours(
        snapshot?.effectiveBreakThresholdHours,
        fallback: defaultBreakThresholdHours
      )
      let breakMinutes =
        breakEnabled
        ? max(0, snapshot?.effectiveBreakDeductionMinutes ?? defaultBreakDeductionMinutes)
        : 0
      let breakHours = Double(breakMinutes) / 60.0

      // Log when using default break settings
      if snapshot == nil {
        logger.warning("Using default break settings - no snapshot available for shift \(shift.id)")
      }

      let afterBreak = BreakDeduction.applyBreakDeduction(
        periods: periods,
        method: method,
        thresholdHours: threshold,
        deductionHours: breakHours
      )
      periods = afterBreak.periods
      breakAudit = afterBreak.audit
    }

    // Calculate paid hours (after break deduction, with fractional precision)
    let paidMinutes = periods.reduce(0.0) { $0 + $1.durationMinutes }
    let paidHours = paidMinutes / 60.0

    // Calculate pay
    let pay = payTotals(for: periods)

    return ShiftComputed(
      id: shift.id,
      durationHours: durationHours,
      paidHours: paidHours,
      basePay: pay.base,
      supplementPay: pay.supplement,
      gross: pay.gross,
      wagePeriods: periods,
      originalWagePeriods: originalPeriods,
      breakAudit: breakAudit
    )
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
      overtimeMinutes: round(overtimeMinutes * currencyPrecision) / currencyPrecision
    )
  }

  /// Preserve minute precision and round once per pay component, independent of period splits.
  static func payTotals(for periods: [WagePeriod]) -> (
    base: Double, supplement: Double, gross: Double
  ) {
    let base = periods.reduce(0) { $0 + max(0, $1.durationHours) * $1.baseRate }
    let supplement = periods.reduce(0) { $0 + max(0, $1.durationHours) * $1.supplementRate }
    let basePay = round(base * currencyPrecision) / currencyPrecision
    let supplementPay = round(supplement * currencyPrecision) / currencyPrecision
    return (
      basePay, supplementPay,
      round((basePay + supplementPay) * currencyPrecision) / currencyPrecision
    )
  }

  // MARK: - Private Helpers

  /// Resolve the base hourly wage rate for a shift
  /// Priority: 1. Snapshot system, 2. Fallback to preset
  private static func resolveBaseRate(shift: ShiftRow, snapshot: WageSnapshot?) -> Double {
    // Priority 1: Use snapshot system
    if let rate = snapshot?.hourly_wage, rate.isFinite, rate > 0 {
      return rate
    }

    // Priority 2: Fallback to tariff level 1
    let fallbackRate = presetWageRates["1"] ?? 184.54
    logger.warning(
      "Using default base rate (\(fallbackRate)) - no snapshot available for shift \(shift.id)")
    return fallbackRate
  }

  /// Resolve supplement rules with custom supplements
  /// When custom supplements exist, they completely replace predefined rules
  private static func resolveSupplementRules(
    snapshot: WageSnapshot?,
    customSupplements: CustomSupplementsData?
  ) -> [SupplementRule] {
    // If custom supplements exist, they replace everything
    if let custom = customSupplements {
      // Empty rules array means "explicitly no supplements" for this shift
      if custom.rules.isEmpty {
        return []
      }
      return custom.rules.map { rule in
        SupplementRule(
          days: Array(1...7),
          from: rule.from,
          to: rule.to,
          rate: rule.rate,
          percent: rule.percent
        )
      }
    }

    // Priority: snapshot supplements (even if empty) > preset fallback
    // If snapshot exists, use its supplements - empty array means "no supplements"
    // Only fall back to presets if there's no snapshot at all (offline fallback)
    if let snapshot {
      return snapshot.effectiveSupplements
    }

    logger.warning("Using preset supplement rules - no snapshot available (offline fallback)")
    return presetSupplementRules
  }

  private static func sanitizedHours(_ value: Double?, fallback: Double) -> Double {
    guard let value, value.isFinite, value >= 0 else {
      return fallback
    }
    return value
  }
}
