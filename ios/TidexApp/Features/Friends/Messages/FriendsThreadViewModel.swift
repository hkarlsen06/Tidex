import Combine
import Foundation
import UIKit
import os.log

private let threadLogger = Logger(subsystem: "com.tidex.app", category: "FriendsThreadViewModel")

@MainActor
protocol SharingPreviewProviding: AnyObject {
  func fetchShiftPreviews(sharerIds: [String], forceRefresh: Bool) async throws
    -> [SharerShiftPreview]
}

extension SharingService: SharingPreviewProviding {}

@MainActor
protocol SharedShiftsCaching: AnyObject {
  func getCachedFriends(
    for viewerId: String,
    includeHidden: Bool
  ) -> SharedShiftsRepository.CachedFriendsSnapshot
  func getShiftPreviews(for viewerId: String) -> [String: SharerShiftPreview]
  func saveShiftPreviews(_ previews: [SharerShiftPreview], for viewerId: String) async
}

extension SharedShiftsRepository: SharedShiftsCaching {}

@MainActor
final class FriendsThreadViewModel: ObservableObject {
  private enum Pagination {
    static let pageSize = 50
  }

  private enum Attachments {
    static let storageBucket = "message-attachments"
  }

  private enum Typing {
    static let refreshInterval: TimeInterval = 2.5
    static let idleStopDelay: Duration = .seconds(4)
    static let remoteTimeout: Duration = .seconds(5)
  }

  private enum ComposerState: Equatable {
    case normal
    case reply(FriendMessage)
    case edit(FriendMessage)

    var mode: FriendsThreadComposerMode {
      switch self {
      case .normal:
        return .normal
      case .reply:
        return .reply
      case .edit:
        return .edit
      }
    }

    var replyTarget: FriendMessage? {
      guard case .reply(let message) = self else { return nil }
      return message
    }

    var editTarget: FriendMessage? {
      guard case .edit(let message) = self else { return nil }
      return message
    }
  }

  private struct ComposerSnapshot: Equatable {
    let state: ComposerState
    let draft: String
    let stagedAttachment: FriendsComposerAttachmentDraft?
  }

  enum ActionError: LocalizedError {
    case missingCounterpart
    case missingPendingAttachment

    var errorDescription: String? {
      switch self {
      case .missingCounterpart:
        return "Missing counterpart user"
      case .missingPendingAttachment:
        return String(localized: .friendsChatSendFailed)
      }
    }
  }

  @Published private(set) var thread: FriendThread
  @Published private(set) var messages: [FriendMessage] = []
  @Published private(set) var isLoading = false
  @Published private(set) var isLoadingOlderMessages = false
  @Published private(set) var hasMoreHistoricalMessages = true
  @Published private(set) var isThreadReadOnly = false
  @Published private(set) var counterpartReadState: FriendThreadState?
  @Published private(set) var counterpartIsTyping = false
  @Published private(set) var restoreScrollTargetMessageId: String?
  @Published private(set) var replyScrollTargetMessageId: String?
  @Published private(set) var quotedMessagesById: [String: FriendMessage] = [:]
  @Published private(set) var counterpartShiftPreview: SharerShiftPreview?
  @Published private var composerState: ComposerState = .normal
  @Published private(set) var composerFocusRequestToken = 0
  @Published var draft = ""
  @Published var stagedComposerAttachment: FriendsComposerAttachmentDraft?
  @Published var sendErrorMessage: String?

  let route: FriendChatRoute

  let viewerUserId: String
  private let service: any FriendsMessagingServiceProviding
  private let capabilities: any FriendsMessagingCapabilityProviding
  private let shareVisibilityResolver: any FriendsThreadShareVisibilityResolving
  private let sharingPreviewService: any SharingPreviewProviding
  private let sharedShiftsCache: any SharedShiftsCaching
  private let jobsRepository: JobsRepository
  private let settingsRepository: SettingsRepository
  private let repository: FriendsMessagesRepository
  private let composerDraftStore: FriendsComposerDraftStore
  private let realtimeCoordinator: FriendsMessagingRealtimeCoordinator
  private var hasLoaded = false
  private var loadingQuotedMessageIds: Set<String> = []
  private var didSendTypingStart = false
  private var lastTypingStartSentAt: Date?
  private var localTypingStopTask: Task<Void, Never>?
  private var counterpartTypingTimeoutTask: Task<Void, Never>?
  private var togglingReactionKeys: Set<String> = []
  private var suspendedComposerSnapshot: ComposerSnapshot?

  var composerMode: FriendsThreadComposerMode {
    composerState.mode
  }

  var draftReplyTarget: FriendMessage? {
    composerState.replyTarget
  }

  var draftEditTarget: FriendMessage? {
    composerState.editTarget
  }

  init(
    route: FriendChatRoute,
    viewerUserId: String,
    service: (any FriendsMessagingServiceProviding)? = nil,
    capabilities: (any FriendsMessagingCapabilityProviding)? = nil,
    shareVisibilityResolver: (any FriendsThreadShareVisibilityResolving)? = nil,
    sharingPreviewService: (any SharingPreviewProviding)? = nil,
    sharedShiftsCache: (any SharedShiftsCaching)? = nil,
    jobsRepository: JobsRepository? = nil,
    settingsRepository: SettingsRepository? = nil,
    repository: FriendsMessagesRepository? = nil,
    composerDraftStore: FriendsComposerDraftStore? = nil,
    realtimeCoordinator: FriendsMessagingRealtimeCoordinator? = nil
  ) {
    self.route = route
    self.viewerUserId = viewerUserId
    self.service = service ?? FriendsMessagingService.shared
    self.capabilities = capabilities ?? FriendsMessagingCapabilities.shared
    self.shareVisibilityResolver = shareVisibilityResolver ?? FriendsThreadShareVisibilityResolver()
    self.sharingPreviewService = sharingPreviewService ?? SharingService.shared
    self.sharedShiftsCache = sharedShiftsCache ?? SharedShiftsRepository.shared
    self.jobsRepository = jobsRepository ?? .shared
    self.settingsRepository = settingsRepository ?? .shared
    self.repository = repository ?? .shared
    self.composerDraftStore = composerDraftStore ?? .shared
    self.realtimeCoordinator = realtimeCoordinator ?? .shared
    self.thread = FriendThread(
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: route.avatarUrl,
      metadataData: nil,
      counterpartUserId: route.counterpartUserId,
      counterpartDisplayName: route.displayName,
      counterpartProfilePictureUrl: route.avatarUrl,
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

    syncCounterpartShiftPreviewFromCache()
  }

  func loadIfNeeded() async {
    guard !hasLoaded else { return }
    hasLoaded = true
    await load()
  }

  func load() async {
    guard !isLoading else { return }
    isLoading = true
    loadFromCache()
    await loadPendingComposerAttachment()

    async let realtimeSubscription: Void = realtimeCoordinator.startThreadSubscription(
      threadId: route.threadId,
      viewerUserId: viewerUserId
    )
    async let serverRefresh: Void = refreshFromServer()
    async let counterpartPreviewRefresh: Void = loadCounterpartShiftPreview(forceRefresh: false)
    _ = await (realtimeSubscription, serverRefresh, counterpartPreviewRefresh)
    isLoading = false

    await markLatestIncomingAsRead()
  }

  func refresh() async {
    await refreshFromServer()
    await loadCounterpartShiftPreview(forceRefresh: true)
    await markLatestIncomingAsRead()
  }

  func reloadFromCache() {
    loadFromCache()
  }

  func handleExternalThreadUpdate(shouldMarkRead: Bool) async {
    loadFromCache()
    await loadCounterpartShiftPreview(forceRefresh: false)
    if shouldMarkRead {
      await markLatestIncomingAsRead()
    }
  }

  func refreshCounterpartShiftPreview() async {
    shareVisibilityResolver.invalidateCachedVisibility(counterpartUserId: route.counterpartUserId)
    await loadCounterpartShiftPreview(forceRefresh: true)
  }

  func markVisibleMessagesReadIfNeeded() async {
    await markLatestIncomingAsRead()
  }

  func loadOlderMessagesIfNeeded(currentFirstMessageId: String) async {
    guard !isLoadingOlderMessages, hasMoreHistoricalMessages,
      let oldestLoadedMessage = messages.first,
      oldestLoadedMessage.id == currentFirstMessageId
    else {
      return
    }

    _ = await loadOlderMessages(
      before: oldestLoadedMessage, preserveScrollTargetMessageId: currentFirstMessageId)
  }

  func consumeRestoreScrollTarget() {
    restoreScrollTargetMessageId = nil
  }

  func consumeReplyScrollTarget() {
    replyScrollTargetMessageId = nil
  }

  func setReplyTarget(_ message: FriendMessage) {
    composerState = .reply(message)
  }

  func clearReplyTarget() {
    guard case .reply = composerState else { return }
    composerState = .normal
  }

  func startEditing(_ message: FriendMessage) async {
    guard message.canEdit(viewerUserId: viewerUserId) else { return }

    await stopTypingIfNeeded()
    sendErrorMessage = nil
    if composerMode != .edit {
      suspendedComposerSnapshot = currentComposerSnapshot()
    }
    composerState = .edit(message)
    draft = message.normalizedBody ?? ""
    stagedComposerAttachment = nil
    await composerDraftStore.clearAttachmentDraft(
      threadId: route.threadId,
      viewerUserId: viewerUserId
    )
    composerFocusRequestToken += 1
  }

  func cancelComposerMode() async {
    if composerMode == .edit {
      await stopTypingIfNeeded()
      await restoreSuspendedComposerAfterEdit()
      return
    }
    composerState = .normal
  }

  func setComposerAttachment(_ attachment: FriendsComposerAttachmentDraft?) async {
    guard composerMode != .edit else { return }
    stagedComposerAttachment = attachment

    if let attachment {
      await composerDraftStore.saveAttachmentDraft(
        attachment,
        threadId: route.threadId,
        viewerUserId: viewerUserId
      )
    } else {
      await composerDraftStore.clearAttachmentDraft(
        threadId: route.threadId,
        viewerUserId: viewerUserId
      )
    }
  }

  var canSendShiftSnapshots: Bool {
    capabilities.canSendShiftSnapshots
  }

  func prepareShiftSnapshotAttachment(for shift: ShiftWithComputations) async
    -> FriendsComposerAttachmentDraft?
  {
    guard capabilities.canSendShiftSnapshots else {
      sendErrorMessage = shiftSnapshotSendUnavailableMessage
      return nil
    }

    do {
      let canSeeOwnerEarnings = try await shareVisibilityResolver.canCounterpartSeeOwnerEarnings(
        counterpartUserId: route.counterpartUserId
      )
      let activeJobs = jobsRepository.getNonDeletedJobs(for: viewerUserId)
      let defaultJobId = activeJobs.first(where: \.is_default)?.id
      let effectiveJobId = shift.shift.job_id ?? defaultJobId
      let job = effectiveJobId.flatMap { jobId in
        activeJobs.first(where: { $0.id == jobId })
      }
      let currency =
        settingsRepository.getSettings(for: viewerUserId)?.currency
        ?? job?.currency
        ?? "kr"

      let draft = OwnShiftSnapshotBuilder(
        shift: shift,
        jobName: job?.name,
        jobColorHex: job?.color,
        currency: currency,
        ownerUserId: viewerUserId,
        ownerDisplayName: AppCoordinator.shared.userDisplayName,
        ownerAvatarUrl: AppCoordinator.shared.userAvatarUrl
      )
      .build(canSeeOwnerEarnings: canSeeOwnerEarnings)

      sendErrorMessage = nil
      return .shiftSnapshot(draft)
    } catch {
      sendErrorMessage = error.localizedDescription
      return nil
    }
  }

  func quotedMessage(for message: FriendMessage) -> FriendMessage? {
    guard let replyToMessageId = message.replyToMessageId else { return nil }
    return messages.first(where: { $0.id == replyToMessageId })
      ?? quotedMessagesById[replyToMessageId]
  }

  func scrollToReplyTarget(for message: FriendMessage) async {
    guard let replyToMessageId = message.replyToMessageId else { return }

    if messages.contains(where: { $0.id == replyToMessageId }) {
      replyScrollTargetMessageId = replyToMessageId
      return
    }

    while hasMoreHistoricalMessages, let oldestLoadedMessage = messages.first {
      let didLoadPage = await loadOlderMessages(
        before: oldestLoadedMessage,
        preserveScrollTargetMessageId: oldestLoadedMessage.id
      )

      if messages.contains(where: { $0.id == replyToMessageId }) {
        replyScrollTargetMessageId = replyToMessageId
        return
      }

      if !didLoadPage {
        break
      }
    }
  }

  func stopRealtime() async {
    if FriendsChatPresentationState.shared.activeThreadId == route.threadId {
      return
    }
    await stopTypingIfNeeded()
    counterpartTypingTimeoutTask?.cancel()
    counterpartTypingTimeoutTask = nil
    counterpartIsTyping = false
    await realtimeCoordinator.stopThreadSubscription(threadId: route.threadId)
  }

  func handleDraftChanged(to draft: String) async {
    guard !isThreadReadOnly, !route.counterpartUserId.isEmpty else { return }
    guard composerMode != .edit else {
      await stopTypingIfNeeded()
      return
    }

    let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if hasText {
      await sendTypingStartIfNeeded()
      scheduleTypingStop()
    } else {
      await stopTypingIfNeeded()
    }
  }

  func handleCounterpartTypingChange(userId: String, isTyping: Bool) {
    guard userId == route.counterpartUserId, !userId.isEmpty else { return }

    counterpartTypingTimeoutTask?.cancel()

    if isTyping {
      counterpartIsTyping = true
      counterpartTypingTimeoutTask = Task { @MainActor [weak self] in
        guard let self else { return }
        try? await Task.sleep(for: Typing.remoteTimeout)
        guard !Task.isCancelled else { return }
        self.counterpartIsTyping = false
      }
    } else {
      counterpartIsTyping = false
      counterpartTypingTimeoutTask = nil
    }
  }

  func sendDraft() async -> Bool {
    await sendMessage(content: draft)
  }

  func sendMessage(content: String) async -> Bool {
    guard !isThreadReadOnly else {
      return false
    }

    if composerMode == .edit {
      return await saveEditedMessage(content: content)
    }

    let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    let composerAttachment = stagedComposerAttachment
    guard !normalizedContent.isEmpty || composerAttachment != nil else { return false }
    guard canSendShiftSnapshotAttachment(composerAttachment) else {
      sendErrorMessage = shiftSnapshotSendUnavailableMessage
      return false
    }

    let previousReplyTarget = draftReplyTarget
    sendErrorMessage = nil

    let clientId = UUID().uuidString.lowercased()
    let optimisticAttachments =
      composerAttachment?.imageAttachment.map {
        [makeOptimisticAttachment(from: $0)]
      } ?? []
    let optimisticMessage = FriendMessage(
      id: "local-\(clientId)",
      threadId: route.threadId,
      senderUserId: viewerUserId,
      messageType: .user,
      body: normalizedContent.isEmpty ? nil : normalizedContent,
      clientId: clientId,
      replyToMessageId: previousReplyTarget?.id,
      createdAt: Date(),
      editedAt: nil,
      deletedAt: nil,
      metadataData: composerAttachment?.metadataData,
      attachments: optimisticAttachments,
      reactions: [],
      sendState: .sending,
      failureMessage: nil
    )

    draft = ""
    composerState = .normal
    stagedComposerAttachment = nil
    await composerDraftStore.clearAttachmentDraft(
      threadId: route.threadId, viewerUserId: viewerUserId)
    await repository.saveOptimisticMessage(
      optimisticMessage,
      in: route.threadId,
      for: viewerUserId
    )
    loadFromCache()
    await stopTypingIfNeeded()
    sendMessageInBackground(optimisticMessage)
    return true
  }

  func deleteMessage(messageId: String) async {
    guard let message = repository.getMessage(id: messageId, viewerUserId: viewerUserId),
      message.threadId == route.threadId,
      message.canDelete(viewerUserId: viewerUserId)
    else {
      return
    }

    let originalThread = repository.getThread(id: route.threadId, viewerUserId: viewerUserId)
    let shouldCancelComposerMode =
      draftReplyTarget?.id == messageId || draftEditTarget?.id == messageId
    let cancelledComposerSnapshot = shouldCancelComposerMode ? currentComposerSnapshot() : nil

    if shouldCancelComposerMode {
      await cancelComposerMode()
    }

    sendErrorMessage = nil
    await repository.deleteMessage(id: messageId, viewerUserId: viewerUserId)
    loadFromCache()

    do {
      let updatedThread = try await service.deleteMessage(messageId: messageId)
      await repository.saveThread(updatedThread, for: viewerUserId)
      loadFromCache()
      Haptics.play(.light)
    } catch {
      await repository.saveMessages([message], in: route.threadId, for: viewerUserId)
      if let originalThread {
        await repository.saveThread(originalThread, for: viewerUserId)
      }
      await restoreComposerSnapshot(cancelledComposerSnapshot)
      loadFromCache()
      sendErrorMessage = deleteMessageFailedMessage
      Haptics.play(.error)
      threadLogger.error("Failed to delete message: \(error.localizedDescription)")
    }
  }

  func retryMessage(messageId: String) async {
    guard let message = repository.getMessage(id: messageId, viewerUserId: viewerUserId),
      message.senderUserId == viewerUserId,
      message.canRetrySend
    else {
      return
    }
    guard canSendShiftSnapshotMessage(message) else {
      sendErrorMessage = shiftSnapshotSendUnavailableMessage
      return
    }

    await repository.updateMessageSendState(
      messageId: messageId,
      viewerUserId: viewerUserId,
      sendState: .sending,
      failureMessage: nil
    )
    loadFromCache()
    sendMessageInBackground(message.withSendState(.sending))
  }

  func toggleReaction(messageId: String, emoji: String) async {
    let normalizedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedEmoji.isEmpty else { return }
    guard !isThreadReadOnly else {
      return
    }
    guard let message = repository.getMessage(id: messageId, viewerUserId: viewerUserId),
      message.threadId == route.threadId,
      message.canReact
    else {
      return
    }

    let reactionKey = "\(messageId):\(normalizedEmoji)"
    guard !togglingReactionKeys.contains(reactionKey) else { return }
    togglingReactionKeys.insert(reactionKey)

    let originalMessage = message
    let optimisticMessage = message.toggledReaction(emoji: normalizedEmoji)
    sendErrorMessage = nil

    await repository.saveMessages([optimisticMessage], in: route.threadId, for: viewerUserId)
    loadFromCache()

    do {
      let updatedMessage = try await service.toggleMessageReaction(
        messageId: messageId,
        emoji: normalizedEmoji
      )
      await repository.saveMessages([updatedMessage], in: route.threadId, for: viewerUserId)
      Haptics.play(.light)
    } catch {
      await repository.saveMessages([originalMessage], in: route.threadId, for: viewerUserId)
      sendErrorMessage = String(localized: .friendsChatReactionFailed)
      Haptics.play(.error)
      threadLogger.error("Failed to toggle reaction: \(error.localizedDescription)")
    }

    togglingReactionKeys.remove(reactionKey)
    loadFromCache()
  }

  func submitReport(messageId: String?, reason: FriendAbuseReportReason) async throws {
    let counterpartUserId = route.counterpartUserId

    try await service.createAbuseReport(
      threadId: route.threadId,
      reportedUserId: counterpartUserId,
      messageId: messageId,
      reason: reason
    )
  }

  func blockCounterpart() async throws {
    let counterpartUserId = route.counterpartUserId

    try await service.blockUserPair(otherUserId: counterpartUserId)
    draft = ""
    composerState = .normal
    stagedComposerAttachment = nil
    await composerDraftStore.clearAttachmentDraft(
      threadId: route.threadId, viewerUserId: viewerUserId)
    sendErrorMessage = nil
    isThreadReadOnly = true
    NotificationCenter.default.post(
      name: Notification.Name("friendsVisibilityChanged"),
      object: nil,
      userInfo: ["blockedUserId": counterpartUserId]
    )
  }

  private func refreshFromServer() async {
    do {
      async let refreshedThreadTask: FriendThread = service.fetchThreadSummary(
        threadId: route.threadId)
      async let refreshedMessagesTask: [FriendMessage] = service.listThreadMessages(
        threadId: route.threadId,
        limit: Pagination.pageSize,
        before: nil
      )
      async let refreshedCounterpartStateTask: FriendThreadState? = fetchCounterpartStateIfNeeded()

      let refreshedThread = try await refreshedThreadTask
      let refreshedMessages = try await refreshedMessagesTask
      let refreshedCounterpartState = try await refreshedCounterpartStateTask

      hasMoreHistoricalMessages = refreshedMessages.count == Pagination.pageSize
      await repository.saveThread(refreshedThread, for: viewerUserId)
      await repository.saveMessages(refreshedMessages, in: route.threadId, for: viewerUserId)
      if let refreshedCounterpartState {
        await repository.saveThreadState(refreshedCounterpartState)
      }
      loadFromCache()
    } catch {
      threadLogger.error("Failed to refresh thread: \(error.localizedDescription)")
    }
  }

  private func fetchCounterpartStateIfNeeded() async throws -> FriendThreadState? {
    guard !route.counterpartUserId.isEmpty else { return nil }

    return try await service.fetchThreadState(
      threadId: route.threadId,
      userId: route.counterpartUserId
    )
  }

  private func markLatestIncomingAsRead() async {
    guard let lastIncomingMessage = messages.last(where: { $0.senderUserId != viewerUserId }) else {
      return
    }

    if repository.getThreadState(threadId: route.threadId, viewerUserId: viewerUserId)?
      .lastReadMessageId == lastIncomingMessage.id
    {
      return
    }

    do {
      let state = try await service.markThreadRead(
        threadId: route.threadId,
        throughMessageId: lastIncomingMessage.id
      )
      await repository.saveThreadState(state)
      loadFromCache()
    } catch {
      threadLogger.error("Failed to mark thread as read: \(error.localizedDescription)")
    }
  }

  private func loadFromCache() {
    if let cachedThread = repository.getThread(id: route.threadId, viewerUserId: viewerUserId) {
      thread = cachedThread
    }
    if route.counterpartUserId.isEmpty {
      counterpartReadState = nil
    } else {
      counterpartReadState = repository.getThreadState(
        threadId: route.threadId,
        viewerUserId: route.counterpartUserId
      )
    }
    messages = repository.getMessages(threadId: route.threadId, viewerUserId: viewerUserId)
    syncCounterpartShiftPreviewFromCache()
    syncComposerStateWithCachedMessages()
    prefetchQuotedMessagesIfNeeded()
  }

  private func loadPendingComposerAttachment() async {
    stagedComposerAttachment = await composerDraftStore.loadAttachmentDraft(
      threadId: route.threadId,
      viewerUserId: viewerUserId
    )
  }

  private func syncComposerStateWithCachedMessages() {
    switch composerState {
    case .normal:
      break
    case .reply(let message):
      guard let refreshedMessage = messageForComposerContext(id: message.id) else {
        composerState = .normal
        return
      }
      composerState = .reply(refreshedMessage)
    case .edit(let message):
      guard let refreshedMessage = messageForComposerContext(id: message.id),
        refreshedMessage.canEdit(viewerUserId: viewerUserId)
      else {
        draft = ""
        composerState = .normal
        return
      }
      composerState = .edit(refreshedMessage)
    }
  }

  private func currentComposerSnapshot() -> ComposerSnapshot {
    ComposerSnapshot(
      state: composerState,
      draft: draft,
      stagedAttachment: stagedComposerAttachment
    )
  }

  private func restoreSuspendedComposerAfterEdit() async {
    let snapshot = suspendedComposerSnapshot
    suspendedComposerSnapshot = nil
    await restoreComposerSnapshot(snapshot)
  }

  private func restoreComposerSnapshot(
    _ snapshot: ComposerSnapshot?,
    requestFocus: Bool? = nil
  ) async {
    let resolvedState = resolvedComposerState(for: snapshot?.state ?? .normal)
    composerState = resolvedState
    draft = snapshot?.draft ?? ""
    stagedComposerAttachment = snapshot?.stagedAttachment

    if let attachment = snapshot?.stagedAttachment {
      await composerDraftStore.saveAttachmentDraft(
        attachment,
        threadId: route.threadId,
        viewerUserId: viewerUserId
      )
    } else {
      await composerDraftStore.clearAttachmentDraft(
        threadId: route.threadId,
        viewerUserId: viewerUserId
      )
    }

    let shouldRequestFocus =
      requestFocus
      ?? (resolvedState.mode == .edit
        || !(snapshot?.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))

    if shouldRequestFocus {
      composerFocusRequestToken += 1
    }
  }

  private func resolvedComposerState(for state: ComposerState) -> ComposerState {
    switch state {
    case .normal:
      return .normal
    case .reply(let message):
      guard let refreshedMessage = messageForComposerContext(id: message.id) else {
        return .normal
      }
      return .reply(refreshedMessage)
    case .edit(let message):
      guard let refreshedMessage = messageForComposerContext(id: message.id),
        refreshedMessage.canEdit(viewerUserId: viewerUserId)
      else {
        return .normal
      }
      return .edit(refreshedMessage)
    }
  }

  private func messageForComposerContext(id: String) -> FriendMessage? {
    messages.first(where: { $0.id == id })
      ?? repository.getMessage(id: id, viewerUserId: viewerUserId)
  }

  private func loadCounterpartShiftPreview(forceRefresh: Bool) async {
    if let cachedCounterpartCanViewSharedShift, !cachedCounterpartCanViewSharedShift {
      counterpartShiftPreview = nil
      return
    }

    if !forceRefresh {
      syncCounterpartShiftPreviewFromCache()
    }

    do {
      let previews = try await sharingPreviewService.fetchShiftPreviews(
        sharerIds: [route.counterpartUserId],
        forceRefresh: forceRefresh
      )
      await sharedShiftsCache.saveShiftPreviews(previews, for: viewerUserId)
      let resolvedPreview = renderablePreview(from: previews.first)
      if counterpartShiftPreview != resolvedPreview {
        counterpartShiftPreview = resolvedPreview
      }
    } catch {
      threadLogger.error(
        "Failed to load counterpart shift preview: \(error.localizedDescription)")
    }
  }

  private func sendTypingStartIfNeeded() async {
    let now = Date()
    if didSendTypingStart,
      let lastTypingStartSentAt,
      now.timeIntervalSince(lastTypingStartSentAt) < Typing.refreshInterval
    {
      return
    }

    await realtimeCoordinator.sendTypingStart(
      threadId: route.threadId,
      userId: viewerUserId
    )
    didSendTypingStart = true
    lastTypingStartSentAt = now
  }

  private func stopTypingIfNeeded() async {
    localTypingStopTask?.cancel()
    localTypingStopTask = nil

    guard didSendTypingStart else { return }

    await realtimeCoordinator.sendTypingStop(
      threadId: route.threadId,
      userId: viewerUserId
    )
    didSendTypingStart = false
    lastTypingStartSentAt = nil
  }

  private func scheduleTypingStop() {
    localTypingStopTask?.cancel()
    localTypingStopTask = Task { @MainActor [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: Typing.idleStopDelay)
      guard !Task.isCancelled else { return }
      await self.stopTypingIfNeeded()
    }
  }

  private func saveEditedMessage(content: String) async -> Bool {
    guard let originalMessage = draftEditTarget,
      let currentMessage = repository.getMessage(
        id: originalMessage.id, viewerUserId: viewerUserId),
      currentMessage.threadId == route.threadId,
      currentMessage.canEdit(viewerUserId: viewerUserId)
    else {
      return false
    }

    let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedContent.isEmpty else { return false }

    if currentMessage.normalizedBody == normalizedContent {
      sendErrorMessage = nil
      await stopTypingIfNeeded()
      await restoreSuspendedComposerAfterEdit()
      return true
    }

    let optimisticMessage = currentMessage.withEditedBody(normalizedContent, editedAt: Date())
    sendErrorMessage = nil
    composerState = .normal
    draft = ""
    await stopTypingIfNeeded()
    await repository.saveMessages([optimisticMessage], in: route.threadId, for: viewerUserId)
    loadFromCache()

    do {
      let updatedMessage = try await service.editMessage(
        messageId: currentMessage.id,
        body: normalizedContent
      )
      await repository.saveMessages([updatedMessage], in: route.threadId, for: viewerUserId)
      await restoreSuspendedComposerAfterEdit()
      loadFromCache()
      Haptics.play(.light)
      return true
    } catch {
      await repository.saveMessages([currentMessage], in: route.threadId, for: viewerUserId)
      draft = normalizedContent
      composerState = .edit(currentMessage)
      composerFocusRequestToken += 1
      loadFromCache()
      sendErrorMessage = editMessageFailedMessage
      Haptics.play(.error)
      threadLogger.error("Failed to edit message: \(error.localizedDescription)")
      return false
    }
  }

  private func loadOlderMessages(
    before oldestLoadedMessage: FriendMessage,
    preserveScrollTargetMessageId: String?
  ) async -> Bool {
    guard !isLoadingOlderMessages else { return false }

    isLoadingOlderMessages = true
    defer { isLoadingOlderMessages = false }

    do {
      let olderMessages = try await service.listThreadMessages(
        threadId: route.threadId,
        limit: Pagination.pageSize,
        before: oldestLoadedMessage.paginationCursor
      )

      hasMoreHistoricalMessages = olderMessages.count == Pagination.pageSize
      guard !olderMessages.isEmpty else { return false }

      await repository.saveMessages(olderMessages, in: route.threadId, for: viewerUserId)
      loadFromCache()
      if let preserveScrollTargetMessageId {
        restoreScrollTargetMessageId = preserveScrollTargetMessageId
      }
      return true
    } catch {
      threadLogger.error("Failed to load older messages: \(error.localizedDescription)")
      return false
    }
  }

  private func prefetchQuotedMessagesIfNeeded() {
    let loadedMessageIds = Set(messages.map(\.id))
    let replyTargetIds = Set(messages.compactMap(\.replyToMessageId))
      .subtracting(loadedMessageIds)
      .subtracting(Set(quotedMessagesById.keys))
      .subtracting(loadingQuotedMessageIds)

    guard !replyTargetIds.isEmpty else { return }

    for messageId in replyTargetIds {
      loadingQuotedMessageIds.insert(messageId)

      Task { @MainActor [weak self] in
        guard let self else { return }

        defer {
          self.loadingQuotedMessageIds.remove(messageId)
        }

        do {
          let quotedMessage = try await self.service.fetchMessagePayload(messageId: messageId)
          guard quotedMessage.threadId == self.route.threadId else { return }
          guard quotedMessage.deletedAt == nil else {
            self.quotedMessagesById.removeValue(forKey: messageId)
            return
          }
          self.quotedMessagesById[messageId] = quotedMessage
        } catch {
          threadLogger.error(
            "Failed to fetch quoted message \(messageId): \(error.localizedDescription)")
        }
      }
    }
  }

  private func sendMessageInBackground(_ message: FriendMessage) {
    Task { @MainActor in
      guard canSendShiftSnapshotMessage(message) else {
        await repository.updateMessageSendState(
          messageId: message.id,
          viewerUserId: viewerUserId,
          sendState: .failed,
          failureMessage: shiftSnapshotSendUnavailableMessage
        )
        loadFromCache()
        return
      }

      do {
        let outgoingAttachments = try await makeOutgoingAttachments(for: message)
        let sentMessage = try await service.sendMessage(
          threadId: route.threadId,
          clientId: message.clientId,
          body: message.body,
          replyToMessageId: message.replyToMessageId,
          attachments: outgoingAttachments,
          metadataData: message.sendableMetadataData
        )

        await repository.saveConfirmedMessage(
          sentMessage,
          replacingLocalMessageId: message.id,
          in: route.threadId,
          for: viewerUserId
        )
        loadFromCache()
      } catch {
        await repository.updateMessageSendState(
          messageId: message.id,
          viewerUserId: viewerUserId,
          sendState: .failed,
          failureMessage: error.localizedDescription
        )
        loadFromCache()
        threadLogger.error("Failed to send thread message: \(error.localizedDescription)")
      }
    }
  }

  private func makeOptimisticAttachment(from image: ImageAttachment) -> FriendMessageAttachment {
    let storagePath = pendingAttachmentStoragePath(for: image.id)
    cacheImage(image, for: storagePath)

    let imageSize = UIImage(data: image.data)?.size
    return FriendMessageAttachment(
      id: image.id,
      attachmentIndex: 0,
      kind: .image,
      storageBucket: Attachments.storageBucket,
      storagePath: storagePath,
      mimeType: image.mediaType,
      byteSize: Int64(image.data.count),
      width: imageSize.map { Int($0.width.rounded()) },
      height: imageSize.map { Int($0.height.rounded()) },
      createdAt: Date()
    )
  }

  private func makeOutgoingAttachments(for message: FriendMessage) async throws
    -> [FriendOutgoingAttachment]
  {
    var outgoingAttachments: [FriendOutgoingAttachment] = []

    for attachment in message.attachments {
      if isPendingAttachment(attachment),
        let pendingImage = await pendingImageAttachment(for: attachment)
      {
        let uploadedAttachment = try await service.uploadImageAttachment(
          threadId: route.threadId,
          image: pendingImage
        )
        cacheImage(pendingImage, for: uploadedAttachment.storagePath)
        outgoingAttachments.append(uploadedAttachment)
        continue
      }

      guard !isPendingAttachment(attachment) else {
        throw ActionError.missingPendingAttachment
      }

      outgoingAttachments.append(
        FriendOutgoingAttachment(
          attachmentId: attachment.id,
          storagePath: attachment.storagePath,
          mimeType: attachment.mimeType,
          byteSize: attachment.byteSize,
          width: attachment.width,
          height: attachment.height
        ))
    }

    return outgoingAttachments
  }

  private func pendingAttachmentStoragePath(for attachmentId: String) -> String {
    "local-pending/\(attachmentId)"
  }

  private func isPendingAttachment(_ attachment: FriendMessageAttachment) -> Bool {
    attachment.storagePath.hasPrefix("local-pending/")
  }

  private func pendingImageAttachment(for attachment: FriendMessageAttachment) async
    -> ImageAttachment?
  {
    let attachmentId = attachment.id
    let storagePath = attachment.storagePath

    return await Task.detached(priority: .userInitiated) {
      let cacheURL = Self.imageCacheURL(for: storagePath)

      if let cachedImage = ImageCache.shared.get(for: cacheURL),
        let data = cachedImage.jpegData(compressionQuality: 0.9)
      {
        return ImageAttachment(id: attachmentId, data: data, mediaType: "image/jpeg")
      }

      if let cachedImage = await ImageCache.shared.getFromDisk(for: cacheURL),
        let data = cachedImage.jpegData(compressionQuality: 0.9)
      {
        return ImageAttachment(id: attachmentId, data: data, mediaType: "image/jpeg")
      }

      return nil
    }.value
  }

  private func cacheImage(_ image: ImageAttachment, for storagePath: String) {
    guard let uiImage = UIImage(data: image.data) else { return }
    ImageCache.shared.set(uiImage, for: Self.imageCacheURL(for: storagePath))
  }

  private nonisolated static func imageCacheURL(for storagePath: String) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "friends-message-cache.local"
    components.path = "/\(storagePath)"
    return components.url ?? URL(filePath: "/tmp/friends-message-cache-fallback")
  }

  private var shiftSnapshotSendUnavailableMessage: String {
    String(localized: "friends.chat.shift_snapshot_send_unavailable", table: "Localizable")
  }

  private var editMessageFailedMessage: String {
    String(localized: "friends.chat.edit_failed", table: "Localizable")
  }

  private var deleteMessageFailedMessage: String {
    String(localized: "friends.chat.delete_failed", table: "Localizable")
  }

  private func canSendShiftSnapshotAttachment(_ attachment: FriendsComposerAttachmentDraft?) -> Bool
  {
    guard attachment?.shiftSnapshot != nil else { return true }
    return capabilities.canSendShiftSnapshots
  }

  private func canSendShiftSnapshotMessage(_ message: FriendMessage) -> Bool {
    guard message.shiftSnapshot != nil else { return true }
    return capabilities.canSendShiftSnapshots
  }

  private var cachedCounterpartCanViewSharedShift: Bool? {
    let cachedFriends = sharedShiftsCache.getCachedFriends(for: viewerUserId, includeHidden: true)
    guard let counterpart = cachedFriends.sharers.first(where: { $0.id == route.counterpartUserId })
    else {
      return nil
    }

    return !counterpart.hidden && !cachedFriends.chatOnlyUserIds.contains(counterpart.id)
  }

  private func syncCounterpartShiftPreviewFromCache() {
    let resolvedPreview: SharerShiftPreview?
    if let cachedCounterpartCanViewSharedShift, !cachedCounterpartCanViewSharedShift {
      resolvedPreview = nil
    } else {
      let cachedPreview = sharedShiftsCache.getShiftPreviews(for: viewerUserId)[
        route.counterpartUserId]
      resolvedPreview = renderablePreview(from: cachedPreview)
    }

    if counterpartShiftPreview != resolvedPreview {
      counterpartShiftPreview = resolvedPreview
    }
  }

  private func renderablePreview(from preview: SharerShiftPreview?) -> SharerShiftPreview? {
    guard let preview, preview.shift != nil, preview.status != nil else { return nil }
    return preview
  }
}
