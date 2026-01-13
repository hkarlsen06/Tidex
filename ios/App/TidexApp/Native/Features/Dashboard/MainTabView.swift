import SwiftUI

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

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label(localization.string(Tab.home.localizationKey), systemImage: Tab.home.icon)
                }
                .tag(Tab.home)

            ShiftsPlaceholderView()
                .tabItem {
                    Label(localization.string(Tab.shifts.localizationKey), systemImage: Tab.shifts.icon)
                }
                .tag(Tab.shifts)

            AddShiftPlaceholderView()
                .tabItem {
                    Label(localization.string(Tab.add.localizationKey), systemImage: Tab.add.icon)
                }
                .tag(Tab.add)

            StatsPlaceholderView()
                .tabItem {
                    Label(localization.string(Tab.stats.localizationKey), systemImage: Tab.stats.icon)
                }
                .tag(Tab.stats)

            SharingPlaceholderView()
                .tabItem {
                    Label(localization.string(Tab.sharing.localizationKey), systemImage: Tab.sharing.icon)
                }
                .tag(Tab.sharing)
        }
        .tint(.tidexBlue)
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tidexDarkBackground
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Welcome message
                    VStack(spacing: 8) {
                        Text(localization.string("dashboard.welcome"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.tidexTextPrimary)

                        Text(localization.string("dashboard.subtitle"))
                            .font(.system(size: 16))
                            .foregroundColor(.tidexTextSecondary)
                    }
                    .padding(.top, 40)

                    // Success checkmark
                    ZStack {
                        Circle()
                            .fill(Color.tidexSuccess.opacity(0.1))
                            .frame(width: 100, height: 100)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.tidexSuccess)
                    }

                    // Sign out button (for testing)
                    Button {
                        Task {
                            await coordinator.signOut()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text(localization.string("dashboard.signOut"))
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.tidexError)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.tidexError.opacity(0.1))
                        .cornerRadius(10)
                    }

                    Spacer()

                    // Coming soon notice
                    VStack(spacing: 8) {
                        Text(localization.string("dashboard.comingSoon"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.tidexTextSecondary)

                        Text(localization.string("dashboard.comingSoonDescription"))
                            .font(.system(size: 12))
                            .foregroundColor(.tidexTextMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle(localization.string("dashboard.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexDarkBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Placeholder Views

struct ShiftsPlaceholderView: View {
    @Environment(\.localization) private var localization

    var body: some View {
        NavigationStack {
            PlaceholderContent(
                icon: "calendar",
                title: localization.string("tabs.shifts"),
                description: localization.string("placeholder.shiftsDescription")
            )
            .navigationTitle(localization.string("tabs.shifts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexDarkBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct AddShiftPlaceholderView: View {
    @Environment(\.localization) private var localization

    var body: some View {
        NavigationStack {
            PlaceholderContent(
                icon: "plus.circle.fill",
                title: localization.string("placeholder.addShift"),
                description: localization.string("placeholder.addShiftDescription")
            )
            .navigationTitle(localization.string("placeholder.addShift"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexDarkBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct StatsPlaceholderView: View {
    @Environment(\.localization) private var localization

    var body: some View {
        NavigationStack {
            PlaceholderContent(
                icon: "chart.bar.xaxis",
                title: localization.string("tabs.stats"),
                description: localization.string("placeholder.statsDescription")
            )
            .navigationTitle(localization.string("tabs.stats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexDarkBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct SharingPlaceholderView: View {
    @Environment(\.localization) private var localization

    var body: some View {
        NavigationStack {
            PlaceholderContent(
                icon: "person.2.fill",
                title: localization.string("tabs.sharing"),
                description: localization.string("placeholder.sharingDescription")
            )
            .navigationTitle(localization.string("tabs.sharing"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexDarkBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct PlaceholderContent: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        ZStack {
            Color.tidexDarkBackground
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundColor(.tidexTextMuted)

                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
