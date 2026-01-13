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
    /// Supplement rules for this snapshot
    let supplements: SupplementRulesSnapshot

    // Tax settings (per-snapshot)
    let tax_enabled: Bool
    let tax_percentage: Double

    // Break deduction settings (per-snapshot)
    let break_enabled: Bool
    let break_method: String
    let break_threshold_hours: Double
    let break_deduction_minutes: Int

    let created_at: String?

    /// Parsed break method enum
    var breakMethod: BreakMethod {
        BreakMethod(rawValue: break_method) ?? .proportional
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
