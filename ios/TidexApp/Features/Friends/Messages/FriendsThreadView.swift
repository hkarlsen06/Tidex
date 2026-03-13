import ExyteChat
import SwiftUI
import UIKit

struct FriendsThreadView: View {
  @Environment(\.openURL) private var openURL

  @StateObject private var viewModel: FriendsThreadViewModel
  @StateObject private var composerBridge = FriendsThreadComposerBridge()
  @StateObject private var reactionPaletteStore = FriendsChatReactionPaletteStore()

  @State private var pendingReportTarget: ReportTarget?
  @State private var showBlockConfirmation = false
  @State private var showSafetySupport = false
  @State private var safariURL: URL?
  @State private var alertState: AlertState?
  @State private var highlightedMessageId: String?
  @State private var unreadIncomingCount = 0
  @State private var showsNewMessagesPill = false
  @State private var showScreenshotBubble = false
  @State private var showScreenshotNotifiedIcon = false
  @State private var screenshotBellShakeTrigger = false
  @State private var showProfile = false
  @State private var isPinnedToBottom = true
  @State private var lastHandledNavigationRequestId: UUID?

  init(route: FriendChatRoute, viewerUserId: String) {
    _viewModel = StateObject(
      wrappedValue: FriendsThreadViewModel(route: route, viewerUserId: viewerUserId)
    )
  }

  private var currentUserDisplayName: String {
    AppCoordinator.shared.userDisplayName
  }

  private var counterpartDisplayName: String {
    viewModel.thread.counterpartDisplayName ?? viewModel.route.displayName
  }

  private var counterpartAvatarUrl: String? {
    viewModel.thread.counterpartAvatarUrl ?? viewModel.route.avatarUrl
  }

  private var counterpartProfileUser: SharedUser {
    SharedUser(
      id: viewModel.route.counterpartUserId,
      email: nil,
      phone: nil,
      firstName: counterpartDisplayName,
      profilePictureUrl: counterpartAvatarUrl,
      oauthAvatarUrl: nil,
      sharedAt: "",
      showEarnings: false,
      hidden: false
    )
  }

  private var composerConfiguration: FriendsThreadComposerConfiguration {
    FriendsThreadComposerConfiguration(
      mode: viewModel.composerMode,
      draftText: viewModel.draft,
      replyPreview: viewModel.draftReplyTarget.map { replyPreviewModel(for: $0) },
      stagedAttachment: viewModel.stagedComposerAttachment,
      isThreadReadOnly: viewModel.isThreadReadOnly,
      sendErrorMessage: viewModel.sendErrorMessage,
      placeholder: String(localized: .friendsChatPlaceholder),
      canSendShiftSnapshots: viewModel.canSendShiftSnapshots,
      focusRequestToken: viewModel.composerFocusRequestToken
    )
  }

  private var latestOutgoingMessageId: String? {
    FriendsThreadMessageStatusResolver.latestOutgoingMessageId(
      messages: viewModel.messages,
      viewerUserId: viewModel.viewerUserId
    )
  }

  private var readReceiptMessageId: String? {
    FriendsThreadMessageStatusResolver.readReceiptMessageId(
      messages: viewModel.messages,
      viewerUserId: viewModel.viewerUserId,
      counterpartLastReadMessageId: viewModel.counterpartReadState?.lastReadMessageId,
      counterpartLastReadAt: viewModel.counterpartReadState?.lastReadAt
    )
  }

  private var presentedMessageLookup: [String: FriendMessage] {
    Dictionary(
      uniqueKeysWithValues: viewModel.messages.map {
        (
          FriendsThreadMessagePresentationID.make(
            for: $0,
            viewerUserId: viewModel.viewerUserId
          ),
          $0
        )
      }
    )
  }

  private var presentedMessageIDs: [String] {
    viewModel.messages.map {
      FriendsThreadMessagePresentationID.make(for: $0, viewerUserId: viewModel.viewerUserId)
    }
  }

  private var exyteMessages: [ExyteChat.Message] {
    FriendsThreadExyteHighlightRedrawResolver.applyingHighlightMarker(
      to: FriendsThreadExyteMessageFactory.makeMessages(
        messages: viewModel.messages,
        conversation: .init(
          viewerUserId: viewModel.viewerUserId,
          currentUserDisplayName: currentUserDisplayName,
          counterpartDisplayName: counterpartDisplayName,
          counterpartAvatarUrl: counterpartAvatarUrl,
          quotedMessagesById: viewModel.quotedMessagesById,
          counterpartLastReadMessageId: viewModel.counterpartReadState?.lastReadMessageId,
          counterpartLastReadAt: viewModel.counterpartReadState?.lastReadAt
        )
      ),
      highlightedPresentedMessageID: highlightedPresentedMessageID
    )
  }

  private var viewportScrollRequest: FriendsThreadChatViewportScrollRequest? {
    FriendsThreadChatViewportRequestResolver.request(
      replyTargetMessageId: viewModel.replyScrollTargetMessageId,
      restoreTargetMessageId: viewModel.restoreScrollTargetMessageId,
      messages: viewModel.messages,
      viewerUserId: viewModel.viewerUserId
    )
  }

  private var highlightedPresentedMessageID: String? {
    FriendsThreadChatViewportRequestResolver.presentedMessageID(
      for: highlightedMessageId,
      messages: viewModel.messages,
      viewerUserId: viewModel.viewerUserId
    )
  }

  private func messageID(for presentedMessageID: String) -> String {
    presentedMessageLookup[presentedMessageID]?.id
      ?? presentedMessageID.replacingOccurrences(of: "message:", with: "")
  }

  var body: some View {
    threadContent
      .task {
        syncComposerBridge()
        await viewModel.loadIfNeeded()
      }
      .task(id: viewModel.route.navigationRequestId) {
        await handleRouteNavigationIfNeeded()
      }
      .onAppear {
        syncComposerBridge()
        FriendsChatPresentationState.shared.setActiveThreadId(viewModel.route.threadId)
        Task {
          await NotificationService.shared.clearDeliveredFriendChatNotifications(
            for: viewModel.route.threadId
          )
        }
      }
      .onChange(of: composerConfiguration) { _, _ in
        syncComposerBridge()
      }
      .onChange(of: isPinnedToBottom) { _, newValue in
        guard newValue else { return }
        unreadIncomingCount = 0
        showsNewMessagesPill = false
        Task {
          await viewModel.markVisibleMessagesReadIfNeeded()
        }
      }
      .onChange(of: presentedMessageIDs) { oldValue, newValue in
        handleMessageIDsChange(from: oldValue, to: newValue)
      }
      .onDisappear {
        FriendsThreadMessageHighlightRegistry.setHighlightedMessageID(
          nil, in: viewModel.route.threadId)
        FriendsChatPresentationState.shared.setActiveThreadId(nil)
        Task {
          await viewModel.stopRealtime()
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .friendsThreadDidUpdate)) {
        notification in
        guard let threadId = notification.userInfo?["threadId"] as? String,
          threadId == viewModel.route.threadId
        else {
          return
        }

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
  }

  private var threadContent: some View {
    VStack(spacing: 0) {
      counterpartShiftPreviewHeader

      ZStack(alignment: .top) {
        chatView

        if viewModel.isLoadingOlderMessages && !viewModel.messages.isEmpty {
          olderMessagesLoadingState
            .padding(.top, Spacing.md)
        }

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
              )
            )
        }

        if viewModel.isLoading && viewModel.messages.isEmpty {
          loadingState
        } else if viewModel.messages.isEmpty {
          emptyState
        }

      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.tidexBackground.ignoresSafeArea())
    .navigationBarTitleDisplayMode(.inline)
    .iPadToolbarBackground()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        actionsMenu
      }
    }
    .iPadToolbarTransaction()
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
      if pendingReportTarget == .user {
        reportButton(.harassmentOrBullying)
        reportButton(.spam)
        reportButton(.inappropriateProfileOrConduct)
        reportButton(.other)
      } else if pendingReportTarget?.messageId != nil {
        reportButton(.harassmentOrBullying)
        reportButton(.sexualContent)
        reportButton(.hateOrDiscriminatoryContent)
        reportButton(.violenceOrThreats)
        reportButton(.spam)
        reportButton(.other)
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
  }

  private var chatView: some View {
    ChatView(
      messages: exyteMessages,
      chatType: .conversation,
      replyMode: .quote,
      messageBuilder: { message, _, _, _, _, _, _ in
        chatRow(for: message)
      },
      inputViewBuilder: { text, _, _, _, _, _ in
        FriendsThreadComposerHostedView(
          bridge: composerBridge,
          text: text
        )
      },
      messageMenuAction: handleMessageMenuAction,
      localization: chatLocalization,
      didSendMessage: { draft in
        Task { @MainActor in
          _ = await viewModel.sendMessage(content: draft.text)
        }
      }
    )
    .showDateHeaders(true)
    .headerBuilder { date in
      FriendsThreadDateSeparator(date: date)
    }
    .betweenListAndInputViewBuilder {
      chatFooterAccessory
    }
    .showMessageTimeView(false)
    .showMessageMenuOnLongPress(true)
    .setAvailableInputs([.text])
    .keyboardDismissMode(.interactive)
    .enableLoadMore(pageSize: 50) { message in
      await viewModel.loadOlderMessagesIfNeeded(currentFirstMessageId: messageID(for: message.id))
    }
    .onMessageReaction(
      didReactTo: { message, draftReaction in
        guard case .emoji(let emoji) = draftReaction.type else { return }
        guard let friendMessage = presentedMessageLookup[message.id] else { return }
        handleReactionSelection(emoji, forMessageId: friendMessage.id)
      },
      canReactTo: { message in
        presentedMessageLookup[message.id]?.canReact ?? false
      },
      availableReactionsFor: { _ in
        reactionPaletteStore.displayEmojis.map(ReactionType.emoji)
      },
      allowEmojiSearchFor: { message in
        presentedMessageLookup[message.id]?.canReact ?? false
      },
      shouldShowOverviewFor: { _ in false }
    )
    .chatTheme(chatTheme)
    .background(Color.tidexBackground)
    .overlay {
      FriendsThreadChatViewportBridge(
        messages: exyteMessages,
        scrollRequest: viewportScrollRequest,
        highlightedPresentedMessageID: highlightedPresentedMessageID,
        onPinnedToBottomChanged: { isPinnedToBottom = $0 },
        onDidHandleScrollRequest: handleViewportScrollRequest
      )
      .allowsHitTesting(false)
    }
  }

  @ViewBuilder
  private var chatFooterAccessory: some View {
    if showsNewMessagesPill || viewModel.counterpartIsTyping {
      VStack(spacing: 0) {
        if showsNewMessagesPill, !viewModel.messages.isEmpty {
          HStack {
            Spacer(minLength: 0)
            scrollToLatestButton
            Spacer(minLength: 0)
          }
          .padding(.top, Spacing.xs)
          .padding(.bottom, viewModel.counterpartIsTyping ? 0 : Spacing.xs)
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        if viewModel.counterpartIsTyping {
          FriendsChatTypingAccessory(
            counterpartAvatarUrl: counterpartAvatarUrl,
            counterpartInitials: FriendsChatMessageGrouping.initials(from: counterpartDisplayName)
          )
        }
      }
      .background(Color.tidexBackground)
    }
  }

  @ViewBuilder
  private func chatRow(for exyteMessage: ExyteChat.Message) -> some View {
    if let message = presentedMessageLookup[exyteMessage.id] {
      let isCurrentUser = message.senderUserId == viewModel.viewerUserId
      let index = viewModel.messages.firstIndex(where: { $0.id == message.id })
      let previousMessage = index.flatMap { $0 > 0 ? viewModel.messages[$0 - 1] : nil }
      let nextMessage = index.flatMap {
        $0 < (viewModel.messages.count - 1) ? viewModel.messages[$0 + 1] : nil
      }
      let groupContext = FriendsChatMessageGrouping.context(
        for: message,
        previous: previousMessage,
        next: nextMessage,
        viewerUserId: viewModel.viewerUserId
      )
      let messageStatus = FriendsThreadMessageStatusResolver.status(
        for: message,
        viewerUserId: viewModel.viewerUserId,
        latestOutgoingMessageId: latestOutgoingMessageId,
        readReceiptMessageId: readReceiptMessageId
      )
      let shouldShowTimestamp = FriendsThreadMessageStatusResolver.shouldShowTimestamp(
        for: message,
        isCurrentUser: isCurrentUser,
        groupContext: groupContext,
        messageStatus: messageStatus
      )

      FriendsChatMessageRowContent(
        message: message,
        quotedPreview: viewModel.quotedMessage(for: message).map(replyPreviewModel(for:)),
        isCurrentUser: isCurrentUser,
        groupContext: groupContext,
        counterpartAvatarUrl: counterpartAvatarUrl,
        counterpartAvatarInitials: FriendsChatMessageGrouping.initials(
          from: counterpartDisplayName),
        isHighlighted: FriendsThreadMessageHighlightRegistry.isHighlighted(
          messageID: message.id,
          in: viewModel.route.threadId
        ),
        senderFirstName: firstName(
          from: isCurrentUser ? currentUserDisplayName : counterpartDisplayName
        ),
        separatorDate: nil,
        showsSenderLabel: false,
        showsTimestamp: shouldShowTimestamp,
        messageStatus: messageStatus,
        onReply: {
          viewModel.setReplyTarget(message)
        },
        onRetry: {
          Task {
            await viewModel.retryMessage(messageId: message.id)
          }
        },
        onToggleReaction: { emoji in
          handleReactionSelection(emoji, forMessageId: message.id)
        },
        onTapQuotedMessage: {
          handleQuotedMessageTap(for: message)
        }
      )
      .id(exyteMessage.id)
    } else {
      EmptyView()
    }
  }

  @ViewBuilder
  private var counterpartShiftPreviewHeader: some View {
    if let counterpartShiftPreview = viewModel.counterpartShiftPreview {
      Button {
        openCounterpartShiftPreview(preview: counterpartShiftPreview)
      } label: {
        CompactFriendShiftPreviewHeader(preview: counterpartShiftPreview)
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(.horizontal, Spacing.md)
      .padding(.top, Spacing.xxs)
      .padding(.bottom, Spacing.xxs)
      .frame(maxWidth: .infinity)
      .background(Color.tidexBackground)
      .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 10)
    }
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

  private var screenshotBubble: some View {
    ScreenshotNotificationBubble(
      showNotifiedIcon: showScreenshotNotifiedIcon,
      bellShakeTrigger: screenshotBellShakeTrigger
    )
  }

  private var scrollToLatestButton: some View {
    Button {
      unreadIncomingCount = 0
      showsNewMessagesPill = false
      Haptics.play(.light)
      SoundManager.shared.play("tap")
      requestScrollToBottom()
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
        displayName: counterpartDisplayName,
        avatarUrl: counterpartAvatarUrl,
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

  private func reportButton(_ reason: FriendAbuseReportReason) -> some View {
    Button(reason.localizedTitle) {
      submitReport(reason: reason)
    }
  }

  private var chatLocalization: ChatLocalization {
    ChatLocalization(
      inputPlaceholder: String(localized: .friendsChatPlaceholder),
      signatureText: String(localized: "friends.chat.signatureText", table: "Localizable"),
      cancelButtonText: String(localized: .commonCancel),
      recentToggleText: String(localized: "friends.chat.recentToggle", table: "Localizable"),
      waitingForNetwork: String(localized: "friends.chat.waitingForNetwork", table: "Localizable"),
      recordingText: String(localized: "friends.chat.recording", table: "Localizable"),
      replyToText: String(localized: "friends.chat.replyTo", table: "Localizable")
    )
  }

  private var chatTheme: ChatTheme {
    ChatTheme(
      colors: .init(
        mainBG: .tidexBackground,
        mainTint: .tidexBlue,
        mainText: .tidexTextPrimary,
        mainCaptionText: .tidexTextSecondary,
        messageMyBG: .tidexBrandPrimary,
        messageReadStatus: .tidexBlue,
        messageMyText: .tidexTextOnBrand,
        messageMyTimeText: .tidexTextOnBrand.opacity(0.72),
        messageFriendBG: .tidexSurfacePrimary,
        messageFriendText: .tidexTextPrimary,
        messageFriendTimeText: .tidexTextMuted,
        messageSystemBG: .tidexSurfaceSecondary,
        messageSystemText: .tidexTextPrimary,
        messageSystemTimeText: .tidexTextMuted,
        inputBG: .tidexBackground,
        inputText: .tidexTextPrimary,
        inputPlaceholderText: .tidexTextMuted,
        inputSignatureBG: .tidexBackground,
        inputSignatureText: .tidexTextPrimary,
        inputSignaturePlaceholderText: .tidexTextMuted,
        menuBG: .tidexSurfacePrimary,
        menuText: .tidexTextPrimary,
        menuTextDelete: .tidexError,
        statusError: .tidexError,
        statusGray: .tidexTextMuted,
        sendButtonBackground: .tidexBrandPrimary,
        recordDot: .tidexError
      )
    )
  }

  private func syncComposerBridge() {
    composerBridge.onDraftChanged = { draft in
      viewModel.draft = draft
      Task {
        await viewModel.handleDraftChanged(to: draft)
      }
    }
    composerBridge.onStagedAttachmentChanged = { attachment in
      viewModel.stagedComposerAttachment = attachment
      Task {
        await viewModel.setComposerAttachment(attachment)
      }
    }
    composerBridge.onPrepareShiftSnapshotAttachment = { shift in
      await viewModel.prepareShiftSnapshotAttachment(for: shift)
    }
    composerBridge.onCancelMode = {
      Task {
        await viewModel.cancelComposerMode()
      }
    }
    composerBridge.onSend = { content in
      let wasPinnedToBottom = isPinnedToBottom
      let didSend = await viewModel.sendMessage(content: content)
      guard didSend else { return false }

      await MainActor.run {
        unreadIncomingCount = 0
        showsNewMessagesPill = false
        if !wasPinnedToBottom {
          requestScrollToBottom()
        }
      }
      return true
    }
    composerBridge.onSaveEdit = { content in
      await viewModel.sendMessage(content: content)
    }
    composerBridge.onAttachmentDrawerOpenChanged = nil
    composerBridge.onHeightChanged = nil
    composerBridge.apply(configuration: composerConfiguration)
  }

  private func handleMessageMenuAction(
    _ action: FriendsThreadMessageMenuAction,
    _ defaultActionClosure: @escaping (ExyteChat.Message, DefaultMessageMenuAction) -> Void,
    _ message: ExyteChat.Message
  ) {
    guard let friendMessage = presentedMessageLookup[message.id] else { return }

    switch action {
    case .reply:
      viewModel.setReplyTarget(friendMessage)
    case .copy:
      UIPasteboard.general.string = friendMessage.body
    case .edit:
      Task {
        await viewModel.startEditing(friendMessage)
      }
    case .delete:
      Task {
        await viewModel.deleteMessage(messageId: friendMessage.id)
      }
    case .report:
      pendingReportTarget = .message(messageId: friendMessage.id)
    }
  }

  private func handleMessageIDsChange(from oldValue: [String], to newValue: [String]) {
    guard !newValue.isEmpty, newValue != oldValue else { return }
    guard let lastMessage = viewModel.messages.last else { return }

    let prependedMessages = FriendsThreadMessageListChangeResolver.isPrependedMessage(
      oldMessageIDs: oldValue,
      newMessageIDs: newValue
    )
    let appendedMessage = FriendsThreadMessageListChangeResolver.isAppendedMessage(
      oldMessageIDs: oldValue,
      newMessageIDs: newValue
    )

    guard appendedMessage, !prependedMessages else { return }
    if lastMessage.senderUserId == viewModel.viewerUserId {
      unreadIncomingCount = 0
      showsNewMessagesPill = false
      if !isPinnedToBottom {
        requestScrollToBottom()
      }
      return
    }

    let appendOutcome = FriendsThreadIncomingAppendResolver.resolve(
      previousMessageCount: oldValue.count,
      unreadIncomingCount: unreadIncomingCount,
      isIncoming: true,
      isPinnedToBottom: isPinnedToBottom
    )
    unreadIncomingCount = appendOutcome.unreadIncomingCount
    showsNewMessagesPill = appendOutcome.showsNewMessagesPill

    if appendOutcome.shouldPlayFeedback {
      Haptics.play(.light)
      SoundManager.shared.play("tap")
      return
    }

    guard isPinnedToBottom else { return }

    Task {
      await viewModel.markVisibleMessagesReadIfNeeded()
    }
  }

  private func requestScrollToBottom() {
    NotificationCenter.default.post(name: .onScrollToBottom, object: nil)

    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(120))
      NotificationCenter.default.post(name: .onScrollToBottom, object: nil)
    }
  }

  private func openCounterpartShiftPreview(preview: SharerShiftPreview) {
    guard let deepLink = FriendsThreadCounterpartPreviewNavigationResolver.deepLink(for: preview)
    else {
      return
    }

    AppCoordinator.shared.pendingDeepLink = deepLink
  }

  private func handleReactionSelection(_ emoji: String, forMessageId messageId: String) {
    reactionPaletteStore.recordSelection(emoji)

    Task {
      await viewModel.toggleReaction(messageId: messageId, emoji: emoji)
    }
  }

  private func handleQuotedMessageTap(for message: FriendMessage) {
    Task {
      await viewModel.scrollToReplyTarget(for: message)
    }
  }

  private func handleViewportScrollRequest(_ request: FriendsThreadChatViewportScrollRequest) {
    switch request.kind {
    case .reply:
      flashHighlightedMessage(request.messageID)
      viewModel.consumeReplyScrollTarget()
      viewModel.consumeRestoreScrollTarget()
    case .restore:
      viewModel.consumeRestoreScrollTarget()
    }
  }

  private func replyPreviewModel(for message: FriendMessage) -> FriendsChatReplyPreviewModel {
    FriendsChatReplyPreviewModel(
      senderName: message.senderUserId == viewModel.viewerUserId
        ? firstName(from: currentUserDisplayName)
        : firstName(from: counterpartDisplayName),
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
    FriendsThreadMessageHighlightRegistry.setHighlightedMessageID(
      messageId,
      in: viewModel.route.threadId
    )

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      if highlightedMessageId == messageId {
        highlightedMessageId = nil
        FriendsThreadMessageHighlightRegistry.setHighlightedMessageID(
          nil,
          in: viewModel.route.threadId
        )
      }
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

  private func handleRouteNavigationIfNeeded() async {
    guard let navigationRequestId = viewModel.route.navigationRequestId,
      lastHandledNavigationRequestId != navigationRequestId
    else {
      return
    }

    lastHandledNavigationRequestId = navigationRequestId
    await viewModel.handleNotificationOpen(
      targetMessageId: viewModel.route.initialMessageId,
      forceRefresh: true
    )
  }
}

private struct FriendsChatTypingAccessory: View {
  let counterpartAvatarUrl: String?
  let counterpartInitials: String

  var body: some View {
    HStack(spacing: Spacing.xs) {
      AvatarView(
        url: counterpartAvatarUrl,
        initials: counterpartInitials,
        size: AvatarView.Size.small,
        cornerRadius: CornerRadius.md
      )

      TypingIndicatorView()

      Spacer(minLength: 0)
    }
    .padding(.horizontal, Spacing.md)
    .padding(.top, Spacing.xxs)
    .padding(.bottom, Spacing.xs)
    .background(Color.tidexBackground)
  }
}

@MainActor
final class FriendsChatReactionPaletteStore: ObservableObject {
  private enum Constants {
    static let defaults = ["❤️", "👍", "😂", "🔥", "😮", "😢"]
    static let maxVisible = 5
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
    guard let firstCharacter = trimmed.first, firstCharacter.tidexIsEmojiLike else { return nil }
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

private struct FriendsThreadDateSeparator: View {
  let date: Date

  var body: some View {
    HStack(spacing: Spacing.sm) {
      Rectangle()
        .fill(Color.tidexBorderSubtle)
        .frame(height: 1)

      Text(separatorText)
        .font(.tidexMicro)
        .foregroundColor(.tidexTextMuted)
        .fixedSize(horizontal: true, vertical: false)

      Rectangle()
        .fill(Color.tidexBorderSubtle)
        .frame(height: 1)
    }
    .frame(width: separatorWidth)
    .padding(.vertical, Spacing.xs)
  }

  private var separatorWidth: CGFloat {
    let screenWidth =
      UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first?
      .screen
      .bounds
      .width
      ?? 390

    return screenWidth - (Spacing.md * 2)
  }

  private var separatorText: String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
      return String(localized: .commonToday)
    }
    if calendar.isDateInYesterday(date) {
      return String(localized: .commonYesterday)
    }

    if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
      return date.formatted(
        .dateTime
          .weekday(.wide)
          .day()
          .month(.wide)
      )
    }

    return date.formatted(
      .dateTime
        .weekday(.wide)
        .day()
        .month(.wide)
        .year()
    )
  }
}

extension Character {
  fileprivate var tidexIsEmojiLike: Bool {
    unicodeScalars.contains { scalar in
      scalar.properties.isEmojiPresentation
        || scalar.properties.generalCategory == .otherSymbol
    }
  }
}

extension FriendAbuseReportReason {
  fileprivate var localizedTitle: String {
    switch self {
    case .harassmentOrBullying:
      return String(localized: "friends.chat.reason.harassment", table: "Localizable")
    case .sexualContent:
      return String(localized: "friends.chat.reason.sexual", table: "Localizable")
    case .hateOrDiscriminatoryContent:
      return String(localized: "friends.chat.reason.hate", table: "Localizable")
    case .violenceOrThreats:
      return String(localized: "friends.chat.reason.violence", table: "Localizable")
    case .spam:
      return String(localized: "friends.chat.reason.spam", table: "Localizable")
    case .inappropriateProfileOrConduct:
      return String(localized: "friends.chat.reason.inappropriateProfile", table: "Localizable")
    case .other:
      return String(localized: "friends.chat.reason.other", table: "Localizable")
    }
  }
}
