import SwiftUI
import UIKit

struct FriendsThreadView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openURL) private var openURL

  @StateObject private var viewModel: FriendsThreadViewModel
  @State private var pendingReportTarget: ReportTarget?
  @State private var showBlockConfirmation = false
  @State private var showSafetySupport = false
  @State private var safariURL: URL?
  @State private var alertState: AlertState?
  @State private var highlightedMessageId: String?
  @State private var isPinnedToBottom = true
  @State private var bottomAccessoryInset: CGFloat = 0
  @State private var unreadIncomingCount = 0
  @State private var showsNewMessagesPill = false
  @State private var scrollToBottomTrigger = 0
  @State private var showScreenshotBubble = false
  @State private var showScreenshotNotifiedIcon = false
  @State private var screenshotBellShakeTrigger = false
  @State private var showProfile = false
  @State private var messageActionMenu: MessageActionMenuState?
  @State private var customReactionTarget: FriendMessage?
  @State private var customReactionDraft = ""
  @State private var isCustomReactionInputActive = false
  @State private var isComposerAttachmentDrawerOpen = false
  @StateObject private var reactionPaletteStore = FriendsChatReactionPaletteStore()

  private struct ScrollState: Equatable {
    let messageCount: Int
    let firstMessageID: String?
    let lastMessageID: String?
  }

  private struct MessageActionMenuState: Identifiable {
    let id = UUID()
    let message: FriendMessage
    let sourceFrame: CGRect
  }

  init(route: FriendChatRoute, viewerUserId: String) {
    _viewModel = StateObject(
      wrappedValue: FriendsThreadViewModel(route: route, viewerUserId: viewerUserId)
    )
  }

  private var scrollState: ScrollState {
    ScrollState(
      messageCount: viewModel.messages.count,
      firstMessageID: viewModel.messages.first?.id,
      lastMessageID: viewModel.messages.last?.id
    )
  }

  private let timelineBottomContentInset = Spacing.lg

  private var scrollToLatestBottomPadding: CGFloat {
    max(bottomAccessoryInset, 0) + Spacing.sm
  }

  private var counterpartProfileUser: SharedUser {
    let displayName = viewModel.thread.counterpartDisplayName ?? viewModel.route.displayName
    let avatarUrl = viewModel.thread.counterpartAvatarUrl ?? viewModel.route.avatarUrl

    return SharedUser(
      id: viewModel.route.counterpartUserId,
      email: nil,
      phone: nil,
      firstName: displayName,
      profilePictureUrl: avatarUrl,
      oauthAvatarUrl: nil,
      sharedAt: "",
      showEarnings: false,
      hidden: false
    )
  }

  var body: some View {
    threadContent
      .refreshable {
        guard !isComposerAttachmentDrawerOpen else { return }
        dismissMessageActionMenu()
        await viewModel.refresh()
      }
  }

  private var threadContent: some View {
    VStack(spacing: 0) {
      if let counterpartShiftPreview = viewModel.counterpartShiftPreview {
        CompactFriendShiftPreviewHeader(
          preview: counterpartShiftPreview
        )
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xxs)
        .padding(.bottom, Spacing.xxs)
        .frame(maxWidth: .infinity)
        .background(Color.tidexBackground)
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 10)
        .zIndex(1)
      }

      ZStack(alignment: .bottom) {
        FriendsThreadSurfaceView(
          timelineConfiguration: FriendsChatTimelineConfiguration(
            messages: viewModel.messages,
            quotedMessagesById: viewModel.quotedMessagesById,
            viewerUserId: viewModel.viewerUserId,
            counterpartLastReadMessageId: viewModel.counterpartReadState?.lastReadMessageId,
            counterpartLastReadAt: viewModel.counterpartReadState?.lastReadAt,
            currentUserDisplayName: AppCoordinator.shared.userDisplayName,
            counterpartDisplayName: viewModel.thread.counterpartDisplayName
              ?? viewModel.route.displayName,
            counterpartAvatarUrl: viewModel.thread.counterpartAvatarUrl
              ?? viewModel.route.avatarUrl,
            highlightedMessageId: highlightedMessageId,
            showTypingIndicator: viewModel.counterpartIsTyping,
            bottomContentInset: timelineBottomContentInset,
            scrollToBottomTrigger: scrollToBottomTrigger,
            restoreScrollTargetMessageId: viewModel.restoreScrollTargetMessageId,
            replyScrollTargetMessageId: viewModel.replyScrollTargetMessageId
          ),
          composerConfiguration: FriendsThreadComposerConfiguration(
            draftText: viewModel.draft,
            replyPreview: viewModel.draftReplyTarget.map { replyPreviewModel(for: $0) },
            stagedAttachment: viewModel.stagedComposerAttachment,
            isThreadReadOnly: viewModel.isThreadReadOnly,
            sendErrorMessage: viewModel.sendErrorMessage,
            placeholder: String(localized: .friendsChatPlaceholder),
            canSendShiftSnapshots: viewModel.canSendShiftSnapshots
          ),
          callbacks: FriendsThreadSurfaceCallbacks(
            onBackgroundTap: dismissComposer,
            onPinnedToBottomChanged: { isPinnedToBottom in
              self.isPinnedToBottom = isPinnedToBottom
            },
            onReachedTopMessage: { currentFirstMessageId in
              Task {
                await viewModel.loadOlderMessagesIfNeeded(
                  currentFirstMessageId: currentFirstMessageId)
              }
            },
            onReply: { message in
              viewModel.setReplyTarget(message)
            },
            onRetryMessage: { messageId in
              Task {
                await viewModel.retryMessage(messageId: messageId)
              }
            },
            onReportMessage: { messageId in
              pendingReportTarget = .message(messageId: messageId)
            },
            onToggleReaction: { message, emoji in
              handleReactionSelection(emoji, for: message)
            },
            onOpenMessageActions: { message, sourceFrame in
              presentMessageActionMenu(for: message, sourceFrame: sourceFrame)
            },
            onTapQuotedMessage: { message in
              Task {
                await viewModel.scrollToReplyTarget(for: message)
              }
            },
            onConsumeRestoreScrollTarget: {
              viewModel.consumeRestoreScrollTarget()
            },
            onConsumeReplyScrollTarget: { messageId in
              flashHighlightedMessage(messageId)
              viewModel.consumeReplyScrollTarget()
            },
            onComposerDraftChanged: { draft in
              viewModel.draft = draft
              Task {
                await viewModel.handleDraftChanged(to: draft)
              }
            },
            onComposerAttachmentChanged: { attachment in
              viewModel.stagedComposerAttachment = attachment
              Task {
                await viewModel.setComposerAttachment(attachment)
              }
            },
            onComposerPrepareShiftSnapshot: { shift in
              await viewModel.prepareShiftSnapshotAttachment(for: shift)
            },
            onComposerCancelReply: {
              viewModel.clearReplyTarget()
            },
            onComposerSend: { content in
              let wasPinnedToBottom = isPinnedToBottom
              let didSend = await viewModel.sendMessage(content: content)
              if didSend {
                await MainActor.run {
                  unreadIncomingCount = 0
                  showsNewMessagesPill = false
                  isPinnedToBottom = true
                  if !wasPinnedToBottom {
                    scrollToBottomTrigger += 1
                  }
                }
              }
              return didSend
            },
            onComposerAttachmentDrawerOpenChanged: { isOpen in
              isComposerAttachmentDrawerOpen = isOpen
            },
            onBottomAccessoryInsetChanged: { inset in
              bottomAccessoryInset = inset
            }
          )
        )
        .background(Color.tidexBackground)
        .overlay(alignment: .top) {
          if (viewModel.isLoading || viewModel.isLoadingOlderMessages)
            && !viewModel.messages.isEmpty
          {
            olderMessagesLoadingState
              .padding(.top, Spacing.md)
          }
        }
        .overlay(alignment: .top) {
          if showScreenshotBubble {
            screenshotBubble
              .padding(.top, Spacing.md)
              .onTapGesture {
                dismissScreenshotBubble()
              }
              .transition(
                .asymmetric(
                  insertion: .scale.combined(with: .opacity),
                  removal: .opacity
                ))
          }
        }
        .overlay(alignment: .bottom) {
          if showsNewMessagesPill, !viewModel.messages.isEmpty {
            scrollToLatestButton
              .padding(.bottom, scrollToLatestBottomPadding)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }

        if let messageActionMenu {
          FriendsChatMessageActionMenuOverlay(
            message: messageActionMenu.message,
            viewerUserId: viewModel.viewerUserId,
            sourceFrame: messageActionMenu.sourceFrame,
            onDismiss: dismissMessageActionMenu,
            onReply: {
              viewModel.setReplyTarget(messageActionMenu.message)
              dismissMessageActionMenu()
            },
            onCopy: {
              UIPasteboard.general.string = messageActionMenu.message.body
              dismissMessageActionMenu()
            },
            onReport: {
              pendingReportTarget = .message(messageId: messageActionMenu.message.id)
              dismissMessageActionMenu()
            },
            onToggleReaction: { emoji in
              handleReactionSelection(emoji, for: messageActionMenu.message)
              dismissMessageActionMenu()
            },
            reactionEmojis: reactionPaletteStore.displayEmojis,
            onAddCustomReaction: {
              startCustomReactionInput(for: messageActionMenu.message)
              dismissMessageActionMenu()
            }
          )
          .transition(.opacity)
          .zIndex(10)
        }

        if viewModel.isLoading && viewModel.messages.isEmpty {
          loadingState
        } else if viewModel.messages.isEmpty {
          emptyState
        }
      }
    }
    .background(Color.tidexBackground.ignoresSafeArea())
    .navigationBarTitleDisplayMode(.inline)
    .iPadToolbarBackground()
    .toolbarBackground(.hidden, for: .tabBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        actionsMenu
      }
    }
    .iPadToolbarTransaction()
    .task {
      await viewModel.loadIfNeeded()
    }
    .onChange(of: scrollState) { oldValue, newValue in
      handleScrollStateChange(from: oldValue, to: newValue)
    }
    .onChange(of: customReactionDraft) { _, newValue in
      guard
        let message = customReactionTarget,
        let normalizedEmoji = FriendsChatReactionPaletteStore.normalizedEmoji(from: newValue)
      else {
        return
      }

      handleReactionSelection(normalizedEmoji, for: message)
      customReactionDraft = ""
      customReactionTarget = nil
      isCustomReactionInputActive = false
    }
    .onChange(of: isCustomReactionInputActive) { _, isActive in
      guard !isActive, customReactionTarget != nil else { return }
      customReactionDraft = ""
      customReactionTarget = nil
    }
    .onAppear {
      FriendsChatPresentationState.shared.setActiveThreadId(viewModel.route.threadId)
    }
    .onChange(of: isPinnedToBottom) { _, isPinnedToBottom in
      if isPinnedToBottom {
        unreadIncomingCount = 0
        showsNewMessagesPill = false
        Task {
          await viewModel.markVisibleMessagesReadIfNeeded()
        }
      }
    }
    .onDisappear {
      dismissMessageActionMenu()
      isCustomReactionInputActive = false
      FriendsChatPresentationState.shared.setActiveThreadId(nil)
      Task {
        await viewModel.stopRealtime()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .friendsThreadDidUpdate)) { notification in
      guard let threadId = notification.userInfo?["threadId"] as? String,
        threadId == viewModel.route.threadId
      else {
        return
      }

      dismissMessageActionMenu()
      Task {
        await viewModel.handleExternalThreadUpdate(shouldMarkRead: isPinnedToBottom)
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: Notification.Name("friendsVisibilityChanged"))
    ) { _ in
      Task {
        await viewModel.refreshCounterpartShiftPreview()
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: .friendsThreadTypingDidChange)
    ) { notification in
      guard let threadId = notification.userInfo?["threadId"] as? String,
        threadId == viewModel.route.threadId,
        let userId = notification.userInfo?["userId"] as? String,
        let isTyping = notification.userInfo?["isTyping"] as? Bool
      else {
        return
      }

      viewModel.handleCounterpartTypingChange(userId: userId, isTyping: isTyping)
    }
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
    ) { _ in
      Task {
        await reportScreenshot()
      }
    }
    .confirmationDialog(
      reportDialogTitle,
      isPresented: .init(
        get: { pendingReportTarget != nil },
        set: {
          if !$0 { pendingReportTarget = nil }
        }
      ),
      titleVisibility: .visible
    ) {
      ForEach(reportReasons, id: \.self) { reason in
        Button(reason.localizedTitle) {
          submitReport(reason: reason)
        }
      }

      Button(String(localized: .commonCancel), role: .cancel) {
        pendingReportTarget = nil
      }
    }
    .confirmationDialog(
      blockConfirmTitle,
      isPresented: $showBlockConfirmation,
      titleVisibility: .visible
    ) {
      Button(String(localized: .friendsChatBlockUser), role: .destructive) {
        blockUser()
      }

      Button(String(localized: .commonCancel), role: .cancel) {}
    } message: {
      Text(.friendsChatBlockConfirmMessage)
    }
    .confirmationDialog(
      String(localized: .friendsChatSafetySupport),
      isPresented: $showSafetySupport,
      titleVisibility: .visible
    ) {
      Button(String(localized: .friendsChatSupportOpenPage)) {
        safariURL = APIConfiguration.webAppBaseURL.appendingPathComponent("support")
      }

      Button(String(localized: .friendsChatSupportEmail)) {
        if let mailURL = URL(string: "mailto:contact@tidex.no") {
          openURL(mailURL)
        }
      }

      Button(String(localized: .paywallPrivacyPolicy)) {
        safariURL = URL(string: "\(TermsVersion.baseURL)/\(Locale.current.urlLanguageCode)/privacy")
      }

      Button(String(localized: .paywallTermsOfUse)) {
        safariURL = URL(string: "\(TermsVersion.baseURL)/\(Locale.current.urlLanguageCode)/terms")
      }

      Button(String(localized: .commonCancel), role: .cancel) {}
    }
    .fullScreenCover(item: $safariURL) { url in
      SafariView(url: url)
        .ignoresSafeArea()
    }
    .sheet(isPresented: $showProfile) {
      FriendProfileView(sharedUser: counterpartProfileUser)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    .alert(item: $alertState) { state in
      Alert(
        title: Text(state.title),
        message: state.message.map(Text.init),
        dismissButton: .default(Text(.commonDone))
      )
    }
    .background(
      FriendsChatSystemEmojiInputHost(
        text: $customReactionDraft,
        isActive: $isCustomReactionInputActive
      )
      .frame(width: 1, height: 1)
      .opacity(0.01)
      .accessibilityHidden(true)
    )
  }

  private var loadingState: some View {
    VStack(spacing: Spacing.sm) {
      ProgressView()
      Text(.friendsChatLoading)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .padding(.horizontal, Spacing.lg)
    .padding(.bottom, bottomAccessoryInset)
  }

  private var emptyState: some View {
    VStack(spacing: Spacing.sm) {
      Image(systemName: "message")
        .font(.system(size: 26, weight: .semibold))
        .foregroundColor(.tidexBlue)
        .padding(14)
        .background(
          Circle()
            .fill(Color.tidexBlue.opacity(0.12))
        )

      Text(.friendsChatEmptyTitle)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

      Text(String(localized: .friendsChatEmptyDescription(viewModel.route.displayName)))
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .padding(.horizontal, Spacing.lg)
    .padding(.bottom, bottomAccessoryInset)
  }

  private var olderMessagesLoadingState: some View {
    HStack(spacing: Spacing.xs) {
      ProgressView()
        .controlSize(.small)

      Text(.friendsChatLoading)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextMuted)
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, Spacing.xs)
  }

  private var scrollToLatestButton: some View {
    Button {
      unreadIncomingCount = 0
      showsNewMessagesPill = false
      Haptics.play(.light)
      SoundManager.shared.play("tap")
      scrollToBottomTrigger += 1
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "arrow.down")
          .font(.system(size: 14, weight: .semibold))

        Text(.friendsChatNewMessages)
          .font(.tidexFootnoteMedium)

        if unreadIncomingCount > 0 {
          Text("\(min(unreadIncomingCount, 99))")
            .font(.tidexMicro.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.tidexBrandPrimary))
        }
      }
      .foregroundColor(.tidexTextPrimary)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .tidexGlass(shape: .capsule, tint: .tidexBlue.opacity(0.12), interactive: true)
    }
    .buttonStyle(.plain)
  }

  private var screenshotBubble: some View {
    ScreenshotNotificationBubble(
      showNotifiedIcon: showScreenshotNotifiedIcon,
      bellShakeTrigger: screenshotBellShakeTrigger
    )
  }

  private var actionsMenu: some View {
    Menu {
      Button(String(localized: .profileTitle)) {
        showProfile = true
      }

      Button(String(localized: .friendsChatReportUser)) {
        pendingReportTarget = .user
      }

      Button(String(localized: .friendsChatSafetySupport)) {
        showSafetySupport = true
      }

      Button(String(localized: .friendsChatBlockUser), role: .destructive) {
        showBlockConfirmation = true
      }
    } label: {
      UserMenuButton(
        displayName: viewModel.thread.counterpartDisplayName ?? viewModel.route.displayName,
        avatarUrl: viewModel.thread.counterpartAvatarUrl ?? viewModel.route.avatarUrl,
        interactive: false
      )
      .fixedSize(horizontal: true, vertical: false)
    }
  }

  private var reportDialogTitle: String {
    guard let pendingReportTarget else {
      return String(localized: .friendsChatReportUser)
    }

    return pendingReportTarget == .user
      ? String(localized: .friendsChatReportUser)
      : String(localized: .friendsChatReportMessage)
  }

  private var blockConfirmTitle: String {
    String(localized: .friendsChatBlockConfirmTitle)
      .replacingOccurrences(of: "{name}", with: viewModel.route.displayName)
  }

  private var reportReasons: [FriendAbuseReportReason] {
    switch pendingReportTarget {
    case .user:
      return [.harassmentOrBullying, .spam, .inappropriateProfileOrConduct, .other]
    case .message:
      return [
        .harassmentOrBullying,
        .sexualContent,
        .hateOrDiscriminatoryContent,
        .violenceOrThreats,
        .spam,
        .other,
      ]
    case .none:
      return []
    }
  }

  private func submitReport(reason: FriendAbuseReportReason) {
    guard let pendingReportTarget else { return }

    Task {
      do {
        try await viewModel.submitReport(messageId: pendingReportTarget.messageId, reason: reason)
        self.pendingReportTarget = nil
        alertState = AlertState(title: String(localized: .friendsChatReportSubmitted))
      } catch {
        self.pendingReportTarget = nil
        alertState = AlertState(
          title: String(localized: .friendsChatReportFailed),
          message: error.localizedDescription
        )
      }
    }
  }

  private func blockUser() {
    Task {
      do {
        try await viewModel.blockCounterpart()
        showBlockConfirmation = false
      } catch {
        showBlockConfirmation = false
        alertState = AlertState(
          title: String(localized: .friendsChatBlockUser),
          message: error.localizedDescription
        )
      }
    }
  }

  private func handleScrollStateChange(
    from oldValue: ScrollState,
    to newValue: ScrollState
  ) {
    guard newValue != oldValue, let lastMessage = viewModel.messages.last else { return }

    let prependedMessages =
      newValue.messageCount > oldValue.messageCount
      && newValue.firstMessageID != oldValue.firstMessageID
      && newValue.lastMessageID == oldValue.lastMessageID
    let appendedMessage =
      newValue.lastMessageID != oldValue.lastMessageID
      || (newValue.messageCount > oldValue.messageCount
        && newValue.firstMessageID == oldValue.firstMessageID)

    guard appendedMessage, !prependedMessages else { return }

    let isIncoming = lastMessage.senderUserId != AppCoordinator.shared.getCurrentUserId()

    if oldValue.messageCount == 0 || isPinnedToBottom {
      unreadIncomingCount = 0
      showsNewMessagesPill = false
      return
    }

    if !isIncoming {
      return
    }

    unreadIncomingCount += 1
    showsNewMessagesPill = true
    isPinnedToBottom = false
    Haptics.play(.light)
    SoundManager.shared.play("tap")
  }

  private func replyPreviewModel(for message: FriendMessage) -> FriendsChatReplyPreviewModel {
    FriendsChatReplyPreviewModel(
      senderName: message.senderUserId == viewModel.viewerUserId
        ? firstName(from: AppCoordinator.shared.userDisplayName)
        : firstName(from: viewModel.route.displayName),
      message: message
    )
  }

  private func firstName(from displayName: String) -> String {
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "?" }
    return trimmed.components(separatedBy: .whitespacesAndNewlines).first ?? trimmed
  }

  private func flashHighlightedMessage(_ messageId: String) {
    highlightedMessageId = messageId

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      if highlightedMessageId == messageId {
        highlightedMessageId = nil
      }
    }
  }

  private func presentMessageActionMenu(for message: FriendMessage, sourceFrame: CGRect?) {
    let resolvedSourceFrame =
      if let sourceFrame, sourceFrame != .zero {
        sourceFrame
      } else {
        CGRect(x: Spacing.md, y: Spacing.huge, width: 280, height: 88)
      }

    messageActionMenu = MessageActionMenuState(message: message, sourceFrame: resolvedSourceFrame)
  }

  private func dismissMessageActionMenu() {
    messageActionMenu = nil
  }

  private func handleReactionSelection(_ emoji: String, for message: FriendMessage) {
    reactionPaletteStore.recordSelection(emoji)

    Task {
      await viewModel.toggleReaction(messageId: message.id, emoji: emoji)
    }
  }

  private func startCustomReactionInput(for message: FriendMessage) {
    customReactionTarget = message
    customReactionDraft = ""
    isCustomReactionInputActive = true
  }

  private func reportScreenshot() async {
    showScreenshotNotifiedIcon = false

    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
      showScreenshotBubble = true
    }

    do {
      try await ScreenshotNotificationService.shared.reportChatScreenshot(
        threadId: viewModel.route.threadId
      )
      withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
        showScreenshotNotifiedIcon = true
      }
      Haptics.play(.success)
      try? await Task.sleep(for: .seconds(0.3))
      screenshotBellShakeTrigger.toggle()
    } catch {
      // Keep the bubble visible, but don't interrupt chat on notification failure.
    }
  }

  private func dismissScreenshotBubble() {
    withAnimation(.easeOut(duration: 0.2)) {
      showScreenshotBubble = false
    }

    Task {
      try? await Task.sleep(for: .seconds(0.3))
      showScreenshotNotifiedIcon = false
      screenshotBellShakeTrigger = false
    }
  }

  private func dismissComposer() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
  }

  private struct AlertState: Identifiable {
    let id = UUID()
    let title: String
    var message: String? = nil
  }

  private enum ReportTarget: Equatable {
    case user
    case message(messageId: String)

    var messageId: String? {
      switch self {
      case .user:
        return nil
      case .message(let messageId):
        return messageId
      }
    }
  }
}

struct FriendsChatMessageActionLayout {
  static func previewWidth(for bubbleWidth: CGFloat) -> CGFloat {
    min(296, max(160, bubbleWidth))
  }

  static func actionMenuWidth(for bubbleWidth: CGFloat) -> CGFloat {
    min(240, max(176, bubbleWidth + (Spacing.md * 2)))
  }

  static func localSourceFrame(_ globalSourceFrame: CGRect, in overlayGlobalFrame: CGRect) -> CGRect
  {
    CGRect(
      x: globalSourceFrame.minX - overlayGlobalFrame.minX,
      y: globalSourceFrame.minY - overlayGlobalFrame.minY,
      width: globalSourceFrame.width,
      height: globalSourceFrame.height
    )
  }
}

private struct FriendsChatMessageActionMenuOverlay: View {
  let message: FriendMessage
  let viewerUserId: String
  let sourceFrame: CGRect
  let onDismiss: () -> Void
  let onReply: () -> Void
  let onCopy: () -> Void
  let onReport: () -> Void
  let onToggleReaction: (String) -> Void
  let reactionEmojis: [String]
  let onAddCustomReaction: () -> Void

  @State private var hasPresented = false

  private var isCurrentUser: Bool {
    message.senderUserId == viewerUserId
  }

  private var actionRows: [ActionRow] {
    var rows: [ActionRow] = [
      ActionRow(
        title: String(localized: .friendsChatActionReply),
        systemImage: "arrowshape.turn.up.left"
      ) {
        onReply()
      }
    ]

    if let body = message.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
      rows.append(
        ActionRow(
          title: String(localized: .commonCopy),
          systemImage: "doc.on.doc"
        ) {
          onCopy()
        }
      )
    }

    if !isCurrentUser {
      rows.append(
        ActionRow(
          title: String(localized: .friendsChatReportMessage),
          systemImage: "flag"
        ) {
          onReport()
        }
      )
    }

    return rows
  }

  var body: some View {
    GeometryReader { geometry in
      let horizontalMargin = Spacing.md
      let safeTop = geometry.safeAreaInsets.top + Spacing.md
      let safeBottom = geometry.safeAreaInsets.bottom + Spacing.md
      let overlayGlobalFrame = geometry.frame(in: .global)
      let localSourceFrame = FriendsChatMessageActionLayout.localSourceFrame(
        sourceFrame,
        in: overlayGlobalFrame
      )
      let maxContentWidth = geometry.size.width - (horizontalMargin * 2)
      let previewWidth = min(
        FriendsChatMessageActionLayout.previewWidth(for: localSourceFrame.width),
        maxContentWidth
      )
      let actionMenuWidth = min(
        FriendsChatMessageActionLayout.actionMenuWidth(for: localSourceFrame.width),
        maxContentWidth
      )
      let previewX =
        isCurrentUser
        ? min(
          max(horizontalMargin, localSourceFrame.maxX - previewWidth),
          geometry.size.width - previewWidth - horizontalMargin)
        : min(
          max(horizontalMargin, localSourceFrame.minX),
          geometry.size.width - previewWidth - horizontalMargin)
      let actionMenuX =
        isCurrentUser
        ? min(
          max(horizontalMargin, localSourceFrame.maxX - actionMenuWidth),
          geometry.size.width - actionMenuWidth - horizontalMargin)
        : min(
          max(horizontalMargin, localSourceFrame.minX),
          geometry.size.width - actionMenuWidth - horizontalMargin)
      let estimatedHeight =
        CGFloat(actionRows.count) * 56
        + (message.canReact ? 66 : 0)
        + previewHeightEstimate
      let previewY = min(
        max(safeTop, localSourceFrame.minY - 84),
        geometry.size.height - estimatedHeight - safeBottom
      )
      let previewStartX = min(
        max(
          horizontalMargin,
          isCurrentUser ? localSourceFrame.maxX - previewWidth : localSourceFrame.minX
        ),
        geometry.size.width - previewWidth - horizontalMargin
      )
      let previewStartY = min(
        max(safeTop, localSourceFrame.minY),
        geometry.size.height - localSourceFrame.height - safeBottom
      )
      let actionMenuY = previewY + localSourceFrame.height + Spacing.xs

      ZStack(alignment: .topLeading) {
        Color.black.opacity(hasPresented ? 0.3 : 0)
          .ignoresSafeArea()
          .onTapGesture {
            onDismiss()
          }
          .animation(.easeOut(duration: 0.18), value: hasPresented)

        if message.canReact {
          HStack(spacing: Spacing.xs) {
            ForEach(reactionEmojis, id: \.self) { emoji in
              let isSelected = message.reactions.contains {
                $0.emoji == emoji && $0.viewerHasReacted
              }

              Button {
                onToggleReaction(emoji)
              } label: {
                FriendsChatEmojiGlyph(emoji: emoji, size: 28)
                  .frame(width: 42, height: 42)
                  .background(
                    Circle()
                      .fill(isSelected ? Color.tidexBlue.opacity(0.14) : Color.clear)
                  )
              }
              .buttonStyle(.plain)
            }

            Button {
              onAddCustomReaction()
            } label: {
              Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)
                .frame(width: 42, height: 42)
                .background(
                  Circle()
                    .fill(Color.tidexSurfacePrimary.opacity(0.72))
                )
                .overlay(
                  Circle()
                    .stroke(Color.tidexBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("friends.chat.customReaction.title"))
          }
          .padding(.horizontal, Spacing.sm)
          .padding(.vertical, Spacing.xs)
          .tidexGlass(shape: .capsule, tint: .tidexBlue.opacity(0.08), interactive: true)
          .frame(width: previewWidth, alignment: isCurrentUser ? .trailing : .leading)
          .offset(x: previewX, y: previewY - 74)
          .opacity(hasPresented ? 1 : 0)
          .offset(y: hasPresented ? 0 : 10)
          .animation(.spring(response: 0.26, dampingFraction: 0.84), value: hasPresented)
        }

        HStack {
          if isCurrentUser { Spacer(minLength: 0) }
          FriendsChatActionMessagePreview(
            message: message,
            isCurrentUser: isCurrentUser
          )
          if !isCurrentUser { Spacer(minLength: 0) }
        }
        .frame(width: previewWidth)
        .offset(
          x: hasPresented ? previewX : previewStartX,
          y: hasPresented ? previewY : previewStartY
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: hasPresented)

        VStack(spacing: 0) {
          ForEach(Array(actionRows.enumerated()), id: \.offset) { index, row in
            Button(action: row.action) {
              HStack(spacing: Spacing.sm) {
                Image(systemName: row.systemImage)
                  .font(.system(size: 18, weight: .medium))
                  .frame(width: 24, height: 24)
                  .foregroundColor(.tidexBlue)

                Text(row.title)
                  .font(.tidexBody)
                  .foregroundColor(.tidexTextPrimary)

                Spacer(minLength: 0)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, Spacing.md)
              .padding(.vertical, Spacing.md)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if index < actionRows.count - 1 {
              Divider()
                .overlay(Color.tidexBorderSubtle)
                .padding(.horizontal, Spacing.md)
            }
          }
        }
        .frame(width: actionMenuWidth)
        .fixedSize(horizontal: true, vertical: false)
        .tidexGlass(shape: .rect(cornerRadius: CornerRadius.xl), tint: .tidexBlue.opacity(0.06))
        .offset(x: actionMenuX, y: actionMenuY)
        .opacity(hasPresented ? 1 : 0)
        .offset(y: hasPresented ? 0 : 14)
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: hasPresented)
      }
      .onAppear {
        guard !hasPresented else { return }
        hasPresented = true
      }
    }
  }

  private struct ActionRow {
    let title: String
    let systemImage: String
    let action: () -> Void
  }

  private var previewHeightEstimate: CGFloat {
    let hasMessageText =
      !(message.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

    if message.shiftSnapshot != nil {
      return hasMessageText ? 276 : 192
    }

    if message.hasImageAttachment && !hasMessageText {
      return 172
    }

    return 108
  }
}

@MainActor
final class FriendsChatReactionPaletteStore: ObservableObject {
  private enum Constants {
    static let defaults = ["❤️", "👍", "😂", "🔥", "😮", "😢"]
    static let maxVisible = 6
    static let maxRecents = 12
    static let recentsKey = "friends.chat.reaction.recents"
  }

  @Published private(set) var displayEmojis: [String] = Constants.defaults

  private let userDefaults: UserDefaults
  private var recentEmojis: [String] = []

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
    load()
  }

  func recordSelection(_ emoji: String) {
    guard let normalizedEmoji = Self.normalizedEmoji(from: emoji) else { return }

    recentEmojis.removeAll { $0 == normalizedEmoji }
    recentEmojis.insert(normalizedEmoji, at: 0)

    if recentEmojis.count > Constants.maxRecents {
      recentEmojis = Array(recentEmojis.prefix(Constants.maxRecents))
    }

    persist()
    rebuildDisplayEmojis()
  }

  static func normalizedEmoji(from rawValue: String) -> String? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let firstCharacter = trimmed.first, firstCharacter.isEmojiLike else { return nil }
    return String(firstCharacter)
  }

  private func load() {
    recentEmojis =
      (userDefaults.stringArray(forKey: Constants.recentsKey) ?? [])
      .compactMap(Self.normalizedEmoji(from:))
    rebuildDisplayEmojis()
  }

  private func persist() {
    userDefaults.set(recentEmojis, forKey: Constants.recentsKey)
  }

  private func rebuildDisplayEmojis() {
    let recentSlice = Array(recentEmojis.prefix(Constants.maxVisible))
    let fallback = Constants.defaults.filter { !recentSlice.contains($0) }
    displayEmojis = Array((recentSlice + fallback).prefix(Constants.maxVisible))
  }
}

private struct FriendsChatSystemEmojiInputHost: UIViewRepresentable {
  @Binding var text: String
  @Binding var isActive: Bool

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, isActive: $isActive)
  }

  func makeUIView(context: Context) -> FriendsChatSystemEmojiTextField {
    let textField = FriendsChatSystemEmojiTextField(frame: .zero)
    textField.delegate = context.coordinator
    textField.autocorrectionType = .no
    textField.spellCheckingType = .no
    textField.autocapitalizationType = .none
    textField.keyboardType = .default
    textField.returnKeyType = .done
    textField.textColor = .clear
    textField.tintColor = .clear
    textField.backgroundColor = .clear
    textField.isAccessibilityElement = false
    textField.addTarget(
      context.coordinator,
      action: #selector(Coordinator.textDidChange(_:)),
      for: .editingChanged
    )
    return textField
  }

  func updateUIView(_ uiView: FriendsChatSystemEmojiTextField, context: Context) {
    if uiView.text != text {
      uiView.text = text
    }

    if isActive {
      guard !uiView.isFirstResponder else { return }

      DispatchQueue.main.async {
        guard isActive else { return }
        uiView.becomeFirstResponder()
      }
      return
    }

    if uiView.isFirstResponder {
      uiView.resignFirstResponder()
    }
  }

  final class Coordinator: NSObject, UITextFieldDelegate {
    @Binding private var text: String
    @Binding private var isActive: Bool

    init(text: Binding<String>, isActive: Binding<Bool>) {
      _text = text
      _isActive = isActive
    }

    @objc
    func textDidChange(_ textField: UITextField) {
      text = textField.text ?? ""
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
      isActive = true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
      isActive = false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
      textField.resignFirstResponder()
      return false
    }
  }
}

private final class FriendsChatSystemEmojiTextField: UITextField {
  override var textInputContextIdentifier: String? {
    ""
  }

  override var textInputMode: UITextInputMode? {
    if let emojiInputMode = UITextInputMode.activeInputModes.first(where: {
      $0.primaryLanguage == "emoji"
    }) {
      return emojiInputMode
    }

    return super.textInputMode
  }
}

extension Character {
  fileprivate var isEmojiLike: Bool {
    unicodeScalars.contains {
      $0.properties.isEmojiPresentation || $0.properties.isEmoji
    }
  }
}

private struct FriendsChatActionMessagePreview: View {
  let message: FriendMessage
  let isCurrentUser: Bool

  private var messageText: String? {
    let trimmed = message.body?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let trimmed, !trimmed.isEmpty else { return nil }
    return trimmed
  }

  var body: some View {
    VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: Spacing.xs) {
      if let shiftSnapshot = message.shiftSnapshot {
        ChatShiftSnapshotCard(snapshot: shiftSnapshot, isCurrentUser: isCurrentUser)
      }

      if message.hasImageAttachment {
        RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
          .fill(isCurrentUser ? Color.tidexBrandPrimary.opacity(0.9) : Color.tidexSurfacePrimary)
          .frame(width: 200, height: 144)
          .overlay {
            Image(systemName: "photo")
              .font(.system(size: 28, weight: .semibold))
              .foregroundColor(isCurrentUser ? .tidexTextOnBrand : .tidexTextPrimary)
          }
          .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
              .stroke(isCurrentUser ? Color.white.opacity(0.18) : Color.tidexBorder, lineWidth: 1)
          )
      }

      if let messageText {
        ChatBubbleCard(
          isCurrentUser: isCurrentUser,
          minWidth: 120,
          maxWidth: 280
        ) {
          Text(messageText)
            .font(.tidexBody)
            .foregroundColor(isCurrentUser ? .tidexTextOnBrand : .tidexTextPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
      } else if !message.hasImageAttachment, message.shiftSnapshot == nil,
        let previewText = message.previewText
      {
        ChatBubbleCard(
          isCurrentUser: isCurrentUser,
          minWidth: 120,
          maxWidth: 280
        ) {
          HStack(alignment: .firstTextBaseline, spacing: Spacing.xxxs) {
            if let iconSystemName = message.previewKind.friendsChatReplyIconSystemName {
              Image(systemName: iconSystemName)
                .font(.tidexCaptionRegular)
                .foregroundColor(isCurrentUser ? .tidexTextOnBrand : .tidexTextMuted)
            }

            Text(previewText)
              .font(.tidexBody)
              .foregroundColor(isCurrentUser ? .tidexTextOnBrand : .tidexTextPrimary)
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }
}

private struct DraftReplyBanner: View {
  let preview: FriendsChatReplyPreviewModel
  let onCancel: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      HStack(alignment: .top, spacing: Spacing.xs) {
        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
          .fill(Color.tidexBlue.opacity(0.7))
          .frame(width: 3, height: 30)

        VStack(alignment: .leading, spacing: 3) {
          Text(preview.senderName)
            .font(.tidexCaptionStrong)
            .foregroundColor(.tidexBlue)

          HStack(alignment: .firstTextBaseline, spacing: Spacing.xxxs) {
            if let iconSystemName = preview.iconPreviewKind?.friendsChatReplyIconSystemName {
              Image(systemName: iconSystemName)
                .font(.tidexCaptionRegular)
                .foregroundColor(.tidexTextMuted)
            }

            Text(preview.snippet)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)
              .lineLimit(1)
          }
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(Color.tidexSurfaceSecondary.opacity(0.72))
      )
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .stroke(Color.tidexBorder.opacity(0.4), lineWidth: 1)
      )

      Button(action: onCancel) {
        Image(systemName: "xmark")
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexTextMuted)
          .frame(width: 32, height: 32)
          .background(
            Circle()
              .fill(Color.tidexSurfaceSecondary)
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(String(localized: .commonCancel)))
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .stroke(Color.tidexBorder.opacity(0.35), lineWidth: 1)
    )
  }
}

extension FriendAbuseReportReason {
  fileprivate var localizedTitle: String {
    switch self {
    case .harassmentOrBullying:
      return String(localized: .friendsChatReasonHarassment)
    case .sexualContent:
      return String(localized: .friendsChatReasonSexual)
    case .hateOrDiscriminatoryContent:
      return String(localized: .friendsChatReasonHate)
    case .violenceOrThreats:
      return String(localized: .friendsChatReasonViolence)
    case .spam:
      return String(localized: .friendsChatReasonSpam)
    case .inappropriateProfileOrConduct:
      return String(localized: .friendsChatReasonInappropriateProfile)
    case .other:
      return String(localized: .friendsChatReasonOther)
    }
  }
}
