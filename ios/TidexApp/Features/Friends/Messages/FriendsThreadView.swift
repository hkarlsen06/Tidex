import SwiftUI

struct FriendsThreadView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openURL) private var openURL

  @StateObject private var viewModel: FriendsThreadViewModel
  @State private var lastScrolledMessageId: String?
  @State private var pendingReportTarget: ReportTarget?
  @State private var showBlockConfirmation = false
  @State private var showSafetySupport = false
  @State private var safariURL: URL?
  @State private var alertState: AlertState?
  @State private var bottomChromeHeight: CGFloat = Spacing.bottomScrollMargin

  init(route: FriendChatRoute, viewerUserId: String) {
    _viewModel = StateObject(
      wrappedValue: FriendsThreadViewModel(route: route, viewerUserId: viewerUserId)
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      Divider()
        .overlay(Color.tidexBorderSubtle)

      ZStack(alignment: .bottom) {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: Spacing.sm) {
              if viewModel.isLoading && viewModel.messages.isEmpty {
                loadingState
              } else if viewModel.messages.isEmpty {
                emptyState
              } else {
                if viewModel.isLoadingOlderMessages {
                  olderMessagesLoadingState
                }

                ForEach(viewModel.messages) { message in
                  messageRow(message)
                    .id(message.id)
                    .onAppear {
                      guard message.id == viewModel.messages.first?.id else { return }
                      Task {
                        await viewModel.loadOlderMessagesIfNeeded(currentFirstMessageId: message.id)
                      }
                    }
                }
              }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, bottomChromeHeight + Spacing.lg)
          }
          .background(Color.tidexBackground)
          .onAppear {
            scrollToBottom(using: proxy, animated: false)
          }
          .onChange(of: viewModel.messages.last?.id) { _, _ in
            scrollToBottom(using: proxy, animated: !reduceMotion)
          }
          .onChange(of: viewModel.restoreScrollTargetMessageId) { _, newValue in
            guard let targetMessageId = newValue else { return }
            proxy.scrollTo(targetMessageId, anchor: .top)
            viewModel.consumeRestoreScrollTarget()
          }
        }
        .overlay(alignment: .bottom) {
          composer
        }
      }
    }
    .background(Color.tidexBackground.ignoresSafeArea())
    .navigationTitle(viewModel.thread.counterpartDisplayName ?? viewModel.route.displayName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        actionsMenu
      }
    }
    .task {
      await viewModel.loadIfNeeded()
    }
    .refreshable {
      await viewModel.refresh()
    }
    .onDisappear {
      Task {
        await viewModel.stopRealtime()
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

  private func messageRow(_ message: FriendMessage) -> some View {
    let isCurrentUser = message.senderUserId == AppCoordinator.shared.getCurrentUserId()

    return ChatMessageRow(isCurrentUser: isCurrentUser, minSpacer: 48, spacing: Spacing.xxs) {
      ForEach(message.attachments) { attachment in
        if attachment.kind == .image {
          FriendMessageImageView(
            attachment: attachment,
            isCurrentUser: isCurrentUser,
            onReport: {
              pendingReportTarget = .message(messageId: message.id)
            }
          )
        }
      }

      if let body = message.body, !body.isEmpty {
        ChatBubbleCard(isCurrentUser: isCurrentUser, maxWidth: 280) {
          Text(body)
            .font(.tidexBody)
            .foregroundColor(isCurrentUser ? .tidexTextOnBrand : .tidexTextPrimary)
        }
        .contextMenu {
          Button {
            UIPasteboard.general.string = body
          } label: {
            Label(String(localized: .commonCopy), systemImage: "doc.on.doc")
          }

          if !isCurrentUser {
            Button(String(localized: .friendsChatReportMessage)) {
              pendingReportTarget = .message(messageId: message.id)
            }
          }
        }
      }

      Text(message.createdAt.formatted(.dateTime.hour().minute()))
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)
    }
  }

  private var composer: some View {
    VStack(spacing: Spacing.xs) {
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

  private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
    guard let lastMessageId = viewModel.messages.last?.id, lastMessageId != lastScrolledMessageId
    else {
      return
    }

    lastScrolledMessageId = lastMessageId

    let action = {
      proxy.scrollTo(lastMessageId, anchor: .bottom)
    }

    if animated {
      withAnimation(.easeOut(duration: 0.2), action)
    } else {
      action()
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

private struct FriendMessageImageView: View {
  let attachment: FriendMessageAttachment
  let isCurrentUser: Bool
  let onReport: () -> Void

  @StateObject private var loader = FriendMessageImageLoader()
  @State private var selectedImageViewer: FriendSelectedImageViewer?

  var body: some View {
    Group {
      if let image = loader.image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(maxWidth: 220, maxHeight: 220)
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
              .strokeBorder(
                isCurrentUser ? Color.white.opacity(0.2) : Color.tidexBorder,
                lineWidth: 1
              )
          )
          .onTapGesture {
            selectedImageViewer = FriendSelectedImageViewer(image: image)
          }
      } else if loader.isLoading {
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(Color.tidexSurfacePrimary)
          .frame(width: 160, height: 160)
          .overlay {
            ProgressView()
          }
      } else {
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(Color.tidexSurfacePrimary)
          .frame(width: 160, height: 120)
          .overlay {
            Image(systemName: "photo")
              .font(.tidexTitle2)
              .foregroundColor(.tidexTextMuted)
          }
      }
    }
    .task(id: attachment.id) {
      await loader.loadIfNeeded(attachment: attachment)
    }
    .contextMenu {
      if let image = loader.image {
        Button {
          UIPasteboard.general.image = image
        } label: {
          Label(String(localized: .commonCopy), systemImage: "doc.on.doc")
        }
      }

      if !isCurrentUser {
        Button(String(localized: .friendsChatReportMessage)) {
          onReport()
        }
      }
    }
    .fullScreenCover(item: $selectedImageViewer) { viewer in
      ImageViewerOverlay(image: viewer.image) {
        selectedImageViewer = nil
      }
    }
  }
}

@MainActor
private final class FriendMessageImageLoader: ObservableObject {
  private static let cache = NSCache<NSString, UIImage>()

  @Published private(set) var image: UIImage?
  @Published private(set) var isLoading = false

  func loadIfNeeded(attachment: FriendMessageAttachment) async {
    if let image {
      self.image = image
      return
    }

    let cacheKey = attachment.storagePath as NSString
    if let cached = Self.cache.object(forKey: cacheKey) {
      image = cached
      return
    }

    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      let data = try await FriendsMessagingService.shared.downloadAttachmentData(
        path: attachment.storagePath
      )
      guard let loadedImage = UIImage(data: data) else { return }
      Self.cache.setObject(loadedImage, forKey: cacheKey)
      image = loadedImage
    } catch {
      image = nil
    }
  }
}

private struct FriendSelectedImageViewer: Identifiable {
  let id = UUID()
  let image: UIImage
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
