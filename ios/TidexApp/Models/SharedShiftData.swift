// MARK: - API Response Types for Sharing

/// Response from /api/sharing endpoint
struct SharedShiftsResponse: Codable {
  let shifts: [SharedShiftData]
  let settings: SharedUserSettings
  let jobs: [SharedJob]
  let payoutTaxSettings: SharedPayoutTaxSettings?
}

/// A shift with computed payroll data from the API
struct SharedShiftData: Codable, Identifiable, Equatable {
  let id: String
  let user_id: String
  let job_id: String?
  let job_name: String?
  let job_color: String?
  let shift_date: String
  let start_time: String
  let end_time: String
  let computed: SharedShiftComputed
  let tax_enabled: Bool?
  let tax_percentage: Double?

  /// Custom supplements (may be null or present)
  let custom_supplements: CustomSupplementsData?

  /// Recurring shift metadata (for virtual shifts)
  let recurring_id: String?
  let recurring_anchor_weekday: Int?

  var isVirtual: Bool {
    recurring_id != nil
  }
}

/// Computed payroll data from the API
struct SharedShiftComputed: Codable, Equatable {
  let id: String
  let durationHours: Double
  let paidHours: Double
  let basePay: Double
  let supplementPay: Double
  let gross: Double
}

/// User settings from the API response
struct SharedUserSettings: Codable, Equatable {
  let payroll_day: Int?
  let half_tax_month: Int?
  let monthly_goal: Double?
  let monthly_goals_by_month: [String: Int]?
  let currency: String?
}

/// Payout tax settings from the API
struct SharedPayoutTaxSettings: Codable, Equatable {
  let enabled: Bool
  let percentage: Double
}

/// Shared job metadata from sharing payload
struct SharedJob: Codable, Identifiable, Equatable {
  let id: String
  let user_id: String
  let name: String
  let color: String?
  let currency: String?
  let is_default: Bool?
  let sort_order: Int?
  let payroll_day: Int?
  let half_tax_month: Int?
  let monthly_goal: Double?
}

// MARK: - SharedShiftData to ShiftWithComputations Conversion

extension SharedShiftData {
  /// Convert to ShiftWithComputations for use with existing UI components
  func toShiftWithComputations() -> ShiftWithComputations {
    let shiftRow = ShiftRow(
      id: id,
      user_id: user_id,
      job_id: job_id,
      shift_date: shift_date,
      start_time: start_time,
      end_time: end_time,
      custom_supplements: custom_supplements,
      created_at: nil,
      recurring_id: recurring_id,
      recurring_anchor_weekday: recurring_anchor_weekday
    )

    let shiftComputed = ShiftComputed(
      id: id,
      durationHours: computed.durationHours,
      paidHours: computed.paidHours,
      basePay: computed.basePay,
      supplementPay: computed.supplementPay,
      gross: computed.gross,
      wagePeriods: [],  // Not provided by API
      originalWagePeriods: [],  // Not provided by API
      breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
    )

    return ShiftWithComputations(
      shift: shiftRow,
      computed: shiftComputed,
      taxEnabled: tax_enabled ?? false,
      taxPercentage: tax_percentage ?? 0
    )
  }
}
