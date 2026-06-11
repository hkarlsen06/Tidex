import SwiftUI
import UIKit

enum SharingDeepLinkNavigationPathResolver {
  static func shouldPreserveExistingPath(
    navigationPathIsEmpty: Bool,
    selectedSharerId: String?,
    activeChatHighlightUserId: String?
  ) -> Bool {
    !navigationPathIsEmpty && selectedSharerId == nil && activeChatHighlightUserId != nil
  }
}

/// Sharing tab view - displays shifts from users who share with the current user
/// Fetches shared shifts from the Next.js API for proper payroll computation
struct SharingView: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order type_body_length line_length
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
  @State private var pendingChatNavigationTask: Task<Void, Never>?
  @State private var highlightClearTask: Task<Void, Never>?
  @State private var openingThreadUserId: String?
  @State private var openingThreadId: String?
  @State private var pendingChatRoute: FriendChatRoute?
  @State private var pendingChatHighlightUserId: String?
  @State private var activeChatHighlightUserId: String?
  @State private var chatOpenErrorMessage: String?
  @State private var unreadChatUserIds: Set<String> = []
  @State private var bottomedChatUserIds: Set<String> = []
  @State private var unreadChatCountsByUserId: [String: Int] = [:]
  @State private var chatPreviewsByUserId: [String: FriendCardMessagePreview] = [:]
  @State private var typingUserIds: Set<String> = []
  @State private var profileSharer: SharedUser?
  @State private var typingResetTasks: [String: Task<Void, Never>] = [:]
  @State private var latestIncomingMessageIdsByUserId: [String: String] = [:]
  @State private var unreadRefreshTask: Task<Void, Never>?
  @State private var isChatTabBarHidden = false

  /// Duration to show highlight before auto-clearing (3 seconds)
  private static let highlightDuration: TimeInterval = 3.0
  private static let typingIndicatorTimeout: Duration = .seconds(5)
  private static let typingStopGraceDelay: Duration = .seconds(2)

  private var startupTaskID: String {
    "\(selectedTab.rawValue):\(coordinator.userId ?? "")"
  }

  private let friendsMessagingService = FriendsMessagingService.shared
  private let friendsMessagesRepository = FriendsMessagesRepository.shared
  private let friendsRealtimeCoordinator = FriendsMessagingRealtimeCoordinator.shared

  private static func normalizedIdentifier(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.isEmpty ? nil : normalized
  }

  @MainActor
  private func pushChatRoute(
    _ route: FriendChatRoute,
    highlightedUserId: String?
  ) {
    pendingChatNavigationTask?.cancel()
    isChatTabBarHidden = true

    let normalizedHighlightUserId = Self.normalizedIdentifier(highlightedUserId)
    pendingChatNavigationTask = Task { @MainActor in
      await Task.yield()
      guard !Task.isCancelled else { return }

      activeChatHighlightUserId = normalizedHighlightUserId
      navigationPath.append(route)
      pendingChatNavigationTask = nil
    }
  }

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
      .toolbar(isChatTabBarHidden ? .hidden : .visible, for: .tabBar)
      .iPadToolbarBackground()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          manageFriendsButton
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
          },
          onSendToChatCompleted: { result in
            let recipientAvatarUrl = result.recipient.avatarURL?.absoluteString
            let threadDisplayName = result.thread.counterpartDisplayName?
              .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackDisplayName =
              if let threadDisplayName, !threadDisplayName.isEmpty {
                threadDisplayName
              } else {
                result.recipient.displayName
              }
            let route = FriendChatRoute(
              thread: result.thread,
              fallbackDisplayName: fallbackDisplayName,
              fallbackAvatarUrl: result.thread.counterpartAvatarUrl ?? recipientAvatarUrl
            )
            navigateToChatRoute(
              route,
              highlightedUserId: result.thread.counterpartUserId ?? result.recipient.id,
              resetNavigationFirst: true
            )
          },
          onFeedPlacementChange: {
            scheduleChatMetadataRefresh()
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
        .id(route.threadId)
        .onAppear {
          hasSelectedSharer = false
        }
        .onDisappear {
          isChatTabBarHidden = false
          activeChatHighlightUserId = nil
          hasSelectedSharer = viewModel.selectedSharer != nil
        }
      }
      .iPadToolbarTransaction()
    }
    .task(id: startupTaskID) {
      guard selectedTab == .sharing else { return }
      refreshChatMetadata()
      await refreshFeedPlacements()
      await viewModel.loadSharers()
      guard !Task.isCancelled, selectedTab == .sharing else { return }
      scheduleChatMetadataRefresh()
      await syncTypingSubscriptions()
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
        initialSnapshot: viewModel.hasFinishedInitialSharersLoad
          ? viewModel.managementSnapshot : nil,
        onBootstrapRefresh: { bootstrap in
          await viewModel.applyFriendsTabBootstrap(bootstrap)
        },
        typingUserIds: typingUserIds,
        unreadChatUserIds: unreadChatUserIds,
        chatPreviewsByUserId: chatPreviewsByUserId,
        shiftPreviews: viewModel.shiftPreviews,
        isLoadingPreviews: viewModel.isLoadingPreviews
      )
    }
    .onChange(of: coordinator.pendingDeepLink) { _, deepLink in
      handlePendingDeepLink(deepLink)
    }
    .onAppear {
      // Handle any pending deep link on initial appearance
      friendsRealtimeCoordinator.setFriendsFeedVisible(selectedTab == .sharing)
      handlePendingDeepLink(coordinator.pendingDeepLink)
      hasSelectedSharer = viewModel.selectedSharer != nil
    }
    .onChange(of: navigationPath) { _, path in
      // When user navigates back (automatic back button or swipe), deselect sharer
      if path.isEmpty {
        isChatTabBarHidden = pendingChatRoute != nil
        activeChatHighlightUserId = nil
        if viewModel.selectedSharer != nil {
          viewModel.deselectSharer()
        }
        hasSelectedSharer = false
        schedulePendingChatNavigationIfNeeded()
      }
    }
    .onChange(of: coordinator.userId) { _, _ in
      scheduleChatMetadataRefresh()
      Task {
        await syncTypingSubscriptions()
      }
    }
    .onChange(of: selectedTab) { _, newTab in
      guard newTab == .sharing else {
        friendsRealtimeCoordinator.setFriendsFeedVisible(false)
        Task {
          await stopTypingSubscriptions()
        }
        return
      }
      friendsRealtimeCoordinator.setFriendsFeedVisible(true)
      refreshChatMetadata()
      Task {
        await resubscribeTypingSubscriptions()
      }
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
      if notification.userInfo?["source"] as? String == "manageSheetBootstrapApplied" {
        return
      }
      Task {
        await viewModel.loadSharers(forceRefreshPreviews: true)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .friendsThreadDidUpdate)) { _ in
      scheduleChatMetadataRefresh()
      Task {
        await syncTypingSubscriptions()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .friendFeedPlacementDidChange)) { _ in
      scheduleChatMetadataRefresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .friendsThreadTypingDidChange)) {
      notification in
      guard
        let threadId = notification.userInfo?["threadId"] as? String,
        let userId = notification.userInfo?["userId"] as? String,
        let isTyping = notification.userInfo?["isTyping"] as? Bool,
        let normalizedUserId = Self.normalizedIdentifier(userId)
      else {
        return
      }

      let normalizedViewerUserId = Self.normalizedIdentifier(coordinator.getCurrentUserId())
      guard normalizedUserId != normalizedViewerUserId else { return }

      handleTypingIndicatorChange(
        threadId: threadId,
        userId: normalizedUserId,
        isTyping: isTyping
      )
    }
    .onReceive(NotificationCenter.default.publisher(for: .tidexDidBecomeActive)) {
      _ in
      guard selectedTab == .sharing else { return }
      scheduleChatMetadataRefresh()
    }
    .onDisappear {
      deepLinkNavigationTask?.cancel()
      deepLinkNavigationTask = nil
      pendingChatNavigationTask?.cancel()
      pendingChatNavigationTask = nil
      highlightClearTask?.cancel()
      highlightClearTask = nil
      unreadRefreshTask?.cancel()
      unreadRefreshTask = nil
      typingResetTasks.values.forEach { $0.cancel() }
      typingResetTasks.removeAll()
      typingUserIds.removeAll()
      friendsRealtimeCoordinator.setFriendsFeedVisible(false)
      friendsRealtimeCoordinator.setVisibleThreadIds([])
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
    // swiftlint:disable:next conditional_returns_on_newline
    guard let deepLink else { return }

    switch deepLink {
    case .sharing(let sharerId, let dates, let changes):
      if let sharerId {
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
            let shouldPreserveNavigationPath =
              SharingDeepLinkNavigationPathResolver.shouldPreserveExistingPath(
                navigationPathIsEmpty: navigationPath.isEmpty,
                selectedSharerId: viewModel.selectedSharer?.id,
                activeChatHighlightUserId: activeChatHighlightUserId
              )
            if !shouldPreserveNavigationPath {
              navigationPath = NavigationPath()
            }
            viewModel.selectSharer(sharer)
            navigationPath.append(sharer)

            // Extract shift IDs for precise highlighting (excludes deleted shifts)
            if let changes, !changes.isEmpty {
              let shiftIds = changes.filter { $0.op != "deleted" }.map(\.shiftId)
              highlightShiftIds = Set(shiftIds)
            }

            // If dates were provided, navigate to the correct month and set highlight
            if let dates, let firstDate = dates.first,
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

            await viewModel.loadShiftsForSelectedSharer()

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

    case .friendChat(
      let threadId,
      let messageId,
      let senderUserId,
      let typingUserId,
      let navigationRequestId
    ):
      deepLinkNavigationTask?.cancel()
      deepLinkNavigationTask = Task { @MainActor in
        await openChat(
          threadId: threadId,
          initialMessageId: messageId,
          notificationSenderUserId: senderUserId,
          notificationTypingUserId: typingUserId,
          navigationRequestId: navigationRequestId
        )
      }
      coordinator.clearPendingDeepLink()

    case .shifts:
      // Not handled here - ShiftsView will handle this
      break

    case .addShift:
      // Not handled here - AddShiftView will handle this
      break

    case .wagey, .settings, .feedback, .adminFeedback, .adminReport:
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
    ScrollView {  // swiftlint:disable:this closure_body_length
      VStack(spacing: Spacing.md) {  // swiftlint:disable:this closure_body_length
        // Sharer list
        SharerListView(
          sharers: viewModel.sharers,
          hiddenSharers: viewModel.hiddenSharers,
          chatOnlyUserIds: viewModel.chatOnlyUserIds,
          typingUserIds: typingUserIds,
          unreadChatUserIds: unreadChatUserIds,
          bottomedUserIds: bottomedChatUserIds,
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
          onMessageTap: { sharer in
            Task {
              await openChat(for: sharer)
            }
          },
          onProfileRequested: { sharer in
            profileSharer = sharer
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
      await refreshFriendsTab()
    }
    .sheet(item: $profileSharer) { sharer in
      FriendProfileView(
        sharedUser: sharer,
        onVisibilityChange: {
          Task {
            await viewModel.loadSharers(forceRefreshPreviews: true)
          }
        },
        onFeedPlacementChange: {
          scheduleChatMetadataRefresh()
        },
        onMessageTapped: {
          profileSharer = nil
          Task {
            await openChat(for: sharer)
          }
        }
      )
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
  }

  private var manageFriendsButton: some View {
    Button(action: {
      showManageSheet = true
    }) {
      HStack(spacing: Spacing.xxxs) {
        Image(systemName: "person.2")
          .font(.tidexSubheadline)
          .accessibilityHidden(true)
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

  private func refreshFriendsTab() async {
    let refreshTask = Task { @MainActor in
      await viewModel.refresh()
    }

    _ = await refreshTask.result

    Task { @MainActor in
      await syncTypingSubscriptions()
      scheduleChatMetadataRefresh()
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
      pushChatRoute(route, highlightedUserId: sharedUser.id)
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
    notificationSenderUserId: String? = nil,
    notificationTypingUserId: String? = nil,
    navigationRequestId: UUID? = nil
  ) async {
    guard openingThreadId == nil else { return }

    openingThreadId = threadId
    defer { openingThreadId = nil }

    let isNotificationOpen =
      navigationRequestId != nil
      || (initialMessageId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
      || (notificationSenderUserId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)

    do {
      if isNotificationOpen {
        let route = makeImmediateChatRoute(
          threadId: threadId,
          initialMessageId: initialMessageId,
          notificationSenderUserId: notificationSenderUserId,
          notificationTypingUserId: notificationTypingUserId,
          navigationRequestId: navigationRequestId
        )

        let highlightedUserId =
          route.counterpartUserId.isEmpty
          ? notificationSenderUserId
          : route.counterpartUserId
        navigateToChatRoute(
          route,
          highlightedUserId: highlightedUserId,
          resetNavigationFirst: true
        )
        return
      }

      let snapshot = try await friendsMessagingService.fetchThreadSyncSnapshotV2(
        threadId: threadId,
        messageLimit: 50
      )
      guard !Task.isCancelled else { return }

      if let viewerUserId = coordinator.getCurrentUserId() {
        await friendsMessagesRepository.saveThread(snapshot.thread, for: viewerUserId)
        await friendsMessagesRepository.saveMessages(
          snapshot.messages,
          in: threadId,
          for: viewerUserId
        )
        await friendsMessagesRepository.saveThreadState(snapshot.viewerState)
        guard !Task.isCancelled else { return }
      }

      let route = FriendChatRoute(
        thread: snapshot.thread,
        fallbackDisplayName: snapshot.thread.counterpartDisplayName
          ?? String(localized: .sharingFriendsTitle),
        fallbackAvatarUrl: snapshot.thread.counterpartAvatarUrl,
        initialMessageId: initialMessageId,
        notificationSenderUserId: notificationSenderUserId,
        notificationTypingUserId: notificationTypingUserId,
        navigationRequestId: navigationRequestId
      )

      navigateToChatRoute(
        route,
        highlightedUserId: snapshot.thread.counterpartUserId,
        resetNavigationFirst: true
      )
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

  private func makeImmediateChatRoute(
    threadId: String,
    initialMessageId: String?,
    notificationSenderUserId: String?,
    notificationTypingUserId: String?,
    navigationRequestId: UUID?
  ) -> FriendChatRoute {
    let cachedThread =
      coordinator.getCurrentUserId().flatMap {
        friendsMessagesRepository.getThread(id: threadId, viewerUserId: $0)
      }
      ?? FriendThread(
        id: threadId,
        kind: .direct,
        title: nil,
        avatarUrl: nil,
        metadataData: nil,
        counterpartUserId: notificationSenderUserId,
        counterpartDisplayName: nil,
        counterpartProfilePictureUrl: nil,
        counterpartOAuthAvatarUrl: nil,
        lastMessageId: nil,
        lastMessageSenderId: nil,
        lastMessageAt: nil,
        lastMessageBody: nil,
        lastMessageHasImage: false,
        unreadCount: 0,
        muted: false,
        createdAt: Date()
      )

    return FriendChatRoute(
      thread: cachedThread,
      fallbackDisplayName: cachedThread.counterpartDisplayName
        ?? String(localized: .sharingFriendsTitle),
      fallbackAvatarUrl: cachedThread.counterpartAvatarUrl,
      initialMessageId: initialMessageId,
      notificationSenderUserId: notificationSenderUserId,
      notificationTypingUserId: notificationTypingUserId,
      navigationRequestId: navigationRequestId
    )
  }

  private func navigateToChatRoute(
    _ route: FriendChatRoute,
    highlightedUserId: String?,
    resetNavigationFirst: Bool
  ) {
    pendingChatNavigationTask?.cancel()

    let normalizedHighlightUserId = Self.normalizedIdentifier(highlightedUserId)

    guard resetNavigationFirst else {
      viewModel.deselectSharer()
      hasSelectedSharer = false
      pendingChatRoute = nil
      pendingChatHighlightUserId = nil
      pushChatRoute(route, highlightedUserId: normalizedHighlightUserId)
      return
    }

    pendingChatRoute = route
    pendingChatHighlightUserId = normalizedHighlightUserId

    if navigationPath.isEmpty {
      schedulePendingChatNavigationIfNeeded()
    } else {
      navigationPath = NavigationPath()
    }
  }

  private func schedulePendingChatNavigationIfNeeded() {
    guard navigationPath.isEmpty, pendingChatRoute != nil else { return }

    pendingChatNavigationTask?.cancel()
    pendingChatNavigationTask = Task { @MainActor in
      await Task.yield()
      guard !Task.isCancelled, navigationPath.isEmpty, let route = pendingChatRoute else { return }

      let highlightUserId = pendingChatHighlightUserId
      pendingChatRoute = nil
      pendingChatHighlightUserId = nil
      viewModel.deselectSharer()
      hasSelectedSharer = false
      isChatTabBarHidden = true
      activeChatHighlightUserId = highlightUserId
      navigationPath.append(route)
      pendingChatNavigationTask = nil
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
    var nextLatestIncomingMessageIdsByUserId: [String: String] = [:]
    var usersWithNewIncomingMessages: Set<String> = []

    for thread in directThreads {
      guard let counterpartUserId = Self.normalizedIdentifier(thread.counterpartUserId) else {
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

      if let latestIncomingMessageId = latestIncomingMessageId(
        in: thread, counterpartUserId: counterpartUserId)
      {
        nextLatestIncomingMessageIdsByUserId[counterpartUserId] = latestIncomingMessageId
        if latestIncomingMessageIdsByUserId[counterpartUserId] != latestIncomingMessageId {
          usersWithNewIncomingMessages.insert(counterpartUserId)
        }
      }
    }

    for userId in usersWithNewIncomingMessages {
      typingResetTasks[userId]?.cancel()
      typingResetTasks[userId] = nil
    }

    withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
      unreadChatCountsByUserId = nextUnreadChatCountsByUserId
      unreadChatUserIds = Set(nextUnreadChatCountsByUserId.keys)
      chatPreviewsByUserId = nextChatPreviewsByUserId
      latestIncomingMessageIdsByUserId = nextLatestIncomingMessageIdsByUserId
      typingUserIds =
        typingUserIds
        .subtracting(usersWithNewIncomingMessages)
        .intersection(
          Set(directThreads.compactMap { Self.normalizedIdentifier($0.counterpartUserId) }))
    }
  }

  private func scheduleChatMetadataRefresh() {
    unreadRefreshTask?.cancel()
    unreadRefreshTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      refreshChatMetadata()
      await refreshFeedPlacements()
    }
  }

  private func refreshFeedPlacements() async {
    guard let viewerUserId = coordinator.getCurrentUserId(), !viewerUserId.isEmpty else {
      withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
        bottomedChatUserIds = []
      }
      return
    }

    let nextBottomedUserIds = await friendsMessagesRepository.getActiveBottomedFriendIds(
      for: viewerUserId
    )
    withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
      bottomedChatUserIds = nextBottomedUserIds
    }
  }

  private func syncTypingSubscriptions() async {
    guard let viewerUserId = coordinator.getCurrentUserId(), !viewerUserId.isEmpty else {
      friendsRealtimeCoordinator.setVisibleThreadIds([])
      await MainActor.run {
        typingResetTasks.values.forEach { $0.cancel() }
        typingResetTasks.removeAll()
        typingUserIds.removeAll()
      }
      return
    }

    let directThreadIds =
      friendsMessagesRepository
      .getThreads(for: viewerUserId)
      .filter { $0.kind == .direct }
      .map(\.id)

    friendsRealtimeCoordinator.setVisibleThreadIds(directThreadIds)
  }

  private func resubscribeTypingSubscriptions() async {
    await stopTypingSubscriptions()
    scheduleChatMetadataRefresh()
    await syncTypingSubscriptions()
  }

  private func stopTypingSubscriptions() async {
    friendsRealtimeCoordinator.setVisibleThreadIds([])
    await MainActor.run {
      typingResetTasks.values.forEach { $0.cancel() }
      typingResetTasks.removeAll()
      typingUserIds.removeAll()
    }
  }

  private func handleTypingIndicatorChange(threadId: String, userId: String, isTyping: Bool) {
    guard
      let viewerUserId = Self.normalizedIdentifier(coordinator.getCurrentUserId()),
      let normalizedUserId = Self.normalizedIdentifier(userId),
      normalizedUserId != viewerUserId,
      let thread = friendsMessagesRepository.getThread(id: threadId, viewerUserId: viewerUserId),
      thread.kind == .direct
    else {
      return
    }

    if let counterpartUserId = Self.normalizedIdentifier(thread.counterpartUserId),
      counterpartUserId != normalizedUserId
    {
      return
    }

    typingResetTasks[normalizedUserId]?.cancel()

    if isTyping {
      _ = withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
        typingUserIds.insert(normalizedUserId)
      }

      typingResetTasks[normalizedUserId] = Task { @MainActor in
        try? await Task.sleep(for: Self.typingIndicatorTimeout)
        guard !Task.isCancelled else { return }
        _ = withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
          typingUserIds.remove(normalizedUserId)
        }
        typingResetTasks[normalizedUserId] = nil
      }
    } else {
      typingResetTasks[normalizedUserId] = Task { @MainActor in
        try? await Task.sleep(for: Self.typingStopGraceDelay)
        guard !Task.isCancelled else { return }
        _ = withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
          typingUserIds.remove(normalizedUserId)
        }
        typingResetTasks[normalizedUserId] = nil
      }
    }
  }

  private func latestIncomingMessageId(in thread: FriendThread, counterpartUserId: String)
    -> String?
  {
    guard
      let lastMessageId = thread.lastMessageId,
      let lastMessageSenderId = Self.normalizedIdentifier(thread.lastMessageSenderId),
      lastMessageSenderId == counterpartUserId
    else {
      return nil
    }

    return lastMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
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
  let onSendToChatCompleted: (SendShiftToChatResult) -> Void
  let onFeedPlacementChange: () -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.userCurrency) private var fallbackCurrency
  @AppStorage("shiftsViewMode") private var showListView = false
  @State private var showProfile = false
  @State private var shouldNavigateBack = false
  @State private var visibleContextOwnerToken = UUID()

  private var isIPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone
  }

  private var effectiveCurrency: String {
    viewModel.sharedCurrency ?? fallbackCurrency
  }

  var body: some View {
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
        isContentReady: viewModel.hasResolvedSelectedSharerShifts,
        highlightDates: highlightDates,
        highlightShiftIds: highlightShiftIds,
        isSuperimposing: viewModel.isSuperimposing,
        userHoursByDate: viewModel.userHoursByDate,
        userShiftsByDate: viewModel.userShiftsByDate,
        userEarningsByDate: viewModel.userEarningsByDate,
        onPreviousMonth: {
          viewModel.goToPreviousMonth()
        },
        onNextMonth: {
          viewModel.goToNextMonth()
        },
        onSendToChatCompleted: { result in
          onSendToChatCompleted(result)
        }
      )
      .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
      .frame(maxWidth: .infinity)
      .environment(\.userCurrency, effectiveCurrency)
    }
    .onAppear {
      SensitiveContentPresentationState.shared.setVisibleContext(
        .sharedCalendar(ownerId: sharer.id, ownerToken: visibleContextOwnerToken)
      )
    }
    .onDisappear {
      SensitiveContentPresentationState.shared.clearVisibleContextIfOwnedBySharedCalendar(
        visibleContextOwnerToken
      )
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
        onFeedPlacementChange: onFeedPlacementChange,
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
}  // swiftlint:disable:this file_length
