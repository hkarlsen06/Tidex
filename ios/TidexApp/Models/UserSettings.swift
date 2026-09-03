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
  /// Calendar content color style preference (defaults to "workplace")
  let calendar_content_color_style: String?
  /// Whether dashboard clock in/out buttons are visible
  let show_dashboard_clock_buttons: Bool?
  /// Whether the user has consented to Wagey AI data sharing
  let ai_data_sharing_enabled: Bool?
  /// Month number (11=November, 12=December) for half tax deduction
  let half_tax_month: Int?
  /// Currency code
  let currency: String?
  /// Default tab to open when launching the app
  let default_startup_tab: String?
  /// Whether the user has dismissed the Wagey showcase
  let wagey_showcase_seen: Bool?  // swiftlint:disable:this identifier_name

  init(
    user_id: String,
    created_at: String?,
    updated_at: String?,
    last_active: String?,
    monthly_goal: Int?,
    monthly_goals_by_month: [String: Int]?,
    default_shifts_view: String?,
    profile_picture_url: String?,
    payroll_day: Int?,
    theme: String,
    calendar_content_color_style: String? = "workplace",
    show_dashboard_clock_buttons: Bool?,
    ai_data_sharing_enabled: Bool? = nil,
    half_tax_month: Int?,
    currency: String?,
    default_startup_tab: String?,  // swiftlint:disable:this identifier_name
    wagey_showcase_seen: Bool? = nil  // swiftlint:disable:this identifier_name
  ) {
    self.user_id = user_id
    self.created_at = created_at
    self.updated_at = updated_at
    self.last_active = last_active
    self.monthly_goal = monthly_goal
    self.monthly_goals_by_month = monthly_goals_by_month
    self.default_shifts_view = default_shifts_view
    self.profile_picture_url = profile_picture_url
    self.payroll_day = payroll_day
    self.theme = theme
    self.calendar_content_color_style = calendar_content_color_style
    self.show_dashboard_clock_buttons = show_dashboard_clock_buttons
    self.ai_data_sharing_enabled = ai_data_sharing_enabled
    self.half_tax_month = half_tax_month
    self.currency = currency
    self.default_startup_tab = default_startup_tab
    self.wagey_showcase_seen = wagey_showcase_seen
  }

  /// Effective payroll day (defaults to 1 if not set)
  var effectivePayrollDay: Int {
    payroll_day ?? 1
  }

  /// Effective default view
  var effectiveDefaultView: String {
    default_shifts_view ?? "calendar"
  }

  /// Effective calendar content color style
  var effectiveCalendarContentColorStyle: String {
    guard let style = calendar_content_color_style else { return "workplace" }
    switch style {
    case "workplace", "monochrome":
      return style

    default:
      return "workplace"
    }
  }

  /// Effective dashboard clock button visibility
  var effectiveShowDashboardClockButtons: Bool {
    show_dashboard_clock_buttons ?? true
  }

  /// Effective Wagey AI data sharing consent state.
  var effectiveAIDataSharingEnabled: Bool {
    ai_data_sharing_enabled ?? false
  }

  /// Effective startup tab (defaults to home)
  var effectiveDefaultStartupTab: String {
    guard let tab = default_startup_tab else { return "home" }
    switch tab {
    case "home", "shifts", "add", "stats", "sharing":
      return tab

    default:
      return "home"
    }
  }

  /// Resolve goal for a specific month with override-first fallback to baseline.
  func effectiveMonthlyGoal(year: Int, month: Int) -> Int? {
    let monthKey: String = Self.monthKey(year: year, month: month)
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
  internal static func defaults(for userId: String) -> Self {
    Self(
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
      calendar_content_color_style: "workplace",
      show_dashboard_clock_buttons: true,
      ai_data_sharing_enabled: false,
      half_tax_month: nil,
      currency: nil,
      default_startup_tab: "home",
      wagey_showcase_seen: false
    )
  }
}
