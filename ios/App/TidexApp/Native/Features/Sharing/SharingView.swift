import SwiftUI

/// Sharing tab view - displays shift sharing functionality
/// Currently a placeholder, will be implemented with sharing features
struct SharingView: View {
    @Environment(\.localization) private var localization
    @State private var isRefreshing = false

    var body: some View {
        RefreshableTabScreenContainer(
            title: localization.string(AppTab.sharing.titleKey),
            onRefresh: {
                // TODO: Implement actual data refresh
                isRefreshing = true
                try? await Task.sleep(nanoseconds: 500_000_000)
                isRefreshing = false
            }
        ) {
            TabPlaceholder(tab: .sharing)
        }
    }
}

#Preview {
    SharingView()
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
