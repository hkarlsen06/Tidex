import Foundation

// MARK: - Shift Row

/// Raw shift data from user_shifts table
struct ShiftRow: Codable, Identifiable, Equatable {
    let id: String
    let user_id: String
    /// Shift date in ISO format (YYYY-MM-DD)
    let shift_date: String
    /// Start time (HH:mm)
    let start_time: String
    /// End time (HH:mm) - can be less than start_time for cross-midnight shifts
    let end_time: String
    /// Snapshot of hourly wage at shift creation (legacy, for backward compatibility)
    let hourly_wage_snapshot: Double?
    /// Snapshot of supplement rules at shift creation (legacy)
    let supplement_rules_snapshot: SupplementRulesSnapshot?
    /// Shift-specific custom supplements
    let custom_supplements: CustomSupplementsData?
    /// Links to recurring_shifts if this is a virtual shift
    let recurring_id: String?
    /// Which weekday anchor (0-6) generated this virtual shift
    let recurring_anchor_weekday: Int?

    /// Whether this shift is from a recurring pattern
    var isVirtual: Bool {
        recurring_id != nil
    }
}

// MARK: - Shift Computed

/// Computed payroll results for a shift
struct ShiftComputed: Equatable {
    let id: String
    /// Raw duration in hours (before break deduction)
    let durationHours: Double
    /// Paid hours (after break deduction)
    let paidHours: Double
    /// Base pay in NOK
    let basePay: Double
    /// Supplement pay in NOK
    let supplementPay: Double
    /// Gross pay in NOK (base + supplement)
    let gross: Double
    /// Wage periods after break deduction
    let wagePeriods: [WagePeriod]
    /// Wage periods before break deduction (for display)
    let originalWagePeriods: [WagePeriod]
    /// Break deduction audit trail
    let breakAudit: BreakAudit

    /// Net pay after tax (if tax settings provided)
    func netPay(taxEnabled: Bool, taxPercentage: Double) -> Double {
        guard taxEnabled else { return gross }
        return gross * (1 - taxPercentage / 100)
    }

    /// Tax amount (if tax settings provided)
    func taxAmount(taxEnabled: Bool, taxPercentage: Double) -> Double {
        guard taxEnabled else { return 0 }
        return gross * taxPercentage / 100
    }
}

// MARK: - Shift With Computations

/// Shift combined with computed payroll data and tax settings
struct ShiftWithComputations: Identifiable, Equatable {
    let shift: ShiftRow
    let computed: ShiftComputed
    /// Whether tax is enabled for this shift's payout
    let taxEnabled: Bool
    /// Tax percentage for this shift's payout
    let taxPercentage: Double

    var id: String { shift.id }
    var shiftDate: String { shift.shift_date }
    var startTime: String { shift.start_time }
    var endTime: String { shift.end_time }
    var isVirtual: Bool { shift.isVirtual }

    /// Net pay after tax
    var netPay: Double {
        computed.netPay(taxEnabled: taxEnabled, taxPercentage: taxPercentage)
    }

    /// Tax amount
    var taxAmount: Double {
        computed.taxAmount(taxEnabled: taxEnabled, taxPercentage: taxPercentage)
    }

    /// Gross pay
    var grossPay: Double {
        computed.gross
    }

    /// Paid hours
    var paidHours: Double {
        computed.paidHours
    }
}

// MARK: - Shifts Aggregates

/// Aggregated statistics for a collection of shifts
struct ShiftsAggregates: Equatable {
    let totalHours: Double
    let totalGross: Double

    /// Calculate net total with tax settings
    func netTotal(taxEnabled: Bool, taxPercentage: Double) -> Double {
        guard taxEnabled else { return totalGross }
        return totalGross * (1 - taxPercentage / 100)
    }

    static var zero: ShiftsAggregates {
        ShiftsAggregates(totalHours: 0, totalGross: 0)
    }
}
