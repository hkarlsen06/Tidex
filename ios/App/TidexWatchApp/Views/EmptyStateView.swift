import SwiftUI

/// Empty state view shown when no shift data is available
/// Prompts user to open Tidex on iPhone to sync
struct EmptyStateView: View {
    @Environment(WatchDataStore.self) private var store
    @Environment(WatchConnectivityManager.self) private var connectivity

    var body: some View {
        ContentUnavailableView {
            Label(store.noShiftsTitle, systemImage: "calendar.badge.clock")
        } description: {
            Text(store.syncInstructionText)
        } actions: {
            if connectivity.isReachable {
                Button(store.refreshButtonTitle) {
                    connectivity.requestRefresh()
                }
                .disabled(connectivity.isRefreshing)
            }
        }
    }
}

#Preview {
    EmptyStateView()
        .environment(WatchDataStore.shared)
        .environment(WatchConnectivityManager.shared)
}
