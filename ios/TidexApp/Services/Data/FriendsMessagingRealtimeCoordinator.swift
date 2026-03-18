import Combine
import Foundation
import Supabase
import os.log

private let realtimeLogger = Logger(
  subsystem: "com.tidex.app", category: "FriendsMessagingRealtime")

extension Notification.Name {
  static let friendsThreadDidUpdate = Notification.Name("friendsThreadDidUpdate")
  static let friendsThreadTypingDidChange = Notification.Name("friendsThreadTypingDidChange")
}

@MainActor
protocol FriendsMessagingRealtimeCoordinating: AnyObject {
  func startThreadListSubscription(viewerUserId: String) async
  func stopThreadListSubscription() async
  func startThreadSubscription(threadId: String, viewerUserId: String) async
  func stopThreadSubscription(threadId: String) async
  func sendTypingStart(threadId: String, userId: String) async -> Bool
  func sendTypingStop(threadId: String, userId: String) async -> Bool
}

@MainActor
final class FriendsMessagingRealtimeCoordinator: ObservableObject {
  private enum Pagination {
    static let pageSize = 50
  }

  private enum TypingEvent {
    static let start = "typing_start"
    static let stop = "typing_stop"
  }

  static let shared = FriendsMessagingRealtimeCoordinator()

  private let service: any FriendsMessagingServiceProviding
  private let repository: any FriendsMessagesRepositoryProviding

  private var threadListChannel: RealtimeChannelV2?
  private var threadListTasks: [Task<Void, Never>] = []
  private var listTypingThreadIds: Set<String> = []
  private var listTypingChannels: [String: RealtimeChannelV2] = [:]
  private var listTypingTasks: [String: [Task<Void, Never>]] = [:]
  private var threadChannels: [String: RealtimeChannelV2] = [:]
  private var threadTasks: [String: [Task<Void, Never>]] = [:]

  private struct ThreadTypingPayload: Codable {
    let threadId: String
    let userId: String
    let sentAtMs: Int64

    enum CodingKeys: String, CodingKey {
      case threadId = "thread_id"
      case userId = "user_id"
      case sentAtMs = "sent_at_ms"
    }
  }

  init(
    service: (any FriendsMessagingServiceProviding)? = nil,
    repository: (any FriendsMessagesRepositoryProviding)? = nil
  ) {
    self.service = service ?? FriendsMessagingService.shared
    self.repository = repository ?? FriendsMessagesRepository.shared
  }

  func startThreadListSubscription(viewerUserId: String) async {
    await stopThreadListSubscription()

    let channel = supabase.channel("friends-thread-list:\(viewerUserId)")
    let threadChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "threads")
    let messageChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "messages")
    let stateChanges = channel.postgresChange(
      AnyAction.self,
      schema: "public",
      table: "thread_user_state",
      filter: .eq("user_id", value: viewerUserId)
    )

    do {
      try await channel.subscribeWithError()
      threadListChannel = channel

      threadListTasks = [
        makeStatusTask(
          for: channel,
          viewerUserId: viewerUserId,
          skipInitialSubscribedRefresh: true
        ),
        Task { [weak self] in
          guard let self else { return }
          for await action in threadChanges {
            await self.handleThreadListThreadAction(action, viewerUserId: viewerUserId)
          }
        },
        Task { [weak self] in
          guard let self else { return }
          for await action in messageChanges {
            await self.handleThreadListMessageAction(action, viewerUserId: viewerUserId)
          }
        },
        Task { [weak self] in
          guard let self else { return }
          for await action in stateChanges {
            await self.handleThreadListStateAction(action, viewerUserId: viewerUserId)
          }
        },
      ]

      await refreshThreadList(viewerUserId: viewerUserId)
    } catch {
      realtimeLogger.error(
        "Failed to subscribe thread list realtime: \(error.localizedDescription)")
      await supabase.removeChannel(channel)
    }
  }

  func stopThreadListSubscription() async {
    threadListTasks.forEach { $0.cancel() }
    threadListTasks.removeAll()

    if let threadListChannel {
      await supabase.removeChannel(threadListChannel)
      self.threadListChannel = nil
    }
  }

  func syncThreadListTypingSubscriptions(threadIds: [String]) async {
    let desiredThreadIds = Set(threadIds)
    let threadIdsToRemove = listTypingThreadIds.subtracting(desiredThreadIds)
    listTypingThreadIds = desiredThreadIds

    for threadId in threadIdsToRemove {
      await teardownListTypingChannel(threadId: threadId)
    }

    for threadId in desiredThreadIds {
      if threadChannels[threadId] != nil {
        await teardownListTypingChannel(threadId: threadId)
      } else {
        _ = await ensureListTypingChannel(threadId: threadId)
      }
    }
  }

  func stopThreadListTypingSubscriptions() async {
    let trackedThreadIds = listTypingThreadIds
    listTypingThreadIds.removeAll()

    for threadId in trackedThreadIds {
      await teardownListTypingChannel(threadId: threadId)
    }
  }

  func startThreadSubscription(threadId: String, viewerUserId: String) async {
    await stopThreadSubscription(threadId: threadId)
    await teardownListTypingChannel(threadId: threadId)

    let channel = supabase.channel("friends-thread-detail:\(threadId)") { config in
      config.broadcast.receiveOwnBroadcasts = true
    }
    let threadChanges = channel.postgresChange(
      AnyAction.self,
      schema: "public",
      table: "threads",
      filter: .eq("id", value: threadId)
    )
    let messageChanges = channel.postgresChange(
      AnyAction.self,
      schema: "public",
      table: "messages",
      filter: .eq("thread_id", value: threadId)
    )
    let reactionChanges = channel.postgresChange(
      AnyAction.self,
      schema: "public",
      table: "message_reactions",
      filter: .eq("thread_id", value: threadId)
    )
    let stateChanges = channel.postgresChange(
      AnyAction.self,
      schema: "public",
      table: "thread_user_state",
      filter: .eq("thread_id", value: threadId)
    )

    do {
      try await channel.subscribeWithError()
      threadChannels[threadId] = channel

      threadTasks[threadId] = [
        makeTypingBroadcastTask(
          for: channel,
          threadId: threadId,
          event: TypingEvent.start,
          isTyping: true
        ),
        makeTypingBroadcastTask(
          for: channel,
          threadId: threadId,
          event: TypingEvent.stop,
          isTyping: false
        ),
        makeThreadStatusTask(
          for: channel,
          threadId: threadId,
          viewerUserId: viewerUserId,
          skipInitialSubscribedRefresh: true
        ),
        Task { [weak self] in
          guard let self else { return }
          for await action in threadChanges {
            await self.handleThreadDetailThreadAction(
              action, threadId: threadId, viewerUserId: viewerUserId)
          }
        },
        Task { [weak self] in
          guard let self else { return }
          for await action in messageChanges {
            await self.handleThreadDetailMessageAction(
              action, threadId: threadId, viewerUserId: viewerUserId)
          }
        },
        Task { [weak self] in
          guard let self else { return }
          for await action in reactionChanges {
            await self.handleThreadDetailReactionAction(
              action, threadId: threadId, viewerUserId: viewerUserId)
          }
        },
        Task { [weak self] in
          guard let self else { return }
          for await action in stateChanges {
            await self.handleThreadDetailStateAction(
              action, threadId: threadId, viewerUserId: viewerUserId)
          }
        },
      ]
    } catch {
      realtimeLogger.error(
        "Failed to subscribe thread detail realtime: \(error.localizedDescription)")
      await supabase.removeChannel(channel)
    }
  }

  func stopThreadSubscription(threadId: String) async {
    threadTasks[threadId]?.forEach { $0.cancel() }
    threadTasks[threadId] = nil

    if let channel = threadChannels[threadId] {
      await supabase.removeChannel(channel)
      threadChannels[threadId] = nil
    }

    if listTypingThreadIds.contains(threadId) {
      _ = await ensureListTypingChannel(threadId: threadId)
    }
  }

  func stopAll() async {
    await stopThreadListSubscription()
    await stopThreadListTypingSubscriptions()
    for threadId in threadChannels.keys {
      await stopThreadSubscription(threadId: threadId)
    }
  }

  func sendTypingStart(threadId: String, userId: String) async -> Bool {
    await broadcastTypingEvent(event: TypingEvent.start, threadId: threadId, userId: userId)
  }

  func sendTypingStop(threadId: String, userId: String) async -> Bool {
    await broadcastTypingEvent(event: TypingEvent.stop, threadId: threadId, userId: userId)
  }

  private func refreshThreadList(viewerUserId: String) async {
    do {
      let threads = try await service.listMyThreads(limit: 100, before: nil)
      await repository.saveThreads(threads, for: viewerUserId)
      NotificationCenter.default.post(name: .friendsThreadDidUpdate, object: nil)
    } catch {
      realtimeLogger.error("Failed to refresh thread list: \(error.localizedDescription)")
    }
  }

  private func refreshThreadDetail(threadId: String, viewerUserId: String) async {
    await refreshThreadSummary(threadId: threadId, viewerUserId: viewerUserId)

    do {
      let messages = try await service.listThreadMessages(
        threadId: threadId, limit: Pagination.pageSize, before: nil)
      await repository.saveMessages(messages, in: threadId, for: viewerUserId)
      notifyThreadUpdated(threadId: threadId)
    } catch {
      realtimeLogger.error(
        "Failed to refresh thread detail for \(threadId, privacy: .private): \(error.localizedDescription)"
      )
    }
  }

  private func refreshThreadSummary(threadId: String, viewerUserId: String) async {
    do {
      let thread = try await service.fetchThreadSummary(threadId: threadId)
      await repository.saveThread(thread, for: viewerUserId)
      notifyThreadUpdated(threadId: threadId)
    } catch {
      realtimeLogger.error(
        "Failed to refresh thread summary for \(threadId, privacy: .private): \(error.localizedDescription)"
      )
    }
  }

  private func refreshMessage(messageId: String, viewerUserId: String) async {
    do {
      let message = try await service.fetchMessagePayload(messageId: messageId)
      if message.deletedAt != nil {
        await repository.deleteMessage(id: messageId, viewerUserId: viewerUserId)
        await refreshThreadSummary(threadId: message.threadId, viewerUserId: viewerUserId)
        notifyThreadUpdated(threadId: message.threadId)
        return
      }
      await repository.saveMessages([message], in: message.threadId, for: viewerUserId)
      await refreshThreadSummary(threadId: message.threadId, viewerUserId: viewerUserId)
      notifyThreadUpdated(threadId: message.threadId)
    } catch {
      realtimeLogger.error(
        "Failed to refresh message \(messageId, privacy: .private): \(error.localizedDescription)")
    }
  }

  private func handleThreadListThreadAction(_ action: AnyAction, viewerUserId: String) async {
    guard let threadId = Self.extractThreadId(from: action) else { return }
    await refreshThreadSummary(threadId: threadId, viewerUserId: viewerUserId)
  }

  private func handleThreadListMessageAction(_ action: AnyAction, viewerUserId: String) async {
    if case .delete = action,
      let messageId = Self.extractMessageId(from: action),
      let threadId = Self.extractThreadId(from: action)
    {
      await repository.deleteMessage(id: messageId, viewerUserId: viewerUserId)
      await refreshThreadSummary(threadId: threadId, viewerUserId: viewerUserId)
      return
    }

    if let messageId = Self.extractMessageId(from: action) {
      await refreshMessage(messageId: messageId, viewerUserId: viewerUserId)
      return
    }

    guard let threadId = Self.extractThreadId(from: action) else { return }
    await refreshThreadSummary(threadId: threadId, viewerUserId: viewerUserId)
  }

  private func handleThreadListStateAction(_ action: AnyAction, viewerUserId: String) async {
    if let state = Self.decodeThreadUserState(from: action) {
      await repository.saveThreadState(state)
      await refreshThreadSummary(threadId: state.threadId, viewerUserId: viewerUserId)
    }
  }

  private func handleThreadDetailThreadAction(
    _ action: AnyAction,
    threadId: String,
    viewerUserId: String
  ) async {
    guard let changedThreadId = Self.extractThreadId(from: action), changedThreadId == threadId
    else { return }
    await refreshThreadSummary(threadId: threadId, viewerUserId: viewerUserId)
  }

  private func handleThreadDetailMessageAction(
    _ action: AnyAction,
    threadId: String,
    viewerUserId: String
  ) async {
    guard Self.extractThreadId(from: action) == threadId else { return }

    if case .delete = action, let messageId = Self.extractMessageId(from: action) {
      await repository.deleteMessage(id: messageId, viewerUserId: viewerUserId)
      await refreshThreadSummary(threadId: threadId, viewerUserId: viewerUserId)
      notifyThreadUpdated(threadId: threadId)
      return
    }

    if let messageId = Self.extractMessageId(from: action) {
      await refreshMessage(messageId: messageId, viewerUserId: viewerUserId)
    } else {
      await refreshThreadDetail(threadId: threadId, viewerUserId: viewerUserId)
    }
  }

  private func handleThreadDetailStateAction(
    _ action: AnyAction,
    threadId: String,
    viewerUserId: String
  ) async {
    guard let state = Self.decodeThreadUserState(from: action), state.threadId == threadId else {
      return
    }
    await repository.saveThreadState(state)
    await refreshThreadSummary(threadId: threadId, viewerUserId: viewerUserId)
    notifyThreadUpdated(threadId: threadId)
  }

  private func handleThreadDetailReactionAction(
    _ action: AnyAction,
    threadId: String,
    viewerUserId: String
  ) async {
    guard Self.extractThreadId(from: action) == threadId else { return }

    if let messageId = Self.extractMessageId(from: action) {
      await refreshMessage(messageId: messageId, viewerUserId: viewerUserId)
    } else {
      await refreshThreadDetail(threadId: threadId, viewerUserId: viewerUserId)
    }
  }

  private func notifyThreadUpdated(threadId: String) {
    NotificationCenter.default.post(
      name: .friendsThreadDidUpdate,
      object: nil,
      userInfo: ["threadId": threadId]
    )
  }

  private func notifyThreadTypingChanged(threadId: String, userId: String, isTyping: Bool) {
    NotificationCenter.default.post(
      name: .friendsThreadTypingDidChange,
      object: nil,
      userInfo: [
        "threadId": threadId,
        "userId": userId,
        "isTyping": isTyping,
      ]
    )
  }

  private func broadcastTypingEvent(event: String, threadId: String, userId: String) async -> Bool {
    guard let channel = threadChannels[threadId] else { return false }

    let payload = ThreadTypingPayload(
      threadId: threadId,
      userId: userId,
      sentAtMs: Int64(Date().timeIntervalSince1970 * 1000)
    )

    do {
      try await channel.broadcast(event: event, message: payload)
      return true
    } catch {
      realtimeLogger.error(
        "Failed to broadcast typing event \(event, privacy: .public): \(error.localizedDescription)"
      )
      return false
    }
  }

  private func makeStatusTask(
    for channel: RealtimeChannelV2,
    viewerUserId: String,
    skipInitialSubscribedRefresh: Bool
  ) -> Task<Void, Never> {
    Task { [weak self] in
      guard let self else { return }
      var hasSkippedInitialSubscribedRefresh = false
      for await status in channel.statusChange where status == .subscribed {
        if skipInitialSubscribedRefresh, !hasSkippedInitialSubscribedRefresh {
          hasSkippedInitialSubscribedRefresh = true
          continue
        }
        await self.refreshThreadList(viewerUserId: viewerUserId)
      }
    }
  }

  private func makeThreadStatusTask(
    for channel: RealtimeChannelV2,
    threadId: String,
    viewerUserId: String,
    skipInitialSubscribedRefresh: Bool
  ) -> Task<Void, Never> {
    Task { [weak self] in
      guard let self else { return }
      var hasSkippedInitialSubscribedRefresh = false
      for await status in channel.statusChange where status == .subscribed {
        if skipInitialSubscribedRefresh, !hasSkippedInitialSubscribedRefresh {
          hasSkippedInitialSubscribedRefresh = true
          continue
        }
        await self.refreshThreadDetail(threadId: threadId, viewerUserId: viewerUserId)
      }
    }
  }

  private func makeTypingBroadcastTask(
    for channel: RealtimeChannelV2,
    threadId: String,
    event: String,
    isTyping: Bool
  ) -> Task<Void, Never> {
    Task { [weak self] in
      guard let self else { return }
      for await payload in channel.broadcastStream(event: event) {
        self.handleTypingBroadcast(
          payload,
          threadId: threadId,
          isTyping: isTyping
        )
      }
    }
  }

  private func makeListTypingBroadcastTasks(
    for channel: RealtimeChannelV2,
    threadId: String
  ) -> [Task<Void, Never>] {
    [
      makeTypingBroadcastTask(
        for: channel,
        threadId: threadId,
        event: TypingEvent.start,
        isTyping: true
      ),
      makeTypingBroadcastTask(
        for: channel,
        threadId: threadId,
        event: TypingEvent.stop,
        isTyping: false
      ),
    ]
  }

  private func handleTypingBroadcast(_ payload: JSONObject, threadId: String, isTyping: Bool) {
    do {
      let typingPayload = try (payload["payload"]?.objectValue ?? payload).decode(
        as: ThreadTypingPayload.self)
      guard typingPayload.threadId == threadId else { return }
      notifyThreadTypingChanged(
        threadId: typingPayload.threadId,
        userId: typingPayload.userId,
        isTyping: isTyping
      )
    } catch {
      realtimeLogger.error(
        "Failed to decode typing payload: \(error.localizedDescription)"
      )
    }
  }

  private func ensureListTypingChannel(threadId: String) async -> Bool {
    guard threadChannels[threadId] == nil else { return true }
    if listTypingChannels[threadId] != nil { return true }

    let channel = supabase.channel("friends-thread-detail:\(threadId)") { config in
      config.broadcast.receiveOwnBroadcasts = true
    }

    do {
      try await channel.subscribeWithError()
      listTypingChannels[threadId] = channel
      listTypingTasks[threadId] = makeListTypingBroadcastTasks(for: channel, threadId: threadId)
      return true
    } catch {
      realtimeLogger.error(
        "Failed to subscribe list typing realtime for \(threadId, privacy: .private): \(error.localizedDescription)"
      )
      await supabase.removeChannel(channel)
      return false
    }
  }

  private func teardownListTypingChannel(threadId: String) async {
    listTypingTasks[threadId]?.forEach { $0.cancel() }
    listTypingTasks[threadId] = nil

    if let channel = listTypingChannels[threadId] {
      await supabase.removeChannel(channel)
      listTypingChannels[threadId] = nil
    }
  }

  static func extractThreadId(from action: AnyAction) -> String? {
    switch action {
    case .insert(let insert):
      return insert.record["thread_id"]?.stringValue ?? insert.record["id"]?.stringValue
    case .update(let update):
      return update.record["thread_id"]?.stringValue ?? update.record["id"]?.stringValue
    case .delete(let delete):
      return delete.oldRecord["thread_id"]?.stringValue ?? delete.oldRecord["id"]?.stringValue
    }
  }

  static func extractMessageId(from action: AnyAction) -> String? {
    switch action {
    case .insert(let insert):
      return insert.record["id"]?.stringValue ?? insert.record["message_id"]?.stringValue
    case .update(let update):
      return update.record["id"]?.stringValue ?? update.record["message_id"]?.stringValue
    case .delete(let delete):
      return delete.oldRecord["id"]?.stringValue ?? delete.oldRecord["message_id"]?.stringValue
    }
  }

  static func decodeThreadUserState(from action: AnyAction) -> FriendThreadState? {
    let payload: JSONObject?
    switch action {
    case .insert(let insert):
      payload = insert.record
    case .update(let update):
      payload = update.record
    case .delete:
      payload = nil
    }

    guard let payload else { return nil }

    do {
      let row = try payload.decode(as: MessagingThreadUserStateRow.self)
      return row.toFriendThreadState()
    } catch {
      realtimeLogger.error(
        "Failed to decode thread user state from realtime payload: \(error.localizedDescription)")
      return nil
    }
  }
}

extension FriendsMessagingRealtimeCoordinator: FriendsMessagingRealtimeCoordinating {}
