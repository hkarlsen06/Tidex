import Foundation
import os.log

private let threadLogger = Logger(subsystem: "com.tidex.app", category: "FriendsThreadViewModel")

@MainActor
final class FriendsThreadViewModel: ObservableObject {
  @Published private(set) var thread: FriendThread
  @Published private(set) var messages: [FriendMessage] = []
  @Published private(set) var isLoading = false
  @Published private(set) var isSending = false
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

  func stopRealtime() async {
    await realtimeCoordinator.stopThreadSubscription(threadId: route.threadId)
  }

  func sendDraft() async {
    let normalizedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedDraft.isEmpty, !isSending else { return }

    let previousDraft = draft
    draft = ""
    sendErrorMessage = nil
    isSending = true

    defer {
      isSending = false
      loadFromCache()
    }

    do {
      let message = try await service.sendMessage(
        threadId: route.threadId,
        clientId: UUID().uuidString,
        body: normalizedDraft,
        attachments: []
      )

      await repository.saveMessages([message], in: route.threadId, for: viewerUserId)
      await refreshFromServer()
    } catch {
      draft = previousDraft
      sendErrorMessage = String(localized: .friendsChatSendFailed)
      threadLogger.error("Failed to send thread message: \(error.localizedDescription)")
    }
  }

  private func refreshFromServer() async {
    do {
      let refreshedThread = try await service.fetchThreadSummary(threadId: route.threadId)
      let refreshedMessages = try await service.listThreadMessages(
        threadId: route.threadId,
        limit: 200,
        before: nil
      )

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
