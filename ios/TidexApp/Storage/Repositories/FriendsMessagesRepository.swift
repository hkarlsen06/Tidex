import Combine
import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "FriendsMessagesRepository")

@MainActor
protocol FriendsMessagesRepositoryProviding: AnyObject {
  func getThread(id: String, viewerUserId: String) -> FriendThread?
  func getMessage(id: String, viewerUserId: String) -> FriendMessage?
  func saveThreads(_ threads: [FriendThread], for viewerUserId: String) async
  func saveThread(_ thread: FriendThread, for viewerUserId: String) async
  func saveMessages(_ messages: [FriendMessage], in threadId: String, for viewerUserId: String)
    async
  func saveThreadState(_ state: FriendThreadState) async
  func deleteMessage(id: String, viewerUserId: String) async
}

@MainActor
final class FriendsMessagesRepository: ObservableObject {
  static let shared = FriendsMessagesRepository()

  private let container: ModelContainer
  private let storeActor: LocalStoreActor

  init(container: ModelContainer? = nil, storeActor: LocalStoreActor? = nil) {
    if let container, let storeActor {
      self.container = container
      self.storeActor = storeActor
    } else {
      self.container = LocalStore.shared.container
      self.storeActor = LocalStore.shared.storeActor
    }
  }

  func getThreads(for viewerUserId: String) -> [FriendThread] {
    let context = ModelContext(container)
    let descriptor = FetchDescriptor<LocalThread>(
      predicate: #Predicate { $0.viewerUserId == viewerUserId },
      sortBy: [
        SortDescriptor(\LocalThread.sortTimestamp, order: .reverse),
        SortDescriptor(\LocalThread.id, order: .reverse),
      ]
    )

    do {
      return try context.fetch(descriptor).map { $0.toFriendThread() }
    } catch {
      logger.error("Failed to fetch threads: \(error.localizedDescription)")
      return []
    }
  }

  func getThread(id: String, viewerUserId: String) -> FriendThread? {
    let context = ModelContext(container)
    let descriptor = FetchDescriptor<LocalThread>(
      predicate: #Predicate { localThread in
        localThread.id == id && localThread.viewerUserId == viewerUserId
      }
    )

    do {
      return try context.fetch(descriptor).first?.toFriendThread()
    } catch {
      logger.error("Failed to fetch thread: \(error.localizedDescription)")
      return nil
    }
  }

  func getThreadState(threadId: String, viewerUserId: String) -> FriendThreadState? {
    let context = ModelContext(container)
    let compositeKey = "\(viewerUserId):\(threadId)"
    let descriptor = FetchDescriptor<LocalThreadState>(
      predicate: #Predicate { $0.compositeKey == compositeKey }
    )

    do {
      return try context.fetch(descriptor).first?.toFriendThreadState()
    } catch {
      logger.error("Failed to fetch thread state: \(error.localizedDescription)")
      return nil
    }
  }

  func getMessages(threadId: String, viewerUserId: String) -> [FriendMessage] {
    let context = ModelContext(container)
    let messageDescriptor = FetchDescriptor<LocalMessage>(
      predicate: #Predicate { localMessage in
        localMessage.threadId == threadId && localMessage.viewerUserId == viewerUserId
      },
      sortBy: [
        SortDescriptor(\LocalMessage.createdAt, order: .forward),
        SortDescriptor(\LocalMessage.id, order: .forward),
      ]
    )

    let attachmentDescriptor = FetchDescriptor<LocalMessageAttachment>(
      predicate: #Predicate { attachment in
        attachment.threadId == threadId && attachment.viewerUserId == viewerUserId
      },
      sortBy: [
        SortDescriptor(\LocalMessageAttachment.attachmentIndex, order: .forward),
        SortDescriptor(\LocalMessageAttachment.id, order: .forward),
      ]
    )
    let reactionDescriptor = FetchDescriptor<LocalMessageReaction>(
      predicate: #Predicate { reaction in
        reaction.threadId == threadId && reaction.viewerUserId == viewerUserId
      },
      sortBy: [
        SortDescriptor(\LocalMessageReaction.reactionIndex, order: .forward),
        SortDescriptor(\LocalMessageReaction.emoji, order: .forward),
      ]
    )

    do {
      let messages = try context.fetch(messageDescriptor)
      let attachments = try context.fetch(attachmentDescriptor)
      let reactions = try context.fetch(reactionDescriptor)
      let attachmentsByMessageId = Dictionary(grouping: attachments, by: \.messageId)
      let reactionsByMessageId = Dictionary(grouping: reactions, by: \.messageId)
      let friendMessages = messages.map { message in
        message.toFriendMessage(
          attachments: attachmentsByMessageId[message.id] ?? [],
          reactions: reactionsByMessageId[message.id] ?? []
        )
      }
      let visibleMessages = friendMessages.filter { $0.deletedAt == nil }
      return deduplicateMessages(visibleMessages, viewerUserId: viewerUserId)
    } catch {
      logger.error("Failed to fetch messages: \(error.localizedDescription)")
      return []
    }
  }

  func getMessage(id: String, viewerUserId: String) -> FriendMessage? {
    let context = ModelContext(container)
    let messageDescriptor = FetchDescriptor<LocalMessage>(
      predicate: #Predicate { localMessage in
        localMessage.id == id && localMessage.viewerUserId == viewerUserId
      }
    )
    let attachmentDescriptor = FetchDescriptor<LocalMessageAttachment>(
      predicate: #Predicate { attachment in
        attachment.messageId == id && attachment.viewerUserId == viewerUserId
      },
      sortBy: [
        SortDescriptor(\LocalMessageAttachment.attachmentIndex, order: .forward),
        SortDescriptor(\LocalMessageAttachment.id, order: .forward),
      ]
    )
    let reactionDescriptor = FetchDescriptor<LocalMessageReaction>(
      predicate: #Predicate { reaction in
        reaction.messageId == id && reaction.viewerUserId == viewerUserId
      },
      sortBy: [
        SortDescriptor(\LocalMessageReaction.reactionIndex, order: .forward),
        SortDescriptor(\LocalMessageReaction.emoji, order: .forward),
      ]
    )

    do {
      guard let message = try context.fetch(messageDescriptor).first else { return nil }
      let attachments = try context.fetch(attachmentDescriptor)
      let reactions = try context.fetch(reactionDescriptor)
      let friendMessage = message.toFriendMessage(attachments: attachments, reactions: reactions)
      return friendMessage.deletedAt == nil ? friendMessage : nil
    } catch {
      logger.error("Failed to fetch message: \(error.localizedDescription)")
      return nil
    }
  }

  func saveThreads(_ threads: [FriendThread], for viewerUserId: String) async {
    do {
      try await storeActor.saveThreadSummaries(threads, for: viewerUserId)
      logger.info("Saved \(threads.count) threads for viewer")
    } catch {
      logger.error("Failed to save threads: \(error.localizedDescription)")
    }
  }

  func saveThread(_ thread: FriendThread, for viewerUserId: String) async {
    do {
      try await storeActor.saveThreadSummary(thread, for: viewerUserId)
      try await storeActor.save()
      logger.info("Saved thread \(thread.id, privacy: .private)")
    } catch {
      logger.error("Failed to save thread: \(error.localizedDescription)")
    }
  }

  func saveMessages(_ messages: [FriendMessage], in threadId: String, for viewerUserId: String)
    async
  {
    do {
      try await storeActor.saveMessages(messages, in: threadId, for: viewerUserId)
      logger.info("Saved \(messages.count) messages for thread \(threadId, privacy: .private)")
    } catch {
      logger.error("Failed to save messages: \(error.localizedDescription)")
    }
  }

  func saveOptimisticMessage(
    _ message: FriendMessage, in threadId: String, for viewerUserId: String
  )
    async
  {
    do {
      try await storeActor.saveOptimisticMessage(message, in: threadId, for: viewerUserId)
      logger.info("Saved optimistic message for thread \(threadId, privacy: .private)")
    } catch {
      logger.error("Failed to save optimistic message: \(error.localizedDescription)")
    }
  }

  func saveConfirmedMessage(
    _ message: FriendMessage,
    replacingLocalMessageId localMessageId: String,
    in threadId: String,
    for viewerUserId: String
  ) async {
    do {
      try await storeActor.saveConfirmedMessage(
        message,
        replacingLocalMessageId: localMessageId,
        in: threadId,
        for: viewerUserId
      )
      logger.info("Saved confirmed message for thread \(threadId, privacy: .private)")
    } catch {
      logger.error("Failed to save confirmed message: \(error.localizedDescription)")
    }
  }

  func updateMessageSendState(
    messageId: String,
    viewerUserId: String,
    sendState: FriendMessageSendState,
    failureMessage: String?
  ) async {
    do {
      try await storeActor.updateMessageSendState(
        messageId: messageId,
        viewerUserId: viewerUserId,
        sendState: sendState,
        failureMessage: failureMessage
      )
      logger.info("Updated message send state for \(messageId, privacy: .private)")
    } catch {
      logger.error("Failed to update message send state: \(error.localizedDescription)")
    }
  }

  func saveThreadState(_ state: FriendThreadState) async {
    do {
      try await storeActor.saveThreadState(state)
      logger.info("Saved thread state for \(state.threadId, privacy: .private)")
    } catch {
      logger.error("Failed to save thread state: \(error.localizedDescription)")
    }
  }

  func deleteMessage(id: String, viewerUserId: String) async {
    do {
      try await storeActor.deleteMessage(id: id, viewerUserId: viewerUserId)
      logger.info("Deleted message \(id, privacy: .private)")
    } catch {
      logger.error("Failed to delete message: \(error.localizedDescription)")
    }
  }
}

extension FriendsMessagesRepository: FriendsMessagesRepositoryProviding {}

extension FriendsMessagesRepository {
  fileprivate func deduplicateMessages(_ messages: [FriendMessage], viewerUserId: String)
    -> [FriendMessage]
  {
    var bestMessageByDeduplicationKey: [String: FriendMessage] = [:]
    var orderedMessages: [FriendMessage] = []

    for message in messages {
      guard let deduplicationKey = deduplicationKey(for: message, viewerUserId: viewerUserId) else {
        orderedMessages.append(message)
        continue
      }

      if let existing = bestMessageByDeduplicationKey[deduplicationKey] {
        bestMessageByDeduplicationKey[deduplicationKey] = preferredMessage(
          between: existing, and: message)
      } else {
        bestMessageByDeduplicationKey[deduplicationKey] = message
      }
    }

    let deduplicated = orderedMessages + bestMessageByDeduplicationKey.values
    return deduplicated.sorted {
      if $0.createdAt == $1.createdAt {
        return $0.id < $1.id
      }
      return $0.createdAt < $1.createdAt
    }
  }

  fileprivate func deduplicationKey(for message: FriendMessage, viewerUserId: String) -> String? {
    guard message.senderUserId == viewerUserId else { return nil }
    let normalizedClientId = message.clientId.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !normalizedClientId.isEmpty else { return nil }
    return "\(message.senderUserId):\(normalizedClientId)"
  }

  fileprivate func preferredMessage(between lhs: FriendMessage, and rhs: FriendMessage)
    -> FriendMessage
  {
    let lhsScore = messagePreferenceScore(lhs)
    let rhsScore = messagePreferenceScore(rhs)

    if lhsScore == rhsScore {
      if lhs.createdAt == rhs.createdAt {
        return lhs.id < rhs.id ? lhs : rhs
      }
      return lhs.createdAt >= rhs.createdAt ? lhs : rhs
    }

    return lhsScore > rhsScore ? lhs : rhs
  }

  fileprivate func messagePreferenceScore(_ message: FriendMessage) -> Int {
    let stateScore: Int
    switch message.sendState {
    case .sent:
      stateScore = 3
    case .failed:
      stateScore = 2
    case .sending:
      stateScore = 1
    }

    let localPenalty = message.id.hasPrefix("local-") ? 0 : 1
    return (stateScore * 10) + localPenalty
  }
}
