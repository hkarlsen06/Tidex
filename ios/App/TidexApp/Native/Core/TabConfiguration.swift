import SwiftUI

/// Centralized tab configuration for the app
/// Each tab represents a main section of the app, making it easy to add new tabs
enum AppTab: String, CaseIterable, Identifiable {
    case home
    case shifts
    case add
    case stats
    case sharing

    var id: String { rawValue }

    /// SF Symbol icon for the tab
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .shifts: return "calendar"
        case .add: return "plus.circle.fill"
        case .stats: return "chart.bar.xaxis"
        case .sharing: return "person.2.fill"
        }
    }

    /// Localization key for tab label
    var localizationKey: String {
        switch self {
        case .home: return "tabs.home"
        case .shifts: return "tabs.shifts"
        case .add: return "tabs.add"
        case .stats: return "tabs.stats"
        case .sharing: return "tabs.sharing"
        }
    }

    /// Title localization key for navigation bar
    var titleKey: String {
        switch self {
        case .home: return "dashboard.title"
        case .shifts: return "tabs.shifts"
        case .add: return "placeholder.addShift"
        case .stats: return "tabs.stats"
        case .sharing: return "tabs.sharing"
        }
    }

    /// Description key for placeholder views
    var descriptionKey: String {
        switch self {
        case .home: return "placeholder.dashboardDescription"
        case .shifts: return "placeholder.shiftsDescription"
        case .add: return "placeholder.addShiftDescription"
        case .stats: return "placeholder.statsDescription"
        case .sharing: return "placeholder.sharingDescription"
        }
    }

    /// Whether this tab supports pull-to-refresh
    var supportsRefresh: Bool {
        switch self {
        case .home, .shifts, .stats, .sharing:
            return true
        case .add:
            return false
        }
    }
}
