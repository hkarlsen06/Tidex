import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "FriendsMessagesRepository")

@MainActor
protocol FriendsMessagesRepositoryProviding: AnyObject {
  func saveThread(_ thread: FriendThread, for viewerUserId: String) async
  func saveMessages(_ messages: [FriendMessage], in threadId: String, for viewerUserId: String)
    async
  func saveThreadState(_ state: FriendThreadState) async
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

    do {
      let messages = try context.fetch(messageDescriptor)
      let attachments = try context.fetch(attachmentDescriptor)
      let attachmentsByMessageId = Dictionary(grouping: attachments, by: \.messageId)
      return messages.map { message in
        message.toFriendMessage(attachments: attachmentsByMessageId[message.id] ?? [])
      }
    } catch {
      logger.error("Failed to fetch messages: \(error.localizedDescription)")
      return []
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

  func saveThreadState(_ state: FriendThreadState) async {
    do {
      try await storeActor.saveThreadState(state)
      logger.info("Saved thread state for \(state.threadId, privacy: .private)")
    } catch {
      logger.error("Failed to save thread state: \(error.localizedDescription)")
    }
  }
}

extension FriendsMessagesRepository: FriendsMessagesRepositoryProviding {}
