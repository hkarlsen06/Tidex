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
  @Published var draft = ""
  @Published var sendErrorMessage: String?

  let route: FriendChatRoute

  private let viewerUserId: String
  private let service: any FriendsMessagingServiceProviding
  private let repository: FriendsMessagesRepository
  private let realtimeCoordinator: FriendsMessagingRealtimeCoordinator
  private var hasLoaded = false

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

  func loadOlderMessagesIfNeeded(currentFirstMessageId: String) async {
    guard !isLoading, !isLoadingOlderMessages, hasMoreHistoricalMessages,
      let oldestLoadedMessage = messages.first,
      oldestLoadedMessage.id == currentFirstMessageId
    else {
      return
    }

    isLoadingOlderMessages = true
    defer { isLoadingOlderMessages = false }

    do {
      let olderMessages = try await service.listThreadMessages(
        threadId: route.threadId,
        limit: Pagination.pageSize,
        before: oldestLoadedMessage.paginationCursor
      )

      hasMoreHistoricalMessages = olderMessages.count == Pagination.pageSize
      guard !olderMessages.isEmpty else { return }

      await repository.saveMessages(olderMessages, in: route.threadId, for: viewerUserId)
      loadFromCache()
      restoreScrollTargetMessageId = currentFirstMessageId
    } catch {
      threadLogger.error("Failed to load older messages: \(error.localizedDescription)")
    }
  }

  func consumeRestoreScrollTarget() {
    restoreScrollTargetMessageId = nil
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
        attachments: outgoingAttachments
      )

      await repository.saveMessages([message], in: route.threadId, for: viewerUserId)
      await refreshFromServer()
      return true
    } catch {
      draft = previousDraft
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
  }
}
