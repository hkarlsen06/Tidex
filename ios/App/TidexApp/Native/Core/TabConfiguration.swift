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
    var localizationKey: LocalizedStringResource {
        switch self {
        case .home: return .tabsHome
        case .shifts: return .tabsShifts
        case .add: return .tabsAdd
        case .stats: return .tabsStats
        case .sharing: return .tabsSharing
        }
    }

    /// Title localization key for navigation bar
    var titleKey: LocalizedStringResource {
        switch self {
        case .home: return .dashboardTitle
        case .shifts: return .tabsShifts
        case .add: return .placeholderAddShift
        case .stats: return .tabsStats
        case .sharing: return .tabsSharing
        }
    }

    /// Description key for placeholder views
    var descriptionKey: LocalizedStringResource {
        switch self {
        case .home: return .placeholderDashboardDescription
        case .shifts: return .placeholderShiftsDescription
        case .add: return .placeholderAddShiftDescription
        case .stats: return .placeholderStatsDescription
        case .sharing: return .placeholderSharingDescription
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
