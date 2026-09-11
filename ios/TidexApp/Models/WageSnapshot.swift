import Foundation

enum WageSnapshotDateError: Error, LocalizedError, Equatable {
  case baselineMustRemainUndated
  case dateConflict

  var errorDescription: String? {
    switch self {
    case .baselineMustRemainUndated:
      return String(localized: .settingsPayEditorBaselineHelp)
    case .dateConflict:
      return String(localized: .settingsPayErrorDateConflict)
    }
  }
}

// MARK: - Wage Snapshot

struct OvertimeRule: Codable, Equatable {
  let days: [Int]
  let appliesOnHolidays: Bool
  let from: String
  let to: String
  let percent: Double
}

struct OvertimeConfig: Codable, Equatable {
  static let defaultWeeklyThresholdHours: Double = 40
  private static let allDays = Set(1...7)

  let enabled: Bool
  let weeklyThresholdHours: Double
  let rules: [OvertimeRule]

  init(
    enabled: Bool = false,
    weeklyThresholdHours: Double = Self.defaultWeeklyThresholdHours,
    rules: [OvertimeRule] = []
  ) {
    self.enabled = enabled
    self.weeklyThresholdHours = weeklyThresholdHours
    self.rules = rules
  }

  static let disabled = OvertimeConfig()

  static let seededDefaults = OvertimeConfig(
    enabled: true,
    weeklyThresholdHours: Self.defaultWeeklyThresholdHours,
    rules: [
      OvertimeRule(
        days: [1, 2, 3, 4, 5, 6],
        appliesOnHolidays: false,
        from: "00:00",
        to: "21:00",
        percent: 50
      ),
      OvertimeRule(
        days: [1, 2, 3, 4, 5, 6],
        appliesOnHolidays: false,
        from: "21:00",
        to: "24:00",
        percent: 100
      ),
      OvertimeRule(
        days: [7],
        appliesOnHolidays: true,
        from: "00:00",
        to: "24:00",
        percent: 100
      ),
      OvertimeRule(
        days: [1, 2, 3, 4, 5, 6, 7],
        appliesOnHolidays: true,
        from: "00:00",
        to: "24:00",
        percent: 100
      ),
    ]
  )

  var runtimeEnabledConfig: OvertimeConfig? {
    guard enabled else { return nil }
    guard weeklyThresholdHours.isFinite, weeklyThresholdHours > 0 else { return nil }
    guard rules.allSatisfy(Self.isValidRule) else { return nil }
    guard Self.rulesCoverFullDay(rules, holiday: false) else { return nil }
    guard Self.rulesCoverFullDay(rules, holiday: true) else { return nil }
    return self
  }

  var isValidForEditing: Bool {
    !enabled || runtimeEnabledConfig != nil
  }

  static func timeToMinutes(_ value: String) -> Int? {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
      let hours = Int(parts[0]),
      let minutes = Int(parts[1]),
      minutes >= 0,
      minutes < 60,
      hours >= 0,
      hours <= 24,
      hours < 24 || minutes == 0
    else {
      return nil
    }
    return hours * 60 + minutes
  }

  static func isValidRule(_ rule: OvertimeRule) -> Bool {
    guard !rule.days.isEmpty,
      Set(rule.days).isSubset(of: allDays),
      rule.percent.isFinite,
      rule.percent > 0,
      let from = timeToMinutes(rule.from),
      let to = timeToMinutes(rule.to)
    else {
      return false
    }
    return from < to && to <= 24 * 60
  }

  private static func isHolidayOnlyRule(_ rule: OvertimeRule) -> Bool {
    rule.appliesOnHolidays && Set(rule.days) == allDays
  }

  private static func rulesCoverFullDay(_ rules: [OvertimeRule], holiday: Bool) -> Bool {
    for day in 1...7 {
      let intervals = rules.compactMap { rule -> (Int, Int)? in
        guard rule.days.contains(day) else { return nil }
        if holiday {
          guard rule.appliesOnHolidays else { return nil }
        } else if isHolidayOnlyRule(rule) {
          return nil
        }
        guard let from = timeToMinutes(rule.from), let to = timeToMinutes(rule.to) else {
          return nil
        }
        return (from, to)
      }
      guard intervalsCoverFullDay(intervals) else {
        return false
      }
    }
    return true
  }

  private static func intervalsCoverFullDay(_ intervals: [(Int, Int)]) -> Bool {
    var coveredUntil = 0
    for interval in intervals.sorted(by: { $0.0 < $1.0 }) {
      guard interval.0 <= coveredUntil else {
        return false
      }
      coveredUntil = max(coveredUntil, interval.1)
      if coveredUntil >= 24 * 60 {
        return true
      }
    }
    return false
  }
}

// swiftlint:disable identifier_name
/// Wage snapshot from the wage_snapshots table
/// Represents a point-in-time capture of wage, supplement, tax, and break settings
///
/// Note: from_date can be nil for the baseline snapshot, which serves as
/// the fallback for all shifts that don't match any dated snapshot
struct WageSnapshot: Codable, Identifiable, Equatable {
  let id: String
  let user_id: String
  /// Job that owns this snapshot (nullable during rollout compatibility)
  var job_id: String?  // swiftlint:disable:this explicit_acl
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
  /// Overtime rules for this historical wage snapshot.
  let overtime: OvertimeConfig

  // Tax settings (per-snapshot) - nullable in DB
  let tax_enabled: Bool?
  let tax_percentage: Double?

  // Break deduction settings (per-snapshot) - nullable in DB
  let break_enabled: Bool?
  let break_method: String?
  let break_threshold_hours: Double?
  let break_deduction_minutes: Int?

  let created_at: String?

  init(
    id: String,
    user_id userId: String,
    job_id jobId: String? = nil,
    from_date fromDate: String?,
    hourly_wage hourlyWage: Double,
    wage_level wageLevel: Int?,
    tariff_type_id tariffTypeId: String?,
    supplements: SupplementRulesSnapshot,
    overtime: OvertimeConfig = .disabled,
    tax_enabled taxEnabled: Bool?,
    tax_percentage taxPercentage: Double?,
    break_enabled breakEnabled: Bool?,
    break_method breakMethod: String?,
    break_threshold_hours breakThresholdHours: Double?,
    break_deduction_minutes breakDeductionMinutes: Int?,
    created_at createdAt: String?
  ) {
    self.id = id
    self.user_id = userId
    self.job_id = jobId
    self.from_date = fromDate
    self.hourly_wage = hourlyWage
    self.wage_level = wageLevel
    self.tariff_type_id = tariffTypeId
    self.supplements = supplements
    self.overtime = overtime
    self.tax_enabled = taxEnabled
    self.tax_percentage = taxPercentage
    self.break_enabled = breakEnabled
    self.break_method = breakMethod
    self.break_threshold_hours = breakThresholdHours
    self.break_deduction_minutes = breakDeductionMinutes
    self.created_at = createdAt
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case jobId = "job_id"
    case fromDate = "from_date"
    case hourlyWage = "hourly_wage"
    case wageLevel = "wage_level"
    case tariffTypeId = "tariff_type_id"
    case supplements
    case overtime
    case taxEnabled = "tax_enabled"
    case taxPercentage = "tax_percentage"
    case breakEnabled = "break_enabled"
    case breakMethod = "break_method"
    case breakThresholdHours = "break_threshold_hours"
    case breakDeductionMinutes = "break_deduction_minutes"
    case createdAt = "created_at"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    user_id = try container.decode(String.self, forKey: .userId)
    job_id = try container.decodeIfPresent(String.self, forKey: .jobId)
    from_date = try container.decodeIfPresent(String.self, forKey: .fromDate)
    hourly_wage = try container.decode(Double.self, forKey: .hourlyWage)
    wage_level = try container.decodeIfPresent(Int.self, forKey: .wageLevel)
    tariff_type_id = try container.decodeIfPresent(String.self, forKey: .tariffTypeId)
    supplements = try container.decode(SupplementRulesSnapshot.self, forKey: .supplements)
    overtime =
      (try? container.decodeIfPresent(OvertimeConfig.self, forKey: .overtime)) ?? .disabled
    tax_enabled = try container.decodeIfPresent(Bool.self, forKey: .taxEnabled)
    tax_percentage = try container.decodeIfPresent(Double.self, forKey: .taxPercentage)
    break_enabled = try container.decodeIfPresent(Bool.self, forKey: .breakEnabled)
    break_method = try container.decodeIfPresent(String.self, forKey: .breakMethod)
    break_threshold_hours = try container.decodeIfPresent(
      Double.self, forKey: .breakThresholdHours)
    break_deduction_minutes = try container.decodeIfPresent(
      Int.self, forKey: .breakDeductionMinutes)
    created_at = try container.decodeIfPresent(String.self, forKey: .createdAt)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(user_id, forKey: .userId)
    try container.encodeIfPresent(job_id, forKey: .jobId)
    try container.encodeIfPresent(from_date, forKey: .fromDate)
    try container.encode(hourly_wage, forKey: .hourlyWage)
    try container.encodeIfPresent(wage_level, forKey: .wageLevel)
    try container.encodeIfPresent(tariff_type_id, forKey: .tariffTypeId)
    try container.encode(supplements, forKey: .supplements)
    try container.encode(overtime, forKey: .overtime)
    try container.encodeIfPresent(tax_enabled, forKey: .taxEnabled)
    try container.encodeIfPresent(tax_percentage, forKey: .taxPercentage)
    try container.encodeIfPresent(break_enabled, forKey: .breakEnabled)
    try container.encodeIfPresent(break_method, forKey: .breakMethod)
    try container.encodeIfPresent(break_threshold_hours, forKey: .breakThresholdHours)
    try container.encodeIfPresent(break_deduction_minutes, forKey: .breakDeductionMinutes)
    try container.encodeIfPresent(created_at, forKey: .createdAt)
  }

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
// swiftlint:enable identifier_name

// MARK: - Payout Tax Settings

/// Tax settings for payout calculations
/// Used for calculating after-tax monthly totals
struct PayoutTaxSettings: Equatable {
  let enabled: Bool
  let percentage: Double

  func adjusted(payoutMonth: Int, halfTaxMonth: Int?) -> PayoutTaxSettings {
    let rate = percentage.isFinite ? min(max(percentage, 0), 100) : 0
    return PayoutTaxSettings(
      enabled: enabled,
      percentage: enabled ? (halfTaxMonth == payoutMonth ? rate / 2 : rate) : 0
    )
  }

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
