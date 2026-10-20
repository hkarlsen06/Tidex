import Combine
import Foundation
import os.log

private let realtimeLogger = Logger(
  subsystem: "com.tidex.app", category: "FriendsMessagingRealtime")

extension Notification.Name {
  static let friendsThreadDidUpdate = Notification.Name("friendsThreadDidUpdate")
  static let friendFeedPlacementDidChange = Notification.Name("friendFeedPlacementDidChange")
  static let friendsThreadTypingDidChange = Notification.Name("friendsThreadTypingDidChange")
}

/// Runs refreshes for the same key one at a time. One new message changes the inbox, the thread
/// and the read states at once. Each used to start its own fetch, and a slow older response could
/// overwrite newer rows and unread counts. Calls that arrive while a refresh runs merge into one
/// more pass, and every caller returns after a pass that started after its call.
@MainActor
final class SerializedRefreshRunner {
  private var runningTasks: [String: Task<Void, Never>] = [:]
  /// The next pass per key. False when any merged caller asked for a full snapshot.
  private var queuedAllowIncrementalSync: [String: Bool] = [:]

  func run(
    key: String,
    allowIncrementalSync: Bool,
    _ refresh: @escaping @MainActor (_ allowIncrementalSync: Bool) async -> Void
  ) async {
    queuedAllowIncrementalSync[key] =
      (queuedAllowIncrementalSync[key] ?? true) && allowIncrementalSync

    if let runningTask = runningTasks[key] {
      await runningTask.value
      return
    }

    let task = Task { @MainActor in
      while let allowIncrementalSync = queuedAllowIncrementalSync.removeValue(forKey: key) {
        await refresh(allowIncrementalSync)
      }
      runningTasks[key] = nil
    }
    runningTasks[key] = task
    await task.value
  }
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

/// Keeps the local store current from Convex subscriptions. A subscription to `threads:inbox`
/// feeds the thread list and the unread count. While a thread is open, subscriptions to
/// `messages:thread` and `threads:states` tell the coordinator to fetch what changed, and
/// `threads:typing` reports who is typing in any thread.
@MainActor
// swiftlint:disable:next type_body_length
final class FriendsMessagingRealtimeCoordinator {
  private enum Pagination {
    static let pageSize = 50
  }

  private enum SyncReplayError: Error {
    case stalledPagination
  }

  private enum Retry {
    static let delay: Duration = .seconds(3)
  }

  private enum TypingToast {
    static let cooldown: TimeInterval = 12
  }

  private enum Typing {
    /// Typing rows a sender's crash left behind are older than this when the app first sees them.
    static let maxAgeMilliseconds: Double = 10_000
  }

  private struct TypingKey: Hashable {
    let threadId: String
    let userId: String
  }

  static let shared = FriendsMessagingRealtimeCoordinator()

  private let service: any FriendsMessagingServiceProviding
  private let repository: any FriendsMessagesRepositoryProviding
  private let realtime = ConvexRealtime.shared

  private var authenticatedViewerUserId: String?
  private var activeThreadId: String?
  private var activeThreadViewerUserId: String?
  private var threadListSubscriptions: [AnyCancellable] = []
  private var threadListRetryTask: Task<Void, Never>?
  /// The newest inbox the subscription delivered and no refresh has stored yet.
  private var pendingInbox: FriendInboxSyncSnapshot?
  private var typingSentAtMsByKey: [TypingKey: Double] = [:]
  private var typingToastLastShownAtByThreadId: [String: Date] = [:]
  private(set) var isFriendsFeedVisible = false
  private var listTypingThreadIds: Set<String> = []
  private var threadSubscriptions: [String: [AnyCancellable]] = [:]
  private var threadRetryTasks: [String: Task<Void, Never>] = [:]
  /// The newest read states per thread that no refresh has stored yet.
  private var pendingThreadStates: [String: [FriendThreadState]] = [:]
  /// Threads with a detail subscribe in flight, so a second call doesn't start another.
  private var pendingThreadDetailSubscriptions: Set<String> = []
  private let refreshRunner = SerializedRefreshRunner()

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

    if !threadListSubscriptions.isEmpty {
      return
    }

    await startThreadListSubscription(viewerUserId: normalizedViewerUserId)
  }

  func stopForAuthenticatedUser() async {
    authenticatedViewerUserId = nil
    activeThreadId = nil
    activeThreadViewerUserId = nil
    listTypingThreadIds.removeAll()
    typingToastLastShownAtByThreadId.removeAll()
    pendingThreadStates.removeAll()
    isFriendsFeedVisible = false

    await stopThreadListSubscription()
    for threadId in Array(threadSubscriptions.keys) + Array(threadRetryTasks.keys) {
      stopThreadDetailSubscription(threadId: threadId)
    }
    await realtime.signOut()
  }

  func handleAppDidBecomeActive() async {
    guard let authenticatedViewerUserId else { return }
    await startForAuthenticatedUser(viewerUserId: authenticatedViewerUserId)
    // The socket reconnects by itself, but a refresh now doesn't wait for it.
    await refreshThreadList(viewerUserId: authenticatedViewerUserId)

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
      stopThreadDetailSubscription(threadId: activeThreadId)
    }

    activeThreadId = normalizedThreadId
    activeThreadViewerUserId = normalizedViewerUserId

    if threadSubscriptions[normalizedThreadId] != nil {
      return
    }

    await startThreadDetailSubscription(
      threadId: normalizedThreadId,
      viewerUserId: normalizedViewerUserId
    )
  }

  // swiftlint:disable:next async_without_await
  func clearActiveThread(threadId: String) async {
    guard let normalizedThreadId = Self.normalizedUserId(threadId) else { return }
    guard activeThreadId == normalizedThreadId else { return }

    activeThreadId = nil
    activeThreadViewerUserId = nil
    stopThreadDetailSubscription(threadId: normalizedThreadId)
  }

  func startThreadListSubscription(viewerUserId: String) async {
    await stopThreadListSubscription()

    guard await realtime.signIn() else {
      scheduleThreadListRetry(viewerUserId: viewerUserId)
      return
    }
    // A nil viewer means sign-out happened during the sign-in.
    guard authenticatedViewerUserId == viewerUserId else { return }

    let inbox = realtime.subscribe(
      to: "threads:inbox",
      args: ["limit": 100.0],
      onUpdate: { [weak self] (payload: MessagingInboxRow) in
        self?.handleInboxUpdate(payload, viewerUserId: viewerUserId)
      },
      onFailure: { [weak self] error in
        self?.threadListSubscriptionFailed(error, viewerUserId: viewerUserId)
      }
    )
    let typing = realtime.subscribe(
      to: "threads:typing",
      onUpdate: { [weak self] (rows: [TypingRow]) in
        self?.handleTypingUpdate(rows, viewerUserId: viewerUserId)
      },
      onFailure: { [weak self] error in
        self?.threadListSubscriptionFailed(error, viewerUserId: viewerUserId)
      }
    )
    threadListSubscriptions = [inbox, typing].compactMap { $0 }
    if threadListSubscriptions.count < 2 {
      scheduleThreadListRetry(viewerUserId: viewerUserId)
    }
  }

  // swiftlint:disable:next async_without_await
  func stopThreadListSubscription() async {
    threadListRetryTask?.cancel()
    threadListRetryTask = nil
    threadListSubscriptions.forEach { $0.cancel() }
    threadListSubscriptions.removeAll()
    pendingInbox = nil
    typingSentAtMsByKey.removeAll()
  }

  func startThreadSubscription(threadId: String, viewerUserId: String) async {
    await setActiveThread(threadId: threadId, viewerUserId: viewerUserId)
  }

  func stopThreadSubscription(threadId: String) async {
    await clearActiveThread(threadId: threadId)
  }

  func sendTypingStart(threadId: String, userId _: String) async -> Bool {
    await sendTyping(threadId: threadId, isTyping: true)
  }

  func sendTypingStop(threadId: String, userId _: String) async -> Bool {
    await sendTyping(threadId: threadId, isTyping: false)
  }

  private func sendTyping(threadId: String, isTyping: Bool) async -> Bool {
    do {
      try await service.setThreadTyping(threadId: threadId, isTyping: isTyping)
      return true
    } catch {
      return false
    }
  }

  // MARK: - Thread detail subscriptions

  private func startThreadDetailSubscription(threadId: String, viewerUserId: String) async {
    // The pending subscribe keeps the subscriptions when the thread is active again once it finishes.
    guard pendingThreadDetailSubscriptions.insert(threadId).inserted else { return }
    defer { pendingThreadDetailSubscriptions.remove(threadId) }
    stopThreadDetailSubscription(threadId: threadId)

    guard await realtime.signIn() else {
      scheduleThreadDetailRetry(threadId: threadId, viewerUserId: viewerUserId)
      return
    }
    // clearActiveThread can run during the sign-in and finds nothing to stop.
    guard authenticatedViewerUserId == viewerUserId, activeThreadId == threadId else { return }

    let messages = realtime.subscribe(
      to: "messages:thread",
      args: ["thread_id": threadId, "message_limit": Double(Pagination.pageSize)],
      onUpdate: { [weak self] (_: ThreadRevision) in
        self?.handleThreadMessagesUpdate(threadId: threadId, viewerUserId: viewerUserId)
      },
      onFailure: { [weak self] error in
        self?.threadDetailSubscriptionFailed(error, threadId: threadId, viewerUserId: viewerUserId)
      }
    )
    let states = realtime.subscribe(
      to: "threads:states",
      args: ["thread_id": threadId],
      onUpdate: { [weak self] (rows: [MessagingThreadUserStateRow]) in
        self?.handleThreadStatesUpdate(
          rows.map { $0.toFriendThreadState() }, threadId: threadId, viewerUserId: viewerUserId)
      },
      onFailure: { [weak self] error in
        self?.threadDetailSubscriptionFailed(error, threadId: threadId, viewerUserId: viewerUserId)
      }
    )
    let subscriptions = [messages, states].compactMap { $0 }
    threadSubscriptions[threadId] = subscriptions
    if subscriptions.count < 2 {
      scheduleThreadDetailRetry(threadId: threadId, viewerUserId: viewerUserId)
    }
  }

  private func stopThreadDetailSubscription(threadId: String) {
    threadRetryTasks[threadId]?.cancel()
    threadRetryTasks[threadId] = nil
    threadSubscriptions[threadId]?.forEach { $0.cancel() }
    threadSubscriptions[threadId] = nil
    pendingThreadStates[threadId] = nil
  }

  private func handleThreadMessagesUpdate(threadId: String, viewerUserId: String) {
    guard authenticatedViewerUserId == viewerUserId, activeThreadId == threadId else { return }
    Task { [weak self] in
      await self?.refreshThreadSnapshot(threadId: threadId, viewerUserId: viewerUserId)
    }
  }

  private func handleThreadStatesUpdate(
    _ states: [FriendThreadState],
    threadId: String,
    viewerUserId: String
  ) {
    guard authenticatedViewerUserId == viewerUserId, activeThreadId == threadId else { return }
    pendingThreadStates[threadId] = states
    Task { [weak self] in
      await self?.refreshRunner.run(
        key: "states:\(viewerUserId):\(threadId)",
        allowIncrementalSync: true
      ) { [weak self] _ in
        await self?.storePendingThreadStates(threadId: threadId, viewerUserId: viewerUserId)
      }
    }
  }

  private func storePendingThreadStates(threadId: String, viewerUserId: String) async {
    guard authenticatedViewerUserId == viewerUserId, let states = pendingThreadStates[threadId]
    else { return }
    pendingThreadStates[threadId] = nil
    for state in states {
      await repository.saveThreadState(state)
    }
    notifyThreadUpdated(threadId: threadId)
  }

  private func threadDetailSubscriptionFailed(
    _ error: Error,
    threadId: String,
    viewerUserId: String
  ) {
    realtimeLogger.error(
      "Thread subscription for \(threadId, privacy: .private) ended: \(error.localizedDescription)")
    scheduleThreadDetailRetry(threadId: threadId, viewerUserId: viewerUserId)
  }

  // MARK: - Thread list subscriptions

  private func handleInboxUpdate(_ payload: MessagingInboxRow, viewerUserId: String) {
    guard authenticatedViewerUserId == viewerUserId else { return }
    pendingInbox = payload.toFriendInboxSyncSnapshot()
    Task { [weak self] in
      await self?.refreshThreadList(viewerUserId: viewerUserId)
    }
  }

  private func threadListSubscriptionFailed(_ error: Error, viewerUserId: String) {
    realtimeLogger.error("Thread list subscription ended: \(error.localizedDescription)")
    scheduleThreadListRetry(viewerUserId: viewerUserId)
  }

  private func refreshThreadList(
    viewerUserId: String,
    allowIncrementalSync: Bool = true
  ) async {
    await refreshRunner.run(
      key: "inbox:\(viewerUserId)",
      allowIncrementalSync: allowIncrementalSync
    ) { [weak self] _ in
      await self?.performThreadListRefresh(viewerUserId: viewerUserId)
    }
  }

  /// Stores the inbox the subscription delivered, or fetches one when none is waiting.
  private func performThreadListRefresh(viewerUserId: String) async {
    // Queued passes can outlive a sign-out or user switch.
    guard authenticatedViewerUserId == viewerUserId else { return }

    let snapshot: FriendInboxSyncSnapshot
    if let pendingInbox {
      self.pendingInbox = nil
      snapshot = pendingInbox
    } else {
      do {
        snapshot = try await service.fetchInboxSyncSnapshotV2(limit: 100, before: nil)
      } catch {
        realtimeLogger.error("Failed to refresh thread list: \(error.localizedDescription)")
        return
      }
    }

    // Don't write the previous user's inbox back after sign-out or a user switch.
    guard authenticatedViewerUserId == viewerUserId else { return }
    await repository.saveThreads(snapshot.threads, for: viewerUserId)
    NotificationCenter.default.post(name: .friendsThreadDidUpdate, object: nil)
  }

  // MARK: - Thread sync

  private func refreshThreadSnapshot(
    threadId: String,
    viewerUserId: String,
    shouldNotify: Bool = true,
    allowIncrementalSync: Bool = true
  ) async {
    await refreshRunner.run(
      key: "thread:\(viewerUserId):\(threadId)",
      allowIncrementalSync: allowIncrementalSync
    ) { [weak self] allowIncrementalSync in
      await self?.performThreadSnapshotRefresh(
        threadId: threadId,
        viewerUserId: viewerUserId,
        allowIncrementalSync: allowIncrementalSync
      )
    }
    if shouldNotify {
      notifyThreadUpdated(threadId: threadId)
    }
  }

  // swiftlint:disable:next function_body_length
  private func performThreadSnapshotRefresh(
    threadId: String,
    viewerUserId: String,
    allowIncrementalSync: Bool
  ) async {
    guard authenticatedViewerUserId == viewerUserId else { return }

    // True when the stored cursor predates the move to Convex, so deletions since are unknown.
    var eventHistoryExpired = false
    if allowIncrementalSync,
      let syncState = await repository.getMessagingSyncState(
        viewerUserId: viewerUserId,
        scope: .thread(threadId: threadId)
      )
    {
      if syncState.retainedFromVersion == FriendsMessagingService.revisionCursorMarker {
        do {
          try await replayThreadEvents(
            threadId: threadId,
            viewerUserId: viewerUserId,
            startingAt: syncState
          )
          return
        } catch {
          realtimeLogger.error(
            "Failed to replay thread changes for \(threadId, privacy: .private): \(error.localizedDescription)"
          )
        }
      } else {
        eventHistoryExpired = true
      }
    }

    do {
      let requestedAt = Date()
      let snapshot = try await service.fetchThreadSyncSnapshotV2(
        threadId: threadId,
        messageLimit: Pagination.pageSize
      )
      await repository.saveThread(from: snapshot, for: viewerUserId)
      await repository.saveMessages(
        snapshot.messages,
        in: threadId,
        for: viewerUserId
      )
      await repository.deleteSentMessagesMissingFromSnapshot(
        snapshot,
        includingOlderHistory: eventHistoryExpired,
        writtenBefore: requestedAt,
        for: viewerUserId
      )
      await repository.saveThreadState(snapshot.viewerState)
      await saveMessagingSyncState(
        viewerUserId: viewerUserId,
        scope: .thread(threadId: threadId),
        version: snapshot.snapshotVersion
      )
    } catch {
      realtimeLogger.error(
        "Failed to refresh thread snapshot for \(threadId, privacy: .private): \(error.localizedDescription)"
      )
    }
  }

  /// Applies the message changes after the stored revision, page by page.
  private func replayThreadEvents(
    threadId: String,
    viewerUserId: String,
    startingAt syncState: FriendMessagingSyncState
  ) async throws {
    var currentVersion = syncState.version

    while true {
      let page = try await service.listThreadEventsV2(
        threadId: threadId,
        afterVersion: currentVersion,
        limit: 100
      )

      if page.hasMore, page.events.isEmpty {
        throw SyncReplayError.stalledPagination
      }

      for event in page.events {
        await applyThreadEvent(event, viewerUserId: viewerUserId)
      }
      currentVersion = max(currentVersion, page.latestVersion)

      await saveMessagingSyncState(
        viewerUserId: viewerUserId,
        scope: .thread(threadId: threadId),
        version: currentVersion
      )

      if !page.hasMore {
        return
      }
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
    version: Int64
  ) async {
    await repository.saveMessagingSyncState(
      FriendMessagingSyncState(
        viewerUserId: viewerUserId,
        scope: scope,
        version: version,
        retainedFromVersion: FriendsMessagingService.revisionCursorMarker,
        updatedAt: Date()
      )
    )
  }

  // MARK: - Typing

  private func handleTypingUpdate(_ rows: [TypingRow], viewerUserId: String) {
    guard authenticatedViewerUserId == viewerUserId else { return }

    let nowMilliseconds = Date().timeIntervalSince1970 * 1_000
    var current: [TypingKey: Double] = [:]
    for row in rows {
      let key = TypingKey(
        threadId: Self.normalizedUserId(row.threadId) ?? row.threadId,
        userId: Self.normalizedUserId(row.userId) ?? row.userId
      )
      // A row that was there before this app saw it and hasn't changed may be a leftover.
      if typingSentAtMsByKey[key] == nil, nowMilliseconds - row.sentAtMs > Typing.maxAgeMilliseconds {
        continue
      }
      current[key] = row.sentAtMs
    }

    // The sender refreshes the row every few seconds, so a new time means still typing.
    for (key, sentAtMs) in current where typingSentAtMsByKey[key] != sentAtMs {
      handleTypingChange(key, isTyping: true)
    }
    for key in typingSentAtMsByKey.keys where current[key] == nil {
      handleTypingChange(key, isTyping: false)
    }
    typingSentAtMsByKey = current
  }

  private func handleTypingChange(_ key: TypingKey, isTyping: Bool) {
    if isTyping {
      notifyTypingToastIfNeeded(key)
    }
    guard activeThreadId == key.threadId || listTypingThreadIds.contains(key.threadId) else {
      return
    }
    notifyThreadTypingChanged(threadId: key.threadId, userId: key.userId, isTyping: isTyping)
  }

  private func notifyTypingToastIfNeeded(_ key: TypingKey) {
    guard !isFriendsFeedVisible else { return }
    guard activeThreadId != key.threadId else { return }
    guard
      let viewerUserId = authenticatedViewerUserId,
      key.userId != viewerUserId,
      let thread = repository.getThread(id: key.threadId, viewerUserId: viewerUserId),
      thread.kind == .direct,
      let counterpartUserId = Self.normalizedUserId(thread.counterpartUserId),
      counterpartUserId == key.userId
    else {
      return
    }

    let now = Date()
    if let lastShownAt = typingToastLastShownAtByThreadId[key.threadId],
      now.timeIntervalSince(lastShownAt) < TypingToast.cooldown
    {
      return
    }
    typingToastLastShownAtByThreadId[key.threadId] = now

    let senderName =
      Self.nonEmptyTrimmed(thread.counterpartDisplayName)
      ?? Self.nonEmptyTrimmed(thread.title)
      ?? String(localized: .friendsChatTypingToastSenderFallback)

    NotificationCenter.default.post(
      name: .inAppChatToastRequested,
      object: InAppChatToastPayload(
        threadId: key.threadId,
        messageId: nil,
        senderUserId: key.userId,
        typingUserId: key.userId,
        senderName: senderName,
        senderAvatarUrl: thread.counterpartAvatarUrl,
        previewText: String(localized: .friendsChatTypingToastBody)
      )
    )
  }

  // MARK: - Helpers

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

  /// Starts the list subscriptions again after a pause. Each failed attempt schedules the next.
  private func scheduleThreadListRetry(viewerUserId: String) {
    guard authenticatedViewerUserId == viewerUserId else { return }
    guard threadListRetryTask == nil else { return }

    threadListRetryTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: Retry.delay)
      guard let self, !Task.isCancelled, authenticatedViewerUserId == viewerUserId else { return }
      // The subscribe below stops the old subscriptions and the retry task, which is this one.
      threadListRetryTask = nil
      await startThreadListSubscription(viewerUserId: viewerUserId)
    }
  }

  private func scheduleThreadDetailRetry(threadId: String, viewerUserId: String) {
    guard activeThreadId == threadId, authenticatedViewerUserId == viewerUserId else { return }
    guard threadRetryTasks[threadId] == nil else { return }

    threadRetryTasks[threadId] = Task { @MainActor [weak self] in
      try? await Task.sleep(for: Retry.delay)
      guard let self, !Task.isCancelled, activeThreadId == threadId,
        authenticatedViewerUserId == viewerUserId
      else { return }
      threadRetryTasks[threadId] = nil
      await startThreadDetailSubscription(threadId: threadId, viewerUserId: viewerUserId)
    }
  }
}

/// A typing row from `threads:typing`: someone typing in a thread of the viewer.
private struct TypingRow: Decodable {
  let threadId: String
  let userId: String
  let sentAtMs: Double

  enum CodingKeys: String, CodingKey {
    case threadId = "thread_id"
    case userId = "user_id"
    case sentAtMs = "sent_at_ms"
  }
}

/// The part of a `messages:thread` result the coordinator reads. A new result means the thread
/// changed, and the coordinator then fetches what changed after its stored revision.
private struct ThreadRevision: Decodable {
  let latestRevision: Int64

  enum CodingKeys: String, CodingKey {
    case latestRevision = "latest_revision"
  }
}

// swiftlint:disable:next file_length
extension FriendsMessagingRealtimeCoordinator: FriendsMessagingRealtimeCoordinating {}
