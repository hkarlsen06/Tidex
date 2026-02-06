import SwiftUI
import UIKit

/// Sharing tab view - displays shifts from users who share with the current user
/// Fetches shared shifts from the Next.js API for proper payroll computation
struct SharingView: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @Environment(\.userCurrency) private var currency
  @Environment(\.layoutDirection) private var layoutDirection

  /// Binding to the selected tab for navigation
  @Binding var selectedTab: MainTabView.Tab

  /// Binding to communicate sharer selection state to parent
  @Binding var hasSelectedSharer: Bool

  @StateObject private var viewModel = SharingViewModel()

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

  // iPad detection - hide logo on iPad
  private var isIPad: Bool {
    UIDevice.current.userInterfaceIdiom == .pad
  }

  var body: some View {
    NavigationStack {
      ZStack {
        // Background that fills entire screen including safe areas
        Color.tidexBackground
          .ignoresSafeArea()

        // Main content - month picker is now in shared overlay
        contentView
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .navigationBarTitleDisplayMode(.inline)
      .iPadToolbarBackground()
      .toolbar {
        // Date label or back button when viewing a sharer
        ToolbarItem(placement: .topBarLeading) {
          if viewModel.selectedSharer == nil {
            TodayDateLabel()
          }
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarLeading) {
          if viewModel.selectedSharer != nil {
            Button(action: {
              withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.deselectSharer()
              }
            }) {
              HStack(spacing: 6) {
                Image(
                  systemName: layoutDirection == .rightToLeft ? "chevron.right" : "chevron.left"
                )
                .font(.system(size: 16, weight: .semibold))
                Text(.commonBack)
                  .font(.system(size: 17))
              }
              .foregroundColor(.tidexBlue)
            }
          }
        }

        // Title area - show sharer info when viewing a sharer (iPhone only)
        ToolbarItem(placement: .principal) {
          if let sharer = viewModel.selectedSharer, !isIPad {
            // Show sharer info in center on iPhone
            sharerToolbarInfo(sharer: sharer)
          }
        }

        // Trailing area - superimpose toggle on iPhone, sharer info on iPad
        ToolbarItem(placement: .topBarTrailing) {
          if let sharer = viewModel.selectedSharer {
            if isIPad {
              // Show sharer info on right side for iPad
              sharerToolbarInfo(sharer: sharer)
            } else {
              // Show superimpose toggle button on iPhone
              superimposeToggleButton
            }
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          // Only show when not viewing a sharer
          if viewModel.selectedSharer == nil {
            // User menu only
            UserMenuButton(
              displayName: coordinator.userDisplayName,
              avatarUrl: coordinator.userAvatarUrl
            )
          }
        }
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
        viewModel.selectedSharer != nil
      else {
        return
      }

      withAnimation(.easeInOut(duration: 0.2)) {
        viewModel.deselectSharer()
      }
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
      hasSelectedSharer = viewModel.selectedSharer != nil
    }
    .onChange(of: viewModel.selectedSharer) { _, sharer in
      // Sync sharer selection state with parent for shared month picker visibility
      hasSelectedSharer = sharer != nil
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
            withAnimation(.easeInOut(duration: 0.2)) {
              viewModel.selectSharer(sharer)
            }

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

    case .tab:
      // Not handled here - MainTabView handles tab navigation
      break
    }
  }

  // MARK: - Content View

  @ViewBuilder
  private var contentView: some View {
    if viewModel.selectedSharer != nil {
      // Show shifts for selected sharer
      sharedShiftsView
    } else {
      // Show sharer list
      sharerListView
    }
  }

  // MARK: - Sharer List

  private var sharerListView: some View {
    ScrollView {
      VStack(spacing: 16) {
        // Title and manage button row
        HStack {
          // "Friends" / "Venner" title
          Text(.sharingFriendsTitle)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.tidexTextPrimary)

          Spacer()

          // Liquid glass manage button
          Button(action: {
            showManageSheet = true
          }) {
            HStack(spacing: 6) {
              Image(systemName: "gearshape")
                .font(.system(size: 14))
              Text(.sharingManageTitle)
                .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.tidexTextPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
          }
          .buttonStyle(PlainButtonStyle())
          .tidexGlass(shape: .capsule, interactive: true)
        }
        .padding(.horizontal, 16)

        // Sharer list
        SharerListView(
          sharers: viewModel.sharers,
          selectedSharer: viewModel.selectedSharer,
          shiftPreviews: viewModel.shiftPreviews,
          isLoading: viewModel.isLoadingSharers,
          isLoadingPreviews: viewModel.isLoadingPreviews,
          isRefreshing: viewModel.isRefreshing,
          onSelectSharer: { sharer in
            withAnimation(.easeInOut(duration: 0.2)) {
              viewModel.selectSharer(sharer)
            }
          },
          onAddFriend: {
            autoExpandAddForm = true
            showManageSheet = true
          }
        )
      }
      .frame(maxWidth: AdaptiveMaxWidth.tabContent)
      .padding(.top, 16)
      .padding(.bottom, 32)
      .frame(maxWidth: .infinity)
    }
    .refreshable {
      await viewModel.refresh()
    }
  }

  // MARK: - Shared Shifts View

  @ViewBuilder
  private var sharedShiftsView: some View {
    if let sharer = viewModel.selectedSharer {
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
      .monthSwipeGesture(
        onSwipeLeft: {
          viewModel.goToNextMonth()
        },
        onSwipeRight: {
          viewModel.goToPreviousMonth()
        }
      )
      .background(
        EdgeSwipeBackGesture {
          withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.deselectSharer()
          }
        }
      )
    }
  }

  // MARK: - Helper Views

  /// Sharer name and avatar for toolbar display
  private func sharerToolbarInfo(sharer: SharedUser) -> some View {
    HStack(spacing: 8) {
      AvatarView(
        url: sharer.avatarUrl,
        initials: sharer.initials,
        size: AvatarView.Size.small
      )

      Text(sharer.firstNameOnly)
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(.tidexTextPrimary)
        .lineLimit(1)
        .truncationMode(.tail)
    }
  }

  /// Superimpose toggle button in the toolbar
  /// Allows overlaying user's own shifts on friend's calendar
  private var superimposeToggleButton: some View {
    Button {
      viewModel.toggleSuperimpose()
    } label: {
      Image(systemName: "rectangle.on.rectangle")
        .font(.system(size: 17, weight: .medium))
        .foregroundColor(viewModel.isSuperimposing ? .tidexBlue : .tidexTextMuted)
    }
  }

}

// MARK: - Edge Swipe Back Gesture

/// A UIViewRepresentable that adds a screen edge pan gesture for back navigation
/// Uses UIScreenEdgePanGestureRecognizer to detect swipes from the left edge
private struct EdgeSwipeBackGesture: UIViewRepresentable {
  let onSwipeBack: () -> Void

  func makeUIView(context: Context) -> UIView {
    let view = EdgeSwipeView()
    view.backgroundColor = .clear

    let edgeGesture = UIScreenEdgePanGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handleEdgeSwipe(_:))
    )
    edgeGesture.edges = .left
    edgeGesture.delaysTouchesBegan = false
    edgeGesture.delaysTouchesEnded = false
    view.addGestureRecognizer(edgeGesture)

    context.coordinator.view = view

    return view
  }

  func updateUIView(_: UIView, context: Context) {
    context.coordinator.onSwipeBack = onSwipeBack
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onSwipeBack: onSwipeBack)
  }

  class Coordinator: NSObject {
    var onSwipeBack: () -> Void
    weak var view: UIView?
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private var hasTriggeredAction = false

    init(onSwipeBack: @escaping () -> Void) {
      self.onSwipeBack = onSwipeBack
      super.init()
      haptic.prepare()
    }

    @objc func handleEdgeSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
      guard let view = view else { return }

      let translation = gesture.translation(in: view)
      let threshold: CGFloat = 80

      switch gesture.state {
      case .changed:
        // Trigger haptic when threshold is reached
        if translation.x >= threshold && !hasTriggeredAction {
          haptic.impactOccurred()
          hasTriggeredAction = true
        }
      case .ended, .cancelled:
        if hasTriggeredAction || translation.x >= threshold {
          onSwipeBack()
        }
        hasTriggeredAction = false
        haptic.prepare()
      default:
        break
      }
    }
  }
}

/// A UIView that moves its gesture recognizers to the parent scroll view
private class EdgeSwipeView: UIView {
  private var movedGestures = false

  override func didMoveToWindow() {
    super.didMoveToWindow()

    guard !movedGestures, window != nil else { return }
    movedGestures = true

    // Find parent scroll view and add gesture there for better recognition
    if let scrollView = findScrollView() {
      gestureRecognizers?.forEach { gesture in
        removeGestureRecognizer(gesture)
        scrollView.addGestureRecognizer(gesture)
      }
    }
  }

  private func findScrollView() -> UIScrollView? {
    var view: UIView? = superview
    while let current = view {
      if let scrollView = current as? UIScrollView {
        return scrollView
      }
      view = current.superview
    }
    return nil
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
