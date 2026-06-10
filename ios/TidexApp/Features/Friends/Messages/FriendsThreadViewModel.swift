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
  private enum NotificationSource {
    static let localRead = "localRead"
  }

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
    static let remoteStopGraceDelay: Duration = .seconds(2)
    static let pushEscalationDelay: Duration = .milliseconds(700)
    static let pushCooldown: TimeInterval = 120
  }

  private enum ActiveThreadReconciliation {
    static let interval: Duration = .seconds(12)
  }

  private enum MessageBody {
    // swiftlint:disable:next explicit_type_interface
    static let characterLimit = 5_000
  }

  private enum VisibleReadTracking {
    static let debounceDelay: Duration = .milliseconds(200)
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
    let stagedAttachments: [FriendsComposerAttachmentDraft]
  }

  private actor SendTaskHandle {
    private var result: Result<FriendMessage, Error>?
    private var continuations: [CheckedContinuation<Result<FriendMessage, Error>, Never>] = []

    func complete(with result: Result<FriendMessage, Error>) {
      guard self.result == nil else { return }
      self.result = result

      let continuations = continuations
      self.continuations.removeAll()
      for continuation in continuations {
        continuation.resume(returning: result)
      }
    }

    func peekResult() -> Result<FriendMessage, Error>? {
      result
    }

    func waitForResult() async -> Result<FriendMessage, Error> {
      if let result {
        return result
      }

      return await withCheckedContinuation { continuation in
        continuations.append(continuation)
      }
    }
  }

  enum ActionError: LocalizedError {
    case missingCounterpart
    case missingPendingAttachment
    case offlineServerAction

    var errorDescription: String? {
      switch self {
      case .missingCounterpart:
        return "Missing counterpart user"

      case .missingPendingAttachment:
        return String(localized: .friendsChatSendFailed)

      case .offlineServerAction:
        return String(localized: .friendsChatWaitingForNetwork)
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
  @Published private(set) var composerValidationMessage: String?
  @Published private(set) var draftCharacterCount = 0
  @Published var draft = "" {
    didSet {
      updateDraftValidation(for: draft)
      clearSafetyFilterSendErrorIfResolved(for: draft)
    }
  }
  @Published var stagedComposerAttachments: [FriendsComposerAttachmentDraft] = []
  @Published var sendErrorMessage: String?

  var stagedComposerAttachment: FriendsComposerAttachmentDraft? {
    get { stagedComposerAttachments.first }
    set { stagedComposerAttachments = newValue.map { [$0] } ?? [] }
  }

  let route: FriendChatRoute

  @Published private(set) var viewerUserId: String
  private let service: any FriendsMessagingServiceProviding
  private let capabilities: any FriendsMessagingCapabilityProviding
  private let shareVisibilityResolver: any FriendsThreadShareVisibilityResolving
  private let sharingPreviewService: any SharingPreviewProviding
  private let sharedShiftsCache: any SharedShiftsCaching
  private let jobsRepository: JobsRepository
  private let settingsRepository: SettingsRepository
  private let repository: FriendsMessagesRepository
  private let composerDraftStore: FriendsComposerDraftStore
  private let realtimeCoordinator: any FriendsMessagingRealtimeCoordinating
  private let viewerUserIdResolver: () async -> String?
  private var hasLoaded = false
  private var loadingQuotedMessageIds: Set<String> = []
  private var didSendTypingStart = false
  private var lastTypingStartSentAt: Date?
  private var localTypingStopTask: Task<Void, Never>?
  private var localTypingPushTask: Task<Void, Never>?
  private var lastTypingPushQueuedAt: Date?
  private var activeThreadCatchUpTask: Task<Void, Never>?
  private var counterpartTypingTimeoutTask: Task<Void, Never>?
  private var counterpartTypingStopGraceTask: Task<Void, Never>?
  private var pendingNotificationTypingUserId: String?
  private var threadStatesRefreshTask: Task<Void, Never>?
  private var latestVisibleMessageReadTask: Task<Void, Never>?
  private var togglingReactionKeys: Set<String> = []
  private var backgroundSendingMessageIds: Set<String> = []
  private var suspendedComposerSnapshot: ComposerSnapshot?
  private var latestVisibleMessageId: String?
  private var latestCounterpartMessageId: String?
  private var receivedReactionCountsByMessageId: [String: Int] = [:]
  private var hasReceivedReactionBaseline = false

  var composerMode: FriendsThreadComposerMode {
    composerState.mode
  }

  var draftReplyTarget: FriendMessage? {
    composerState.replyTarget
  }

  var draftEditTarget: FriendMessage? {
    composerState.editTarget
  }

  private var effectiveCounterpartUserId: String {
    Self.normalizedUserId(thread.counterpartUserId)
      ?? Self.normalizedUserId(route.counterpartUserId)
      ?? ""
  }

  var draftCharacterLimit: Int {
    MessageBody.characterLimit
  }

  var isDraftOverCharacterLimit: Bool {
    draftCharacterCount > MessageBody.characterLimit
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
    realtimeCoordinator: (any FriendsMessagingRealtimeCoordinating)? = nil,
    viewerUserIdResolver: (() async -> String?)? = nil
  ) {
    self.route = route
    self.viewerUserId = Self.normalizedUserId(viewerUserId) ?? ""
    self.service = service ?? FriendsMessagingService.shared
    self.capabilities = capabilities ?? FriendsMessagingCapabilities.shared
    self.shareVisibilityResolver = shareVisibilityResolver ?? FriendsThreadShareVisibilityResolver()
    self.sharingPreviewService = sharingPreviewService ?? SharingService.shared
    self.sharedShiftsCache = sharedShiftsCache ?? SharedShiftsRepository.shared
    self.jobsRepository = jobsRepository ?? .shared
    self.settingsRepository = settingsRepository ?? .shared
    self.repository = repository ?? .shared
    self.composerDraftStore = composerDraftStore ?? .shared
    self.realtimeCoordinator = realtimeCoordinator ?? FriendsMessagingRealtimeCoordinator.shared
    self.viewerUserIdResolver =
      viewerUserIdResolver
      ?? {
        if let coordinatorUserId = Self.normalizedUserId(AppCoordinator.shared.getCurrentUserId()) {
          return coordinatorUserId
        }

        return Self.normalizedUserId(await AuthSessionManager.shared.getUserIdIfAvailable())
      }
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

    if !self.viewerUserId.isEmpty {
      loadFromCache()
    }
    syncCounterpartShiftPreviewFromCache()
  }

  deinit {
    localTypingStopTask?.cancel()
    localTypingPushTask?.cancel()
    activeThreadCatchUpTask?.cancel()
    counterpartTypingTimeoutTask?.cancel()
    counterpartTypingStopGraceTask?.cancel()
    threadStatesRefreshTask?.cancel()
    latestVisibleMessageReadTask?.cancel()
  }

  func loadIfNeeded() async {
    if hasLoaded {
      await startRealtime()
      return
    }
    await load()
  }

  func load() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    guard await resolveViewerUserIdIfNeeded() else {
      threadLogger.error("Unable to load thread without a viewer user ID")
      return
    }
    hasLoaded = true
    loadFromCache()
    await loadPendingComposerDraft()

    async let realtimeSubscription: Void = startRealtime()
    async let counterpartPreviewRefresh: Void = loadCounterpartShiftPreview(forceRefresh: false)
    await refreshFromServer()
    retryQueuedMessagesIfNeeded()
    _ = await (realtimeSubscription, counterpartPreviewRefresh)
  }

  func refresh() async {
    await refreshFromServer()
    retryQueuedMessagesIfNeeded()
    await loadCounterpartShiftPreview(forceRefresh: true)
    await markVisibleMessagesReadIfNeeded()
  }

  func reloadFromCache() {
    loadFromCache()
  }

  func handleExternalThreadUpdate(shouldMarkRead: Bool) async {
    loadFromCache()
    await loadCounterpartShiftPreview(forceRefresh: false)
    if shouldMarkRead {
      await markVisibleMessagesReadIfNeeded()
    }
  }

  func refreshCounterpartShiftPreview() async {
    shareVisibilityResolver.invalidateCachedVisibility(counterpartUserId: route.counterpartUserId)
    await loadCounterpartShiftPreview(forceRefresh: true)
  }

  func markVisibleMessagesReadIfNeeded() async {
    guard let visibleMessage = latestVisibleMessage else { return }
    guard shouldAdvanceReadMarker(through: visibleMessage) else { return }

    do {
      let state = try await service.markThreadRead(
        threadId: route.threadId,
        throughMessageId: visibleMessage.id
      )
      await repository.saveThreadState(state)
      notifyThreadUpdated(source: NotificationSource.localRead)
    } catch {
      threadLogger.error("Failed to mark thread as read: \(error.localizedDescription)")
    }
  }

  func updateLatestVisibleMessage(messageId: String?) {
    latestVisibleMessageReadTask?.cancel()

    guard let normalizedMessageId = normalizedMessageId(messageId) else {
      latestVisibleMessageId = nil
      return
    }

    latestVisibleMessageId = normalizedMessageId
    latestVisibleMessageReadTask = Task { @MainActor [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: VisibleReadTracking.debounceDelay)
      guard !Task.isCancelled else { return }
      await markVisibleMessagesReadIfNeeded()
    }
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
    composerFocusRequestToken += 1
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
    stagedComposerAttachments = []
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
    await setComposerAttachments(attachment.map { [$0] } ?? [])
  }

  func setComposerAttachments(_ attachments: [FriendsComposerAttachmentDraft]) async {
    guard composerMode != .edit else { return }
    stagedComposerAttachments = normalizedComposerAttachments(attachments)
    await persistPendingComposerDraft()
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
      sendErrorMessage =
        isConnectivityError(error)
        ? shiftSnapshotOfflineUnavailableMessage
        : error.localizedDescription
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
      restoreScrollTargetMessageId = nil
      replyScrollTargetMessageId = replyToMessageId
      return
    }

    while hasMoreHistoricalMessages, let oldestLoadedMessage = messages.first {
      let didLoadPage = await loadOlderMessages(
        before: oldestLoadedMessage,
        preserveScrollTargetMessageId: oldestLoadedMessage.id
      )

      if messages.contains(where: { $0.id == replyToMessageId }) {
        restoreScrollTargetMessageId = nil
        replyScrollTargetMessageId = replyToMessageId
        return
      }

      if !didLoadPage {
        break
      }
    }
  }

  func handleNotificationOpen(
    targetMessageId: String?,
    notificationTypingUserId: String?,
    forceRefresh: Bool
  ) async {
    primeNotificationTypingIndicator(userId: notificationTypingUserId)

    if forceRefresh {
      await refresh()
    }

    guard let targetMessageId = normalizedMessageId(targetMessageId) else {
      return
    }

    await focusMessage(messageId: targetMessageId)
  }

  func stopRealtime() async {
    if SensitiveContentPresentationState.shared.activeFriendThreadId == route.threadId {
      return
    }
    await stopTypingIfNeeded()
    activeThreadCatchUpTask?.cancel()
    activeThreadCatchUpTask = nil
    counterpartTypingTimeoutTask?.cancel()
    counterpartTypingStopGraceTask?.cancel()
    resetCounterpartTypingState()
    threadStatesRefreshTask?.cancel()
    threadStatesRefreshTask = nil
    await realtimeCoordinator.clearActiveThread(threadId: route.threadId)
  }

  func startRealtime() async {
    guard await resolveViewerUserIdIfNeeded(forceReloadCache: false) else {
      threadLogger.error("Skipping realtime thread subscription because viewer user ID is missing")
      return
    }
    await realtimeCoordinator.setActiveThread(
      threadId: route.threadId,
      viewerUserId: viewerUserId
    )
    startActiveThreadCatchUpLoopIfNeeded()
  }

  func handleAppDidBecomeActive() async {
    if pendingNotificationTypingUserId == nil {
      resetCounterpartTypingState()
    }
    await startRealtime()
    await refreshFromServer()
    retryQueuedMessagesIfNeeded()
    reapplyPendingNotificationTypingIndicatorIfNeeded()
  }

  func handleDraftChanged(to draft: String) async {
    guard await resolveViewerUserIdIfNeeded(forceReloadCache: false) else { return }
    guard !isThreadReadOnly else { return }
    guard composerMode != .edit else {
      await stopTypingIfNeeded()
      return
    }

    let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if hasText {
      await sendTypingStartIfNeeded()
      scheduleTypingNotificationIfNeeded()
      scheduleTypingStop()
    } else {
      await stopTypingIfNeeded()
    }

    await persistPendingComposerDraft()
  }

  func handleCounterpartTypingChange(userId: String, isTyping: Bool) {
    guard
      let normalizedUserId = Self.normalizedUserId(userId),
      normalizedUserId != viewerUserId
    else {
      return
    }

    let counterpartUserId = effectiveCounterpartUserId
    if !counterpartUserId.isEmpty, normalizedUserId != counterpartUserId {
      return
    }

    counterpartTypingTimeoutTask?.cancel()
    counterpartTypingStopGraceTask?.cancel()

    if isTyping {
      counterpartIsTyping = true
      counterpartTypingTimeoutTask = Task { @MainActor [weak self] in
        guard let self else { return }
        try? await Task.sleep(for: Typing.remoteTimeout)
        guard !Task.isCancelled else { return }
        resetCounterpartTypingState()
      }
    } else {
      if pendingNotificationTypingUserId == normalizedUserId {
        pendingNotificationTypingUserId = nil
      }
      counterpartTypingStopGraceTask = Task { @MainActor [weak self] in
        guard let self else { return }
        try? await Task.sleep(for: Typing.remoteStopGraceDelay)
        guard !Task.isCancelled else { return }
        resetCounterpartTypingState()
      }
    }
  }

  func sendDraft() async -> Bool {
    await sendMessage(content: draft)
  }

  func sendMessage(content: String) async -> Bool {
    guard await resolveViewerUserIdIfNeeded(forceReloadCache: false) else {
      sendErrorMessage = sendMessageFailedMessage
      return false
    }
    guard !isThreadReadOnly else {
      return false
    }

    if composerMode == .edit {
      return await saveEditedMessage(content: content)
    }

    let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    let composerAttachments = stagedComposerAttachments
    guard !normalizedContent.isEmpty || !composerAttachments.isEmpty else { return false }
    guard !isMessageBodyTooLong(normalizedContent) else { return false }
    guard !UserGeneratedContentFilter.containsBlockedText(normalizedContent) else {
      sendErrorMessage = messageBlockedBySafetyFilterMessage
      composerValidationMessage = messageBlockedBySafetyFilterMessage
      return false
    }
    guard canSendShiftSnapshotAttachments(composerAttachments) else {
      sendErrorMessage = shiftSnapshotSendUnavailableMessage
      return false
    }

    let previousReplyTarget = draftReplyTarget
    let composerSnapshot = currentComposerSnapshot()
    sendErrorMessage = nil

    let clientId = UUID().uuidString.lowercased()
    let optimisticAttachments = composerAttachments.imageAttachments.enumerated().map {
      makeOptimisticAttachment(from: $0.element, index: $0.offset)
    }
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
      metadataData: composerAttachments.metadataData,
      attachments: optimisticAttachments,
      reactions: [],
      sendState: .sending,
      failureMessage: nil
    )
    draft = ""
    composerState = .normal
    stagedComposerAttachments = []
    await composerDraftStore.clearDraft(
      threadId: route.threadId, viewerUserId: viewerUserId)
    await stopTypingIfNeeded()

    let sendTask = startSendTask(for: optimisticMessage)
    await repository.saveOptimisticMessage(
      optimisticMessage,
      in: route.threadId,
      for: viewerUserId
    )

    if let earlyResult = await sendTask.peekResult() {
      switch earlyResult {
      case .success(let sentMessage):
        await repository.saveConfirmedMessage(
          sentMessage,
          replacingLocalMessageId: optimisticMessage.id,
          in: route.threadId,
          for: viewerUserId
        )
        loadFromCache()
        return true

      case .failure(let error):
        if isConnectivityError(error) {
          await repository.updateMessageSendState(
            messageId: optimisticMessage.id,
            viewerUserId: viewerUserId,
            sendState: .sending,
            failureMessage: waitingForNetworkMessage
          )
          sendErrorMessage = nil
        } else {
          await repository.deleteMessage(id: optimisticMessage.id, viewerUserId: viewerUserId)
          await restoreComposerSnapshot(composerSnapshot, requestFocus: true)
          if isSafetyFilterError(error) {
            sendErrorMessage = messageBlockedBySafetyFilterMessage
          } else {
            sendErrorMessage = isMessageBodyTooLongError(error) ? nil : sendMessageFailedMessage
          }
        }
        loadFromCache()
        threadLogger.error("Failed to send thread message: \(error.localizedDescription)")
        return isConnectivityError(error)
      }
    }

    loadFromCache()
    sendMessageInBackground(optimisticMessage, sendTask: sendTask)
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
      draftReplyTarget.map { $0.matchesLogicalRow(of: message, viewerUserId: viewerUserId) }
      ?? false
      || draftEditTarget.map { $0.matchesLogicalRow(of: message, viewerUserId: viewerUserId) }
        ?? false
    let cancelledComposerSnapshot = shouldCancelComposerMode ? currentComposerSnapshot() : nil

    if shouldCancelComposerMode {
      await cancelComposerMode()
    }

    sendErrorMessage = nil
    await repository.deleteMessage(id: messageId, viewerUserId: viewerUserId)
    loadFromCache()

    guard message.sendState == .sent else {
      Haptics.play(.light)
      return
    }

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
      sendErrorMessage =
        isConnectivityError(error) ? serverActionOfflineMessage : deleteMessageFailedMessage
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

  func toggleReaction(messageId: String, emoji: String, attachmentId: String? = nil) async {
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

    if let attachmentId, !message.attachments.contains(where: { $0.id == attachmentId }) {
      return
    }

    let reactionKey = "\(messageId):\(attachmentId ?? "message"):\(normalizedEmoji)"
    guard !togglingReactionKeys.contains(reactionKey) else { return }
    togglingReactionKeys.insert(reactionKey)

    let originalMessage = message
    let optimisticMessage = message.toggledReaction(
      emoji: normalizedEmoji,
      attachmentId: attachmentId
    )
    sendErrorMessage = nil

    await repository.saveMessages([optimisticMessage], in: route.threadId, for: viewerUserId)
    loadFromCache()

    do {
      let updatedMessage = try await service.toggleMessageReaction(
        messageId: messageId,
        emoji: normalizedEmoji,
        attachmentId: attachmentId
      )
      await repository.saveMessages([updatedMessage], in: route.threadId, for: viewerUserId)
      Haptics.play(.light)
    } catch {
      await repository.saveMessages([originalMessage], in: route.threadId, for: viewerUserId)
      sendErrorMessage =
        isConnectivityError(error)
        ? serverActionOfflineMessage
        : String(localized: .friendsChatReactionFailed)
      Haptics.play(.error)
      threadLogger.error("Failed to toggle reaction: \(error.localizedDescription)")
    }

    togglingReactionKeys.remove(reactionKey)
    loadFromCache()
  }

  func submitReport(messageId: String?, reason: FriendAbuseReportReason) async throws {
    let counterpartUserId = route.counterpartUserId

    do {
      try await service.createAbuseReport(
        threadId: route.threadId,
        reportedUserId: counterpartUserId,
        messageId: messageId,
        reason: reason
      )
    } catch {
      throw offlineDisplayErrorIfNeeded(error)
    }
  }

  func blockCounterpart() async throws {
    let counterpartUserId = route.counterpartUserId

    do {
      try await service.blockUserPair(otherUserId: counterpartUserId)
    } catch {
      throw offlineDisplayErrorIfNeeded(error)
    }
    draft = ""
    composerState = .normal
    stagedComposerAttachments = []
    await composerDraftStore.clearDraft(
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
    async let threadRefresh: Void = refreshThreadSnapshotFromServer()
    async let statesRefresh: Void = refreshThreadStatesFromServer()
    _ = await (threadRefresh, statesRefresh)
  }

  private func resolveViewerUserIdIfNeeded(forceReloadCache: Bool = true) async -> Bool {
    if let normalizedViewerUserId = Self.normalizedUserId(viewerUserId) {
      if viewerUserId != normalizedViewerUserId {
        viewerUserId = normalizedViewerUserId
        resetReceivedReactionBaseline()
      }
      return true
    }

    guard let resolvedViewerUserId = await viewerUserIdResolver() else {
      return false
    }

    let didChangeViewerUserId = viewerUserId != resolvedViewerUserId
    viewerUserId = resolvedViewerUserId

    if forceReloadCache, didChangeViewerUserId {
      resetReceivedReactionBaseline()
      loadFromCache()
    }

    return true
  }

  private func refreshThreadSnapshotFromServer() async {
    do {
      let snapshot = try await service.fetchThreadSyncSnapshotV2(
        threadId: route.threadId,
        messageLimit: Pagination.pageSize
      )
      hasMoreHistoricalMessages = snapshot.hasMore
      await repository.saveThread(snapshot.thread, for: viewerUserId)
      await repository.saveMessages(snapshot.messages, in: route.threadId, for: viewerUserId)
      await repository.saveThreadState(snapshot.viewerState)
      loadFromCache()
      notifyThreadUpdated()
    } catch {
      threadLogger.error("Failed to refresh thread snapshot: \(error.localizedDescription)")
    }
  }

  private func refreshThreadStatesInBackground() {
    threadStatesRefreshTask?.cancel()
    threadStatesRefreshTask = Task { @MainActor [weak self] in
      guard let self else { return }

      do {
        // swiftlint:disable:next explicit_type_interface
        let refreshedStates = try await service.listThreadStates(threadId: route.threadId)
        await saveThreadStates(refreshedStates)
      } catch is CancellationError {
        return
      } catch {
        threadLogger.error("Failed to refresh thread states: \(error.localizedDescription)")
      }
    }
  }

  private func startActiveThreadCatchUpLoopIfNeeded() {
    guard activeThreadCatchUpTask == nil else { return }

    activeThreadCatchUpTask = Task { @MainActor [weak self] in
      guard let self else { return }

      while !Task.isCancelled {
        do {
          try await Task.sleep(for: ActiveThreadReconciliation.interval)
        } catch {
          return
        }

        guard !Task.isCancelled else { return }
        guard SensitiveContentPresentationState.shared.activeFriendThreadId == route.threadId
        else {
          continue
        }
        guard UIApplication.shared.applicationState == .active else {
          continue
        }

        await refreshFromServer()
      }
    }
  }

  private func refreshThreadStatesFromServer() async {
    refreshThreadStatesInBackground()
    await threadStatesRefreshTask?.value
  }

  private func saveThreadStates(_ states: [FriendThreadState]) async {
    for state in states {
      await repository.saveThreadState(state)
    }
    loadFromCache()
    notifyThreadUpdated()
  }

  private func notifyThreadUpdated(source: String? = nil) {
    var userInfo: [String: Any] = ["threadId": route.threadId]
    if let source {
      userInfo["source"] = source
    }

    NotificationCenter.default.post(
      name: .friendsThreadDidUpdate,
      object: nil,
      userInfo: userInfo
    )
  }

  private func loadFromCache() {
    let previousCounterpartMessageId = latestCounterpartMessageId

    if let cachedThread = repository.getThread(id: route.threadId, viewerUserId: viewerUserId),
      cachedThread != thread
    {
      thread = cachedThread
    }

    let cachedCounterpartReadState: FriendThreadState?
    if route.counterpartUserId.isEmpty {
      cachedCounterpartReadState = nil
    } else {
      cachedCounterpartReadState = repository.getThreadState(
        threadId: route.threadId,
        viewerUserId: route.counterpartUserId
      )
    }
    if counterpartReadState != cachedCounterpartReadState {
      counterpartReadState = cachedCounterpartReadState
    }

    let cachedMessages = repository.getMessages(
      threadId: route.threadId, viewerUserId: viewerUserId)
    let messagesDidChange = messages != cachedMessages
    if messagesDidChange || !hasReceivedReactionBaseline {
      playReceivedReactionHapticIfNeeded(for: cachedMessages)
    }
    if messagesDidChange {
      messages = cachedMessages
    }

    latestCounterpartMessageId = latestIncomingCounterpartMessageId(in: thread)
    if latestCounterpartMessageId != nil, latestCounterpartMessageId != previousCounterpartMessageId
    {
      if pendingNotificationTypingUserId == nil {
        resetCounterpartTypingState()
      }
    }
    syncCounterpartShiftPreviewFromCache()
    syncComposerStateWithCachedMessages()
    prefetchQuotedMessagesIfNeeded()
  }

  private func playReceivedReactionHapticIfNeeded(for cachedMessages: [FriendMessage]) {
    let reactionCounts = receivedReactionCounts(in: cachedMessages)
    defer {
      receivedReactionCountsByMessageId = reactionCounts
      hasReceivedReactionBaseline = true
    }

    guard hasReceivedReactionBaseline else { return }

    let hasNewReceivedReaction = reactionCounts.contains { messageId, count in
      count > (receivedReactionCountsByMessageId[messageId] ?? 0)
    }
    if hasNewReceivedReaction {
      Haptics.play(.light)
    }
  }

  private func resetReceivedReactionBaseline() {
    receivedReactionCountsByMessageId = [:]
    hasReceivedReactionBaseline = false
  }

  private func receivedReactionCounts(in messages: [FriendMessage]) -> [String: Int] {
    Dictionary(
      uniqueKeysWithValues:
        messages
        .filter { $0.senderUserId == viewerUserId }
        .map { message in
          (
            message.id,
            Self.receivedReactionCount(for: message)
          )
        }
    )
  }

  private static func receivedReactionCount(for message: FriendMessage) -> Int {
    let messageReactionCount = message.reactions.reduce(0) { partialResult, reaction in
      partialResult + max(reaction.count - (reaction.viewerHasReacted ? 1 : 0), 0)
    }
    let attachmentReactionCount = message.attachments.reduce(0) { partialResult, attachment in
      partialResult
        + attachment.reactions.reduce(0) { attachmentResult, reaction in
          attachmentResult + max(reaction.count - (reaction.viewerHasReacted ? 1 : 0), 0)
        }
    }

    return messageReactionCount + attachmentReactionCount
  }

  private func loadPendingComposerDraft() async {
    guard
      let storedDraft = await composerDraftStore.loadDraft(
        threadId: route.threadId,
        viewerUserId: viewerUserId
      )
    else {
      return
    }

    draft = storedDraft.text
    stagedComposerAttachments = normalizedComposerAttachments(storedDraft.attachments)
  }

  private func syncComposerStateWithCachedMessages() {
    switch composerState {
    case .normal:
      break

    case .reply(let message):
      guard let refreshedMessage = messageForComposerContext(matching: message) else {
        composerState = .normal
        return
      }
      composerState = .reply(refreshedMessage)

    case .edit(let message):
      guard let refreshedMessage = messageForComposerContext(matching: message),
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
      stagedAttachments: stagedComposerAttachments
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
    stagedComposerAttachments = normalizedComposerAttachments(snapshot?.stagedAttachments ?? [])
    await persistPendingComposerDraft()

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
      guard let refreshedMessage = messageForComposerContext(matching: message) else {
        return .normal
      }
      return .reply(refreshedMessage)

    case .edit(let message):
      guard let refreshedMessage = messageForComposerContext(matching: message),
        refreshedMessage.canEdit(viewerUserId: viewerUserId)
      else {
        return .normal
      }
      return .edit(refreshedMessage)
    }
  }

  private func messageForComposerContext(matching reference: FriendMessage) -> FriendMessage? {
    if let message = messages.first(where: {
      $0.matchesLogicalRow(of: reference, viewerUserId: viewerUserId)
    }) {
      return message
    }

    return repository.getMessages(threadId: route.threadId, viewerUserId: viewerUserId)
      .first(where: {
        $0.matchesLogicalRow(of: reference, viewerUserId: viewerUserId)
      })
  }

  private func persistPendingComposerDraft() async {
    guard composerMode != .edit else { return }

    await composerDraftStore.saveDraft(
      text: draft,
      attachments: stagedComposerAttachments,
      threadId: route.threadId,
      viewerUserId: viewerUserId
    )
  }

  private func loadCounterpartShiftPreview(forceRefresh: Bool) async {
    if !forceRefresh,
      let cachedCounterpartCanViewSharedShift,
      !cachedCounterpartCanViewSharedShift
    {
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

    guard
      await realtimeCoordinator.sendTypingStart(
        threadId: route.threadId,
        userId: viewerUserId
      )
    else {
      return
    }

    didSendTypingStart = true
    lastTypingStartSentAt = now
  }

  private func stopTypingIfNeeded() async {
    localTypingStopTask?.cancel()
    localTypingStopTask = nil
    localTypingPushTask?.cancel()
    localTypingPushTask = nil

    guard didSendTypingStart else { return }

    _ = await realtimeCoordinator.sendTypingStop(
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
      await stopTypingIfNeeded()
    }
  }

  private func scheduleTypingNotificationIfNeeded() {
    let now = Date()
    if let lastTypingPushQueuedAt,
      now.timeIntervalSince(lastTypingPushQueuedAt) < Typing.pushCooldown
    {
      return
    }

    guard localTypingPushTask == nil else { return }

    localTypingPushTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { localTypingPushTask = nil }

      try? await Task.sleep(for: Typing.pushEscalationDelay)
      guard !Task.isCancelled else { return }
      // swiftlint:disable:next conditional_returns_on_newline
      guard !isThreadReadOnly, composerMode != .edit else { return }
      // swiftlint:disable:next conditional_returns_on_newline
      guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

      await queueTypingNotificationIfNeeded()
    }
  }

  private func queueTypingNotificationIfNeeded() async {
    let now = Date()
    if let lastTypingPushQueuedAt,
      now.timeIntervalSince(lastTypingPushQueuedAt) < Typing.pushCooldown
    {
      return
    }

    do {
      let didQueue = try await service.queueThreadTypingNotification(threadId: route.threadId)
      if didQueue {
        lastTypingPushQueuedAt = Date()
      }
    } catch {
      threadLogger.error(
        "Failed to queue typing push notification: \(error.localizedDescription)")
    }
  }

  private func resetTypingNotificationCooldown() {
    lastTypingPushQueuedAt = nil
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
    guard !isMessageBodyTooLong(normalizedContent) else { return false }
    guard !UserGeneratedContentFilter.containsBlockedText(normalizedContent) else {
      sendErrorMessage = messageBlockedBySafetyFilterMessage
      composerValidationMessage = messageBlockedBySafetyFilterMessage
      return false
    }

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
      sendErrorMessage =
        isConnectivityError(error)
        ? serverActionOfflineMessage
        : (isSafetyFilterError(error)
          ? messageBlockedBySafetyFilterMessage
          : (isMessageBodyTooLongError(error) ? nil : editMessageFailedMessage))
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
      let page = try await service.listThreadMessagesV2(
        threadId: route.threadId,
        limit: Pagination.pageSize,
        before: oldestLoadedMessage.paginationCursor
      )

      let olderMessages = page.messages
      hasMoreHistoricalMessages = page.hasMore
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
          loadingQuotedMessageIds.remove(messageId)
        }

        do {
          // swiftlint:disable:next explicit_type_interface
          let quotedMessage = try await service.fetchMessageSyncPayloadV2(messageId: messageId)
          // swiftlint:disable:next conditional_returns_on_newline
          guard quotedMessage.threadId == route.threadId else { return }
          guard quotedMessage.deletedAt == nil else {
            quotedMessagesById.removeValue(forKey: messageId)
            return
          }
          quotedMessagesById[messageId] = quotedMessage
        } catch {
          threadLogger.error(
            "Failed to fetch quoted message \(messageId): \(error.localizedDescription)")
        }
      }
    }
  }

  private func focusMessage(messageId: String) async {
    if messages.contains(where: { $0.id == messageId }) {
      restoreScrollTargetMessageId = nil
      replyScrollTargetMessageId = messageId
      return
    }

    while hasMoreHistoricalMessages, let oldestLoadedMessage = messages.first {
      let didLoadPage = await loadOlderMessages(
        before: oldestLoadedMessage,
        preserveScrollTargetMessageId: oldestLoadedMessage.id
      )

      if messages.contains(where: { $0.id == messageId }) {
        restoreScrollTargetMessageId = nil
        replyScrollTargetMessageId = messageId
        return
      }

      if !didLoadPage {
        break
      }
    }

    do {
      let message = try await service.fetchMessageSyncPayloadV2(messageId: messageId)
      guard message.threadId == route.threadId, message.deletedAt == nil else { return }
      await repository.saveMessages([message], in: route.threadId, for: viewerUserId)
      loadFromCache()
      restoreScrollTargetMessageId = nil
      replyScrollTargetMessageId = messageId
    } catch {
      threadLogger.error("Failed to focus message \(messageId): \(error.localizedDescription)")
    }
  }

  private func normalizedMessageId(_ messageId: String?) -> String? {
    guard let messageId else { return nil }

    let normalizedMessageId = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalizedMessageId.isEmpty ? nil : normalizedMessageId
  }

  private var latestVisibleMessage: FriendMessage? {
    guard let latestVisibleMessageId else { return nil }
    return messages.first(where: { $0.id == latestVisibleMessageId })
  }

  private func shouldAdvanceReadMarker(through visibleMessage: FriendMessage) -> Bool {
    guard
      let currentState = repository.getThreadState(
        threadId: route.threadId,
        viewerUserId: viewerUserId
      )
    else {
      return true
    }

    if currentState.lastReadMessageId == visibleMessage.id {
      return false
    }

    if let currentReadMessageId = currentState.lastReadMessageId,
      let currentReadMessage = messages.first(where: { $0.id == currentReadMessageId })
    {
      return isMessage(currentReadMessage, orderedBefore: visibleMessage)
    }

    guard let lastReadAt = currentState.lastReadAt else { return true }
    return (lastReadAt, currentState.lastReadMessageId ?? "") < (
      visibleMessage.createdAt, visibleMessage.id
    )
  }

  private func isMessage(_ lhs: FriendMessage, orderedBefore rhs: FriendMessage) -> Bool {
    (lhs.createdAt, lhs.id) < (rhs.createdAt, rhs.id)
  }

  private func sendMessageInBackground(
    _ message: FriendMessage,
    sendTask: SendTaskHandle? = nil
  ) {
    guard !backgroundSendingMessageIds.contains(message.id) else { return }
    backgroundSendingMessageIds.insert(message.id)
    let sendTask = sendTask ?? startSendTask(for: message)
    Task { @MainActor in
      defer {
        backgroundSendingMessageIds.remove(message.id)
      }

      switch await sendTask.waitForResult() {
      case .success(let sentMessage):
        await repository.saveConfirmedMessage(
          sentMessage,
          replacingLocalMessageId: message.id,
          in: route.threadId,
          for: viewerUserId
        )
        loadFromCache()

      case .failure(let error):
        let sendState: FriendMessageSendState = isConnectivityError(error) ? .sending : .failed
        let failureMessage =
          isConnectivityError(error)
          ? waitingForNetworkMessage
          : error.localizedDescription
        await repository.updateMessageSendState(
          messageId: message.id,
          viewerUserId: viewerUserId,
          sendState: sendState,
          failureMessage: failureMessage
        )
        loadFromCache()
        threadLogger.error("Failed to send thread message: \(error.localizedDescription)")
      }
    }
  }

  private func startSendTask(for message: FriendMessage) -> SendTaskHandle {
    let handle = SendTaskHandle()

    Task { @MainActor in
      do {
        let sentMessage = try await sendMessageToService(message)
        await handle.complete(with: .success(sentMessage))
      } catch {
        await handle.complete(with: .failure(error))
      }
    }

    return handle
  }

  private func retryQueuedMessagesIfNeeded() {
    let queuedMessages = messages.filter { message in
      message.threadId == route.threadId
        && message.senderUserId == viewerUserId
        && message.sendState == .sending
        && !backgroundSendingMessageIds.contains(message.id)
    }

    for message in queuedMessages {
      sendMessageInBackground(message)
    }
  }

  private func updateDraftValidation(for draft: String) {
    let normalizedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    draftCharacterCount = messageBodyLengthForBackendValidation(normalizedDraft)
    composerValidationMessage =
      if isMessageBodyTooLong(normalizedDraft) {
        messageTooLongMessage
      } else if UserGeneratedContentFilter.containsBlockedText(normalizedDraft) {
        messageBlockedBySafetyFilterMessage
      } else {
        nil
      }
  }

  private func clearSafetyFilterSendErrorIfResolved(for draft: String) {
    guard sendErrorMessage == messageBlockedBySafetyFilterMessage else { return }

    let normalizedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    if !UserGeneratedContentFilter.containsBlockedText(normalizedDraft) {
      sendErrorMessage = nil
    }
  }

  private func isMessageBodyTooLong(_ normalizedBody: String) -> Bool {
    messageBodyLengthForBackendValidation(normalizedBody) > MessageBody.characterLimit
  }

  private func messageBodyLengthForBackendValidation(_ normalizedBody: String) -> Int {
    normalizedBody.unicodeScalars.count
  }

  private func latestIncomingCounterpartMessageId(in thread: FriendThread) -> String? {
    guard
      let counterpartUserId = Self.normalizedUserId(thread.counterpartUserId)
        ?? Self.normalizedUserId(route.counterpartUserId),
      let lastMessageSenderId = Self.normalizedUserId(thread.lastMessageSenderId),
      counterpartUserId == lastMessageSenderId
    else {
      return nil
    }

    return normalizedMessageId(thread.lastMessageId)
  }

  private func resetCounterpartTypingState() {
    counterpartTypingTimeoutTask?.cancel()
    counterpartTypingTimeoutTask = nil
    counterpartTypingStopGraceTask?.cancel()
    counterpartTypingStopGraceTask = nil
    counterpartIsTyping = false
  }

  private func primeNotificationTypingIndicator(userId: String?) {
    guard let normalizedUserId = Self.normalizedUserId(userId) else { return }
    pendingNotificationTypingUserId = normalizedUserId
    handleCounterpartTypingChange(userId: normalizedUserId, isTyping: true)
  }

  private func reapplyPendingNotificationTypingIndicatorIfNeeded() {
    guard let pendingNotificationTypingUserId else { return }
    handleCounterpartTypingChange(userId: pendingNotificationTypingUserId, isTyping: true)
    self.pendingNotificationTypingUserId = nil
  }

  private static func normalizedUserId(_ userId: String?) -> String? {
    guard let userId else { return nil }
    let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalizedUserId.isEmpty ? nil : normalizedUserId
  }

  private func isMessageBodyTooLongError(_ error: Error) -> Bool {
    guard let serviceError = error as? FriendsMessagingServiceError else { return false }
    guard case .httpError(_, let message) = serviceError else { return false }
    return (message ?? "").localizedCaseInsensitiveContains("character limit")
  }

  private func isSafetyFilterError(_ error: Error) -> Bool {
    guard let serviceError = error as? FriendsMessagingServiceError else { return false }
    guard case .httpError(_, let message) = serviceError else { return false }
    return (message ?? "").localizedCaseInsensitiveContains("safety filter")
  }

  private func isConnectivityError(_ error: Error) -> Bool {
    if error is CancellationError {
      return false
    }

    if let serviceError = error as? FriendsMessagingServiceError {
      switch serviceError {
      case .networkError:
        return true

      case .notAuthenticated, .decodingError, .httpError:
        return false
      }
    }

    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      return true
    }

    if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
      return isConnectivityError(underlyingError)
    }

    return false
  }

  private func offlineDisplayErrorIfNeeded(_ error: Error) -> Error {
    isConnectivityError(error) ? ActionError.offlineServerAction : error
  }

  private func sendMessageToService(_ message: FriendMessage) async throws -> FriendMessage {
    let outgoingAttachments = try await makeOutgoingAttachments(for: message)
    let sentMessage = try await service.sendMessage(
      threadId: route.threadId,
      clientId: message.clientId,
      body: message.body,
      replyToMessageId: message.replyToMessageId,
      attachments: outgoingAttachments,
      metadataData: message.sendableMetadataData
    )
    resetTypingNotificationCooldown()
    return sentMessage
  }

  private func makeOptimisticAttachment(from image: ImageAttachment, index: Int)
    -> FriendMessageAttachment
  {
    let storagePath = pendingAttachmentStoragePath(for: image.id)
    cacheImage(image, for: storagePath)

    let imageSize = UIImage(data: image.data)?.size
    return FriendMessageAttachment(
      id: image.id,
      attachmentIndex: index,
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

      if let cachedImage = ImageCache.shared.get(for: cacheURL, policy: .messageAttachment),
        let data = cachedImage.jpegData(compressionQuality: 0.9)
      {
        return ImageAttachment(id: attachmentId, data: data, mediaType: "image/jpeg")
      }

      if let cachedImage = await ImageCache.shared.getFromDisk(
        for: cacheURL,
        policy: .messageAttachment
      ),
        let data = cachedImage.jpegData(compressionQuality: 0.9)
      {
        return ImageAttachment(id: attachmentId, data: data, mediaType: "image/jpeg")
      }

      return nil
    }.value
  }

  private func cacheImage(_ image: ImageAttachment, for storagePath: String) {
    guard let uiImage = UIImage(data: image.data) else { return }
    ImageCache.shared.set(
      uiImage,
      for: Self.imageCacheURL(for: storagePath),
      policy: .messageAttachment
    )
  }

  private nonisolated static func imageCacheURL(for storagePath: String) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "friends-message-cache.local"
    components.path = "/\(storagePath)"
    return components.url ?? URL(filePath: "/tmp/friends-message-cache-fallback")
  }

  private var shiftSnapshotSendUnavailableMessage: String {
    String(localized: .friendsChatShiftSnapshotSendUnavailable)
  }

  private var shiftSnapshotOfflineUnavailableMessage: String {
    waitingForNetworkMessage
  }

  private var serverActionOfflineMessage: String {
    waitingForNetworkMessage
  }

  private var waitingForNetworkMessage: String {
    String(localized: .friendsChatWaitingForNetwork)
  }

  private var sendMessageFailedMessage: String {
    String(localized: .friendsChatSendFailed)
  }

  private var messageTooLongMessage: String {
    String(localized: .friendsChatComposerMessageTooLong)
      .replacingOccurrences(of: "{limit}", with: "\(MessageBody.characterLimit)")
  }

  private var messageBlockedBySafetyFilterMessage: String {
    String(localized: .friendsChatComposerSafetyFilter)
  }

  private var editMessageFailedMessage: String {
    String(localized: .friendsChatEditFailed)
  }

  private var deleteMessageFailedMessage: String {
    String(localized: .friendsChatDeleteFailed)
  }

  private func canSendShiftSnapshotAttachments(_ attachments: [FriendsComposerAttachmentDraft])
    -> Bool
  {
    guard attachments.hasShiftSnapshot else { return true }
    return capabilities.canSendShiftSnapshots
  }

  private func canSendShiftSnapshotMessage(_ message: FriendMessage) -> Bool {
    guard message.shiftSnapshot != nil else { return true }
    return capabilities.canSendShiftSnapshots
  }

  private func normalizedComposerAttachments(_ attachments: [FriendsComposerAttachmentDraft])
    -> [FriendsComposerAttachmentDraft]
  {
    if let shiftSnapshotDraft = attachments.shiftSnapshotDraft {
      return [.shiftSnapshot(shiftSnapshotDraft)]
    }

    return attachments.imageAttachments
      .uniquePayloads()
      .prefix(FriendsComposerAttachmentLimits.maxImagesPerMessage)
      .map(FriendsComposerAttachmentDraft.image)
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
