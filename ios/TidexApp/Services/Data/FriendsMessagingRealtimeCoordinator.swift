import Combine
import Foundation
import os.log
import Supabase

private let realtimeLogger = Logger(
  subsystem: "com.tidex.app", category: "FriendsMessagingRealtime")

extension Notification.Name {
  static let friendsThreadDidUpdate = Notification.Name("friendsThreadDidUpdate")
  static let friendFeedPlacementDidChange = Notification.Name("friendFeedPlacementDidChange")
  static let friendsThreadTypingDidChange = Notification.Name("friendsThreadTypingDidChange")
}

@MainActor
protocol FriendsMessagingRealtimeCoordinating: AnyObject {
  func startForAuthenticatedUser(viewerUserId: String) async
  func stopForAuthenticatedUser() async
  func handleAppDidBecomeActive() async
  func setFriendsFeedVisible(_ isVisible: Bool)
  func setVisibleThreadIds(_ threadIds: [String])
  func setActiveThread(threadId: String, viewerUserId: String) async
  func clearActiveThread(threadId: String) async
  func startThreadListSubscription(viewerUserId: String) async
  func stopThreadListSubscription() async
  func startThreadSubscription(threadId: String, viewerUserId: String) async
  func stopThreadSubscription(threadId: String) async
  func sendTypingStart(threadId: String, userId: String) async -> Bool
  func sendTypingStop(threadId: String, userId: String) async -> Bool
}

@MainActor
// swiftlint:disable:next type_body_length
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

  private enum TypingRepair {
    static let retryDelay: Duration = .seconds(3)
  }

  private enum TypingToast {
    static let cooldown: TimeInterval = 12
  }

  private enum TypingEvent {
    static let start = "typing_start"
    static let stop = "typing_stop"
  }

  private enum TypingTopic {
    static func name(threadId: String) -> String {
      "friends-thread-typing:\(threadId)"
    }

    static func realtimeName(threadId: String) -> String {
      "realtime:\(name(threadId: threadId))"
    }
  }

  enum TypingChannelHealth {
    static let listenerTaskCount = 2

    static func isHealthy(
      threadId: String,
      topic: String?,
      status: RealtimeChannelStatus?,
      listenerTaskCount: Int,
      hasSubscriptionTask: Bool
    ) -> Bool {
      topic == TypingTopic.realtimeName(threadId: threadId)
        && status == .subscribed
        && listenerTaskCount >= Self.listenerTaskCount
        && !hasSubscriptionTask
    }
  }

  static let shared = FriendsMessagingRealtimeCoordinator()

  private let service: any FriendsMessagingServiceProviding
  private let repository: any FriendsMessagesRepositoryProviding

  private var authenticatedViewerUserId: String?
  private var activeThreadId: String?
  private var activeThreadViewerUserId: String?
  private var threadListChannel: RealtimeChannelV2?
  private var threadListTasks: [Task<Void, Never>] = []
  private var threadListRetryTask: Task<Void, Never>?
  private var outboundListTypingChannel: RealtimeChannelV2?
  private var outboundListTypingRecipientUserId: String?
  private var typingToastLastShownAtByThreadId: [String: Date] = [:]
  private var isFriendsFeedVisible = false
  private var listTypingThreadIds: Set<String> = []
  private var detailTypingThreadIds: Set<String> = []
  private var typingChannels: [String: RealtimeChannelV2] = [:]
  private var typingTasks: [String: [Task<Void, Never>]] = [:]
  private var typingSubscriptionTasks: [String: Task<Bool, Never>] = [:]
  private var typingRepairTasks: [String: Task<Void, Never>] = [:]
  private var typingRetryTasks: [String: Task<Void, Never>] = [:]
  private var threadChannels: [String: RealtimeChannelV2] = [:]
  private var threadTasks: [String: [Task<Void, Never>]] = [:]

  struct ThreadTypingPayload: Codable, Equatable {
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

  func startForAuthenticatedUser(viewerUserId: String) async {
    guard let normalizedViewerUserId = Self.normalizedUserId(viewerUserId) else {
      await stopForAuthenticatedUser()
      return
    }

    if authenticatedViewerUserId != normalizedViewerUserId {
      await stopForAuthenticatedUser()
      authenticatedViewerUserId = normalizedViewerUserId
    }

    if threadListChannel?.status == .subscribed {
      return
    }

    await startThreadListSubscription(viewerUserId: normalizedViewerUserId)
  }

  func stopForAuthenticatedUser() async {
    threadListRetryTask?.cancel()
    threadListRetryTask = nil
    authenticatedViewerUserId = nil
    activeThreadId = nil
    activeThreadViewerUserId = nil
    listTypingThreadIds.removeAll()
    detailTypingThreadIds.removeAll()
    typingToastLastShownAtByThreadId.removeAll()
    isFriendsFeedVisible = false

    await stopThreadListSubscription()
    await teardownOutboundListTypingChannel()

    for threadId in Array(threadChannels.keys) {
      await teardownThreadDetailChannel(threadId: threadId)
    }

    for threadId in Array(typingChannels.keys) {
      await teardownTypingChannel(threadId: threadId)
    }
  }

  func handleAppDidBecomeActive() async {
    guard let authenticatedViewerUserId else { return }
    await startForAuthenticatedUser(viewerUserId: authenticatedViewerUserId)

    guard
      let activeThreadId,
      let activeThreadViewerUserId
    else {
      return
    }
    await setActiveThread(threadId: activeThreadId, viewerUserId: activeThreadViewerUserId)
  }

  func setVisibleThreadIds(_ threadIds: [String]) {
    listTypingThreadIds = Set(threadIds.compactMap(Self.normalizedUserId))
  }

  func setFriendsFeedVisible(_ isVisible: Bool) {
    isFriendsFeedVisible = isVisible
  }

  func setActiveThread(threadId: String, viewerUserId: String) async {
    guard
      let normalizedThreadId = Self.normalizedUserId(threadId),
      let normalizedViewerUserId = Self.normalizedUserId(viewerUserId)
    else {
      return
    }

    if authenticatedViewerUserId != normalizedViewerUserId {
      await startForAuthenticatedUser(viewerUserId: normalizedViewerUserId)
    }

    if let activeThreadId, activeThreadId != normalizedThreadId {
      detailTypingThreadIds.remove(activeThreadId)
      await teardownThreadDetailChannel(threadId: activeThreadId)
      await teardownTypingChannel(threadId: activeThreadId)
    }

    activeThreadId = normalizedThreadId
    activeThreadViewerUserId = normalizedViewerUserId
    detailTypingThreadIds = [normalizedThreadId]

    _ = await ensureTypingChannel(threadId: normalizedThreadId)
    if let counterpartUserId = counterpartUserId(
      threadId: normalizedThreadId,
      viewerUserId: normalizedViewerUserId
    ) {
      await ensureOutboundListTypingChannel(recipientUserId: counterpartUserId)
    }

    if let existingChannel = threadChannels[normalizedThreadId],
      existingChannel.status == .subscribed
    {
      return
    }

    await startThreadDetailSubscription(
      threadId: normalizedThreadId,
      viewerUserId: normalizedViewerUserId
    )
  }

  func clearActiveThread(threadId: String) async {
    guard let normalizedThreadId = Self.normalizedUserId(threadId) else { return }
    guard activeThreadId == normalizedThreadId else { return }

    activeThreadId = nil
    activeThreadViewerUserId = nil
    detailTypingThreadIds.remove(normalizedThreadId)
    await teardownThreadDetailChannel(threadId: normalizedThreadId)
    await teardownTypingChannel(threadId: normalizedThreadId)
    await teardownOutboundListTypingChannel()
  }

  func startThreadListSubscription(viewerUserId: String) async {
    await stopThreadListSubscription()

    let channel = supabase.channel("friends-thread-list:\(viewerUserId)") { config in
      config.broadcast.receiveOwnBroadcasts = true
    }
    let threadChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "threads")
    let messageChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "messages")
    let stateChanges = channel.postgresChange(
      AnyAction.self,
      schema: "public",
      table: "thread_user_state"
    )

    do {
      try await subscribeWithTimeout(channel)
      // A nil viewer means sign-out happened during the subscribe; drop the channel.
      guard authenticatedViewerUserId == viewerUserId else {
        await supabase.removeChannel(channel)
        return
      }
      threadListChannel = channel
      threadListRetryTask?.cancel()
      threadListRetryTask = nil

      threadListTasks =
        [
          makeStatusTask(
            for: channel,
            viewerUserId: viewerUserId,
            skipInitialSubscribedRefresh: true
          ),
          Task { [weak self] in
            guard let self else { return }
            for await action in threadChanges {
              await handleThreadListThreadAction(action, viewerUserId: viewerUserId)
            }
          },
          Task { [weak self] in
            guard let self else { return }
            for await action in messageChanges {
              await handleThreadListMessageAction(action, viewerUserId: viewerUserId)
            }
          },
          Task { [weak self] in
            guard let self else { return }
            for await action in stateChanges {
              await handleThreadListStateAction(action, viewerUserId: viewerUserId)
            }
          },
        ] + makeThreadListTypingChannelTasks(for: channel)

      await refreshThreadList(viewerUserId: viewerUserId)
    } catch {
      realtimeLogger.error(
        "Failed to subscribe thread list realtime: \(error.localizedDescription)")
      await supabase.removeChannel(channel)
      scheduleThreadListRetry(
        viewerUserId: viewerUserId,
        reason: error.localizedDescription
      )
    }
  }

  func stopThreadListSubscription() async {
    threadListRetryTask?.cancel()
    threadListRetryTask = nil
    threadListTasks.forEach { $0.cancel() }
    threadListTasks.removeAll()

    if let threadListChannel {
      await supabase.removeChannel(threadListChannel)
      self.threadListChannel = nil
    }
  }

  func syncThreadListTypingSubscriptions(threadIds: [String]) {
    setVisibleThreadIds(threadIds)
  }

  func stopThreadListTypingSubscriptions() {
    listTypingThreadIds.removeAll()
  }

  func startThreadSubscription(threadId: String, viewerUserId: String) async {
    await setActiveThread(threadId: threadId, viewerUserId: viewerUserId)
  }

  private func startThreadDetailSubscription(threadId: String, viewerUserId: String) async {
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
      guard authenticatedViewerUserId == viewerUserId else {
        await supabase.removeChannel(channel)
        return
      }
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
            await handleThreadDetailThreadAction(
              action, threadId: threadId, viewerUserId: viewerUserId)
          }
        },
        Task { [weak self] in
          guard let self else { return }
          for await action in messageChanges {
            await handleThreadDetailMessageAction(
              action, threadId: threadId, viewerUserId: viewerUserId)
          }
        },
        Task { [weak self] in
          guard let self else { return }
          for await action in reactionChanges {
            await handleThreadDetailReactionAction(
              action, threadId: threadId, viewerUserId: viewerUserId)
          }
        },
        Task { [weak self] in
          guard let self else { return }
          for await action in stateChanges {
            await handleThreadDetailStateAction(
              action, threadId: threadId, viewerUserId: viewerUserId)
          }
        },
      ]
    } catch {
      realtimeLogger.error(
        "Failed to subscribe thread detail realtime: \(error.localizedDescription)")
      await supabase.removeChannel(channel)
      if activeThreadId == threadId {
        scheduleTypingChannelRepair(threadId: threadId, reason: error.localizedDescription)
      }
    }
  }

  func stopThreadSubscription(threadId: String) async {
    await clearActiveThread(threadId: threadId)
  }

  func stopAll() async {
    await stopForAuthenticatedUser()
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
      // Don't write the previous user's inbox back after sign-out or a user switch.
      guard authenticatedViewerUserId == viewerUserId else { return }
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
    await refreshThreadDetail(threadId: threadId, viewerUserId: viewerUserId)
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

    if let messageId = Self.extractReactionMessageId(from: action) {
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
    let payload = ThreadTypingPayload(
      threadId: threadId,
      userId: userId,
      // swiftlint:disable:next no_magic_numbers
      sentAtMs: Int64(Date().timeIntervalSince1970 * 1_000)
    )

    let didSendThreadTyping: Bool
    if let channel = typingChannels[threadId],
      isTypingChannelHealthy(threadId: threadId, channel: channel)
    {
      didSendThreadTyping = await broadcastTypingPayload(
        payload,
        event: event,
        channel: channel
      )
    } else {
      scheduleTypingChannelRepair(threadId: threadId, reason: "pre-send health check failed")
      didSendThreadTyping = false
    }

    let didSendListTyping = await broadcastTypingPayloadToCounterpartList(
      payload,
      event: event,
      senderUserId: userId
    )

    return didSendThreadTyping || didSendListTyping
  }

  private func broadcastTypingPayload(
    _ payload: ThreadTypingPayload,
    event: String,
    channel: RealtimeChannelV2
  ) async -> Bool {
    do {
      try await channel.broadcast(event: event, message: payload)
      return true
    } catch {
      return false
    }
  }

  private func broadcastTypingPayloadToCounterpartList(
    _ payload: ThreadTypingPayload,
    event: String,
    senderUserId: String
  ) async -> Bool {
    guard
      let counterpartUserId = counterpartUserId(
        threadId: payload.threadId,
        viewerUserId: senderUserId
      )
    else {
      return false
    }

    guard
      outboundListTypingRecipientUserId == counterpartUserId,
      let channel = outboundListTypingChannel,
      channel.status == .subscribed
    else {
      Task { @MainActor [weak self] in
        await self?.ensureOutboundListTypingChannel(recipientUserId: counterpartUserId)
      }
      return false
    }

    do {
      try await channel.broadcast(event: event, message: payload)
      return true
    } catch {
      return false
    }
  }

  private func counterpartUserId(threadId: String, viewerUserId: String) -> String? {
    guard
      let normalizedViewerUserId = Self.normalizedUserId(viewerUserId),
      let thread = repository.getThread(id: threadId, viewerUserId: normalizedViewerUserId),
      thread.kind == .direct,
      let counterpartUserId = Self.normalizedUserId(thread.counterpartUserId),
      counterpartUserId != normalizedViewerUserId
    else {
      return nil
    }
    return counterpartUserId
  }

  private func listTopic(userId: String) -> String {
    "friends-thread-list:\(userId)"
  }

  private func ensureOutboundListTypingChannel(recipientUserId: String) async {
    guard let normalizedRecipientUserId = Self.normalizedUserId(recipientUserId) else { return }

    if outboundListTypingRecipientUserId == normalizedRecipientUserId,
      let outboundListTypingChannel,
      outboundListTypingChannel.status == .subscribed
    {
      return
    }

    await teardownOutboundListTypingChannel()

    let channel = supabase.channel(listTopic(userId: normalizedRecipientUserId)) { config in
      config.broadcast.receiveOwnBroadcasts = false
    }

    do {
      try await subscribeWithTimeout(channel)
      guard activeThreadId != nil else {
        await supabase.removeChannel(channel)
        return
      }
      outboundListTypingRecipientUserId = normalizedRecipientUserId
      outboundListTypingChannel = channel
    } catch {
      await supabase.removeChannel(channel)
    }
  }

  private func teardownOutboundListTypingChannel() async {
    outboundListTypingRecipientUserId = nil
    if let outboundListTypingChannel {
      await supabase.removeChannel(outboundListTypingChannel)
      self.outboundListTypingChannel = nil
    }
  }

  private static func normalizedUserId(_ userId: String?) -> String? {
    guard let userId else { return nil }
    let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalizedUserId.isEmpty ? nil : normalizedUserId
  }

  private static func nonEmptyTrimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedValue.isEmpty ? nil : trimmedValue
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
        if status == .unsubscribed {
          scheduleThreadListRetry(
            viewerUserId: viewerUserId,
            reason: "thread list status unsubscribed"
          )
          continue
        }
        guard status == .subscribed else { continue }
        if skipInitialSubscribedRefresh, !hasSkippedInitialSubscribedRefresh {
          hasSkippedInitialSubscribedRefresh = true
          continue
        }
        await refreshThreadList(
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
        await refreshThreadDetail(
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
    event _: String,
    isTyping: Bool
  ) -> Task<Void, Never> {
    Task { [weak self] in
      guard let self else { return }
      for await payload in stream {
        handleTypingBroadcast(
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

  private func makeThreadListTypingChannelTasks(
    for channel: RealtimeChannelV2
  ) -> [Task<Void, Never>] {
    let typingStartBroadcast = channel.broadcastStream(event: TypingEvent.start)
    let typingStopBroadcast = channel.broadcastStream(event: TypingEvent.stop)
    return [
      makeThreadListTypingBroadcastTask(
        stream: typingStartBroadcast,
        isTyping: true
      ),
      makeThreadListTypingBroadcastTask(
        stream: typingStopBroadcast,
        isTyping: false
      ),
    ]
  }

  private func makeThreadListTypingBroadcastTask(
    stream: AsyncStream<JSONObject>,
    isTyping: Bool
  ) -> Task<Void, Never> {
    Task { [weak self] in
      guard let self else { return }
      for await payload in stream {
        handleThreadListTypingBroadcast(payload, isTyping: isTyping)
      }
    }
  }

  private func handleThreadListTypingBroadcast(_ payload: JSONObject, isTyping: Bool) {
    do {
      let typingPayload = try Self.decodeTypingPayload(from: payload)
      if isTyping {
        notifyTypingToastIfNeeded(typingPayload)
      }
      guard listTypingThreadIds.contains(typingPayload.threadId) else { return }
      notifyThreadTypingChanged(
        threadId: typingPayload.threadId,
        userId: typingPayload.userId,
        isTyping: isTyping
      )
    } catch {
      realtimeLogger.error(
        "Failed to decode thread list typing payload: \(error.localizedDescription)"
      )
    }
  }

  private func notifyTypingToastIfNeeded(_ typingPayload: ThreadTypingPayload) {
    guard !isFriendsFeedVisible else { return }
    guard activeThreadId != typingPayload.threadId else { return }
    guard
      let viewerUserId = authenticatedViewerUserId,
      let normalizedTypingUserId = Self.normalizedUserId(typingPayload.userId),
      normalizedTypingUserId != viewerUserId,
      let thread = repository.getThread(id: typingPayload.threadId, viewerUserId: viewerUserId),
      thread.kind == .direct,
      let counterpartUserId = Self.normalizedUserId(thread.counterpartUserId),
      counterpartUserId == normalizedTypingUserId
    else {
      return
    }

    let now = Date()
    if let lastShownAt = typingToastLastShownAtByThreadId[typingPayload.threadId],
      now.timeIntervalSince(lastShownAt) < TypingToast.cooldown
    {
      return
    }
    typingToastLastShownAtByThreadId[typingPayload.threadId] = now

    let senderName =
      Self.nonEmptyTrimmed(thread.counterpartDisplayName)
      ?? Self.nonEmptyTrimmed(thread.title)
      ?? String(localized: .friendsChatTypingToastSenderFallback)

    NotificationCenter.default.post(
      name: .inAppChatToastRequested,
      object: InAppChatToastPayload(
        threadId: typingPayload.threadId,
        messageId: nil,
        senderUserId: typingPayload.userId,
        typingUserId: typingPayload.userId,
        senderName: senderName,
        senderAvatarUrl: thread.counterpartAvatarUrl,
        previewText: String(localized: .friendsChatTypingToastBody)
      )
    )
  }

  private func handleTypingBroadcast(_ payload: JSONObject, threadId: String, isTyping: Bool) {
    do {
      let typingPayload = try Self.decodeTypingPayload(from: payload)
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

  // swiftlint:disable:next function_body_length
  private func ensureTypingChannel(threadId: String) async -> Bool {
    if let channel = typingChannels[threadId],
      isTypingChannelHealthy(threadId: threadId, channel: channel)
    {
      return true
    }

    if let task = typingSubscriptionTasks[threadId] {
      return await task.value
    }

    // swiftlint:disable:next closure_body_length
    let task = Task { @MainActor [weak self] in
      guard let self else { return false }
      defer { typingSubscriptionTasks[threadId] = nil }

      if let channel = typingChannels[threadId],
        isTypingChannelHealthy(threadId: threadId, channel: channel)
      {
        return true
      }

      if let channel = typingChannels[threadId] {
        realtimeLogger.info(
          "Replacing stale typing realtime channel for \(threadId, privacy: .private) with status \(String(describing: channel.status), privacy: .public)"
        )
        await teardownTypingChannel(threadId: threadId, cancelSubscriptionTask: false)
      }

      let channel = supabase.channel(TypingTopic.name(threadId: threadId)) { config in
        config.broadcast.receiveOwnBroadcasts = true
      }
      let typingTasks: [Task<Void, Never>] = makeTypingChannelTasks(
        for: channel,
        threadId: threadId
      )

      do {
        try await subscribeWithTimeout(channel)
        typingChannels[threadId] = channel
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
        scheduleTypingChannelRetry(threadId: threadId, reason: error.localizedDescription)
        return false
      }
    }

    typingSubscriptionTasks[threadId] = task
    return await task.value
  }

  private func teardownTypingChannel(
    threadId: String,
    cancelSubscriptionTask: Bool = true,
    cancelRepairTask: Bool = true
  ) async {
    if cancelSubscriptionTask {
      typingSubscriptionTasks[threadId]?.cancel()
      typingSubscriptionTasks[threadId] = nil
    }
    if cancelRepairTask {
      typingRepairTasks[threadId]?.cancel()
      typingRepairTasks[threadId] = nil
      typingRetryTasks[threadId]?.cancel()
      typingRetryTasks[threadId] = nil
    }
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
    let shouldTrackTyping = shouldTrackTypingChannel(threadId: threadId)

    if shouldTrackTyping {
      _ = await ensureTypingChannel(threadId: threadId)
    } else {
      await teardownTypingChannel(threadId: threadId)
    }
  }

  private func shouldTrackTypingChannel(threadId: String) -> Bool {
    detailTypingThreadIds.contains(threadId)
  }

  private func isTypingChannelHealthy(threadId: String, channel: RealtimeChannelV2?) -> Bool {
    TypingChannelHealth.isHealthy(
      threadId: threadId,
      topic: channel?.topic,
      status: channel?.status,
      listenerTaskCount: typingTasks[threadId]?.count ?? 0,
      hasSubscriptionTask: typingSubscriptionTasks[threadId] != nil
    )
  }

  private func repairTypingChannel(threadId: String, reason: String) async {
    realtimeLogger.info(
      "Repairing typing realtime channel for \(threadId, privacy: .private): \(reason, privacy: .public)"
    )
    await teardownTypingChannel(threadId: threadId, cancelRepairTask: false)

    if shouldTrackTypingChannel(threadId: threadId) {
      _ = await ensureTypingChannel(threadId: threadId)
    }
  }

  private func scheduleTypingChannelRepair(threadId: String, reason: String) {
    guard shouldTrackTypingChannel(threadId: threadId) else { return }
    guard typingRepairTasks[threadId] == nil else { return }

    typingRepairTasks[threadId] = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { typingRepairTasks[threadId] = nil }
      await repairTypingChannel(threadId: threadId, reason: reason)
    }
  }

  // swiftlint:disable:next type_contents_order
  private func scheduleTypingChannelRetry(threadId: String, reason _: String) {
    guard shouldTrackTypingChannel(threadId: threadId) else { return }
    guard typingRetryTasks[threadId] == nil else { return }

    typingRetryTasks[threadId] = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { typingRetryTasks[threadId] = nil }
      do {
        try await Task.sleep(for: TypingRepair.retryDelay)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      guard shouldTrackTypingChannel(threadId: threadId) else {
        return
      }
      _ = await ensureTypingChannel(threadId: threadId)
    }
  }

  // swiftlint:disable:next type_contents_order
  private func scheduleThreadListRetry(viewerUserId: String, reason _: String) {
    guard authenticatedViewerUserId == viewerUserId else { return }
    guard threadListRetryTask == nil else { return }

    threadListRetryTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { threadListRetryTask = nil }
      do {
        try await Task.sleep(for: TypingRepair.retryDelay)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      guard authenticatedViewerUserId == viewerUserId else {
        return
      }
      await startThreadListSubscription(viewerUserId: viewerUserId)
    }
  }

  private func prepareRealtimeAuth() async throws {
    let session = try await AuthSessionManager.shared.getSession()
    await supabase.realtimeV2.setAuth(session.accessToken)
  }

  private func subscribeWithTimeout(_ channel: RealtimeChannelV2) async throws {
    try await prepareRealtimeAuth()

    let operationTask = Task {
      try await channel.subscribeWithError()
    }
    defer {
      operationTask.cancel()
    }

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

  /// The row a realtime action carries: the new row for inserts and updates, the old row for deletes.
  static func changedRecord(of action: AnyAction) -> JSONObject {
    switch action {
    case .insert(let insert):
      return insert.record

    case .update(let update):
      return update.record

    case .delete(let delete):
      return delete.oldRecord
    }
  }

  static func extractThreadId(from action: AnyAction) -> String? {
    extractThreadId(fromRecord: changedRecord(of: action))
  }

  static func extractThreadId(fromRecord record: JSONObject) -> String? {
    record["thread_id"]?.stringValue ?? record["id"]?.stringValue
  }

  static func extractMessageId(from action: AnyAction) -> String? {
    extractMessageId(fromRecord: changedRecord(of: action))
  }

  static func extractMessageId(fromRecord record: JSONObject) -> String? {
    record["id"]?.stringValue ?? record["message_id"]?.stringValue
  }

  static func extractReactionMessageId(from action: AnyAction) -> String? {
    extractReactionMessageId(fromRecord: changedRecord(of: action))
  }

  static func extractReactionMessageId(fromRecord record: JSONObject) -> String? {
    record["message_id"]?.stringValue
  }

  static func decodeThreadUserState(from action: AnyAction) -> FriendThreadState? {
    if case .delete = action { return nil }
    return decodeThreadUserState(fromRecord: changedRecord(of: action))
  }

  static func decodeThreadUserState(fromRecord record: JSONObject) -> FriendThreadState? {
    do {
      let row = try record.decode(as: MessagingThreadUserStateRow.self)
      return row.toFriendThreadState()
    } catch {
      realtimeLogger.error(
        "Failed to decode thread user state from realtime payload: \(error.localizedDescription)")
      return nil
    }
  }

  static func decodeTypingPayload(from payload: JSONObject) throws -> ThreadTypingPayload {
    try (payload["payload"]?.objectValue ?? payload).decode(as: ThreadTypingPayload.self)
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

// swiftlint:disable:next file_length
extension FriendsMessagingRealtimeCoordinator: FriendsMessagingRealtimeCoordinating {}
