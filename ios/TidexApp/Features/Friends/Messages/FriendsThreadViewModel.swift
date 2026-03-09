import Combine
import Foundation
import UIKit
import os.log

private let threadLogger = Logger(subsystem: "com.tidex.app", category: "FriendsThreadViewModel")

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
  @Published var draftReplyTarget: FriendMessage?
  @Published var draft = ""
  @Published var sendErrorMessage: String?

  let route: FriendChatRoute

  let viewerUserId: String
  private let service: any FriendsMessagingServiceProviding
  private let repository: FriendsMessagesRepository
  private let realtimeCoordinator: FriendsMessagingRealtimeCoordinator
  private var hasLoaded = false
  private var loadingQuotedMessageIds: Set<String> = []
  private var didSendTypingStart = false
  private var lastTypingStartSentAt: Date?
  private var localTypingStopTask: Task<Void, Never>?
  private var counterpartTypingTimeoutTask: Task<Void, Never>?
  private var reconcilingOptimisticMessageIds: Set<String> = []
  private var togglingReactionKeys: Set<String> = []

  init(
    route: FriendChatRoute,
    viewerUserId: String,
    service: (any FriendsMessagingServiceProviding)? = nil,
    repository: FriendsMessagesRepository? = nil,
    realtimeCoordinator: FriendsMessagingRealtimeCoordinator? = nil
  ) {
    self.route = route
    self.viewerUserId = viewerUserId
    self.service = service ?? FriendsMessagingService.shared
    self.repository = repository ?? .shared
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
  }

  func loadIfNeeded() async {
    guard !hasLoaded else { return }
    hasLoaded = true
    await load()
  }

  func load() async {
    isLoading = true
    loadFromCache()

    await realtimeCoordinator.startThreadSubscription(
      threadId: route.threadId,
      viewerUserId: viewerUserId
    )

    await refreshFromServer()
    await markLatestIncomingAsRead()
    isLoading = false
  }

  func refresh() async {
    await refreshFromServer()
    await markLatestIncomingAsRead()
  }

  func reloadFromCache() {
    loadFromCache()
  }

  func handleExternalThreadUpdate(shouldMarkRead: Bool) async {
    loadFromCache()
    if shouldMarkRead {
      await markLatestIncomingAsRead()
    }
  }

  func markVisibleMessagesReadIfNeeded() async {
    await markLatestIncomingAsRead()
  }

  func loadOlderMessagesIfNeeded(currentFirstMessageId: String) async {
    guard !isLoading, !isLoadingOlderMessages, hasMoreHistoricalMessages,
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
    draftReplyTarget = message
  }

  func clearReplyTarget() {
    draftReplyTarget = nil
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
    await sendMessage(content: draft, image: nil)
  }

  func sendMessage(content: String, image: ImageAttachment?) async -> Bool {
    guard !isThreadReadOnly else {
      return false
    }

    let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedContent.isEmpty || image != nil else { return false }

    let previousReplyTarget = draftReplyTarget
    sendErrorMessage = nil

    let clientId = UUID().uuidString.lowercased()
    let optimisticAttachments = image.map { [makeOptimisticAttachment(from: $0)] } ?? []
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
      metadataData: nil,
      attachments: optimisticAttachments,
      reactions: [],
      sendState: .sending,
      failureMessage: nil
    )

    draft = ""
    draftReplyTarget = nil
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

  func retryMessage(messageId: String) async {
    guard let message = repository.getMessage(id: messageId, viewerUserId: viewerUserId),
      message.senderUserId == viewerUserId,
      message.canRetrySend
    else {
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
    draftReplyTarget = nil
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
      let refreshedThread = try await service.fetchThreadSummary(threadId: route.threadId)
      let refreshedMessages = try await service.listThreadMessages(
        threadId: route.threadId,
        limit: Pagination.pageSize,
        before: nil
      )
      let refreshedCounterpartState =
        route.counterpartUserId.isEmpty
        ? nil
        : try await service.fetchThreadState(
          threadId: route.threadId,
          userId: route.counterpartUserId
        )

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
    reconcileOptimisticMessagesIfNeeded()
    prefetchQuotedMessagesIfNeeded()
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
      do {
        let outgoingAttachments = try await makeOutgoingAttachments(for: message)
        let sentMessage = try await service.sendMessage(
          threadId: route.threadId,
          clientId: message.clientId,
          body: message.body,
          replyToMessageId: message.replyToMessageId,
          attachments: outgoingAttachments
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
    let cacheURL = imageCacheURL(for: attachment.storagePath)

    if let cachedImage = ImageCache.shared.get(for: cacheURL),
      let data = cachedImage.jpegData(compressionQuality: 0.9)
    {
      return ImageAttachment(id: attachment.id, data: data, mediaType: attachment.mimeType)
    }

    if let cachedImage = await ImageCache.shared.getFromDisk(for: cacheURL),
      let data = cachedImage.jpegData(compressionQuality: 0.9)
    {
      return ImageAttachment(id: attachment.id, data: data, mediaType: attachment.mimeType)
    }

    return nil
  }

  private func cacheImage(_ image: ImageAttachment, for storagePath: String) {
    guard let uiImage = UIImage(data: image.data) else { return }
    ImageCache.shared.set(uiImage, for: imageCacheURL(for: storagePath))
  }

  private func imageCacheURL(for storagePath: String) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "friends-message-cache.local"
    components.path = "/\(storagePath)"
    return components.url ?? URL(filePath: "/tmp/friends-message-cache-fallback")
  }

  private func reconcileOptimisticMessagesIfNeeded() {
    guard thread.lastMessageSenderId == viewerUserId else { return }

    let pendingMessages = messages.filter {
      $0.senderUserId == viewerUserId && $0.sendState == .sending
    }

    for message in pendingMessages where shouldPromoteOptimisticMessage(message) {
      guard !reconcilingOptimisticMessageIds.contains(message.id) else { continue }
      reconcilingOptimisticMessageIds.insert(message.id)

      Task { @MainActor [weak self] in
        guard let self else { return }

        await repository.updateMessageSendState(
          messageId: message.id,
          viewerUserId: viewerUserId,
          sendState: .sent,
          failureMessage: nil
        )
        reconcilingOptimisticMessageIds.remove(message.id)
        loadFromCache()
      }
    }
  }

  private func shouldPromoteOptimisticMessage(_ message: FriendMessage) -> Bool {
    guard let lastMessageAt = thread.lastMessageAt else { return false }
    guard lastMessageAt >= message.createdAt else { return false }
    guard lastMessageAt.timeIntervalSince(message.createdAt) < 300 else { return false }

    let normalizedMessageBody = message.body?.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedThreadBody = thread.lastMessageBody?.trimmingCharacters(
      in: .whitespacesAndNewlines)

    if normalizedMessageBody != normalizedThreadBody {
      return false
    }

    return message.hasImageAttachment == thread.lastMessageHasImage
  }
}
