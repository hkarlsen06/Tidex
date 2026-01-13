import Foundation

// MARK: - User Settings

/// User settings from the user_settings table
/// Contains global calendar and payroll preferences
struct UserSettings: Codable, Equatable {
    let user_id: String?
    /// Month number (11=November, 12=December) for half tax deduction
    let half_tax_month: Int?
    /// Day of month for payroll (1-31)
    let payroll_day: Int?
    /// Monthly earnings goal
    let monthly_goal: Double?
    /// Default view for shifts (calendar, list, etc.)
    let default_shifts_view: String?

    /// Effective payroll day (defaults to 1 if not set)
    var effectivePayrollDay: Int {
        payroll_day ?? 1
    }

    /// Effective default view
    var effectiveDefaultView: String {
        default_shifts_view ?? "calendar"
    }

    /// Static default settings for when user has no settings
    static var defaults: UserSettings {
        UserSettings(
            user_id: nil,
            half_tax_month: nil,
            payroll_day: 1,
            monthly_goal: nil,
            default_shifts_view: "calendar"
        )
    }
}
