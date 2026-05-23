import ExyteChat
import Photos
import SwiftUI
import UIKit

struct FriendsThreadView: View {
  private static let bottomMessageComposerClearance: CGFloat = 14

  @MainActor
  private final class ChatListRuntime: ObservableObject {
    var lastWillDisplayPresentedMessageID: String?
  }

  private enum AccessibilityID {
    static let threadView = "friends-thread.view"
    static let unreadPill = "friends-thread.unread-pill"
  }

  private struct SelectedImageGallery: Identifiable {
    let attachmentID: String
    var id: String { attachmentID }
  }

  private struct PendingForwardAttachment: Identifiable {
    let id = UUID()
    let snapshot: FriendShiftSnapshot
  }

  private struct PendingAttachmentReactionTarget: Equatable {
    let messageId: String
    let attachmentId: String
    let createdAt: Date

    func isValid(for messageId: String, now: Date = .now) -> Bool {
      self.messageId == messageId && now.timeIntervalSince(createdAt) <= 10
    }
  }

  private static func normalizedIdentifier(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.isEmpty ? nil : normalized
  }

  @Environment(\.openURL) private var openURL

  private let route: FriendChatRoute
  @StateObject private var viewModel: FriendsThreadViewModel
  @StateObject private var composerBridge = FriendsThreadComposerBridge()
  @StateObject private var reactionPaletteStore = FriendsChatReactionPaletteStore()
  @StateObject private var chatListRuntime = ChatListRuntime()

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
  @State private var isComposerFocused = false
  @State private var isAttachmentDrawerOpen = false
  @State private var lastHandledNavigationRequestId: UUID?
  @State private var pendingFocusScrollTask: Task<Void, Never>?
  @State private var liveEdgeTargetPresentedMessageID: String?
  @State private var selectedImageGallery: SelectedImageGallery?
  @State private var pendingForwardAttachment: PendingForwardAttachment?
  @State private var activeAttachmentReactionTarget: PendingAttachmentReactionTarget?
  @State private var pendingAttachmentReactionTarget: PendingAttachmentReactionTarget?
  @State private var timestampRevealOffset: CGFloat = 0
  @State private var visibilityOwnerId = UUID()

  init(route: FriendChatRoute, viewerUserId: String) {
    self.route = route
    _viewModel = StateObject(
      wrappedValue: FriendsThreadViewModel(route: route, viewerUserId: viewerUserId)
    )
  }

  init(viewModel: FriendsThreadViewModel) {
    self.route = viewModel.route
    _viewModel = StateObject(wrappedValue: viewModel)
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
      stagedAttachments: viewModel.stagedComposerAttachments,
      isThreadReadOnly: viewModel.isThreadReadOnly,
      sendErrorMessage: viewModel.sendErrorMessage,
      composerValidationMessage: viewModel.composerValidationMessage,
      draftCharacterCount: viewModel.draftCharacterCount,
      draftCharacterLimit: viewModel.draftCharacterLimit,
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

  private var presentedMessageIndexLookup: [String: Int] {
    Dictionary(uniqueKeysWithValues: zip(presentedMessageIDs, viewModel.messages.indices))
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
          counterpartLastReadAt: viewModel.counterpartReadState?.lastReadAt,
          showsTypingIndicator: viewModel.counterpartIsTyping,
          typingIndicatorCreatedAt: viewModel.thread.lastMessageAt ?? viewModel.thread.createdAt,
          reactionAttachmentTargets: activeReactionAttachmentTargets
        )
      ),
      highlightedPresentedMessageID: highlightedPresentedMessageID
    )
  }

  private var activeReactionAttachmentTargets: [String: String] {
    [activeAttachmentReactionTarget, pendingAttachmentReactionTarget]
      .compactMap { target -> (String, String)? in
        guard let target, target.isValid(for: target.messageId) else { return nil }
        return (target.messageId, target.attachmentId)
      }
      .reduce(into: [:]) { targets, pair in
        targets[pair.0] = pair.1
      }
  }

  private var viewportScrollRequest: FriendsThreadChatViewportScrollRequest? {
    FriendsThreadChatViewportRequestResolver.request(
      replyTargetMessageId: viewModel.replyScrollTargetMessageId,
      restoreTargetMessageId: viewModel.restoreScrollTargetMessageId,
      liveEdgeTargetPresentedMessageID: liveEdgeTargetPresentedMessageID,
      messages: viewModel.messages,
      viewerUserId: viewModel.viewerUserId
    )
  }

  private var packageReplyScrollRequest: FriendsThreadChatViewportScrollRequest? {
    guard viewportScrollRequest?.kind == .reply else { return nil }
    return viewportScrollRequest
  }

  private var bridgeViewportScrollRequest: FriendsThreadChatViewportScrollRequest? {
    guard viewportScrollRequest?.kind != .reply else { return nil }
    return viewportScrollRequest
  }

  private var highlightedPresentedMessageID: String? {
    FriendsThreadChatViewportRequestResolver.presentedMessageID(
      for: highlightedMessageId,
      messages: viewModel.messages,
      viewerUserId: viewModel.viewerUserId
    )
  }

  private var shouldStickToLatest: Bool {
    FriendsThreadLiveEdgeResolver.shouldStickToLatest(
      isPinnedToBottom: isPinnedToBottom,
      isComposerFocused: isComposerFocused
    )
  }

  private var shouldAutoFollowLatest: Bool {
    shouldStickToLatest
  }

  private var shouldShowCounterpartShiftPreviewHeader: Bool {
    viewModel.counterpartShiftPreview != nil
      && !(isComposerFocused && isAttachmentDrawerOpen)
  }

  private var chatImageAttachments: [FriendMessageAttachment] {
    FriendsThreadImageGalleryResolver.imageAttachments(messages: viewModel.messages)
  }

  private func messageID(for presentedMessageID: String) -> String? {
    if let messageId = presentedMessageLookup[presentedMessageID]?.id {
      return messageId
    }

    return presentedMessageID.replacingOccurrences(of: "message:", with: "")
  }

  var body: some View {
    threadContent
      .task {
        await viewModel.loadIfNeeded()
      }
      .task(id: route.navigationRequestId) {
        await handleRouteNavigationIfNeeded()
      }
      .onAppear {
        syncComposerBridge()
        SensitiveContentPresentationState.shared.setVisibleContext(
          .friendThread(threadId: route.threadId, ownerId: visibilityOwnerId)
        )
        Task {
          await NotificationService.shared.clearDeliveredFriendChatNotifications(
            for: route.threadId
          )
        }
      }
      .onChange(of: isPinnedToBottom) { _, newValue in
        guard newValue else { return }
        unreadIncomingCount = 0
        showsNewMessagesPill = false
        Task {
          await viewModel.markVisibleMessagesReadIfNeeded()
        }
      }
      .onChange(of: isComposerFocused) { _, newValue in
        pendingFocusScrollTask?.cancel()
        guard newValue else { return }
        unreadIncomingCount = 0
        showsNewMessagesPill = false
        if !isPinnedToBottom {
          scheduleScrollToBottomAfterKeyboardSettles()
        }
        Task {
          await viewModel.markVisibleMessagesReadIfNeeded()
        }
      }
      .onChange(of: presentedMessageIDs) { oldValue, newValue in
        handleMessageIDsChange(from: oldValue, to: newValue)
      }
      .onDisappear {
        pendingFocusScrollTask?.cancel()
        SensitiveContentPresentationState.shared.clearVisibleContextIfOwnedByFriendThread(
          visibilityOwnerId
        )
        Task {
          await viewModel.stopRealtime()
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .friendsThreadDidUpdate)) {
        notification in
        guard
          let threadId = Self.normalizedIdentifier(notification.userInfo?["threadId"] as? String),
          threadId == Self.normalizedIdentifier(viewModel.route.threadId)
        else {
          return
        }

        if notification.userInfo?["source"] as? String == "localRead" {
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
        guard
          let threadId = Self.normalizedIdentifier(notification.userInfo?["threadId"] as? String),
          threadId == Self.normalizedIdentifier(viewModel.route.threadId),
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
      .onReceive(
        NotificationCenter.default.publisher(for: .tidexDidBecomeActive)
      ) { _ in
        Task {
          await viewModel.handleAppDidBecomeActive()
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
    .accessibilityIdentifier(AccessibilityID.threadView)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background {
      ZStack(alignment: .top) {
        Color.tidexBackground
          .ignoresSafeArea()

        TidexAppBackground()
          .frame(height: 280)
          .mask(
            LinearGradient(
              colors: [
                .black,
                .black,
                .clear,
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .ignoresSafeArea(edges: .top)
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbarBackground(.hidden, for: .tabBar)
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
        safariURL = APIConfiguration.supportURL
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
    .fullScreenCover(item: $selectedImageGallery) { selection in
      if let initialAttachmentID = FriendsThreadImageGalleryResolver.initialSelectionID(
        requestedAttachmentID: selection.attachmentID,
        attachments: chatImageAttachments
      ) {
        FriendsChatImageGalleryOverlay(
          attachments: chatImageAttachments,
          initialAttachmentID: initialAttachmentID,
          onDismiss: {
            selectedImageGallery = nil
          },
          onSaveImage: { image in
            await saveImageToPhotoLibrary(image)
          }
        )
      } else {
        FriendsChatImageGalleryUnavailableOverlay {
          selectedImageGallery = nil
        }
      }
    }
    .sheet(item: $pendingForwardAttachment) { pendingAttachment in
      SendAttachmentToChatSheet(
        viewerUserId: viewModel.viewerUserId,
        buildAttachment: { recipient in
          .shiftSnapshot(
            ForwardedShiftSnapshotBuilder(
              snapshot: pendingAttachment.snapshot,
              viewerUserId: viewModel.viewerUserId
            )
            .build(for: recipient)
          )
        },
        onCompleted: { result in
          pendingForwardAttachment = nil
          AppCoordinator.shared.pendingDeepLink = .friendChat(
            threadId: result.threadId,
            messageId: nil,
            senderUserId: nil,
            typingUserId: nil,
            navigationRequestId: UUID()
          )
        }
      )
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
      didSendMessage: { draft in
        Task { @MainActor in
          _ = await viewModel.sendMessage(content: draft.text)
        }
      },
      messageBuilder: { params in
        chatRow(for: params.message, messageFrame: params.messageFrame)
      },
      inputViewBuilder: { params in
        FriendsThreadComposerHostedView(
          configuration: composerConfiguration,
          bridge: composerBridge,
          text: params.text
        )
      },
      messageMenuAction: handleMessageMenuAction
    )
    .localization(chatLocalization)
    .showDateHeaders(true)
    .appliesFocusModifierToCustomInputView(false)
    .animateMessageUpdates(false)
    .dateHeaderBuilder { date in
      FriendsThreadDateSeparator(date: date)
    }
    .betweenListAndInputViewBuilder {
      chatFooterAccessory
    }
    .showMessageTimeView(false)
    .showMessageMenuOnLongPress(true)
    .setAvailableInputs([.text])
    .keyboardDismissMode(.interactive)
    .contentInsets(bottom: Self.bottomMessageComposerClearance)
    .onWillDisplayCell(handleChatCellWillDisplay)
    .scrollToMessageID(packageReplyScrollRequest?.presentedMessageID)
    .enableLoadMore(offset: 50) {
      guard
        let lastWillDisplayPresentedMessageID = chatListRuntime.lastWillDisplayPresentedMessageID,
        let currentFirstMessageId = messageID(for: lastWillDisplayPresentedMessageID)
      else { return }
      Task {
        await viewModel.loadOlderMessagesIfNeeded(
          currentFirstMessageId: currentFirstMessageId
        )
      }
    }
    .onMessageReaction(
      didReactTo: { message, draftReaction in
        guard case .emoji(let emoji) = draftReaction.type else { return }
        guard let friendMessage = presentedMessageLookup[message.id] else { return }
        let attachmentId = resolvedPendingAttachmentReactionTarget(
          forMessageId: friendMessage.id
        )?.attachmentId
        activeAttachmentReactionTarget = nil
        pendingAttachmentReactionTarget = nil
        handleReactionSelection(emoji, forMessageId: friendMessage.id, attachmentId: attachmentId)
        FriendsThreadAttachmentReactionMenuTarget.clear(messageId: friendMessage.id)
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
    .overlay {
      FriendsThreadChatViewportBridge(
        messages: exyteMessages,
        scrollRequest: bridgeViewportScrollRequest,
        observedPresentedMessageID: packageReplyScrollRequest?.presentedMessageID,
        highlightedPresentedMessageID: highlightedPresentedMessageID,
        onPinnedToBottomChanged: {
          isPinnedToBottom = $0
        },
        onLatestVisiblePresentedMessageIDChanged: { presentedMessageID in
          viewModel.updateLatestVisibleMessage(
            messageId: presentedMessageID.flatMap(messageID(for:))
          )
        },
        onObservedPresentedMessageVisible: handlePackageReplyPresentedMessageVisible,
        onDidHandleScrollRequest: handleViewportScrollRequest
      )
      .allowsHitTesting(false)
    }
  }

  @ViewBuilder
  private var chatFooterAccessory: some View {
    if showsNewMessagesPill {
      VStack(spacing: 0) {
        if showsNewMessagesPill, !viewModel.messages.isEmpty {
          HStack {
            Spacer(minLength: 0)
            scrollToLatestButton
            Spacer(minLength: 0)
          }
          .padding(.top, Spacing.xs)
          .padding(.bottom, Spacing.xs)
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
    }
  }

  @ViewBuilder
  private func chatRow(for exyteMessage: ExyteChat.Message, messageFrame: Binding<CGRect>?)
    -> some View
  {
    if exyteMessage.id == FriendsThreadExyteMessageFactory.typingIndicatorMessageID {
      FriendsChatTypingRow(
        counterpartAvatarUrl: counterpartAvatarUrl,
        counterpartInitials: FriendsChatMessageGrouping.initials(from: counterpartDisplayName),
        joinsPrevious: shouldTypingIndicatorJoinPrevious
      )
      .id(exyteMessage.id)
    } else if let message = presentedMessageLookup[exyteMessage.id] {
      let isCurrentUser = message.senderUserId == viewModel.viewerUserId
      let index = presentedMessageIndexLookup[exyteMessage.id]
      let previousMessage = index.flatMap { $0 > 0 ? viewModel.messages[$0 - 1] : nil }
      let nextMessage = index.flatMap {
        $0 < (viewModel.messages.count - 1) ? viewModel.messages[$0 + 1] : nil
      }
      let baseGroupContext = FriendsChatMessageGrouping.context(
        for: message,
        previous: previousMessage,
        next: nextMessage,
        viewerUserId: viewModel.viewerUserId
      )
      let groupContext =
        if shouldJoinTypingIndicator(message: message, index: index) {
          baseGroupContext.joiningNext()
        } else {
          baseGroupContext
        }
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
      let isHighlighted = FriendsThreadExyteHighlightRedrawResolver.isHighlighted(exyteMessage)
      let attachmentHighlightTarget =
        activeAttachmentReactionTarget?.isValid(for: message.id) == true
        ? activeAttachmentReactionTarget
        : pendingAttachmentReactionTarget
      let highlightedAttachmentId: String? =
        if attachmentHighlightTarget?.isValid(for: message.id) == true {
          attachmentHighlightTarget?.attachmentId
        } else {
          nil
        }

      FriendsChatMessageRowContent(
        message: message,
        quotedPreview: viewModel.quotedMessage(for: message).map(replyPreviewModel(for:)),
        isCurrentUser: isCurrentUser,
        groupContext: groupContext,
        counterpartAvatarUrl: counterpartAvatarUrl,
        counterpartAvatarInitials: FriendsChatMessageGrouping.initials(
          from: counterpartDisplayName),
        isHighlighted: isHighlighted,
        highlightedAttachmentId: highlightedAttachmentId,
        visibleMessageText: FriendsThreadExyteHighlightRedrawResolver.visibleText(
          for: exyteMessage
        ),
        senderFirstName: firstName(
          from: isCurrentUser ? currentUserDisplayName : counterpartDisplayName
        ),
        separatorDate: nil,
        showsSenderLabel: false,
        showsTimestamp: shouldShowTimestamp,
        messageStatus: messageStatus,
        stackingOrder: Double(viewModel.messages.count - (index ?? 0)),
        onRetry: {
          Task {
            await viewModel.retryMessage(messageId: message.id)
          }
        },
        onToggleReaction: { emoji, attachmentId in
          handleReactionSelection(emoji, forMessageId: message.id, attachmentId: attachmentId)
        },
        onTapQuotedMessage: {
          handleQuotedMessageTap(for: message)
        },
        onOpenImageAttachment: { attachment in
          selectedImageGallery = SelectedImageGallery(attachmentID: attachment.id)
        },
        onImageReactionPressChanged: { attachment, isPressing in
          if isPressing {
            activeAttachmentReactionTarget = PendingAttachmentReactionTarget(
              messageId: message.id,
              attachmentId: attachment.id,
              createdAt: .now
            )
          } else if pendingAttachmentReactionTarget?.attachmentId != attachment.id {
            activeAttachmentReactionTarget = nil
          }
        },
        onPrepareImageReaction: { attachment in
          let target = PendingAttachmentReactionTarget(
            messageId: message.id,
            attachmentId: attachment.id,
            createdAt: .now
          )
          activeAttachmentReactionTarget = target
          pendingAttachmentReactionTarget = target
        },
        onOpenShiftSnapshot: { snapshot in
          openShiftSnapshot(snapshot)
        },
        onReplySwipe: canReply(to: message)
          ? {
            viewModel.setReplyTarget(message)
          }
          : nil,
        timestampRevealOffset: $timestampRevealOffset,
        messageFrame: messageFrame
      )
      .id(exyteMessage.id)
    } else {
      EmptyView()
    }
  }

  private func shouldJoinTypingIndicator(message: FriendMessage, index: Int?) -> Bool {
    guard viewModel.counterpartIsTyping else { return false }
    guard message.senderUserId != viewModel.viewerUserId else { return false }
    guard message.messageType == .user, message.deletedAt == nil else { return false }
    guard index == viewModel.messages.indices.last else { return false }
    guard Date().timeIntervalSince(message.createdAt) <= FriendsChatMessageGrouping.maximumGap
    else {
      return false
    }
    return true
  }

  private func canReply(to message: FriendMessage) -> Bool {
    message.messageType == .user && message.deletedAt == nil
  }

  private var shouldTypingIndicatorJoinPrevious: Bool {
    guard viewModel.counterpartIsTyping, let lastMessage = viewModel.messages.last else {
      return false
    }
    return shouldJoinTypingIndicator(message: lastMessage, index: viewModel.messages.indices.last)
  }

  @ViewBuilder
  private var counterpartShiftPreviewHeader: some View {
    if shouldShowCounterpartShiftPreviewHeader,
      let counterpartShiftPreview = viewModel.counterpartShiftPreview
    {
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
    .accessibilityIdentifier(AccessibilityID.unreadPill)
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
        mainBG: .clear,
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
      guard viewModel.draft != draft else { return }
      viewModel.draft = draft
      Task {
        await viewModel.handleDraftChanged(to: draft)
      }
    }
    composerBridge.stagedAttachmentsProvider = {
      viewModel.stagedComposerAttachments
    }
    composerBridge.onStagedAttachmentsChanged = { attachments in
      guard viewModel.stagedComposerAttachments != attachments else { return }
      viewModel.stagedComposerAttachments = attachments
      Task {
        await viewModel.setComposerAttachments(attachments)
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
      let didSend = await viewModel.sendMessage(content: content)
      guard didSend else { return false }

      await MainActor.run {
        unreadIncomingCount = 0
        showsNewMessagesPill = false
        requestScrollToBottom()
      }
      return true
    }
    composerBridge.onSaveEdit = { content in
      await viewModel.sendMessage(content: content)
    }
    composerBridge.onFocusChanged = { isFocused in
      guard isComposerFocused != isFocused else { return }
      isComposerFocused = isFocused
    }
    composerBridge.onAttachmentDrawerOpenChanged = { isOpen in
      guard isAttachmentDrawerOpen != isOpen else { return }
      isAttachmentDrawerOpen = isOpen
    }
    composerBridge.onHeightChanged = nil
  }

  private func handleMessageMenuAction(
    _ action: FriendsThreadMessageMenuAction,
    _ defaultActionClosure: @escaping (ExyteChat.Message, DefaultMessageMenuAction) -> Void,
    _ message: ExyteChat.Message
  ) {
    guard let friendMessage = presentedMessageLookup[message.id] else { return }
    activeAttachmentReactionTarget = nil
    pendingAttachmentReactionTarget = nil
    FriendsThreadAttachmentReactionMenuTarget.clear(messageId: friendMessage.id)

    switch action {
    case .reply:
      viewModel.setReplyTarget(friendMessage)
    case .copy:
      UIPasteboard.general.string = friendMessage.body
    case .edit:
      Task {
        await viewModel.startEditing(friendMessage)
      }
    case .forward:
      guard let shiftSnapshot = friendMessage.shiftSnapshot else { return }
      pendingForwardAttachment = PendingForwardAttachment(
        snapshot: shiftSnapshot
      )
    case .delete:
      Task {
        await viewModel.deleteMessage(messageId: friendMessage.id)
      }
    case .report:
      pendingReportTarget = .message(messageId: friendMessage.id)
    }
  }

  private func handleMessageIDsChange(from oldValue: [String], to newValue: [String]) {
    let change = FriendsThreadMessageListChangeResolver.resolve(
      oldMessageIDs: oldValue,
      newMessageIDs: newValue,
      lastMessageSenderId: viewModel.messages.last?.senderUserId,
      viewerUserId: viewModel.viewerUserId
    )

    switch change {
    case .none, .prependedHistory:
      return
    case .appendedOutgoing:
      unreadIncomingCount = 0
      showsNewMessagesPill = false
      return
    case .appendedIncoming:
      break
    }

    let appendOutcome = FriendsThreadIncomingAppendResolver.resolve(
      previousMessageCount: oldValue.count,
      unreadIncomingCount: unreadIncomingCount,
      isIncoming: true,
      isPinnedToBottom: shouldAutoFollowLatest
    )
    unreadIncomingCount = appendOutcome.unreadIncomingCount
    showsNewMessagesPill = appendOutcome.showsNewMessagesPill

    if appendOutcome.shouldPlayFeedback {
      Haptics.play(.light)
      SoundManager.shared.play("tap")
      return
    }

    guard shouldAutoFollowLatest else { return }

    Task {
      await viewModel.markVisibleMessagesReadIfNeeded()
    }
  }

  private func requestScrollToBottom() {
    liveEdgeTargetPresentedMessageID = presentedMessageIDs.last
  }

  private func scheduleScrollToBottomAfterKeyboardSettles() {
    pendingFocusScrollTask?.cancel()
    pendingFocusScrollTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(220))
      guard !Task.isCancelled, isComposerFocused else { return }
      guard !isPinnedToBottom else { return }
      requestScrollToBottom()
    }
  }

  private func openCounterpartShiftPreview(preview: SharerShiftPreview) {
    guard let deepLink = FriendsThreadCounterpartPreviewNavigationResolver.deepLink(for: preview)
    else {
      return
    }

    AppCoordinator.shared.pendingDeepLink = deepLink
  }

  private func openShiftSnapshot(_ snapshot: FriendShiftSnapshot) {
    let cachedFriends = SharedShiftsRepository.shared.getCachedFriends(
      for: viewModel.viewerUserId,
      includeHidden: true
    )
    guard
      let deepLink = FriendsThreadShiftSnapshotNavigationResolver.deepLink(
        for: snapshot,
        viewerUserId: viewModel.viewerUserId,
        cachedFriends: cachedFriends
      )
    else {
      return
    }

    AppCoordinator.shared.pendingDeepLink = deepLink
  }

  private func handleReactionSelection(
    _ emoji: String,
    forMessageId messageId: String,
    attachmentId: String? = nil
  ) {
    reactionPaletteStore.recordSelection(emoji)

    Task {
      await viewModel.toggleReaction(messageId: messageId, emoji: emoji, attachmentId: attachmentId)
    }
  }

  private func resolvedPendingAttachmentReactionTarget(
    forMessageId messageId: String
  ) -> PendingAttachmentReactionTarget? {
    if let target = pendingAttachmentReactionTarget {
      if target.isValid(for: messageId) {
        return target
      }
      pendingAttachmentReactionTarget = nil
    }

    if let attachmentId = FriendsThreadAttachmentReactionMenuTarget.attachmentId(for: messageId) {
      return PendingAttachmentReactionTarget(
        messageId: messageId,
        attachmentId: attachmentId,
        createdAt: .now
      )
    }

    return nil
  }

  private func handleQuotedMessageTap(for message: FriendMessage) {
    Task {
      await viewModel.scrollToReplyTarget(for: message)
    }
  }

  private func handleChatCellWillDisplay(_ message: ExyteChat.Message) {
    chatListRuntime.lastWillDisplayPresentedMessageID = message.id
  }

  private func handlePackageReplyPresentedMessageVisible(_ presentedMessageID: String) {
    guard let request = packageReplyScrollRequest, request.presentedMessageID == presentedMessageID
    else { return }
    completeReplyScrollRequest(request)
  }

  private func handleViewportScrollRequest(_ request: FriendsThreadChatViewportScrollRequest) {
    switch request.kind {
    case .reply:
      completeReplyScrollRequest(request)
    case .restore:
      Task { @MainActor in
        viewModel.consumeRestoreScrollTarget()
      }
    case .liveEdge:
      liveEdgeTargetPresentedMessageID = nil
    }
  }

  private func completeReplyScrollRequest(_ request: FriendsThreadChatViewportScrollRequest) {
    flashHighlightedMessage(request.messageID)
    viewModel.consumeReplyScrollTarget()
    viewModel.consumeRestoreScrollTarget()
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

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      if highlightedMessageId == messageId {
        highlightedMessageId = nil
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

  @MainActor
  private func saveImageToPhotoLibrary(_ image: UIImage) async -> Bool {
    do {
      try await FriendsChatPhotoLibrarySaver.save(image: image)
      Haptics.play(.success)
      return true
    } catch let error as FriendsChatPhotoLibrarySaveError {
      Haptics.play(.error)
      alertState = AlertState(
        title: String(localized: .commonError),
        message: error.errorDescription
      )
      return false
    } catch {
      Haptics.play(.error)
      alertState = AlertState(
        title: String(localized: .commonError),
        message: String(localized: "friends.chat.image.save_failed", table: "Localizable")
      )
      return false
    }
  }

  private struct AlertState: Identifiable {
    let id = UUID()
    let title: String
    var message: String? = nil
  }

  private enum FriendsChatPhotoLibrarySaveError: LocalizedError {
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
      switch self {
      case .permissionDenied:
        return String(
          localized: "friends.chat.image.save_permission_denied",
          table: "Localizable"
        )
      case .saveFailed:
        return String(localized: "friends.chat.image.save_failed", table: "Localizable")
      }
    }
  }

  private enum FriendsChatPhotoLibrarySaver {
    static func save(image: UIImage) async throws {
      try await ensureWriteAccess()

      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        PHPhotoLibrary.shared().performChanges({
          PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
          if let error {
            continuation.resume(throwing: error)
            return
          }

          if success {
            continuation.resume(returning: ())
          } else {
            continuation.resume(throwing: FriendsChatPhotoLibrarySaveError.saveFailed)
          }
        }
      }
    }

    private static func ensureWriteAccess() async throws {
      let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      switch status {
      case .authorized, .limited:
        return
      case .notDetermined:
        let requestedStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard requestedStatus == .authorized || requestedStatus == .limited else {
          throw FriendsChatPhotoLibrarySaveError.permissionDenied
        }
      case .denied, .restricted:
        throw FriendsChatPhotoLibrarySaveError.permissionDenied
      @unknown default:
        throw FriendsChatPhotoLibrarySaveError.saveFailed
      }
    }
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
    guard let navigationRequestId = route.navigationRequestId,
      lastHandledNavigationRequestId != navigationRequestId
    else {
      return
    }

    lastHandledNavigationRequestId = navigationRequestId
    await viewModel.handleNotificationOpen(
      targetMessageId: route.initialMessageId,
      notificationTypingUserId: route.notificationTypingUserId,
      forceRefresh: false
    )
  }
}

private struct FriendsChatTypingRow: View {
  private static let avatarSize = AvatarView.Size.small
  @State private var dotScales: [Bool] = [false, false, false]

  let counterpartAvatarUrl: String?
  let counterpartInitials: String
  let joinsPrevious: Bool

  var body: some View {
    let groupContext = FriendsChatMessageGroupContext(
      position: joinsPrevious ? .trailing : .standalone,
      isCurrentUser: false
    )

    return ChatMessageRow(
      isCurrentUser: false,
      minSpacer: Spacing.xxxl,
      spacing: Spacing.xxs,
      horizontalInset: Spacing.sm
    ) {
      HStack(alignment: .top, spacing: Spacing.xs) {
        if groupContext.showsAvatar {
          AvatarView(
            url: counterpartAvatarUrl,
            initials: counterpartInitials,
            size: Self.avatarSize,
            cornerRadius: CornerRadius.md
          )
          .padding(.top, 2)
        } else {
          Color.clear
            .frame(width: Self.avatarSize, height: Self.avatarSize)
        }

        FriendsChatReactionAnchoredBubbleCard(
          isCurrentUser: false,
          groupContext: groupContext,
          messageFrame: nil
        ) {
          HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
              Circle()
                .fill(Color.tidexTextMuted)
                .frame(width: 7, height: 7)
                .scaleEffect(dotScales[index] ? 1.0 : 0.5)
                .opacity(dotScales[index] ? 1.0 : 0.4)
            }
          }
          .padding(.vertical, Spacing.xxxs)
          .onAppear {
            for index in 0..<3 {
              withAnimation(
                .easeInOut(duration: 0.5)
                  .repeatForever(autoreverses: true)
                  .delay(Double(index) * 0.15)
              ) {
                dotScales[index] = true
              }
            }
          }
        } reaction: {
          EmptyView()
        }
      }
    }
    .padding(.top, Spacing.xxs)
    .padding(.bottom, Spacing.xs)
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
    .frame(maxWidth: .infinity)
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xs)
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
