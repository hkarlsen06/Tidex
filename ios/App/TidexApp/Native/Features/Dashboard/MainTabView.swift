import SwiftUI

/// Main tab view for authenticated users
/// Orchestrates navigation between the main app tabs
/// Each tab has its own view in the Features folder
struct MainTabView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization

    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label(
                        localization.string(AppTab.home.localizationKey),
                        systemImage: AppTab.home.icon
                    )
                }
                .tag(AppTab.home)

            ShiftsView()
                .tabItem {
                    Label(
                        localization.string(AppTab.shifts.localizationKey),
                        systemImage: AppTab.shifts.icon
                    )
                }
                .tag(AppTab.shifts)

            AddShiftView()
                .tabItem {
                    Label(
                        localization.string(AppTab.add.localizationKey),
                        systemImage: AppTab.add.icon
                    )
                }
                .tag(AppTab.add)

            StatsView()
                .tabItem {
                    Label(
                        localization.string(AppTab.stats.localizationKey),
                        systemImage: AppTab.stats.icon
                    )
                }
                .tag(AppTab.stats)

            SharingView()
                .tabItem {
                    Label(
                        localization.string(AppTab.sharing.localizationKey),
                        systemImage: AppTab.sharing.icon
                    )
                }
                .tag(AppTab.sharing)
        }
        .tint(.tidexBlue)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
