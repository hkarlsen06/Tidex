// MARK: - Job

/// Job row from the jobs table
struct Job: Codable, Identifiable, Equatable {
  let id: String
  let user_id: String
  let name: String
  let color: String?
  let currency: String
  let is_default: Bool
  let sort_order: Int
  let payroll_day: Int?
  let half_tax_month: Int?
  /// nil means calendar month, paid on `payroll_day` the month after.
  let pay_period: PayPeriod?  // swiftlint:disable:this identifier_name
  let monthly_goal: Int?
  let archived_at: String?
  let deleted_at: String?
  let created_at: String?
  let updated_at: String?

  init(
    id: String,
    user_id: String,
    name: String,
    color: String?,
    currency: String,
    is_default: Bool,
    sort_order: Int,
    payroll_day: Int?,
    half_tax_month: Int?,
    monthly_goal: Int?,
    archived_at: String?,
    deleted_at: String?,
    created_at: String?,
    updated_at: String?,  // swiftlint:disable:this identifier_name
    pay_period: PayPeriod? = nil  // swiftlint:disable:this identifier_name
  ) {
    self.id = id
    self.user_id = user_id
    self.name = name
    self.color = color
    self.currency = currency
    self.is_default = is_default
    self.sort_order = sort_order
    self.payroll_day = payroll_day
    self.half_tax_month = half_tax_month
    self.pay_period = pay_period
    self.monthly_goal = monthly_goal
    self.archived_at = archived_at
    self.deleted_at = deleted_at
    self.created_at = created_at
    self.updated_at = updated_at
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case user_id
    case name
    case color
    case currency
    case is_default
    case sort_order
    case payroll_day
    case half_tax_month
    case pay_period  // swiftlint:disable:this identifier_name
    case monthly_goal
    case archived_at
    case deleted_at
    case created_at
    case updated_at
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    id = try container.decode(String.self, forKey: .id)
    user_id = try container.decode(String.self, forKey: .user_id)
    name = try container.decode(String.self, forKey: .name)
    color = try container.decodeIfPresent(String.self, forKey: .color)
    currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "kr"
    is_default = try container.decode(Bool.self, forKey: .is_default)
    sort_order = try container.decode(Int.self, forKey: .sort_order)
    payroll_day = try container.decodeIfPresent(Int.self, forKey: .payroll_day)
    half_tax_month = try container.decodeIfPresent(Int.self, forKey: .half_tax_month)
    // An unreadable value falls back to the calendar month instead of failing the whole job.
    pay_period = try? container.decodeIfPresent(PayPeriod.self, forKey: .pay_period)
    monthly_goal = try container.decodeIfPresent(Int.self, forKey: .monthly_goal)
    archived_at = try container.decodeIfPresent(String.self, forKey: .archived_at)
    deleted_at = try container.decodeIfPresent(String.self, forKey: .deleted_at)
    created_at = try container.decodeIfPresent(String.self, forKey: .created_at)
    updated_at = try container.decodeIfPresent(String.self, forKey: .updated_at)
  }
}
