import SwiftUI

// MARK: - Tab Reselection Notification

extension Notification.Name {
    /// Posted when a tab is tapped while already selected
    static let tabReselected = Notification.Name("tabReselected")
}

/// Main tab view for authenticated users
/// This is the home screen after successful login
/// Currently a placeholder - will be expanded with full dashboard functionality
struct MainTabView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization

    @State private var selectedTab: Tab = .home

    enum Tab: String, CaseIterable {
        case home
        case shifts
        case add
        case stats
        case sharing

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .shifts: return "calendar"
            case .add: return "plus.circle.fill"
            case .stats: return "chart.bar.xaxis"
            case .sharing: return "person.2.fill"
            }
        }

        var localizationKey: String {
            switch self {
            case .home: return "tabs.home"
            case .shifts: return "tabs.shifts"
            case .add: return "tabs.add"
            case .stats: return "tabs.stats"
            case .sharing: return "tabs.sharing"
            }
        }
    }

    /// Custom binding that detects tab reselection and posts notification
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == selectedTab {
                    // Same tab tapped again - post notification
                    NotificationCenter.default.post(
                        name: .tabReselected,
                        object: nil,
                        userInfo: ["tab": newTab]
                    )
                } else {
                    selectedTab = newTab
                }
            }
        )
    }

    var body: some View {
        ZStack {
            // Background that fills entire screen including safe areas
            // Prevents black bars from showing behind tab content
            Color.tidexBackground
                .ignoresSafeArea()

            TabView(selection: tabSelection) {
                DashboardView(selectedTab: $selectedTab)
                    .tabItem {
                        Label(localization.string(Tab.home.localizationKey), systemImage: Tab.home.icon)
                    }
                    .tag(Tab.home)

                ShiftsView(selectedTab: $selectedTab)
                    .tabItem {
                        Label(localization.string(Tab.shifts.localizationKey), systemImage: Tab.shifts.icon)
                    }
                    .tag(Tab.shifts)

                AddShiftView(selectedTab: $selectedTab)
                    .tabItem {
                        Label(localization.string(Tab.add.localizationKey), systemImage: Tab.add.icon)
                    }
                    .tag(Tab.add)

                StatsPlaceholderView()
                    .tabItem {
                        Label(localization.string(Tab.stats.localizationKey), systemImage: Tab.stats.icon)
                    }
                    .tag(Tab.stats)

                SharingView(selectedTab: $selectedTab)
                    .tabItem {
                        Label(localization.string(Tab.sharing.localizationKey), systemImage: Tab.sharing.icon)
                    }
                    .tag(Tab.sharing)
            }
            .tint(.tidexBlue)
        }
    }
}

// MARK: - Placeholder Views

/// Generic placeholder tab view that reduces duplication
/// Used for tabs that are not yet implemented
struct PlaceholderTabView: View {
    let icon: String
    let titleKey: String
    let descriptionKey: String
    let supportsRefresh: Bool

    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization

    init(
        icon: String,
        titleKey: String,
        descriptionKey: String,
        supportsRefresh: Bool = true
    ) {
        self.icon = icon
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.supportsRefresh = supportsRefresh
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // Background that fills entire screen including safe areas
                    // Prevents black bars from showing in status bar and home indicator areas
                    Color.tidexBackground
                        .ignoresSafeArea()

                    ScrollView {
                        PlaceholderContent(
                            icon: icon,
                            title: localization.string(titleKey),
                            description: localization.string(descriptionKey)
                        )
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height - 200)
                    }
                    .applyRefreshable(enabled: supportsRefresh)
                }
            }
            .navigationTitle(localization.string(titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    UserMenuButton(
                        displayName: coordinator.userDisplayName,
                        avatarUrl: coordinator.userAvatarUrl
                    )
                }
            }
        }
    }
}

// MARK: - Refreshable Extension

private extension View {
    @ViewBuilder
    func applyRefreshable(enabled: Bool) -> some View {
        if enabled {
            self.refreshable {
                // Placeholder for future data refresh
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        } else {
            self
        }
    }
}

// MARK: - Concrete Placeholder Views

/// These type aliases maintain backwards compatibility while using the generic PlaceholderTabView
struct ShiftsPlaceholderView: View {
    var body: some View {
        PlaceholderTabView(
            icon: "calendar",
            titleKey: "tabs.shifts",
            descriptionKey: "placeholder.shiftsDescription"
        )
    }
}

struct AddShiftPlaceholderView: View {
    var body: some View {
        PlaceholderTabView(
            icon: "plus.circle.fill",
            titleKey: "tabs.add",
            descriptionKey: "placeholder.addShiftDescription",
            supportsRefresh: false
        )
    }
}

struct StatsPlaceholderView: View {
    var body: some View {
        PlaceholderTabView(
            icon: "chart.bar.xaxis",
            titleKey: "tabs.stats",
            descriptionKey: "placeholder.statsDescription"
        )
    }
}

struct SharingPlaceholderView: View {
    var body: some View {
        PlaceholderTabView(
            icon: "person.2.fill",
            titleKey: "tabs.sharing",
            descriptionKey: "placeholder.sharingDescription"
        )
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
