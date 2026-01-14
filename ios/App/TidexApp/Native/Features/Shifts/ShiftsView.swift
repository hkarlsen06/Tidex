import SwiftUI

/// Shifts tab view - displays list of user's shifts
/// Currently a placeholder, will be implemented with full shift list functionality
struct ShiftsView: View {
    @Environment(\.localization) private var localization
    @State private var isRefreshing = false

    var body: some View {
        RefreshableTabScreenContainer(
            title: localization.string(AppTab.shifts.titleKey),
            onRefresh: {
                // TODO: Implement actual data refresh
                isRefreshing = true
                try? await Task.sleep(nanoseconds: 500_000_000)
                isRefreshing = false
            }
        ) {
            TabPlaceholder(tab: .shifts)
        }
    }
}

#Preview {
    ShiftsView()
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
