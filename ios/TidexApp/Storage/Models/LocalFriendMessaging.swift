import Foundation
import SwiftData

// MARK: - Local Thread

@Model
final class LocalThread {
  @Attribute(.unique)
  var compositeKey: String
  var id: String
  var viewerUserId: String
  var kindRaw: String
  var title: String?
  var avatarUrl: String?
  var metadataData: Data
  var counterpartUserId: String?
  var counterpartDisplayName: String?
  var counterpartProfilePictureUrl: String?
  var counterpartOAuthAvatarUrl: String?
  var lastMessageId: String?
  var lastMessageSenderId: String?
  var lastMessageAt: Date?
  var lastMessageBody: String?
  var lastMessageHasImage: Bool
  var unreadCount: Int
  var muted: Bool
  var createdAt: Date
  var sortTimestamp: Date
  var updatedAt: Date

  init(
    id: String,
    viewerUserId: String,
    kindRaw: String,
    title: String?,
    avatarUrl: String?,
    metadataData: Data = Data(),
    counterpartUserId: String?,
    counterpartDisplayName: String?,
    counterpartProfilePictureUrl: String?,
    counterpartOAuthAvatarUrl: String?,
    lastMessageId: String?,
    lastMessageSenderId: String?,
    lastMessageAt: Date?,
    lastMessageBody: String?,
    lastMessageHasImage: Bool,
    unreadCount: Int,
    muted: Bool,
    createdAt: Date,
    updatedAt: Date = Date()
  ) {
    self.compositeKey = "\(viewerUserId):\(id)"
    self.id = id
    self.viewerUserId = viewerUserId
    self.kindRaw = kindRaw
    self.title = title
    self.avatarUrl = avatarUrl
    self.metadataData = metadataData
    self.counterpartUserId = counterpartUserId
    self.counterpartDisplayName = counterpartDisplayName
    self.counterpartProfilePictureUrl = counterpartProfilePictureUrl
    self.counterpartOAuthAvatarUrl = counterpartOAuthAvatarUrl
    self.lastMessageId = lastMessageId
    self.lastMessageSenderId = lastMessageSenderId
    self.lastMessageAt = lastMessageAt
    self.lastMessageBody = lastMessageBody
    self.lastMessageHasImage = lastMessageHasImage
    self.unreadCount = unreadCount
    self.muted = muted
    self.createdAt = createdAt
    self.sortTimestamp = lastMessageAt ?? createdAt
    self.updatedAt = updatedAt
  }
}

// MARK: - Local Thread State

@Model
final class LocalThreadState {
  @Attribute(.unique)
  var compositeKey: String
  var threadId: String
  var userId: String
  var lastReadMessageId: String?
  var lastReadAt: Date?
  var muted: Bool
  var updatedAt: Date

  init(
    threadId: String,
    userId: String,
    lastReadMessageId: String? = nil,
    lastReadAt: Date? = nil,
    muted: Bool = false,
    updatedAt: Date = Date()
  ) {
    self.compositeKey = "\(userId):\(threadId)"
    self.threadId = threadId
    self.userId = userId
    self.lastReadMessageId = lastReadMessageId
    self.lastReadAt = lastReadAt
    self.muted = muted
    self.updatedAt = updatedAt
  }
}

// MARK: - Local Message

@Model
final class LocalMessage {
  @Attribute(.unique)
  var compositeKey: String
  var id: String
  var viewerUserId: String
  var threadId: String
  var senderUserId: String
  var messageTypeRaw: String
  var body: String?
  var clientId: String
  var replyToMessageId: String?
  var createdAt: Date
  var editedAt: Date?
  var deletedAt: Date?
  var metadataData: Data
  var updatedAt: Date

  init(
    id: String,
    viewerUserId: String,
    threadId: String,
    senderUserId: String,
    messageTypeRaw: String,
    body: String?,
    clientId: String,
    replyToMessageId: String?,
    createdAt: Date,
    editedAt: Date?,
    deletedAt: Date?,
    metadataData: Data = Data(),
    updatedAt: Date = Date()
  ) {
    self.compositeKey = "\(viewerUserId):\(id)"
    self.id = id
    self.viewerUserId = viewerUserId
    self.threadId = threadId
    self.senderUserId = senderUserId
    self.messageTypeRaw = messageTypeRaw
    self.body = body
    self.clientId = clientId
    self.replyToMessageId = replyToMessageId
    self.createdAt = createdAt
    self.editedAt = editedAt
    self.deletedAt = deletedAt
    self.metadataData = metadataData
    self.updatedAt = updatedAt
  }
}

// MARK: - Local Message Attachment

@Model
final class LocalMessageAttachment {
  @Attribute(.unique)
  var compositeKey: String
  var id: String
  var viewerUserId: String
  var threadId: String
  var messageId: String
  var attachmentIndex: Int
  var kindRaw: String
  var storageBucket: String
  var storagePath: String
  var mimeType: String
  var byteSize: Int64
  var width: Int?
  var height: Int?
  var createdAt: Date
  var updatedAt: Date

  init(
    id: String,
    viewerUserId: String,
    threadId: String,
    messageId: String,
    attachmentIndex: Int,
    kindRaw: String,
    storageBucket: String,
    storagePath: String,
    mimeType: String,
    byteSize: Int64,
    width: Int?,
    height: Int?,
    createdAt: Date,
    updatedAt: Date = Date()
  ) {
    self.compositeKey = "\(viewerUserId):\(id)"
    self.id = id
    self.viewerUserId = viewerUserId
    self.threadId = threadId
    self.messageId = messageId
    self.attachmentIndex = attachmentIndex
    self.kindRaw = kindRaw
    self.storageBucket = storageBucket
    self.storagePath = storagePath
    self.mimeType = mimeType
    self.byteSize = byteSize
    self.width = width
    self.height = height
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

// MARK: - Conversions

extension LocalThread {
  func toFriendThread() -> FriendThread {
    FriendThread(
      id: id,
      kind: FriendThreadKind(rawValue: kindRaw) ?? .direct,
      title: title,
      avatarUrl: avatarUrl,
      metadataData: metadataData.isEmpty ? nil : metadataData,
      counterpartUserId: counterpartUserId,
      counterpartDisplayName: counterpartDisplayName,
      counterpartProfilePictureUrl: counterpartProfilePictureUrl,
      counterpartOAuthAvatarUrl: counterpartOAuthAvatarUrl,
      lastMessageId: lastMessageId,
      lastMessageSenderId: lastMessageSenderId,
      lastMessageAt: lastMessageAt,
      lastMessageBody: lastMessageBody,
      lastMessageHasImage: lastMessageHasImage,
      unreadCount: unreadCount,
      muted: muted,
      createdAt: createdAt
    )
  }

  func apply(thread: FriendThread) {
    kindRaw = thread.kind.rawValue
    title = thread.title
    avatarUrl = thread.avatarUrl
    metadataData = thread.metadataData ?? Data()
    counterpartUserId = thread.counterpartUserId
    counterpartDisplayName = thread.counterpartDisplayName
    counterpartProfilePictureUrl = thread.counterpartProfilePictureUrl
    counterpartOAuthAvatarUrl = thread.counterpartOAuthAvatarUrl
    lastMessageId = thread.lastMessageId
    lastMessageSenderId = thread.lastMessageSenderId
    lastMessageAt = thread.lastMessageAt
    lastMessageBody = thread.lastMessageBody
    lastMessageHasImage = thread.lastMessageHasImage
    unreadCount = thread.unreadCount
    muted = thread.muted
    createdAt = thread.createdAt
    sortTimestamp = thread.sortTimestamp
    updatedAt = Date()
  }
}

extension LocalThreadState {
  func toFriendThreadState() -> FriendThreadState {
    FriendThreadState(
      threadId: threadId,
      userId: userId,
      lastReadMessageId: lastReadMessageId,
      lastReadAt: lastReadAt,
      muted: muted,
      updatedAt: updatedAt
    )
  }

  func apply(state: FriendThreadState) {
    lastReadMessageId = state.lastReadMessageId
    lastReadAt = state.lastReadAt
    muted = state.muted
    updatedAt = state.updatedAt
  }
}

extension LocalMessageAttachment {
  func toFriendMessageAttachment() -> FriendMessageAttachment {
    FriendMessageAttachment(
      id: id,
      attachmentIndex: attachmentIndex,
      kind: FriendMessageAttachmentKind(rawValue: kindRaw) ?? .image,
      storageBucket: storageBucket,
      storagePath: storagePath,
      mimeType: mimeType,
      byteSize: byteSize,
      width: width,
      height: height,
      createdAt: createdAt
    )
  }
}

extension LocalMessage {
  func toFriendMessage(attachments: [LocalMessageAttachment]) -> FriendMessage {
    FriendMessage(
      id: id,
      threadId: threadId,
      senderUserId: senderUserId,
      messageType: FriendMessageType(rawValue: messageTypeRaw) ?? .user,
      body: body,
      clientId: clientId,
      replyToMessageId: replyToMessageId,
      createdAt: createdAt,
      editedAt: editedAt,
      deletedAt: deletedAt,
      metadataData: metadataData.isEmpty ? nil : metadataData,
      attachments:
        attachments
        .sorted {
          if $0.attachmentIndex == $1.attachmentIndex {
            return $0.id < $1.id
          }
          return $0.attachmentIndex < $1.attachmentIndex
        }
        .map { $0.toFriendMessageAttachment() }
    )
  }

  func apply(message: FriendMessage) {
    senderUserId = message.senderUserId
    messageTypeRaw = message.messageType.rawValue
    body = message.body
    clientId = message.clientId
    replyToMessageId = message.replyToMessageId
    createdAt = message.createdAt
    editedAt = message.editedAt
    deletedAt = message.deletedAt
    metadataData = message.metadataData ?? Data()
    updatedAt = Date()
  }
}
