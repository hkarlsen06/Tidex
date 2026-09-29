import Foundation

// MARK: - Friends Messaging Domain Models

internal enum FriendThreadKind: String, Codable, Equatable {
  case direct
  case room
  case feed
}

internal enum FriendMessageType: String, Codable, Equatable {
  case user
  case system
}

internal enum FriendMessageAttachmentKind: String, Codable, Equatable {
  case image
}

internal enum FriendMessageSendState: String, Codable, Equatable {
  case sending
  case sent
  case failed
}

internal enum FriendAbuseReportReason: String, Codable, CaseIterable, Equatable {
  case harassmentOrBullying = "harassment_or_bullying"
  case sexualContent = "sexual_content"
  case hateOrDiscriminatoryContent = "hate_or_discriminatory_content"
  case violenceOrThreats = "violence_or_threats"
  case spam
  case inappropriateProfileOrConduct = "inappropriate_profile_or_conduct"
  case other
}

internal struct FriendThreadCursor: Equatable {
  internal let lastMessageAt: Date
  internal let threadId: String
}

internal struct FriendMessageCursor: Equatable {
  internal let createdAt: Date
  internal let messageId: String
}

internal struct FriendInboxSyncSnapshot: Equatable {
  internal let threads: [FriendThread]
  internal let unreadDirectMessageCount: Int
  internal let nextCursor: FriendThreadCursor?
  internal let snapshotVersion: Int64
  internal let retainedFromVersion: Int64
  internal let hasMore: Bool
}

internal struct FriendThreadCounterpartPresence: Equatable {
  internal let userId: String
  internal let displayName: String?
  internal let profilePictureUrl: String?
  internal let oauthAvatarUrl: String?
}

internal struct FriendThreadSyncSnapshot: Equatable {
  internal let thread: FriendThread
  internal let viewerState: FriendThreadState
  internal let counterpartPresence: FriendThreadCounterpartPresence?
  internal let messages: [FriendMessage]
  internal let nextCursor: FriendMessageCursor?
  internal let snapshotVersion: Int64
  internal let retainedFromVersion: Int64
  internal let hasMore: Bool
}

internal enum FriendMessagingSyncScope: Equatable {
  case inbox
  case thread(threadId: String)
}

internal struct FriendMessagingSyncState: Equatable {
  internal let viewerUserId: String
  internal let scope: FriendMessagingSyncScope
  internal let version: Int64
  internal let retainedFromVersion: Int64
  internal let updatedAt: Date
}

internal struct FriendInboxSyncEvent: Equatable {
  internal enum EventType: String, Equatable {
    case threadUpserted = "thread_upserted"
    case threadRemoved = "thread_removed"
  }

  internal let id: String
  internal let version: Int64
  internal let threadId: String?
  internal let eventType: EventType
  internal let thread: FriendThread?
}

internal struct FriendInboxSyncEventsPage: Equatable {
  internal let requiresSnapshot: Bool
  internal let latestVersion: Int64
  internal let retainedFromVersion: Int64
  internal let hasMore: Bool
  internal let events: [FriendInboxSyncEvent]
}

internal struct FriendThreadSyncEvent: Equatable {
  internal enum EventType: String, Equatable {
    case messageUpserted = "message_upserted"
    case messageDeleted = "message_deleted"
  }

  internal let id: String
  internal let version: Int64
  internal let eventType: EventType
  internal let message: FriendMessage?
  internal let deletedMessageId: String?
}

internal struct FriendThreadSyncEventsPage: Equatable {
  internal let requiresSnapshot: Bool
  internal let latestVersion: Int64
  internal let retainedFromVersion: Int64
  internal let hasMore: Bool
  internal let events: [FriendThreadSyncEvent]
}

internal struct FriendThreadMessagesPage: Equatable {
  internal let messages: [FriendMessage]
  internal let nextCursor: FriendMessageCursor?
  internal let hasMore: Bool
}

internal enum FriendLastMessagePreviewKind: String, Codable, Equatable {
  case text
  case image
  case shiftSnapshot = "shift_snapshot"
  case unknown
}

internal enum FriendRichContentKind: Equatable {
  case shiftSnapshot
  case unsupported(String)
}

internal enum FriendRichContent: Equatable {
  case shiftSnapshot(FriendShiftSnapshot)
}

extension ImageAttachment: Codable {
  private enum CodingKeys: String, CodingKey {
    case id
    case data
    case mediaType
  }

  public init(from decoder: Decoder) throws {
    let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(
      keyedBy: CodingKeys.self)
    let id: String = try container.decode(String.self, forKey: .id)
    let data: Data = try container.decode(Data.self, forKey: .data)
    let mediaType: String = try container.decode(String.self, forKey: .mediaType)
    self.init(id: id, data: data, mediaType: mediaType)
  }

  public func encode(to encoder: Encoder) throws {
    var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(data, forKey: .data)
    try container.encode(mediaType, forKey: .mediaType)
  }
}
