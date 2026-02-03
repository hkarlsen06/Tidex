import Foundation

// MARK: - Wage Snapshot

/// Wage snapshot from the wage_snapshots table
/// Represents a point-in-time capture of wage, supplement, tax, and break settings
///
/// Note: from_date can be nil for the baseline snapshot, which serves as
/// the fallback for all shifts that don't match any dated snapshot
struct WageSnapshot: Codable, Identifiable, Equatable {
    let id: String
    let user_id: String
    /// ISO date (YYYY-MM-DD) or nil for baseline snapshot
    let from_date: String?
    /// Hourly wage in NOK
    let hourly_wage: Double
    /// nil = custom wage, 1-9 = tariff level
    let wage_level: Int?
    /// The tariff type ID (e.g., "hk_retail") or nil for custom wage
    let tariff_type_id: String?
    /// Supplement rules for this snapshot (stored as JSONB object with "rules" key)
    /// This is NOT NULL in the database - always contains { rules: [...] }
    let supplements: SupplementRulesSnapshot

    // Tax settings (per-snapshot) - nullable in DB
    let tax_enabled: Bool?
    let tax_percentage: Double?

    // Break deduction settings (per-snapshot) - nullable in DB
    let break_enabled: Bool?
    let break_method: String?
    let break_threshold_hours: Double?
    let break_deduction_minutes: Int?

    let created_at: String?

    /// Effective tax enabled (defaults to false if nil)
    var effectiveTaxEnabled: Bool {
        tax_enabled ?? false
    }

    /// Effective tax percentage (defaults to 0 if nil)
    var effectiveTaxPercentage: Double {
        tax_percentage ?? 0
    }

    /// Effective supplements (the rules array from supplements object)
    var effectiveSupplements: [SupplementRule] {
        supplements.rules
    }

    /// Parsed break method enum
    var breakMethod: BreakMethod {
        guard let method = break_method else { return .proportional }
        return BreakMethod(rawValue: method) ?? .proportional
    }

    /// Effective break enabled (defaults to true if nil)
    var effectiveBreakEnabled: Bool {
        break_enabled ?? true
    }

    /// Effective break threshold hours (defaults to 5.5 if nil)
    var effectiveBreakThresholdHours: Double {
        break_threshold_hours ?? 5.5
    }

    /// Effective break deduction minutes (defaults to 30 if nil)
    var effectiveBreakDeductionMinutes: Int {
        break_deduction_minutes ?? 30
    }

    /// Whether this is a baseline (undated) snapshot
    var isBaseline: Bool {
        from_date == nil
    }
}

// MARK: - Payout Tax Settings

/// Tax settings for payout calculations
/// Used for calculating after-tax monthly totals
struct PayoutTaxSettings: Equatable {
    let enabled: Bool
    let percentage: Double

    /// Calculate net amount after tax
    func netAmount(from gross: Double) -> Double {
        guard enabled else { return gross }
        return gross * (1 - percentage / 100)
    }

    /// Calculate tax amount
    func taxAmount(from gross: Double) -> Double {
        guard enabled else { return 0 }
        return gross * percentage / 100
    }
}
