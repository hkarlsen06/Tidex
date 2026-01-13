import Foundation

/// Pure payroll calculation logic
/// Port of lib/payroll/calc.ts
struct PayrollCalculator {

    // MARK: - Constants

    /// Precision for hour calculations (3 decimal places)
    private static let hourPrecision: Double = 1000
    /// Precision for currency calculations (2 decimal places)
    private static let currencyPrecision: Double = 100

    /// Weekday mapping: JS getDay() 0=Sun maps to 7, then 1-6 for Mon-Sat
    private static let weekdayMap = [7, 1, 2, 3, 4, 5, 6]

    /// Preset wage rates by tariff level
    static let presetWageRates: [String: Double] = [
        "-1": 129.91, "-2": 132.90, "1": 184.54, "2": 185.38,
        "3": 187.46, "4": 193.05, "5": 210.81, "6": 256.14
    ]

    /// Preset supplement rules (Norwegian tariff-based)
    static let presetSupplementRules: [SupplementRule] = [
        SupplementRule(days: [1, 2, 3, 4, 5], from: "18:00", to: "21:00", rate: 22, percent: nil),
        SupplementRule(days: [1, 2, 3, 4, 5], from: "21:00", to: "23:59", rate: 45, percent: nil),
        SupplementRule(days: [6], from: "13:00", to: "15:00", rate: 45, percent: nil),
        SupplementRule(days: [6], from: "15:00", to: "18:00", rate: 55, percent: nil),
        SupplementRule(days: [6], from: "18:00", to: "23:59", rate: 110, percent: nil),
        SupplementRule(days: [7], from: "00:00", to: "23:59", rate: 115, percent: nil)
    ]

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
        // Get weekday (1-7 where 1=Mon, 7=Sun)
        let weekday = Date.weekdayFromISO(shift.shift_date)

        // Resolve base rate from snapshot or fallback
        let baseRate = resolveBaseRate(shift: shift, snapshot: snapshot)

        // Resolve supplement rules
        let rules = resolveSupplementRules(
            weekday: weekday,
            snapshot: snapshot,
            shiftSnapshot: shift.supplement_rules_snapshot,
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

        // Calculate raw duration
        let totalMinutes = periods.reduce(0) { $0 + $1.durationMinutes }
        let durationHours = round(Double(totalMinutes) / 60.0 * 100) / 100

        // Store original periods before break deduction (for display)
        let originalPeriods = periods

        // Resolve break settings from snapshot (with defaults for backward compatibility)
        let breakEnabled = snapshot?.break_enabled ?? defaultBreakEnabled
        let method = snapshot?.breakMethod ?? defaultBreakMethod
        let threshold = snapshot?.break_threshold_hours ?? defaultBreakThresholdHours
        let breakMinutes = breakEnabled
            ? (snapshot?.break_deduction_minutes ?? defaultBreakDeductionMinutes)
            : 0
        let breakHours = Double(breakMinutes) / 60.0

        // Apply automatic break deduction
        let afterBreak = BreakDeduction.applyBreakDeduction(
            periods: periods,
            method: method,
            thresholdHours: threshold,
            deductionHours: breakHours
        )
        periods = afterBreak.periods

        // Calculate paid hours
        let paidMinutes = periods.reduce(0) { $0 + $1.durationMinutes }
        let paidHours = round(Double(paidMinutes) / 60.0 * 100) / 100

        // Calculate pay
        var basePay: Double = 0
        var supplementPay: Double = 0

        for period in periods {
            // Round hours to 3 decimals to match old codebase behavior
            let h = round(period.durationHours * hourPrecision) / hourPrecision
            // Round each period's contribution to cents
            basePay += round(h * period.baseRate * currencyPrecision) / currencyPrecision
            supplementPay += round(h * period.supplementRate * currencyPrecision) / currencyPrecision
        }

        basePay = round(basePay * 100) / 100
        supplementPay = round(supplementPay * 100) / 100
        let gross = round((basePay + supplementPay) * 100) / 100

        return ShiftComputed(
            id: shift.id,
            durationHours: durationHours,
            paidHours: paidHours,
            basePay: basePay,
            supplementPay: supplementPay,
            gross: gross,
            wagePeriods: periods,
            originalWagePeriods: originalPeriods,
            breakAudit: afterBreak.audit
        )
    }

    // MARK: - Private Helpers

    /// Resolve the base hourly wage rate for a shift
    /// Priority: 1. New snapshot system, 2. Old per-shift snapshot, 3. Fallback to preset
    private static func resolveBaseRate(shift: ShiftRow, snapshot: WageSnapshot?) -> Double {
        // Priority 1: Use new snapshot system
        if let rate = snapshot?.hourly_wage, rate > 0 {
            return rate
        }

        // Priority 2: Backward compatibility - old per-shift snapshot
        if let rate = shift.hourly_wage_snapshot, rate > 0 {
            return rate
        }

        // Priority 3: Fallback to tariff level 1
        return presetWageRates["1"] ?? 184.54
    }

    /// Resolve supplement rules with custom supplements
    /// When custom supplements exist, they completely replace predefined rules
    private static func resolveSupplementRules(
        weekday: Int,
        snapshot: WageSnapshot?,
        shiftSnapshot: SupplementRulesSnapshot?,
        customSupplements: CustomSupplementsData?
    ) -> [SupplementRule] {
        // If custom supplements exist, they replace everything
        if let custom = customSupplements, !custom.rules.isEmpty {
            return custom.rules.map { rule in
                SupplementRule(
                    days: [weekday],
                    from: rule.from,
                    to: rule.to,
                    rate: rule.rate,
                    percent: rule.percent
                )
            }
        }

        // Priority: snapshot > shift snapshot > preset
        if let rules = snapshot?.supplements.rules, !rules.isEmpty {
            return rules
        }

        if let rules = shiftSnapshot?.rules, !rules.isEmpty {
            return rules
        }

        return presetSupplementRules
    }
}
