import Foundation
import Supabase
import os.log

private let realtimeLogger = Logger(
  subsystem: "com.tidex.app", category: "FriendsMessagingRealtime")

@MainActor
final class FriendsMessagingRealtimeCoordinator: ObservableObject {
  static let shared = FriendsMessagingRealtimeCoordinator()

  private let service: any FriendsMessagingServiceProviding
  private let repository: any FriendsMessagesRepositoryProviding

  private var threadListChannel: RealtimeChannelV2?
  private var threadListTasks: [Task<Void, Never>] = []
  private var threadChannels: [String: RealtimeChannelV2] = [:]
  private var threadTasks: [String: [Task<Void, Never>]] = [:]

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
        makeStatusTask(for: channel, viewerUserId: viewerUserId),
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

  func startThreadSubscription(threadId: String, viewerUserId: String) async {
    await stopThreadSubscription(threadId: threadId)

    let channel = supabase.channel("friends-thread-detail:\(threadId)")
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
    let stateChanges = channel.postgresChange(
      AnyAction.self,
      schema: "public",
      table: "thread_user_state",
      filter: .eq("user_id", value: viewerUserId)
    )

    do {
      try await channel.subscribeWithError()
      threadChannels[threadId] = channel

      threadTasks[threadId] = [
        makeThreadStatusTask(for: channel, threadId: threadId, viewerUserId: viewerUserId),
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
          for await action in stateChanges {
            await self.handleThreadDetailStateAction(
              action, threadId: threadId, viewerUserId: viewerUserId)
          }
        },
      ]

      await refreshThreadDetail(threadId: threadId, viewerUserId: viewerUserId)
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
  }

  func stopAll() async {
    await stopThreadListSubscription()
    for threadId in threadChannels.keys {
      await stopThreadSubscription(threadId: threadId)
    }
  }

  private func refreshThreadList(viewerUserId: String) async {
    do {
      let threads = try await service.listMyThreads(limit: 100, before: nil)
      await repository.saveThreads(threads, for: viewerUserId)
    } catch {
      realtimeLogger.error("Failed to refresh thread list: \(error.localizedDescription)")
    }
  }

  private func refreshThreadDetail(threadId: String, viewerUserId: String) async {
    await refreshThreadSummary(threadId: threadId, viewerUserId: viewerUserId)

    do {
      let messages = try await service.listThreadMessages(
        threadId: threadId, limit: 200, before: nil)
      await repository.saveMessages(messages, in: threadId, for: viewerUserId)
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
    } catch {
      realtimeLogger.error(
        "Failed to refresh thread summary for \(threadId, privacy: .private): \(error.localizedDescription)"
      )
    }
  }

  private func refreshMessage(messageId: String, viewerUserId: String) async {
    do {
      let message = try await service.fetchMessagePayload(messageId: messageId)
      await repository.saveMessages([message], in: message.threadId, for: viewerUserId)
      await refreshThreadSummary(threadId: message.threadId, viewerUserId: viewerUserId)
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
  }

  private func makeStatusTask(for channel: RealtimeChannelV2, viewerUserId: String) -> Task<
    Void, Never
  > {
    Task { [weak self] in
      guard let self else { return }
      for await status in channel.statusChange where status == .subscribed {
        await self.refreshThreadList(viewerUserId: viewerUserId)
      }
    }
  }

  private func makeThreadStatusTask(
    for channel: RealtimeChannelV2,
    threadId: String,
    viewerUserId: String
  ) -> Task<Void, Never> {
    Task { [weak self] in
      guard let self else { return }
      for await status in channel.statusChange where status == .subscribed {
        await self.refreshThreadDetail(threadId: threadId, viewerUserId: viewerUserId)
      }
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
      return insert.record["id"]?.stringValue
    case .update(let update):
      return update.record["id"]?.stringValue
    case .delete(let delete):
      return delete.oldRecord["id"]?.stringValue
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
