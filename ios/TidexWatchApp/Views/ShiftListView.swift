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
      Section {
        summaryHeader
      }
      .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))

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
          ForEach(store.orderedFriendShifts) { shift in
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

  private var summaryHeader: some View {
    VStack(alignment: .leading, spacing: 5) {
      if store.activeShiftCount > 0 {
        Label(store.currentlyActiveTitle, systemImage: "bolt.fill")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.green)
      } else if let nextShift = store.nextRelevantShift {
        HStack(spacing: 6) {
          Image(systemName: "calendar.badge.clock")
            .foregroundStyle(.blue)

          VStack(alignment: .leading, spacing: 1) {
            Text(store.nextShiftTitle)
              .font(.caption2)
              .foregroundStyle(.secondary)
            Text("\(nextShift.personName) · \(store.formattedDate(for: nextShift))")
              .font(.caption2.weight(.semibold))
              .lineLimit(1)
          }
        }
      }

      if store.isStale {
        Label(store.staleDataTitle, systemImage: "exclamationmark.triangle.fill")
          .font(.caption2)
          .foregroundStyle(.orange)
      } else if let updatedAgoText = store.updatedAgoText {
        Text("\(store.updatedTitle) \(updatedAgoText)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
