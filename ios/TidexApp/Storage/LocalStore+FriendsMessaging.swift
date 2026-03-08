import Foundation
import SwiftData

extension LocalStoreActor {
  func saveThreadSummaries(_ threads: [FriendThread], for viewerUserId: String) throws {
    for thread in threads {
      try saveThreadSummary(thread, for: viewerUserId)
    }
    try modelContext.save()
  }

  func saveThreadSummary(_ thread: FriendThread, for viewerUserId: String) throws {
    let threadId = thread.id
    let descriptor = FetchDescriptor<LocalThread>(
      predicate: #Predicate { localThread in
        localThread.id == threadId && localThread.viewerUserId == viewerUserId
      }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      existing.apply(thread: thread)
    } else {
      modelContext.insert(
        LocalThread(
          id: threadId,
          viewerUserId: viewerUserId,
          kindRaw: thread.kind.rawValue,
          title: thread.title,
          avatarUrl: thread.avatarUrl,
          metadataData: thread.metadataData ?? Data(),
          counterpartUserId: thread.counterpartUserId,
          counterpartDisplayName: thread.counterpartDisplayName,
          counterpartProfilePictureUrl: thread.counterpartProfilePictureUrl,
          counterpartOAuthAvatarUrl: thread.counterpartOAuthAvatarUrl,
          lastMessageId: thread.lastMessageId,
          lastMessageSenderId: thread.lastMessageSenderId,
          lastMessageAt: thread.lastMessageAt,
          lastMessageBody: thread.lastMessageBody,
          lastMessageHasImage: thread.lastMessageHasImage,
          unreadCount: thread.unreadCount,
          muted: thread.muted,
          createdAt: thread.createdAt
        ))
    }

    try upsertThreadState(
      FriendThreadState(
        threadId: thread.id,
        userId: viewerUserId,
        lastReadMessageId: nil,
        lastReadAt: nil,
        muted: thread.muted,
        updatedAt: Date()
      ),
      updateReadMarker: false
    )
  }

  func saveMessages(_ messages: [FriendMessage], in threadId: String, for viewerUserId: String)
    throws
  {
    for message in messages {
      try saveMessage(message, in: threadId, for: viewerUserId)
    }
    try modelContext.save()
  }

  func saveMessage(_ message: FriendMessage, in threadId: String, for viewerUserId: String) throws {
    let messageId = message.id
    let descriptor = FetchDescriptor<LocalMessage>(
      predicate: #Predicate { localMessage in
        localMessage.id == messageId && localMessage.viewerUserId == viewerUserId
      }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      existing.apply(message: message)
    } else {
      modelContext.insert(
        LocalMessage(
          id: messageId,
          viewerUserId: viewerUserId,
          threadId: threadId,
          senderUserId: message.senderUserId,
          messageTypeRaw: message.messageType.rawValue,
          body: message.body,
          clientId: message.clientId,
          replyToMessageId: message.replyToMessageId,
          createdAt: message.createdAt,
          editedAt: message.editedAt,
          deletedAt: message.deletedAt,
          metadataData: message.metadataData ?? Data()
        ))
    }

    try replaceAttachments(for: message, viewerUserId: viewerUserId)
    try updateThreadPreviewIfNeeded(for: message, viewerUserId: viewerUserId)
  }

  func saveThreadState(_ state: FriendThreadState) throws {
    try upsertThreadState(state, updateReadMarker: true)
    try modelContext.save()
  }

  private func upsertThreadState(_ state: FriendThreadState, updateReadMarker: Bool) throws {
    let stateUserId = state.userId
    let stateThreadId = state.threadId
    let compositeKey = "\(stateUserId):\(stateThreadId)"
    let descriptor = FetchDescriptor<LocalThreadState>(
      predicate: #Predicate { $0.compositeKey == compositeKey }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      if updateReadMarker {
        existing.apply(state: state)
      } else {
        existing.muted = state.muted
        existing.updatedAt = state.updatedAt
      }
    } else {
      modelContext.insert(
        LocalThreadState(
          threadId: stateThreadId,
          userId: stateUserId,
          lastReadMessageId: updateReadMarker ? state.lastReadMessageId : nil,
          lastReadAt: updateReadMarker ? state.lastReadAt : nil,
          muted: state.muted,
          updatedAt: state.updatedAt
        ))
    }

    let threadDescriptor = FetchDescriptor<LocalThread>(
      predicate: #Predicate { localThread in
        localThread.id == stateThreadId && localThread.viewerUserId == stateUserId
      }
    )

    if let localThread = try modelContext.fetch(threadDescriptor).first {
      localThread.muted = state.muted
      if updateReadMarker, state.lastReadMessageId != nil {
        localThread.unreadCount = 0
      }
      localThread.updatedAt = Date()
    }
  }

  private func replaceAttachments(for message: FriendMessage, viewerUserId: String) throws {
    let messageId = message.id
    let descriptor = FetchDescriptor<LocalMessageAttachment>(
      predicate: #Predicate { attachment in
        attachment.messageId == messageId && attachment.viewerUserId == viewerUserId
      }
    )

    for existing in try modelContext.fetch(descriptor) {
      modelContext.delete(existing)
    }

    for attachment in message.attachments {
      modelContext.insert(
        LocalMessageAttachment(
          id: attachment.id,
          viewerUserId: viewerUserId,
          threadId: message.threadId,
          messageId: message.id,
          attachmentIndex: attachment.attachmentIndex,
          kindRaw: attachment.kind.rawValue,
          storageBucket: attachment.storageBucket,
          storagePath: attachment.storagePath,
          mimeType: attachment.mimeType,
          byteSize: attachment.byteSize,
          width: attachment.width,
          height: attachment.height,
          createdAt: attachment.createdAt
        ))
    }
  }

  private func updateThreadPreviewIfNeeded(for message: FriendMessage, viewerUserId: String) throws
  {
    let threadId = message.threadId
    let descriptor = FetchDescriptor<LocalThread>(
      predicate: #Predicate { localThread in
        localThread.id == threadId && localThread.viewerUserId == viewerUserId
      }
    )

    guard let thread = try modelContext.fetch(descriptor).first else { return }

    let shouldReplacePreview: Bool
    if let existingDate = thread.lastMessageAt, let existingId = thread.lastMessageId {
      shouldReplacePreview = (message.createdAt, message.id) >= (existingDate, existingId)
    } else {
      shouldReplacePreview = true
    }

    guard shouldReplacePreview else { return }

    thread.lastMessageId = message.id
    thread.lastMessageSenderId = message.senderUserId
    thread.lastMessageAt = message.createdAt
    thread.lastMessageBody = message.body
    thread.lastMessageHasImage = message.hasImageAttachment
    thread.sortTimestamp = message.createdAt
    thread.updatedAt = Date()
  }
}
