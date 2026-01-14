import SwiftUI

/// Stats tab view - displays statistics and analytics
/// Currently a placeholder, will be implemented with charts and metrics
struct StatsView: View {
    @Environment(\.localization) private var localization
    @State private var isRefreshing = false

    var body: some View {
        RefreshableTabScreenContainer(
            title: localization.string(AppTab.stats.titleKey),
            onRefresh: {
                // TODO: Implement actual data refresh
                isRefreshing = true
                try? await Task.sleep(nanoseconds: 500_000_000)
                isRefreshing = false
            }
        ) {
            TabPlaceholder(tab: .stats)
        }
    }
}

#Preview {
    StatsView()
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
