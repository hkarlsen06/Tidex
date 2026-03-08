import Foundation
import os.log

private let threadLogger = Logger(subsystem: "com.tidex.app", category: "FriendsThreadViewModel")

@MainActor
final class FriendsThreadViewModel: ObservableObject {
  private enum Pagination {
    static let pageSize = 50
  }

  enum ActionError: LocalizedError {
    case missingCounterpart

    var errorDescription: String? {
      switch self {
      case .missingCounterpart:
        return "Missing counterpart user"
      }
    }
  }

  @Published private(set) var thread: FriendThread
  @Published private(set) var messages: [FriendMessage] = []
  @Published private(set) var isLoading = false
  @Published private(set) var isLoadingOlderMessages = false
  @Published private(set) var hasMoreHistoricalMessages = true
  @Published private(set) var isSending = false
  @Published private(set) var isThreadReadOnly = false
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

  func handleExternalThreadUpdate() async {
    loadFromCache()
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
    await realtimeCoordinator.stopThreadSubscription(threadId: route.threadId)
  }

  func sendDraft() async -> Bool {
    await sendMessage(content: draft, image: nil)
  }

  func sendMessage(content: String, image: ImageAttachment?) async -> Bool {
    guard !isThreadReadOnly else {
      sendErrorMessage = String(localized: .friendsChatBlockedReadOnly)
      return false
    }

    let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !isSending, !normalizedContent.isEmpty || image != nil else { return false }

    let previousDraft = content
    let previousReplyTarget = draftReplyTarget
    draft = ""
    sendErrorMessage = nil
    isSending = true

    defer {
      isSending = false
      loadFromCache()
    }

    do {
      let outgoingAttachments: [FriendOutgoingAttachment]
      if let image {
        outgoingAttachments = [
          try await service.uploadImageAttachment(threadId: route.threadId, image: image)
        ]
      } else {
        outgoingAttachments = []
      }

      let message = try await service.sendMessage(
        threadId: route.threadId,
        clientId: UUID().uuidString,
        body: normalizedContent.isEmpty ? nil : normalizedContent,
        replyToMessageId: previousReplyTarget?.id,
        attachments: outgoingAttachments
      )

      await repository.saveMessages([message], in: route.threadId, for: viewerUserId)
      draftReplyTarget = nil
      await refreshFromServer()
      return true
    } catch {
      draft = previousDraft
      draftReplyTarget = previousReplyTarget
      sendErrorMessage = String(localized: .friendsChatSendFailed)
      threadLogger.error("Failed to send thread message: \(error.localizedDescription)")
      return false
    }
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
    sendErrorMessage = String(localized: .friendsChatBlockedReadOnly)
    isThreadReadOnly = true
    NotificationCenter.default.post(
      name: Notification.Name("friendsVisibilityChanged"),
      object: nil
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

      hasMoreHistoricalMessages = refreshedMessages.count == Pagination.pageSize
      await repository.saveThread(refreshedThread, for: viewerUserId)
      await repository.saveMessages(refreshedMessages, in: route.threadId, for: viewerUserId)
      loadFromCache()
    } catch {
      threadLogger.error("Failed to refresh thread: \(error.localizedDescription)")
    }
  }

  private func markLatestIncomingAsRead() async {
    guard let lastMessage = messages.last, lastMessage.senderUserId != viewerUserId else { return }

    do {
      let state = try await service.markThreadRead(
        threadId: route.threadId,
        throughMessageId: lastMessage.id
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
    messages = repository.getMessages(threadId: route.threadId, viewerUserId: viewerUserId)
    prefetchQuotedMessagesIfNeeded()
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
}
