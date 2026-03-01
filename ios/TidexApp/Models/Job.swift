// MARK: - Job

/// Job row from the jobs table
struct Job: Codable, Identifiable, Equatable {
  let id: String
  let user_id: String
  let name: String
  let color: String?
  let is_default: Bool
  let sort_order: Int
  let payroll_day: Int?
  let half_tax_month: Int?
  let monthly_goal: Int?
  let archived_at: String?
  let deleted_at: String?
  let created_at: String?
  let updated_at: String?
}
