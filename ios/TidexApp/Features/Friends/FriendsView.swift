import SwiftUI

/// Sharing tab view - displays shifts from users who share with the current user
/// Fetches shared shifts from the Next.js API for proper payroll computation
struct SharingView: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @Environment(\.userCurrency) private var currency

  /// Binding to the selected tab for navigation
  @Binding var selectedTab: MainTabView.Tab

  /// Binding to communicate sharer selection state to parent
  @Binding var hasSelectedSharer: Bool

  @StateObject private var viewModel = SharingViewModel()

  /// Navigation path for push navigation (friend detail slides in from right)
  @State private var navigationPath = NavigationPath()

  /// State for showing the manage sharing sheet
  @State private var showManageSheet = false

  /// User ID to highlight in the manage sheet (from deep link)
  @State private var highlightUserId: String?

  /// Whether to auto-expand the add friend form when the manage sheet opens
  @State private var autoExpandAddForm = false

  /// Dates to highlight in the calendar (from shared shift notification)
  @State private var highlightDates: Set<String> = []

  /// Shift IDs to highlight in the calendar (from changes array in notification)
  @State private var highlightShiftIds: Set<String> = []

  /// Duration to show highlight before auto-clearing (3 seconds)
  private static let highlightDuration: TimeInterval = 3.0

  var body: some View {
    NavigationStack(path: $navigationPath) {
      ZStack {
        // Background that fills entire screen including safe areas
        Color.tidexBackground
          .ignoresSafeArea()

        // Always show sharer list as root content
        sharerListView
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .navigationBarTitleDisplayMode(.inline)
      .iPadToolbarBackground()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          TodayDateLabel()
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .topBarTrailing) {
          UserMenuButton(
            displayName: coordinator.userDisplayName,
            avatarUrl: coordinator.userAvatarUrl
          )
        }
      }
      .navigationDestination(for: SharedUser.self) { sharer in
        SharedShiftsDetailView(
          sharer: sharer,
          viewModel: viewModel,
          highlightDates: $highlightDates,
          highlightShiftIds: $highlightShiftIds
        )
        .toolbarRole(.editor)
      }
      .iPadToolbarTransaction()
    }
    .task {
      await viewModel.loadSharers()
    }
    .onReceive(NotificationCenter.default.publisher(for: .tabReselected)) { notification in
      // Handle tab reselection - if sharing tab is tapped again while viewing a sharer,
      // navigate back to the sharer list
      guard let tab = notification.userInfo?["tab"] as? MainTabView.Tab,
        tab == .sharing,
        !navigationPath.isEmpty
      else {
        return
      }

      navigationPath = NavigationPath()
      viewModel.deselectSharer()
    }
    .sheet(
      isPresented: $showManageSheet,
      onDismiss: {
        // Clear state when sheet is dismissed
        highlightUserId = nil
        autoExpandAddForm = false
      }
    ) {
      ManageSharingSheet(
        highlightUserId: highlightUserId,
        autoExpandAddForm: autoExpandAddForm,
        onVisibilityChange: {
          // Refresh sharers list when visibility changes (block/unblock)
          Task {
            await viewModel.loadSharers(forceRefreshPreviews: true)
          }
        }
      )
    }
    .onChange(of: coordinator.pendingDeepLink) { _, deepLink in
      handlePendingDeepLink(deepLink)
    }
    .onAppear {
      // Handle any pending deep link on initial appearance
      handlePendingDeepLink(coordinator.pendingDeepLink)
      // Sync initial state
      hasSelectedSharer = !navigationPath.isEmpty
    }
    .onChange(of: navigationPath) { _, path in
      // Sync sharer selection state with parent for shared month picker visibility
      let hasSharer = !path.isEmpty
      hasSelectedSharer = hasSharer

      // When user navigates back (automatic back button or swipe), deselect sharer
      if !hasSharer && viewModel.selectedSharer != nil {
        viewModel.deselectSharer()
      }
    }
  }

  // MARK: - Deep Link Handling

  /// Handle pending deep link from AppCoordinator
  /// Navigates to a specific sharer or opens the manage modal
  private func handlePendingDeepLink(_ deepLink: AppCoordinator.DeepLink?) {
    guard let deepLink = deepLink else { return }

    switch deepLink {
    case .sharing(let sharerId, let dates, let changes):
      if let sharerId = sharerId {
        // Wait for sharers to load, then select the sharer
        Task {
          // Wait for sharers to be loaded if still loading
          await viewModel.waitForSharersLoaded()

          // Find and select the sharer
          if let sharer = viewModel.sharers.first(where: { $0.id == sharerId }) {
            navigationPath = NavigationPath()
            viewModel.selectSharer(sharer)
            navigationPath.append(sharer)

            // Extract shift IDs for precise highlighting (excludes deleted shifts)
            if let changes = changes, !changes.isEmpty {
              let shiftIds = changes.filter { $0.op != "deleted" }.map(\.shiftId)
              highlightShiftIds = Set(shiftIds)
            }

            // If dates were provided, navigate to the correct month and set highlight
            if let dates = dates, let firstDate = dates.first,
              let date = Date.fromISODateString(firstDate)
            {
              let calendar = Calendar.current
              let components = calendar.dateComponents([.year, .month], from: date)
              if let year = components.year, let month = components.month {
                // Navigate to the month containing the highlighted shifts
                SharedMonthContext.shared.navigateTo(year: year, month: month)
              }

              // Set highlight dates for the calendar (fallback for older payloads without shift IDs)
              highlightDates = Set(dates)

              // Clear highlights after a delay
              Task {
                try? await Task.sleep(nanoseconds: UInt64(Self.highlightDuration * 1_000_000_000))
                withAnimation(.easeOut(duration: 0.3)) {
                  highlightDates = []
                  highlightShiftIds = []
                }
              }
            }
          }
        }
      }
      coordinator.clearPendingDeepLink()

    case .sharingManage(let highlightId):
      // Open manage modal with optional highlight
      highlightUserId = highlightId
      showManageSheet = true
      coordinator.clearPendingDeepLink()

    case .shifts:
      // Not handled here - ShiftsView will handle this
      break

    case .addShift:
      // Not handled here - AddShiftView will handle this
      break

    case .feedback, .adminFeedback:
      // Not handled here - MainTabView handles these
      break
    }
  }

  // MARK: - Sharer List

  private var sharerListView: some View {
    ScrollView {
      VStack(spacing: Spacing.md) {
        // Title and manage button row
        HStack {
          // "Friends" / "Venner" title
          Text(.sharingFriendsTitle)
            .font(.tidexTitle2)
            .foregroundColor(.tidexTextPrimary)

          Spacer()

          // Liquid glass manage button
          Button(action: {
            showManageSheet = true
          }) {
            HStack(spacing: Spacing.xxxs) {
              Image(systemName: "person.2")
                .font(.tidexSubheadline)
              Text(.sharingSeeFriends)
                .font(.tidexLabel)
            }
            .foregroundColor(.tidexTextPrimary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
          }
          .buttonStyle(PlainButtonStyle())
          .tidexGlass(shape: .capsule, interactive: true)
        }
        .padding(.horizontal, Spacing.md)

        // Sharer list
        SharerListView(
          sharers: viewModel.sharers,
          selectedSharer: viewModel.selectedSharer,
          shiftPreviews: viewModel.shiftPreviews,
          isLoading: viewModel.isLoadingSharers,
          isLoadingPreviews: viewModel.isLoadingPreviews,
          isRefreshing: viewModel.isRefreshing,
          onSelectSharer: { sharer in
            viewModel.selectSharer(sharer)
            navigationPath.append(sharer)
          },
          onAddFriend: {
            autoExpandAddForm = true
            showManageSheet = true
          }
        )
      }
      .frame(maxWidth: AdaptiveMaxWidth.tabContent)
      .padding(.top, Spacing.md)
      .padding(.bottom, Spacing.xl)
      .frame(maxWidth: .infinity)
    }
    .refreshable {
      await viewModel.refresh()
    }
  }

}

// MARK: - Shared Shifts Detail View (pushed from friend list)

/// Detail view shown when tapping a friend card
/// Displays the friend's shifts in a calendar/list with month navigation
private struct SharedShiftsDetailView: View {
  let sharer: SharedUser
  @ObservedObject var viewModel: SharingViewModel
  @Binding var highlightDates: Set<String>
  @Binding var highlightShiftIds: Set<String>

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      SharedShiftsListView(
        sharer: sharer,
        shifts: viewModel.sharedShifts,
        year: viewModel.committedYear,
        month: viewModel.committedMonth,
        isLoading: viewModel.isLoadingShifts,
        highlightDates: highlightDates,
        highlightShiftIds: highlightShiftIds,
        isSuperimposing: viewModel.isSuperimposing,
        userHoursByDate: viewModel.isSuperimposing ? viewModel.userHoursByDate : nil
      )
      .frame(maxWidth: AdaptiveMaxWidth.tabContent)
      .frame(maxWidth: .infinity)
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      // Superimpose toggle
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          viewModel.toggleSuperimpose()
        } label: {
          Image(systemName: "rectangle.on.rectangle")
            .font(.tidexBodyMedium)
            .foregroundColor(viewModel.isSuperimposing ? .tidexBlue : .tidexTextMuted)
        }
      }

      ToolbarSpacer(.fixed, placement: .topBarTrailing)

      // Friend display using UserMenuButton in display-only mode
      ToolbarItem(placement: .topBarTrailing) {
        UserMenuButton(
          displayName: sharer.displayName,
          avatarUrl: sharer.avatarUrl,
          interactive: false
        )
        .fixedSize(horizontal: true, vertical: false)
      }
    }
  }
}

#Preview {
  struct PreviewWrapper: View {
    @State private var selectedTab: MainTabView.Tab = .sharing
    @State private var hasSelectedSharer = false

    var body: some View {
      SharingView(selectedTab: $selectedTab, hasSelectedSharer: $hasSelectedSharer)
        .environmentObject(AppCoordinator.shared)
        .environment(\.userCurrency, "kr")
    }
  }

  return PreviewWrapper()
}
