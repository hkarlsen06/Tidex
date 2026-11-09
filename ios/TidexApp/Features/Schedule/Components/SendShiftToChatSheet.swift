import SwiftUI

struct SendShiftToChatResult {
  let thread: FriendThread
  let recipient: ShareRecipient

  var threadId: String {
    thread.id
  }
}

enum SendAttachmentRecipientOrdering {
  static func sortedRecipients(
    _ recipients: [ShareRecipient],
    threads: [FriendThread]
  ) -> [ShareRecipient] {
    let directThreadTimestampsByRecipientId = threads.reduce(into: [String: Date]()) {
      result, thread in
      guard thread.kind == .direct, let counterpartUserId = thread.counterpartUserId else { return }

      let timestamp = thread.sortTimestamp
      if let existing = result[counterpartUserId] {
        result[counterpartUserId] = max(existing, timestamp)
      } else {
        result[counterpartUserId] = timestamp
      }
    }

    return recipients.sorted { lhs, rhs in
      let lhsTimestamp = directThreadTimestampsByRecipientId[lhs.id]
      let rhsTimestamp = directThreadTimestampsByRecipientId[rhs.id]

      switch (lhsTimestamp, rhsTimestamp) {
      case (let lhsTimestamp?, let rhsTimestamp?):
        if lhsTimestamp != rhsTimestamp {
          return lhsTimestamp > rhsTimestamp
        }

      case (.some, .none):
        return true

      case (.none, .some):
        return false

      case (.none, .none):
        break
      }

      return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
  }
}

enum SendAttachmentRecipientResolver {
  /// The stored direct thread with a recipient, so sending doesn't need the network
  /// when the conversation already exists on this device. Expects newest-first order.
  static func localDirectThread(for recipientId: String, in threads: [FriendThread])
    -> FriendThread?
  {
    threads.first { $0.kind == .direct && $0.counterpartUserId == recipientId }
  }

  static func mergedRecipients(
    fetchedRecipients: [ShareRecipient],
    cachedFriends: SharedShiftsRepository.CachedFriendsSnapshot,
    threads: [FriendThread],
    includeLocalFallbacks: Bool
  ) -> [ShareRecipient] {
    var recipientsById = Dictionary(uniqueKeysWithValues: fetchedRecipients.map { ($0.id, $0) })

    guard includeLocalFallbacks else {
      return SendAttachmentRecipientOrdering.sortedRecipients(
        Array(recipientsById.values),
        threads: threads
      )
    }

    for friend in cachedFriends.sharers {
      guard recipientsById[friend.id] == nil else { continue }
      recipientsById[friend.id] = ShareRecipient(
        id: friend.id,
        displayName: friend.displayName,
        avatarURL: URL(string: friend.avatarUrl ?? ""),
        statusText: friend.contactInfo,
        // Safe default for local fallback recipients when share settings are unavailable locally.
        canSeeOwnerEarnings: false
      )
    }

    for thread in threads {
      guard thread.kind == .direct, let counterpartUserId = thread.counterpartUserId else {
        continue
      }
      guard recipientsById[counterpartUserId] == nil else { continue }

      let counterpartDisplayName = thread.counterpartDisplayName?.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      let displayName =
        if let counterpartDisplayName, !counterpartDisplayName.isEmpty {
          counterpartDisplayName
        } else {
          "Unknown"
        }

      recipientsById[counterpartUserId] = ShareRecipient(
        id: counterpartUserId,
        displayName: displayName,
        avatarURL: URL(string: thread.counterpartAvatarUrl ?? ""),
        statusText: nil,
        canSeeOwnerEarnings: false
      )
    }

    return SendAttachmentRecipientOrdering.sortedRecipients(
      Array(recipientsById.values),
      threads: threads
    )
  }
}

@MainActor
@Observable
private final class SendAttachmentToChatViewModel {
  enum LoadState {
    case loading
    case loaded([ShareRecipient])
    /// Nobody to show: the fetch failed and no cached friend or thread exists.
    case failed(message: String)
  }

  var loadState = LoadState.loading
  var recipientSelection = ShareRecipientSelectionState()
  var isSubmitting = false
  /// Why the last tap on a recipient did not open the chat.
  var submitErrorMessage: String?

  private let viewerUserId: String
  private let buildAttachment: (ShareRecipient) throws -> FriendsComposerAttachmentDraft
  private let service: FriendsMessagingServiceProviding
  private let composerDraftStore: FriendsComposerDraftStore
  private let capabilities: any FriendsMessagingCapabilityProviding
  private let repository: FriendsMessagesRepository
  private let sharedShiftsRepository: SharedShiftsRepository
  @ObservationIgnored private var hasLoaded = false

  init(
    viewerUserId: String,
    buildAttachment: @escaping (ShareRecipient) throws -> FriendsComposerAttachmentDraft,
    service: FriendsMessagingServiceProviding,
    composerDraftStore: FriendsComposerDraftStore,
    capabilities: any FriendsMessagingCapabilityProviding,
    repository: FriendsMessagesRepository,
    sharedShiftsRepository: SharedShiftsRepository
  ) {
    self.viewerUserId = viewerUserId
    self.buildAttachment = buildAttachment
    self.service = service
    self.composerDraftStore = composerDraftStore
    self.capabilities = capabilities
    self.repository = repository
    self.sharedShiftsRepository = sharedShiftsRepository
  }

  var recipients: [ShareRecipient] {
    if case .loaded(let recipients) = loadState { return recipients }
    return []
  }

  var canContinue: Bool {
    selectedRecipient != nil && !isSubmitting
  }

  var selectedRecipient: ShareRecipient? {
    recipientSelection.selectedRecipient(in: recipients)
  }

  func beginSubmitting() -> Bool {
    guard !isSubmitting else { return false }
    isSubmitting = true
    submitErrorMessage = nil
    return true
  }

  func loadIfNeeded() async {
    guard !hasLoaded else { return }
    hasLoaded = true
    await load()
  }

  func load() async {
    loadState = .loading
    let threads = repository.getThreads(for: viewerUserId)
    let cachedFriends = sharedShiftsRepository.getCachedFriends(
      for: viewerUserId, includeHidden: true)

    do {
      let fetchedRecipients = try await ShareExtensionMessagingClient.fetchRecipients()
      loadState = .loaded(
        SendAttachmentRecipientResolver.mergedRecipients(
          fetchedRecipients: fetchedRecipients,
          cachedFriends: cachedFriends,
          threads: threads,
          includeLocalFallbacks: false
        ))
      recipientSelection = ShareRecipientSelectionState()
    } catch {
      let fallbackRecipients = SendAttachmentRecipientResolver.mergedRecipients(
        fetchedRecipients: [],
        cachedFriends: cachedFriends,
        threads: threads,
        includeLocalFallbacks: true
      )
      if fallbackRecipients.isEmpty,
        let message = ErrorTranslations.translate(error, fallback: .commonErrorLoadFailed)
      {
        loadState = .failed(message: message)
      } else {
        loadState = .loaded(fallbackRecipients)
      }
    }
  }

  func continueToChat() async -> SendShiftToChatResult? {
    guard let recipient = selectedRecipient else { return nil }
    guard beginSubmitting() else { return nil }
    return await continueToChat(recipient: recipient, beganSubmission: true)
  }

  func continueToChat(recipient: ShareRecipient, beganSubmission: Bool = false) async
    -> SendShiftToChatResult?
  {
    if !beganSubmission, !beginSubmitting() {
      return nil
    }
    defer { isSubmitting = false }

    do {
      let attachment = try buildAttachment(recipient)
      guard attachment.shiftSnapshot == nil || capabilities.canSendShiftSnapshots else {
        submitErrorMessage = String(localized: .friendsChatShiftSnapshotSendUnavailable)
        return nil
      }

      let thread: FriendThread
      if let localThread = SendAttachmentRecipientResolver.localDirectThread(
        for: recipient.id, in: repository.getThreads(for: viewerUserId))
      {
        thread = localThread
      } else {
        thread = try await service.getOrCreateDirectThread(otherUserId: recipient.id)
        await repository.saveThread(thread, for: viewerUserId)
      }
      await composerDraftStore.saveAttachmentDraft(
        attachment,
        threadId: thread.id,
        viewerUserId: viewerUserId
      )
      return SendShiftToChatResult(thread: thread, recipient: recipient)
    } catch {
      submitErrorMessage = ErrorTranslations.translate(error)
      return nil
    }
  }

}

struct SendAttachmentToChatSheet: View {
  let viewerUserId: String
  let buildAttachment: (ShareRecipient) throws -> FriendsComposerAttachmentDraft
  let onCompleted: (SendShiftToChatResult) -> Void

  @Environment(\.dismiss) private var dismiss
  @ScaledMetric(relativeTo: .largeTitle) private var emptyIconSize: CGFloat = 32
  @State private var viewModel: SendAttachmentToChatViewModel

  @MainActor
  init(
    viewerUserId: String,
    buildAttachment: @escaping (ShareRecipient) throws -> FriendsComposerAttachmentDraft,
    onCompleted: @escaping (SendShiftToChatResult) -> Void
  ) {
    self.viewerUserId = viewerUserId
    self.buildAttachment = buildAttachment
    self.onCompleted = onCompleted
    _viewModel = State(
      wrappedValue: SendAttachmentToChatViewModel(
        viewerUserId: viewerUserId,
        buildAttachment: buildAttachment,
        service: FriendsMessagingService.shared,
        composerDraftStore: .shared,
        capabilities: FriendsMessagingCapabilities.shared,
        repository: .shared,
        sharedShiftsRepository: .shared
      )
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color.tidexBackground
          .ignoresSafeArea()

        content
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, Spacing.md)
      }
      .navigationTitle(String(localized: .friendsChatSendToChat))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(String(localized: .commonCancel)) {
            dismiss()
          }
          .foregroundStyle(Color.tidexBlueText)
        }

        ToolbarItem(placement: .topBarTrailing) {
          if viewModel.isSubmitting {
            ProgressView()
          }
        }
      }
    }
    .task {
      await viewModel.loadIfNeeded()
    }
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.loadState {
    case .loading:
      VStack(spacing: Spacing.md) {
        ProgressView()
        Text(.friendsChatSendToChatLoading)
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextMuted)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .failed(let message):
      ContentUnavailableView {
        Label(String(localized: .commonErrorLoadFailed), systemImage: "wifi.exclamationmark")
      } description: {
        Text(message)
      } actions: {
        Button(String(localized: .commonRetry)) {
          Task { await viewModel.load() }
        }
        .buttonStyle(.borderedProminent)
        .tint(.tidexBlue)
      }
      .announcesToVoiceOver(message)

    case .loaded(let recipients) where recipients.isEmpty:
      VStack(spacing: Spacing.md) {
        Image(systemName: "person.2.slash")
          .font(.system(size: emptyIconSize, weight: .medium))
          .foregroundStyle(Color.tidexTextMuted)
          .accessibilityHidden(true)

        Text(.friendsChatSendToChatEmptyTitle)
          .font(.tidexHeadline)
          .foregroundStyle(Color.tidexTextPrimary)

        Text(
          .friendsChatSendToChatEmptyMessage
        )
        .font(.tidexFootnote)
        .foregroundStyle(Color.tidexTextMuted)
        .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .loaded(let recipients):
      VStack(alignment: .leading, spacing: Spacing.md) {
        Text(.friendsChatSendToChatPrompt)
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextMuted)

        if let errorMessage = viewModel.submitErrorMessage {
          Text(errorMessage)
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexError)
            .announcesToVoiceOver(errorMessage)
        }

        ShareRecipientPickerList(
          recipients: recipients,
          selectionState: Binding(
            get: { viewModel.recipientSelection },
            set: { viewModel.recipientSelection = $0 }
          ),
          onRecipientTap: { recipient in
            guard viewModel.beginSubmitting() else { return }

            Task {
              let result = await viewModel.continueToChat(
                recipient: recipient, beganSubmission: true)
              if let result { onCompleted(result) }
            }
          }
        )
        .disabled(viewModel.isSubmitting)
      }
    }
  }
}

struct SendShiftToChatSheet: View {
  let viewerUserId: String
  let buildDraft: (ShareRecipient) throws -> ComposerShiftSnapshotDraft
  let onCompleted: (SendShiftToChatResult) -> Void

  var body: some View {
    SendAttachmentToChatSheet(
      viewerUserId: viewerUserId,
      buildAttachment: { recipient in
        .shiftSnapshot(try buildDraft(recipient))
      },
      onCompleted: onCompleted
    )
  }
}
