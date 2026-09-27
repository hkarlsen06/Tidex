// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_enum_raw_value explicit_top_level_acl sorted_enum_cases
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable switch_case_on_newline
import Foundation

/// Centralized tab configuration for the app
/// Each tab represents a main section of the app, making it easy to add new tabs
enum AppTab: String, CaseIterable, Identifiable {
  case home
  case shifts
  case add
  case wagey
  case sharing

  var id: String { rawValue }

  /// SF Symbol icon for the tab
  var icon: String {
    switch self {
    case .home: return "house.fill"
    case .shifts: return "calendar"
    case .add: return "plus.capsule.fill"
    case .wagey: return "sparkles"
    case .sharing: return "person.2.fill"
    }
  }

  /// Localization key for tab label
  var localizationKey: LocalizedStringResource {
    switch self {
    case .home: return .tabsHome
    case .shifts: return .tabsShifts
    case .add: return .tabsAdd
    case .wagey: return .tabsWagey
    case .sharing: return .tabsSharing
    }
  }

  /// Whether this tab supports pull-to-refresh
  var supportsRefresh: Bool {
    switch self {
    case .home, .shifts, .sharing:
      return true

    case .add, .wagey:
      return false
    }
  }
}
