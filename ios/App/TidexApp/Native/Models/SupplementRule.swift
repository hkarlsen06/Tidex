import Foundation

// MARK: - Supplement Rule

/// Supplement rule for time-based wage additions
/// Matches the TypeScript SupplementRule type from lib/payroll/types.ts
struct SupplementRule: Codable, Equatable {
    /// Weekdays this rule applies to (1-7 where 1=Monday, 7=Sunday)
    let days: [Int]
    /// Start time (HH:mm) inclusive
    let from: String
    /// End time (HH:mm) inclusive
    let to: String
    /// Fixed NOK per hour supplement (e.g., 22, 45, 110)
    let rate: Double?
    /// Percentage supplement (e.g., 50 for 50% of base rate)
    let percent: Double?

    init(days: [Int], from: String, to: String, rate: Double? = nil, percent: Double? = nil) {
        self.days = days
        self.from = from
        self.to = to
        self.rate = rate
        self.percent = percent
    }
}

// MARK: - Custom Supplement Rule (Per-Shift)

/// Custom supplement rule saved on a shift (without days field)
/// Used for shift-specific supplement overrides
struct CustomSupplementRule: Codable, Equatable {
    let from: String
    let to: String
    let rate: Double?
    let percent: Double?
    /// true = user-added, false/nil = from tariff
    let isCustom: Bool?
}

/// Container for custom supplements on a shift
struct CustomSupplementsData: Codable, Equatable {
    let rules: [CustomSupplementRule]
}

/// Container for supplement rules snapshot
struct SupplementRulesSnapshot: Codable, Equatable {
    let rules: [SupplementRule]
}

// MARK: - Wage Period

/// A time period with associated wage rates after splitting by supplement rules
/// Note: fromMin/toMin are Double (not Int) to support exact proportional break deductions
/// as specified in lib/payroll/breaks.ts (TypeScript uses number which allows fractions)
struct WagePeriod: Equatable {
    /// Start time in minutes from midnight (Double for precision in break deductions)
    let fromMin: Double
    /// End time in minutes from midnight (exclusive, Double for precision)
    let toMin: Double
    /// Base hourly rate in NOK
    let baseRate: Double
    /// Supplement per hour in NOK
    let supplementRate: Double

    /// Total rate (base + supplement)
    var totalRate: Double { baseRate + supplementRate }

    /// Duration in minutes
    var durationMinutes: Double { toMin - fromMin }

    /// Duration in hours
    var durationHours: Double { durationMinutes / 60.0 }
}

// MARK: - Break Method

/// Method for applying break deductions
enum BreakMethod: String, Codable, Equatable {
    /// Deduct break proportionally across all periods
    case proportional = "proportional"
    /// Deduct from base/lowest supplement periods first
    case baseOnly = "base_only"
    /// Deduct from end of shift
    case endOfShift = "end_of_shift"
    /// No break deduction
    case none = "none"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = BreakMethod(rawValue: rawValue) ?? .proportional
    }
}

// MARK: - Break Audit

/// Audit trail for break deduction
struct BreakAudit: Equatable {
    let method: BreakMethod
    let thresholdHours: Double
    let deductedHours: Double
    let notes: [String]
}
