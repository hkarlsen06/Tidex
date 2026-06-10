// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_enum_raw_value explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_types_order prefer_self_in_static_references type_contents_order
import Foundation

// MARK: - Calendar Day Info

/// Represents a single day cell in a calendar grid
/// Shared across all calendar views (Shifts, Add Shift, Friends)
struct CalendarDayInfo: Identifiable, Equatable {
  /// Stable slot identity within a single rendered month grid.
  /// The month grid itself is remounted across month changes so SwiftUI treats
  /// the entire month swap atomically instead of diffing individual day cells.
  let id: Int
  let dayNumber: Int
  let dateISO: String?
  let weekNumber: Int?  // ISO week number (only on Mondays)
  let isOutsideMonth: Bool

  /// Create a day info for a day within the current month
  static func inMonth(id: Int, dayNumber: Int, dateISO: String, weekNumber: Int?) -> Self {
    Self(
      id: id,
      dayNumber: dayNumber,
      dateISO: dateISO,
      weekNumber: weekNumber,
      isOutsideMonth: false
    )
  }

  /// Create a day info for a day outside the current month (prev/next month padding)
  static func outsideMonth(id: Int, dayNumber: Int, dateISO: String, weekNumber: Int?)
    -> Self
  {
    Self(
      id: id,
      dayNumber: dayNumber,
      dateISO: dateISO,
      weekNumber: weekNumber,
      isOutsideMonth: true
    )
  }
}

// MARK: - Hours Data

/// Time range data for displaying shift hours in a calendar cell
struct HoursData: Equatable {
  let start: String
  let end: String
  let crossesMidnight: Bool
}

/// Earnings breakdown for calendar cells
struct CalendarEarningsData: Equatable {
  /// Amount after tax (or gross when tax is disabled)
  let net: Double
  /// Amount before tax
  let gross: Double
  /// Whether tax is enabled for this day
  let hasTaxEnabled: Bool
}

// MARK: - Calendar View Mode

/// Mode for displaying data in calendar cells (hours or money)
enum CalendarViewMode: String, CaseIterable {
  case hours
  case money

  /// UserDefaults key for persisting view mode
  static let userDefaultsKey = "shifts_calendar_view_mode"

  /// Save the current mode to UserDefaults
  func save() {
    UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
  }

  /// Load saved mode from UserDefaults (defaults to hours)
  static func load() -> Self {
    guard let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
      let mode = Self(rawValue: rawValue)
    else {
      return .hours
    }
    return mode
  }
}
