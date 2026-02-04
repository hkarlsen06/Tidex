import SwiftUI

/// Main shift list view for the Watch app
/// Shows user's shift at top, followed by friends' shifts
struct ShiftListView: View {
    @Environment(WatchDataStore.self) private var store
    @Environment(WatchConnectivityManager.self) private var connectivity

    var body: some View {
        NavigationStack {
            Group {
                if store.hasData {
                    shiftList
                } else {
                    EmptyStateView()
                }
            }
            .navigationTitle(store.shiftsTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    refreshButton
                }
            }
        }
    }

    // MARK: - Shift List

    private var shiftList: some View {
        List {
            // User's shift section
            if let userShift = store.userShift {
                Section(store.myShiftTitle) {
                    ShiftRowView(
                        shift: userShift,
                        isCurrentUser: true,
                        isRefreshing: connectivity.isRefreshing
                    )
                }
            }

            // Friends' shifts section
            if !store.friendShifts.isEmpty {
                Section(store.friendsTitle) {
                    ForEach(store.friendShifts) { shift in
                        ShiftRowView(
                            shift: shift,
                            isCurrentUser: false,
                            isRefreshing: connectivity.isRefreshing
                        )
                    }
                }
            }
        }
    }

    // MARK: - Refresh Button

    private var refreshButton: some View {
        Button {
            connectivity.requestRefresh()
        } label: {
            if connectivity.isRefreshing {
                ProgressView()
            } else if connectivity.lastRefreshFailed {
                // Show error state briefly after failed refresh
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        // Enable when either iPhone is reachable OR we have a valid API token
        .disabled(!connectivity.canRefresh || connectivity.isRefreshing)
    }
}

#Preview {
    ShiftListView()
        .environment(WatchDataStore.shared)
        .environment(WatchConnectivityManager.shared)
}
