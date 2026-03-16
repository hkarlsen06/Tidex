import SwiftUI
import UIKit

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
  @State private var deepLinkNavigationTask: Task<Void, Never>?
  @State private var highlightClearTask: Task<Void, Never>?
  @State private var openingThreadUserId: String?
  @State private var openingThreadId: String?
  @State private var activeChatHighlightUserId: String?
  @State private var chatOpenErrorMessage: String?
  @State private var unreadChatUserIds: Set<String> = []
  @State private var unreadChatCountsByUserId: [String: Int] = [:]
  @State private var chatPreviewsByUserId: [String: FriendCardMessagePreview] = [:]
  @State private var unreadRefreshTask: Task<Void, Never>?

  /// Duration to show highlight before auto-clearing (3 seconds)
  private static let highlightDuration: TimeInterval = 3.0

  private let friendsMessagingService = FriendsMessagingService.shared
  private let friendsMessagesRepository = FriendsMessagesRepository.shared

  var body: some View {
    NavigationStack(path: $navigationPath) {
      ZStack {
        // Background that fills entire screen including safe areas
        TidexAppBackground()

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
          highlightShiftIds: $highlightShiftIds,
          onMessageTapped: { sharedUser in
            Task {
              await openChat(for: sharedUser)
            }
          }
        )
        .toolbarRole(.editor)
        .onAppear {
          hasSelectedSharer = true
        }
      }
      .navigationDestination(for: FriendChatRoute.self) { route in
        FriendsThreadView(
          route: route,
          viewerUserId: coordinator.getCurrentUserId() ?? ""
        )
        .onAppear {
          hasSelectedSharer = false
        }
        .onDisappear {
          activeChatHighlightUserId = nil
          hasSelectedSharer = viewModel.selectedSharer != nil
        }
      }
      .iPadToolbarTransaction()
    }
    .task {
      await viewModel.loadSharers()
      scheduleChatMetadataRefresh()
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
          // Refresh sharers list when visibility changes (hide/show)
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
      hasSelectedSharer = viewModel.selectedSharer != nil
    }
    .onChange(of: navigationPath) { _, path in
      // When user navigates back (automatic back button or swipe), deselect sharer
      if path.isEmpty {
        activeChatHighlightUserId = nil
        if viewModel.selectedSharer != nil {
          viewModel.deselectSharer()
        }
        hasSelectedSharer = false
      }
    }
    .onChange(of: coordinator.userId) { _, _ in
      scheduleChatMetadataRefresh()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: Notification.Name("friendsVisibilityChanged"))
    ) { notification in
      if let blockedUserId = notification.userInfo?["blockedUserId"] as? String {
        viewModel.handleBlockedUser(blockedUserId)
      }
      if let unblockedUserId = notification.userInfo?["unblockedUserId"] as? String {
        viewModel.handleUnblockedUser(unblockedUserId)
      }
      scheduleChatMetadataRefresh()
      Task {
        await viewModel.loadSharers(forceRefreshPreviews: true)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .friendsThreadDidUpdate)) { _ in
      scheduleChatMetadataRefresh()
    }
    .onDisappear {
      deepLinkNavigationTask?.cancel()
      deepLinkNavigationTask = nil
      highlightClearTask?.cancel()
      highlightClearTask = nil
      unreadRefreshTask?.cancel()
      unreadRefreshTask = nil
    }
    .alert(
      String(localized: .friendsChatOpenFailed),
      isPresented: .init(
        get: { chatOpenErrorMessage != nil },
        set: {
          if !$0 { chatOpenErrorMessage = nil }
        }
      )
    ) {
      Button(String(localized: .commonDone), role: .cancel) {
        chatOpenErrorMessage = nil
      }
    } message: {
      Text(chatOpenErrorMessage ?? String(localized: .friendsChatOpenFailed))
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
        deepLinkNavigationTask?.cancel()
        deepLinkNavigationTask = Task { @MainActor in
          // Wait for sharers to be loaded if still loading
          await viewModel.waitForSharersLoaded()
          guard !Task.isCancelled else { return }

          // Find and select the sharer
          if let sharer = (viewModel.sharers + viewModel.hiddenSharers).first(where: {
            $0.id == sharerId
          }) {
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
            }

            if !highlightDates.isEmpty || !highlightShiftIds.isEmpty {
              scheduleHighlightAutoClear()
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

    case .friendChat(let threadId, let messageId, let senderUserId):
      deepLinkNavigationTask?.cancel()
      deepLinkNavigationTask = Task { @MainActor in
        await openChat(
          threadId: threadId,
          initialMessageId: messageId,
          notificationSenderUserId: senderUserId
        )
      }
      coordinator.clearPendingDeepLink()

    case .shifts:
      // Not handled here - ShiftsView will handle this
      break

    case .addShift:
      // Not handled here - AddShiftView will handle this
      break

    case .feedback, .adminFeedback, .adminReport:
      // Not handled here - MainTabView handles these
      break
    }
  }

  private func scheduleHighlightAutoClear() {
    highlightClearTask?.cancel()
    highlightClearTask = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: UInt64(Self.highlightDuration * 1_000_000_000))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.3)) {
        highlightDates = []
        highlightShiftIds = []
      }
      highlightClearTask = nil
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
          hiddenSharers: viewModel.hiddenSharers,
          chatOnlyUserIds: viewModel.chatOnlyUserIds,
          unreadChatUserIds: unreadChatUserIds,
          unreadChatCountsByUserId: unreadChatCountsByUserId,
          chatPreviewsByUserId: chatPreviewsByUserId,
          selectedSharer: viewModel.selectedSharer,
          shiftPreviews: viewModel.shiftPreviews,
          isLoading: viewModel.isLoadingSharers,
          isLoadingPreviews: viewModel.isLoadingPreviews,
          hasFinishedInitialLoad: viewModel.hasFinishedInitialSharersLoad,
          isRefreshing: viewModel.isRefreshing,
          onSelectSharer: { sharer in
            viewModel.selectSharer(sharer)
            navigationPath.append(sharer)
          },
          onSelectHiddenSharer: { sharer in
            viewModel.selectSharer(sharer)
            navigationPath.append(sharer)
          },
          onMessageTap: { sharer in
            Task {
              await openChat(for: sharer)
            }
          },
          highlightedChatUserId: activeChatHighlightUserId,
          openingThreadUserId: openingThreadUserId,
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

  private func openChat(for sharedUser: SharedUser) async {
    guard openingThreadUserId == nil else { return }

    openingThreadUserId = sharedUser.id
    defer { openingThreadUserId = nil }

    do {
      let thread = try await friendsMessagingService.getOrCreateDirectThread(
        otherUserId: sharedUser.id)
      let route = FriendChatRoute(
        thread: thread,
        fallbackDisplayName: sharedUser.displayName,
        fallbackAvatarUrl: sharedUser.avatarUrl
      )
      activeChatHighlightUserId = sharedUser.id
      navigationPath.append(route)
    } catch let error as FriendsMessagingServiceError
      where isBlockedDirectThreadCreationError(error)
    {
      activeChatHighlightUserId = nil
      viewModel.handleBlockedUser(sharedUser.id)
      scheduleChatMetadataRefresh()
      Task {
        await viewModel.loadSharers(forceRefreshPreviews: true)
      }
    } catch {
      activeChatHighlightUserId = nil
      chatOpenErrorMessage =
        error.localizedDescription.isEmpty
        ? String(localized: .friendsChatOpenFailed)
        : error.localizedDescription
    }
  }

  private func openChat(
    threadId: String,
    initialMessageId: String? = nil,
    notificationSenderUserId: String? = nil
  ) async {
    guard openingThreadId == nil else { return }

    openingThreadId = threadId
    defer { openingThreadId = nil }

    do {
      async let threadTask = friendsMessagingService.fetchThreadSummary(threadId: threadId)
      async let messagesTask = friendsMessagingService.listThreadMessages(
        threadId: threadId,
        limit: 50,
        before: nil
      )

      let thread = try await threadTask
      let messages = try await messagesTask
      guard !Task.isCancelled else { return }

      if let viewerUserId = coordinator.getCurrentUserId() {
        await friendsMessagesRepository.saveThread(thread, for: viewerUserId)
        await friendsMessagesRepository.saveMessages(messages, in: threadId, for: viewerUserId)
        guard !Task.isCancelled else { return }
      }

      let route = FriendChatRoute(
        thread: thread,
        fallbackDisplayName: thread.counterpartDisplayName
          ?? String(localized: .sharingFriendsTitle),
        fallbackAvatarUrl: thread.counterpartAvatarUrl,
        initialMessageId: initialMessageId,
        notificationSenderUserId: notificationSenderUserId
      )

      activeChatHighlightUserId = thread.counterpartUserId
      navigationPath = NavigationPath()
      viewModel.deselectSharer()
      navigationPath.append(route)
      hasSelectedSharer = false
    } catch is CancellationError {
      return
    } catch {
      activeChatHighlightUserId = nil
      chatOpenErrorMessage =
        error.localizedDescription.isEmpty
        ? String(localized: .friendsChatOpenFailed)
        : error.localizedDescription
    }
  }

  private func isBlockedDirectThreadCreationError(_ error: FriendsMessagingServiceError) -> Bool {
    guard case .httpError(let statusCode, let message) = error else {
      return false
    }

    let normalizedMessage = message?.lowercased() ?? ""
    return statusCode == 400 && normalizedMessage.contains("not allowed for this user pair")
  }

  private func refreshChatMetadata() {
    guard let viewerUserId = coordinator.getCurrentUserId(), !viewerUserId.isEmpty else {
      withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
        unreadChatUserIds = []
        unreadChatCountsByUserId = [:]
        chatPreviewsByUserId = [:]
      }
      return
    }

    let directThreads =
      friendsMessagesRepository
      .getThreads(for: viewerUserId)
      .filter { $0.kind == .direct }

    var nextUnreadChatCountsByUserId: [String: Int] = [:]
    var nextChatPreviewsByUserId: [String: FriendCardMessagePreview] = [:]

    for thread in directThreads {
      guard let counterpartUserId = thread.counterpartUserId, !counterpartUserId.isEmpty else {
        continue
      }

      if thread.unreadCount > 0 {
        nextUnreadChatCountsByUserId[counterpartUserId] = thread.unreadCount
      }

      if nextChatPreviewsByUserId[counterpartUserId] == nil,
        let preview = makeChatPreview(from: thread, viewerUserId: viewerUserId)
      {
        nextChatPreviewsByUserId[counterpartUserId] = preview
      }
    }

    withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
      unreadChatCountsByUserId = nextUnreadChatCountsByUserId
      unreadChatUserIds = Set(nextUnreadChatCountsByUserId.keys)
      chatPreviewsByUserId = nextChatPreviewsByUserId
    }
  }

  private func scheduleChatMetadataRefresh() {
    unreadRefreshTask?.cancel()
    unreadRefreshTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      refreshChatMetadata()
    }
  }

  private func makeChatPreview(from thread: FriendThread, viewerUserId: String)
    -> FriendCardMessagePreview?
  {
    guard let lastMessageId = thread.lastMessageId else { return nil }

    let lastMessage = friendsMessagesRepository.getMessage(
      id: lastMessageId, viewerUserId: viewerUserId)
    let previewText = (lastMessage?.previewText ?? thread.lastMessagePreviewText)?
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let previewText, !previewText.isEmpty else { return nil }

    let previewTimestamp = lastMessage?.createdAt ?? thread.lastMessageAt ?? thread.createdAt

    return FriendCardMessagePreview(
      text: previewText,
      timestamp: previewTimestamp,
      state: makeChatPreviewState(
        thread: thread,
        viewerUserId: viewerUserId,
        lastMessage: lastMessage
      )
    )
  }

  private func makeChatPreviewState(
    thread: FriendThread,
    viewerUserId: String,
    lastMessage: FriendMessage?
  ) -> FriendCardMessageState {
    let isOutgoing =
      lastMessage?.senderUserId == viewerUserId
      || (lastMessage == nil && thread.lastMessageSenderId == viewerUserId)

    if isOutgoing {
      switch lastMessage?.sendState {
      case .sending:
        return .outgoingSending
      case .failed:
        return .outgoingFailed
      case .sent, .none:
        break
      }

      let counterpartState =
        thread.counterpartUserId.flatMap {
          friendsMessagesRepository.getThreadState(threadId: thread.id, viewerUserId: $0)
        }

      return hasOpenedLastMessage(
        lastMessageId: thread.lastMessageId,
        lastMessageTimestamp: thread.lastMessageAt ?? thread.createdAt,
        state: counterpartState
      )
        ? .outgoingOpened
        : .outgoingSent
    }

    if thread.unreadCount > 0 {
      return .incomingUnread
    }

    return .incomingOpened
  }

  private func hasOpenedLastMessage(
    lastMessageId: String?,
    lastMessageTimestamp: Date,
    state: FriendThreadState?
  ) -> Bool {
    guard let state else { return false }

    if let lastMessageId, state.lastReadMessageId == lastMessageId {
      return true
    }

    guard let lastReadAt = state.lastReadAt else { return false }
    return lastReadAt >= lastMessageTimestamp
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
  let onMessageTapped: (SharedUser) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.userCurrency) private var fallbackCurrency
  @Environment(\.layoutDirection) private var layoutDirection
  @AppStorage("shiftsViewMode") private var showListView = false
  @State private var showProfile = false
  @State private var shouldNavigateBack = false

  private var isIPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone
  }

  private let swipeThreshold: CGFloat = 50
  private let verticalLimit: CGFloat = 50
  private let edgeExclusion: CGFloat = 24
  private let monthSwipeHaptic = UIImpactFeedbackGenerator(style: .medium)

  private var effectiveCurrency: String {
    viewModel.sharedCurrency ?? fallbackCurrency
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        Color.tidexBackground
          .ignoresSafeArea()

        SharedShiftsListView(
          sharer: sharer,
          shifts: viewModel.sharedShifts,
          jobs: viewModel.sharedJobs,
          year: viewModel.committedYear,
          month: viewModel.committedMonth,
          phase: viewModel.transitionPhase,
          isLoading: viewModel.isLoadingShifts,
          highlightDates: highlightDates,
          highlightShiftIds: highlightShiftIds,
          isSuperimposing: viewModel.isSuperimposing,
          userHoursByDate: viewModel.userHoursByDate,
          userEarningsByDate: viewModel.userEarningsByDate
        )
        .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
        .frame(maxWidth: .infinity)
        .environment(\.userCurrency, effectiveCurrency)
      }
      .contentShape(Rectangle())
      .simultaneousGesture(monthSwipeDragGesture(containerWidth: geometry.size.width))
    }
    .onAppear {
      monthSwipeHaptic.prepare()
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      // Superimpose toggle
      if !showListView {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            viewModel.toggleSuperimpose()
          } label: {
            superimposeToggleLabel
              .font(.tidexFootnoteMedium)
              .foregroundColor(viewModel.isSuperimposing ? .tidexBlue : .tidexTextMuted)
          }
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)
      }

      // Friend display using UserMenuButton - tapping opens profile
      ToolbarItem(placement: .topBarTrailing) {
        UserMenuButton(
          displayName: sharer.displayName,
          avatarUrl: sharer.avatarUrl,
          onTap: { showProfile = true }
        )
        .fixedSize(horizontal: true, vertical: false)
      }
    }
    .sheet(
      isPresented: $showProfile,
      onDismiss: {
        if shouldNavigateBack {
          shouldNavigateBack = false
          dismiss()
        }
      }
    ) {
      FriendProfileView(
        sharedUser: sharer,
        onVisibilityChange: {
          Task {
            await viewModel.loadSharers(forceRefreshPreviews: true)
          }
        },
        onFriendRemoved: {
          shouldNavigateBack = true
        },
        onMessageTapped: {
          showProfile = false
          onMessageTapped(sharer)
        }
      )
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
  }

  private var superimposeToggleLabel: Text {
    let resource: LocalizedStringResource =
      viewModel.isSuperimposing
      ? .sharingSuperimposeHideMyShifts
      : .sharingSuperimposeShowMyShifts
    let localized = String(localized: resource)

    if let attributed = try? AttributedString(
      markdown: localized,
      options: AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace
      )
    ) {
      return Text(attributed)
    }

    return Text(localized)
  }

  private func monthSwipeDragGesture(containerWidth: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 10)
      .onEnded { value in
        let horizontal = value.translation.width
        let vertical = abs(value.translation.height)
        guard vertical <= verticalLimit else { return }
        guard abs(horizontal) >= swipeThreshold else { return }

        // Leave edge swipes to NavigationStack interactive pop gesture.
        let startX = value.startLocation.x
        guard startX > edgeExclusion && startX < (containerWidth - edgeExclusion) else { return }

        AppearanceTracker.shared.reset()
        monthSwipeHaptic.impactOccurred()
        monthSwipeHaptic.prepare()

        let swipeLeft = horizontal < 0
        if swipeLeft {
          if layoutDirection == .rightToLeft {
            viewModel.goToPreviousMonth()
          } else {
            viewModel.goToNextMonth()
          }
        } else if layoutDirection == .rightToLeft {
          viewModel.goToNextMonth()
        } else {
          viewModel.goToPreviousMonth()
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
