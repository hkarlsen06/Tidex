import Combine
import Foundation
import Supabase
import os.log

private let realtimeLogger = Logger(
  subsystem: "com.tidex.app", category: "FriendsMessagingRealtime")

extension Notification.Name {
  static let friendsThreadDidUpdate = Notification.Name("friendsThreadDidUpdate")
  static let friendFeedPlacementDidChange = Notification.Name("friendFeedPlacementDidChange")
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

  private enum SyncReplayError: Error {
    case stalledPagination
  }

  private enum SubscriptionError: LocalizedError {
    case timedOut

    var errorDescription: String? {
      switch self {
      case .timedOut:
        return "Realtime subscription timed out"
      }
    }
  }

  private enum Subscription {
    static let timeoutNanoseconds: UInt64 = 15_000_000_000
  }

  private enum TypingEvent {
    static let start = "typing_start"
    static let stop = "typing_stop"
  }

  private enum TypingTopic {
    static func name(threadId: String) -> String {
      "friends-thread-typing:\(threadId)"
    }
  }

  static let shared = FriendsMessagingRealtimeCoordinator()

  private let service: any FriendsMessagingServiceProviding
  private let repository: any FriendsMessagesRepositoryProviding

  private var threadListChannel: RealtimeChannelV2?
  private var threadListTasks: [Task<Void, Never>] = []
  private var listTypingThreadIds: Set<String> = []
  private var detailTypingThreadIds: Set<String> = []
  private var typingChannels: [String: RealtimeChannelV2] = [:]
  private var typingTasks: [String: [Task<Void, Never>]] = [:]
  private var typingSubscriptionTasks: [String: Task<Bool, Never>] = [:]
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
      table: "thread_user_state"
    )

    do {
      try await subscribeWithTimeout(channel)
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
    let previousThreadIds = listTypingThreadIds
    let desiredThreadIds = Set(threadIds)
    listTypingThreadIds = desiredThreadIds

    for threadId in previousThreadIds.union(desiredThreadIds) {
      await syncTypingChannel(threadId: threadId)
    }
  }

  func stopThreadListTypingSubscriptions() async {
    let trackedThreadIds = listTypingThreadIds
    listTypingThreadIds.removeAll()

    for threadId in trackedThreadIds {
      await syncTypingChannel(threadId: threadId)
    }
  }

  func startThreadSubscription(threadId: String, viewerUserId: String) async {
    detailTypingThreadIds.insert(threadId)
    _ = await ensureTypingChannel(threadId: threadId)

    if let existingChannel = threadChannels[threadId], existingChannel.status == .subscribed {
      return
    }

    await teardownThreadDetailChannel(threadId: threadId)

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
      try await subscribeWithTimeout(channel)
      threadChannels[threadId] = channel

      threadTasks[threadId] = [
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
      detailTypingThreadIds.remove(threadId)
      await syncTypingChannel(threadId: threadId)
    }
  }

  func stopThreadSubscription(threadId: String) async {
    detailTypingThreadIds.remove(threadId)
    await syncTypingChannel(threadId: threadId)
    await teardownThreadDetailChannel(threadId: threadId)
  }

  func stopAll() async {
    await stopThreadListSubscription()
    await stopThreadListTypingSubscriptions()
    for threadId in Array(threadChannels.keys) {
      await stopThreadSubscription(threadId: threadId)
    }
  }

  func sendTypingStart(threadId: String, userId: String) async -> Bool {
    await broadcastTypingEvent(event: TypingEvent.start, threadId: threadId, userId: userId)
  }

  func sendTypingStop(threadId: String, userId: String) async -> Bool {
    await broadcastTypingEvent(event: TypingEvent.stop, threadId: threadId, userId: userId)
  }

  private func refreshThreadList(
    viewerUserId: String,
    allowIncrementalSync: Bool = true
  ) async {
    if allowIncrementalSync {
      do {
        if let syncState = await repository.getMessagingSyncState(
          viewerUserId: viewerUserId,
          scope: .inbox
        ),
          try await replayInboxEvents(viewerUserId: viewerUserId, startingAt: syncState)
        {
          NotificationCenter.default.post(name: .friendsThreadDidUpdate, object: nil)
          return
        }
      } catch {
        realtimeLogger.error("Failed to replay inbox sync events: \(error.localizedDescription)")
      }
    }

    do {
      let snapshot = try await service.fetchInboxSyncSnapshotV2(limit: 100, before: nil)
      await repository.saveThreads(snapshot.threads, for: viewerUserId)
      await saveMessagingSyncState(
        viewerUserId: viewerUserId,
        scope: .inbox,
        version: snapshot.snapshotVersion,
        retainedFromVersion: snapshot.retainedFromVersion
      )
      NotificationCenter.default.post(name: .friendsThreadDidUpdate, object: nil)
    } catch {
      realtimeLogger.error("Failed to refresh thread list: \(error.localizedDescription)")
    }
  }

  private func refreshThreadDetail(
    threadId: String,
    viewerUserId: String,
    allowIncrementalSync: Bool = true
  ) async {
    await refreshThreadSnapshot(
      threadId: threadId,
      viewerUserId: viewerUserId,
      shouldNotify: false,
      allowIncrementalSync: allowIncrementalSync
    )
    await refreshThreadStates(threadId: threadId, shouldNotify: false)
    notifyThreadUpdated(threadId: threadId)
  }

  private func refreshThreadSummary(
    threadId: String,
    viewerUserId: String,
    shouldNotify: Bool = true
  ) async {
    do {
      let thread = try await service.fetchThreadSummary(threadId: threadId)
      await repository.saveThread(thread, for: viewerUserId)
      if shouldNotify {
        notifyThreadUpdated(threadId: threadId)
      }
    } catch {
      realtimeLogger.error(
        "Failed to refresh thread summary for \(threadId, privacy: .private): \(error.localizedDescription)"
      )
    }
  }

  private func refreshThreadSnapshot(
    threadId: String,
    viewerUserId: String,
    shouldNotify: Bool = true,
    allowIncrementalSync: Bool = true
  ) async {
    if allowIncrementalSync {
      do {
        if let syncState = await repository.getMessagingSyncState(
          viewerUserId: viewerUserId,
          scope: .thread(threadId: threadId)
        ),
          try await replayThreadEvents(
            threadId: threadId,
            viewerUserId: viewerUserId,
            startingAt: syncState
          )
        {
          if shouldNotify {
            notifyThreadUpdated(threadId: threadId)
          }
          return
        }
      } catch {
        realtimeLogger.error(
          "Failed to replay thread sync events for \(threadId, privacy: .private): \(error.localizedDescription)"
        )
      }
    }

    do {
      let snapshot = try await service.fetchThreadSyncSnapshotV2(
        threadId: threadId,
        messageLimit: Pagination.pageSize
      )
      await repository.saveThread(snapshot.thread, for: viewerUserId)
      await repository.saveMessages(
        snapshot.messages,
        in: threadId,
        for: viewerUserId
      )
      await repository.saveThreadState(snapshot.viewerState)
      await saveMessagingSyncState(
        viewerUserId: viewerUserId,
        scope: .thread(threadId: threadId),
        version: snapshot.snapshotVersion,
        retainedFromVersion: snapshot.retainedFromVersion
      )
      if shouldNotify {
        notifyThreadUpdated(threadId: threadId)
      }
    } catch {
      realtimeLogger.error(
        "Failed to refresh thread snapshot for \(threadId, privacy: .private): \(error.localizedDescription)"
      )
    }
  }

  private func refreshThreadStates(threadId: String, shouldNotify: Bool = true) async {
    do {
      let states = try await service.listThreadStates(threadId: threadId)
      for state in states {
        await repository.saveThreadState(state)
      }
      if shouldNotify {
        notifyThreadUpdated(threadId: threadId)
      }
    } catch {
      realtimeLogger.error(
        "Failed to refresh thread states for \(threadId, privacy: .private): \(error.localizedDescription)"
      )
    }
  }

  private func refreshMessage(messageId: String, viewerUserId: String) async {
    do {
      let message = try await service.fetchMessageSyncPayloadV2(messageId: messageId)
      if message.deletedAt != nil {
        await repository.deleteMessage(id: messageId, viewerUserId: viewerUserId)
        await refreshThreadSummary(
          threadId: message.threadId,
          viewerUserId: viewerUserId,
          shouldNotify: false
        )
        notifyThreadUpdated(threadId: message.threadId)
        return
      }
      await repository.saveMessages([message], in: message.threadId, for: viewerUserId)
      notifyThreadUpdated(threadId: message.threadId)
    } catch {
      realtimeLogger.error(
        "Failed to refresh message \(messageId, privacy: .private): \(error.localizedDescription)")
    }
  }

  private func handleThreadListThreadAction(_ action: AnyAction, viewerUserId: String) async {
    guard Self.extractThreadId(from: action) != nil else { return }
    await refreshThreadList(viewerUserId: viewerUserId)
  }

  private func handleThreadListMessageAction(_ action: AnyAction, viewerUserId: String) async {
    guard Self.extractThreadId(from: action) != nil || Self.extractMessageId(from: action) != nil
    else {
      return
    }
    await refreshThreadList(viewerUserId: viewerUserId)
  }

  private func handleThreadListStateAction(_ action: AnyAction, viewerUserId: String) async {
    if let state = Self.decodeThreadUserState(from: action) {
      await repository.saveThreadState(state)
      if Self.shouldRefreshThreadList(
        forThreadStateUserId: state.userId, viewerUserId: viewerUserId)
      {
        await refreshThreadList(viewerUserId: viewerUserId)
      } else {
        notifyThreadUpdated(threadId: state.threadId)
      }
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
      await refreshThreadDetail(threadId: threadId, viewerUserId: viewerUserId)
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
    await refreshThreadList(viewerUserId: viewerUserId)
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
    guard await ensureTypingChannel(threadId: threadId),
      let channel = typingChannels[threadId],
      channel.status == .subscribed
    else {
      return false
    }

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
      for await status in channel.statusChange {
        guard !Task.isCancelled else { return }
        guard status == .subscribed else { continue }
        if skipInitialSubscribedRefresh, !hasSkippedInitialSubscribedRefresh {
          hasSkippedInitialSubscribedRefresh = true
          continue
        }
        await self.refreshThreadList(
          viewerUserId: viewerUserId,
          allowIncrementalSync: false
        )
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
      for await status in channel.statusChange {
        guard !Task.isCancelled else { return }
        guard status == .subscribed else { continue }
        if skipInitialSubscribedRefresh, !hasSkippedInitialSubscribedRefresh {
          hasSkippedInitialSubscribedRefresh = true
          continue
        }
        await self.refreshThreadDetail(
          threadId: threadId,
          viewerUserId: viewerUserId,
          allowIncrementalSync: false
        )
      }
    }
  }

  private func makeTypingBroadcastTask(
    stream: AsyncStream<JSONObject>,
    threadId: String,
    event: String,
    isTyping: Bool
  ) -> Task<Void, Never> {
    Task { [weak self] in
      guard let self else { return }
      for await payload in stream {
        self.handleTypingBroadcast(
          payload,
          threadId: threadId,
          isTyping: isTyping
        )
      }
    }
  }

  private func makeTypingChannelTasks(
    for channel: RealtimeChannelV2,
    threadId: String
  ) -> [Task<Void, Never>] {
    let typingStartBroadcast = channel.broadcastStream(event: TypingEvent.start)
    let typingStopBroadcast = channel.broadcastStream(event: TypingEvent.stop)
    return [
      makeTypingBroadcastTask(
        stream: typingStartBroadcast,
        threadId: threadId,
        event: TypingEvent.start,
        isTyping: true
      ),
      makeTypingBroadcastTask(
        stream: typingStopBroadcast,
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

  private func ensureTypingChannel(threadId: String) async -> Bool {
    if let channel = typingChannels[threadId], channel.status == .subscribed {
      return true
    }

    if let task = typingSubscriptionTasks[threadId] {
      return await task.value
    }

    let task = Task { @MainActor [weak self] in
      guard let self else { return false }
      defer { self.typingSubscriptionTasks[threadId] = nil }

      if let channel = self.typingChannels[threadId], channel.status == .subscribed {
        return true
      }

      let channel = supabase.channel(TypingTopic.name(threadId: threadId)) { config in
        config.broadcast.receiveOwnBroadcasts = true
      }
      let typingTasks = self.makeTypingChannelTasks(for: channel, threadId: threadId)

      do {
        try await self.subscribeWithTimeout(channel)
        self.typingChannels[threadId] = channel
        self.typingTasks[threadId] = typingTasks
        return true
      } catch is CancellationError {
        typingTasks.forEach { $0.cancel() }
        await supabase.removeChannel(channel)
        return false
      } catch {
        typingTasks.forEach { $0.cancel() }
        realtimeLogger.error(
          "Failed to subscribe typing realtime for \(threadId, privacy: .private): \(error.localizedDescription)"
        )
        await supabase.removeChannel(channel)
        return false
      }
    }

    typingSubscriptionTasks[threadId] = task
    return await task.value
  }

  private func teardownTypingChannel(threadId: String) async {
    typingSubscriptionTasks[threadId]?.cancel()
    typingSubscriptionTasks[threadId] = nil
    typingTasks[threadId]?.forEach { $0.cancel() }
    typingTasks[threadId] = nil

    if let channel = typingChannels[threadId] {
      await supabase.removeChannel(channel)
      typingChannels[threadId] = nil
    }
  }

  private func teardownThreadDetailChannel(threadId: String) async {
    threadTasks[threadId]?.forEach { $0.cancel() }
    threadTasks[threadId] = nil

    if let channel = threadChannels[threadId] {
      await supabase.removeChannel(channel)
      threadChannels[threadId] = nil
    }
  }

  private func syncTypingChannel(threadId: String) async {
    let shouldTrackTyping =
      listTypingThreadIds.contains(threadId) || detailTypingThreadIds.contains(threadId)

    if shouldTrackTyping {
      _ = await ensureTypingChannel(threadId: threadId)
    } else {
      await teardownTypingChannel(threadId: threadId)
    }
  }

  private func subscribeWithTimeout(_ channel: RealtimeChannelV2) async throws {
    let operationTask = Task {
      try await channel.subscribeWithError()
    }
    defer { operationTask.cancel() }

    try await withTaskCancellationHandler {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          try await operationTask.value
        }
        group.addTask {
          try await Task.sleep(nanoseconds: Subscription.timeoutNanoseconds)
          operationTask.cancel()
          throw SubscriptionError.timedOut
        }

        do {
          _ = try await group.next()
          group.cancelAll()
        } catch {
          group.cancelAll()
          throw error
        }
      }
    } onCancel: {
      operationTask.cancel()
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

  static func shouldRefreshThreadList(
    forThreadStateUserId stateUserId: String,
    viewerUserId: String
  ) -> Bool {
    stateUserId == viewerUserId
  }

  private func replayInboxEvents(
    viewerUserId: String,
    startingAt syncState: FriendMessagingSyncState
  ) async throws -> Bool {
    var currentVersion = syncState.version

    while true {
      let page = try await service.listInboxEventsV2(
        afterVersion: currentVersion,
        limit: 100
      )

      if page.requiresSnapshot {
        return false
      }

      if page.hasMore, page.events.isEmpty {
        throw SyncReplayError.stalledPagination
      }

      for event in page.events {
        await applyInboxEvent(event, viewerUserId: viewerUserId)
        currentVersion = event.version
      }

      await saveMessagingSyncState(
        viewerUserId: viewerUserId,
        scope: .inbox,
        version: currentVersion,
        retainedFromVersion: page.retainedFromVersion
      )

      if !page.hasMore {
        return true
      }
    }
  }

  private func replayThreadEvents(
    threadId: String,
    viewerUserId: String,
    startingAt syncState: FriendMessagingSyncState
  ) async throws -> Bool {
    var currentVersion = syncState.version

    while true {
      let page = try await service.listThreadEventsV2(
        threadId: threadId,
        afterVersion: currentVersion,
        limit: 100
      )

      if page.requiresSnapshot {
        return false
      }

      if page.hasMore, page.events.isEmpty {
        throw SyncReplayError.stalledPagination
      }

      for event in page.events {
        await applyThreadEvent(event, viewerUserId: viewerUserId)
        currentVersion = event.version
      }

      await saveMessagingSyncState(
        viewerUserId: viewerUserId,
        scope: .thread(threadId: threadId),
        version: currentVersion,
        retainedFromVersion: page.retainedFromVersion
      )

      if !page.hasMore {
        return true
      }
    }
  }

  private func applyInboxEvent(_ event: FriendInboxSyncEvent, viewerUserId: String) async {
    switch event.eventType {
    case .threadUpserted:
      guard let thread = event.thread else { return }
      await repository.saveThread(thread, for: viewerUserId)
    case .threadRemoved:
      guard let threadId = event.threadId else { return }
      await repository.deleteThread(id: threadId, viewerUserId: viewerUserId)
    }
  }

  private func applyThreadEvent(_ event: FriendThreadSyncEvent, viewerUserId: String) async {
    switch event.eventType {
    case .messageUpserted:
      guard let message = event.message else { return }
      await repository.saveMessages([message], in: message.threadId, for: viewerUserId)
    case .messageDeleted:
      guard let deletedMessageId = event.deletedMessageId else { return }
      await repository.deleteMessage(id: deletedMessageId, viewerUserId: viewerUserId)
    }
  }

  private func saveMessagingSyncState(
    viewerUserId: String,
    scope: FriendMessagingSyncScope,
    version: Int64,
    retainedFromVersion: Int64
  ) async {
    await repository.saveMessagingSyncState(
      FriendMessagingSyncState(
        viewerUserId: viewerUserId,
        scope: scope,
        version: version,
        retainedFromVersion: retainedFromVersion,
        updatedAt: Date()
      )
    )
  }
}

extension FriendsMessagingRealtimeCoordinator: FriendsMessagingRealtimeCoordinating {}
