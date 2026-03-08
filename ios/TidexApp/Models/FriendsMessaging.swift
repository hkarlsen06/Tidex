import Foundation

// MARK: - Friends Messaging Domain Models

enum FriendThreadKind: String, Codable, Equatable {
  case direct
  case room
  case feed
}

enum FriendMessageType: String, Codable, Equatable {
  case user
  case system
}

enum FriendMessageAttachmentKind: String, Codable, Equatable {
  case image
}

enum FriendMessageSendState: String, Codable, Equatable {
  case sending
  case sent
  case failed
}

enum FriendAbuseReportReason: String, Codable, CaseIterable, Equatable {
  case harassmentOrBullying = "harassment_or_bullying"
  case sexualContent = "sexual_content"
  case hateOrDiscriminatoryContent = "hate_or_discriminatory_content"
  case violenceOrThreats = "violence_or_threats"
  case spam = "spam"
  case inappropriateProfileOrConduct = "inappropriate_profile_or_conduct"
  case other
}

struct FriendThreadCursor: Equatable {
  let lastMessageAt: Date
  let threadId: String
}

struct FriendMessageCursor: Equatable {
  let createdAt: Date
  let messageId: String
}

struct FriendThread: Identifiable, Codable, Equatable {
  let id: String
  let kind: FriendThreadKind
  let title: String?
  let avatarUrl: String?
  let metadataData: Data?
  let counterpartUserId: String?
  let counterpartDisplayName: String?
  let counterpartProfilePictureUrl: String?
  let counterpartOAuthAvatarUrl: String?
  let lastMessageId: String?
  let lastMessageSenderId: String?
  let lastMessageAt: Date?
  let lastMessageBody: String?
  let lastMessageHasImage: Bool
  let unreadCount: Int
  let muted: Bool
  let createdAt: Date

  var counterpartAvatarUrl: String? {
    counterpartProfilePictureUrl ?? counterpartOAuthAvatarUrl
  }

  var sortTimestamp: Date {
    lastMessageAt ?? createdAt
  }

  var paginationCursor: FriendThreadCursor? {
    guard let lastMessageAt else { return nil }
    return FriendThreadCursor(lastMessageAt: lastMessageAt, threadId: id)
  }
}

struct FriendThreadState: Codable, Equatable {
  let threadId: String
  let userId: String
  let lastReadMessageId: String?
  let lastReadAt: Date?
  let muted: Bool
  let updatedAt: Date
}

struct FriendMessageAttachment: Identifiable, Codable, Equatable {
  let id: String
  let attachmentIndex: Int
  let kind: FriendMessageAttachmentKind
  let storageBucket: String
  let storagePath: String
  let mimeType: String
  let byteSize: Int64
  let width: Int?
  let height: Int?
  let createdAt: Date
}

struct FriendMessage: Identifiable, Codable, Equatable {
  let id: String
  let threadId: String
  let senderUserId: String
  let messageType: FriendMessageType
  let body: String?
  let clientId: String
  let replyToMessageId: String?
  let createdAt: Date
  let editedAt: Date?
  let deletedAt: Date?
  let metadataData: Data?
  let attachments: [FriendMessageAttachment]
  let sendState: FriendMessageSendState
  let failureMessage: String?

  var hasImageAttachment: Bool {
    attachments.contains { $0.kind == .image }
  }

  var canRetrySend: Bool {
    sendState == .failed
  }

  var paginationCursor: FriendMessageCursor {
    FriendMessageCursor(createdAt: createdAt, messageId: id)
  }

  func withSendState(
    _ sendState: FriendMessageSendState,
    failureMessage: String? = nil
  ) -> FriendMessage {
    FriendMessage(
      id: id,
      threadId: threadId,
      senderUserId: senderUserId,
      messageType: messageType,
      body: body,
      clientId: clientId,
      replyToMessageId: replyToMessageId,
      createdAt: createdAt,
      editedAt: editedAt,
      deletedAt: deletedAt,
      metadataData: metadataData,
      attachments: attachments,
      sendState: sendState,
      failureMessage: failureMessage
    )
  }
}

struct FriendOutgoingAttachment: Codable, Equatable {
  let attachmentId: String
  let storagePath: String
  let mimeType: String
  let byteSize: Int64
  let width: Int?
  let height: Int?

  enum CodingKeys: String, CodingKey {
    case attachmentId = "attachment_id"
    case storagePath = "storage_path"
    case mimeType = "mime_type"
    case byteSize = "byte_size"
    case width
    case height
  }
}
