import Foundation

// MARK: - User Settings

/// User settings from the user_settings table
/// Contains global calendar and payroll preferences
struct UserSettings: Codable, Equatable {
  /// User ID (primary key)
  let user_id: String
  /// When the settings were created
  let created_at: String?
  /// When the settings were last updated (NOT NULL in DB)
  let updated_at: String?
  /// When the user was last active
  let last_active: String?
  /// Monthly earnings goal
  let monthly_goal: Int?
  /// Sparse month-specific goal overrides keyed by YYYY-MM
  let monthly_goals_by_month: [String: Int]?
  /// Default view for shifts (calendar, list, etc.)
  let default_shifts_view: String?
  /// Profile picture URL
  let profile_picture_url: String?
  /// Day of month for payroll (1-31)
  let payroll_day: Int?
  /// Theme preference (NOT NULL in DB, defaults to "system")
  let theme: String
  /// Calendar animation style preference (NOT NULL in DB, defaults to "horizontal")
  let calendar_animation_style: String
  /// Month number (11=November, 12=December) for half tax deduction
  let half_tax_month: Int?
  /// Currency code
  let currency: String?

  /// Effective payroll day (defaults to 1 if not set)
  var effectivePayrollDay: Int {
    payroll_day ?? 1
  }

  /// Effective default view
  var effectiveDefaultView: String {
    default_shifts_view ?? "calendar"
  }

  /// Resolve goal for a specific month with override-first fallback to baseline.
  func effectiveMonthlyGoal(year: Int, month: Int) -> Int? {
    let monthKey = UserSettings.monthKey(year: year, month: month)
    if let override = monthly_goals_by_month?[monthKey], override > 0 {
      return override
    }
    guard let baseline = monthly_goal, baseline > 0 else { return nil }
    return baseline
  }

  static func monthKey(year: Int, month: Int) -> String {
    String(format: "%04d-%02d", year, month)
  }

  /// Static default settings for when user has no settings
  static func defaults(for userId: String) -> UserSettings {
    UserSettings(
      user_id: userId,
      created_at: nil,
      updated_at: nil,
      last_active: nil,
      monthly_goal: nil,
      monthly_goals_by_month: nil,
      default_shifts_view: "calendar",
      profile_picture_url: nil,
      payroll_day: 1,
      theme: "system",
      calendar_animation_style: "horizontal",
      half_tax_month: nil,
      currency: nil
    )
  }
}
