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
  var lastMessagePreviewKindRaw: String?
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
    lastMessagePreviewKindRaw: String? = nil,
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
    self.lastMessagePreviewKindRaw = lastMessagePreviewKindRaw
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

// MARK: - Local Thread Feed Placement

@Model
final class LocalThreadFeedPlacement {
  @Attribute(.unique)
  var compositeKey: String
  var viewerUserId: String
  var friendUserId: String
  var threadId: String?
  var baselineLastMessageId: String?
  var baselineLastMessageAt: Date?
  var createdAt: Date
  var updatedAt: Date

  init(
    viewerUserId: String,
    friendUserId: String,
    threadId: String?,
    baselineLastMessageId: String?,
    baselineLastMessageAt: Date?,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.compositeKey = "\(viewerUserId):\(friendUserId)"
    self.viewerUserId = viewerUserId
    self.friendUserId = friendUserId
    self.threadId = threadId
    self.baselineLastMessageId = baselineLastMessageId
    self.baselineLastMessageAt = baselineLastMessageAt
    self.createdAt = createdAt
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
  var sendStateRaw: String?
  var failureMessage: String?
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
    sendStateRaw: String? = FriendMessageSendState.sent.rawValue,
    failureMessage: String? = nil,
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
    self.sendStateRaw = sendStateRaw
    self.failureMessage = failureMessage
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

// MARK: - Local Message Reaction

@Model
final class LocalMessageReaction {
  @Attribute(.unique)
  var compositeKey: String
  var viewerUserId: String
  var threadId: String
  var messageId: String
  var reactionIndex: Int
  var emoji: String
  var count: Int
  var viewerHasReacted: Bool
  var updatedAt: Date

  init(
    viewerUserId: String,
    threadId: String,
    messageId: String,
    reactionIndex: Int,
    emoji: String,
    count: Int,
    viewerHasReacted: Bool,
    updatedAt: Date = Date()
  ) {
    self.compositeKey = "\(viewerUserId):\(messageId):\(emoji)"
    self.viewerUserId = viewerUserId
    self.threadId = threadId
    self.messageId = messageId
    self.reactionIndex = reactionIndex
    self.emoji = emoji
    self.count = count
    self.viewerHasReacted = viewerHasReacted
    self.updatedAt = updatedAt
  }
}

@Model
final class LocalFriendMessagingSyncState {
  @Attribute(.unique)
  var compositeKey: String
  var viewerUserId: String
  var scopeRaw: String
  var threadId: String?
  var version: Int64
  var retainedFromVersion: Int64
  var updatedAt: Date

  init(
    viewerUserId: String,
    scopeRaw: String,
    threadId: String? = nil,
    version: Int64 = 0,
    retainedFromVersion: Int64 = 0,
    updatedAt: Date = Date()
  ) {
    self.compositeKey = Self.makeCompositeKey(
      viewerUserId: viewerUserId,
      scopeRaw: scopeRaw,
      threadId: threadId
    )
    self.viewerUserId = viewerUserId
    self.scopeRaw = scopeRaw
    self.threadId = threadId
    self.version = version
    self.retainedFromVersion = retainedFromVersion
    self.updatedAt = updatedAt
  }

  static func makeCompositeKey(viewerUserId: String, scopeRaw: String, threadId: String?) -> String
  {
    if let threadId {
      return "\(viewerUserId):\(scopeRaw):\(threadId)"
    }

    return "\(viewerUserId):\(scopeRaw)"
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
      lastMessagePreviewKind: lastMessagePreviewKindRaw.flatMap(FriendLastMessagePreviewKind.init),
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
    lastMessagePreviewKindRaw = thread.lastMessagePreviewKind?.rawValue
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
  func toFriendMessage(
    attachments: [LocalMessageAttachment],
    reactions: [LocalMessageReaction]
  ) -> FriendMessage {
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
        .map { $0.toFriendMessageAttachment() },
      reactions:
        reactions
        .sorted {
          if $0.reactionIndex == $1.reactionIndex {
            return $0.emoji < $1.emoji
          }
          return $0.reactionIndex < $1.reactionIndex
        }
        .map {
          FriendMessageReaction(
            emoji: $0.emoji,
            count: $0.count,
            viewerHasReacted: $0.viewerHasReacted
          )
        },
      sendState: FriendMessageSendState(
        rawValue: sendStateRaw ?? FriendMessageSendState.sent.rawValue) ?? .sent,
      failureMessage: failureMessage
    )
  }

  func apply(message: FriendMessage) {
    senderUserId = message.senderUserId
    messageTypeRaw = message.messageType.rawValue
    body = message.body
    clientId = message.clientId.lowercased()
    replyToMessageId = message.replyToMessageId
    createdAt = message.createdAt
    editedAt = message.editedAt
    deletedAt = message.deletedAt
    metadataData = message.metadataData ?? Data()
    sendStateRaw = message.sendState.rawValue
    failureMessage = message.failureMessage
    updatedAt = Date()
  }
}

extension LocalFriendMessagingSyncState {
  func toFriendMessagingSyncState() -> FriendMessagingSyncState {
    let scope: FriendMessagingSyncScope
    if scopeRaw == "thread", let threadId {
      scope = .thread(threadId: threadId)
    } else {
      scope = .inbox
    }

    return FriendMessagingSyncState(
      viewerUserId: viewerUserId,
      scope: scope,
      version: version,
      retainedFromVersion: retainedFromVersion,
      updatedAt: updatedAt
    )
  }
}
