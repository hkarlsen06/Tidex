import SwiftUI

struct FriendsThreadView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openURL) private var openURL

  @StateObject private var viewModel: FriendsThreadViewModel
  @State private var pendingReportTarget: ReportTarget?
  @State private var showBlockConfirmation = false
  @State private var showSafetySupport = false
  @State private var safariURL: URL?
  @State private var alertState: AlertState?
  @State private var bottomChromeHeight: CGFloat = Spacing.bottomScrollMargin
  @State private var highlightedMessageId: String?
  @State private var isPinnedToBottom = true
  @State private var unreadIncomingCount = 0
  @State private var showsNewMessagesPill = false
  @State private var scrollToBottomTrigger = 0
  @State private var showScreenshotBubble = false
  @State private var showScreenshotNotifiedIcon = false
  @State private var screenshotBellShakeTrigger = false

  private struct ScrollState: Equatable {
    let messageCount: Int
    let firstMessageID: String?
    let lastMessageID: String?
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

  var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .bottom) {
        FriendsChatTimelineView(
          messages: viewModel.messages,
          quotedMessagesById: viewModel.quotedMessagesById,
          viewerUserId: viewModel.viewerUserId,
          counterpartLastReadMessageId: viewModel.counterpartReadState?.lastReadMessageId,
          counterpartLastReadAt: viewModel.counterpartReadState?.lastReadAt,
          currentUserDisplayName: AppCoordinator.shared.userDisplayName,
          counterpartDisplayName: viewModel.thread.counterpartDisplayName
            ?? viewModel.route.displayName,
          highlightedMessageId: highlightedMessageId,
          bottomContentInset: bottomChromeHeight + Spacing.lg,
          scrollToBottomTrigger: scrollToBottomTrigger,
          restoreScrollTargetMessageId: viewModel.restoreScrollTargetMessageId,
          replyScrollTargetMessageId: viewModel.replyScrollTargetMessageId,
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
          onReportMessage: { messageId in
            pendingReportTarget = .message(messageId: messageId)
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
          }
        )
        .opacity(viewModel.messages.isEmpty ? 0 : 1)
        .background(Color.tidexBackground)
        .overlay(alignment: .top) {
          if viewModel.isLoadingOlderMessages && !viewModel.messages.isEmpty {
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
              .padding(.bottom, bottomChromeHeight + Spacing.sm)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
        .overlay(alignment: .bottom) {
          composer
        }

        if viewModel.isLoading && viewModel.messages.isEmpty {
          loadingState
        } else if viewModel.messages.isEmpty {
          emptyState
        }
      }
    }
    .background(Color.tidexBackground.ignoresSafeArea())
    .navigationTitle(viewModel.thread.counterpartDisplayName ?? viewModel.route.displayName)
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
    .onAppear {
      FriendsChatPresentationState.shared.setActiveThreadId(viewModel.route.threadId)
    }
    .onChange(of: isPinnedToBottom) { _, isPinnedToBottom in
      if isPinnedToBottom {
        unreadIncomingCount = 0
        showsNewMessagesPill = false
      }
    }
    .refreshable {
      await viewModel.refresh()
    }
    .onDisappear {
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

      Task {
        await viewModel.handleExternalThreadUpdate()
      }
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
    .alert(item: $alertState) { state in
      Alert(
        title: Text(state.title),
        message: state.message.map(Text.init),
        dismissButton: .default(Text(.commonDone))
      )
    }
    .onPreferenceChange(FriendsBottomChromeHeightPreferenceKey.self) { value in
      bottomChromeHeight = value
    }
  }

  private var loadingState: some View {
    VStack(spacing: Spacing.sm) {
      ProgressView()
      Text(.friendsChatLoading)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, Spacing.xxl)
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
    .frame(maxWidth: .infinity)
    .padding(.top, Spacing.xxl)
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

  private var composer: some View {
    VStack(spacing: Spacing.xs) {
      if let replyTarget = viewModel.draftReplyTarget {
        DraftReplyBanner(
          preview: replyPreviewModel(for: replyTarget),
          onCancel: {
            viewModel.clearReplyTarget()
          }
        )
        .padding(.horizontal, Spacing.md)
      }

      if viewModel.isThreadReadOnly {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "hand.raised.fill")
            .foregroundColor(.tidexWarning)

          Text(.friendsChatBlockedReadOnly)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)

          Spacer()
        }
        .padding(.horizontal, Spacing.md)
      }

      if let sendErrorMessage = viewModel.sendErrorMessage {
        HStack(spacing: Spacing.xs) {
          Text(sendErrorMessage)
            .font(.tidexFootnote)
            .foregroundColor(.tidexError)

          Spacer()

          if !viewModel.isThreadReadOnly {
            Button {
              Task {
                _ = await viewModel.sendDraft()
              }
            } label: {
              Text(.friendsChatRetry)
                .font(.tidexFootnoteMedium)
                .foregroundColor(.tidexBlue)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, Spacing.md)
      }

      ChatInputField(
        inputText: $viewModel.draft,
        placeholder: String(localized: .friendsChatPlaceholder),
        horizontalPadding: MonthPickerLayout.horizontalPadding,
        bottomPadding: MonthPickerLayout.bottomPadding,
        onSend: { message in
          await viewModel.sendMessage(content: message, image: nil)
        },
        onSendWithImage: { message, image in
          await viewModel.sendMessage(content: message, image: image)
        },
        disabled: viewModel.isSending || viewModel.isThreadReadOnly
      )
    }
    .background(
      GeometryReader { geometry in
        Color.clear.preference(
          key: FriendsBottomChromeHeightPreferenceKey.self,
          value: geometry.size.height
        )
      }
    )
  }

  private var actionsMenu: some View {
    Menu {
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
      Image(systemName: "ellipsis.circle")
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(.tidexBlue)
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
      scrollToBottomTrigger += 1
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
      snippet: replySnippet(for: message),
      hasImageAttachment: message.hasImageAttachment
    )
  }

  private func replySnippet(for message: FriendMessage) -> String? {
    let snippet = message.body?
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let snippet, !snippet.isEmpty else { return nil }
    return snippet
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
          if preview.hasImageAttachment {
            Image(systemName: "photo")
              .font(.tidexCaptionRegular)
              .foregroundColor(.tidexTextMuted)
          }

          if let snippet = preview.snippet {
            Text(snippet)
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

private struct FriendsBottomChromeHeightPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = Spacing.bottomScrollMargin

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
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
