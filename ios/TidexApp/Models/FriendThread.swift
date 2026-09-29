import Foundation

internal struct FriendThread: Identifiable, Codable, Equatable {
  internal let id: String
  internal let kind: FriendThreadKind
  internal let title: String?
  internal let avatarUrl: String?
  internal let metadataData: Data?
  internal let counterpartUserId: String?
  internal let counterpartDisplayName: String?
  internal let counterpartProfilePictureUrl: String?
  internal let counterpartOAuthAvatarUrl: String?
  internal let lastMessageId: String?
  internal let lastMessageSenderId: String?
  internal let lastMessageAt: Date?
  internal let lastMessageBody: String?
  internal let lastMessagePreviewKind: FriendLastMessagePreviewKind?
  internal let lastMessageHasImage: Bool
  internal let unreadCount: Int
  internal let muted: Bool
  internal let createdAt: Date

  internal init(
    id: String,
    kind: FriendThreadKind,
    title: String?,
    avatarUrl: String?,
    metadataData: Data? = nil,
    counterpartUserId: String?,
    counterpartDisplayName: String?,
    counterpartProfilePictureUrl: String?,
    counterpartOAuthAvatarUrl: String?,
    lastMessageId: String?,
    lastMessageSenderId: String?,
    lastMessageAt: Date?,
    lastMessageBody: String?,
    lastMessagePreviewKind: FriendLastMessagePreviewKind? = nil,
    lastMessageHasImage: Bool = false,
    unreadCount: Int = 0,
    muted: Bool = false,
    createdAt: Date
  ) {
    self.id = id
    self.kind = kind
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
    self.lastMessagePreviewKind = lastMessagePreviewKind
    self.lastMessageHasImage = lastMessageHasImage
    self.unreadCount = unreadCount
    self.muted = muted
    self.createdAt = createdAt
  }

  internal var counterpartAvatarUrl: String? {
    counterpartProfilePictureUrl ?? counterpartOAuthAvatarUrl
  }

  internal var resolvedLastMessagePreviewKind: FriendLastMessagePreviewKind {
    FriendMessagePreviewPolicy.resolvedPreviewKind(
      explicitPreviewKind: lastMessagePreviewKind,
      body: lastMessageBody,
      hasImageAttachment: lastMessageHasImage
    )
  }

  internal var lastMessagePreviewText: String? {
    guard lastMessageId != nil else {
      return nil
    }
    return FriendMessagePreviewPolicy.previewText(
      body: lastMessageBody,
      previewKind: resolvedLastMessagePreviewKind
    )
  }

  internal var sortTimestamp: Date {
    lastMessageAt ?? createdAt
  }

  internal var paginationCursor: FriendThreadCursor? {
    guard let lastMessageAt else {
      return nil
    }
    return FriendThreadCursor(lastMessageAt: lastMessageAt, threadId: id)
  }
}

internal struct FriendThreadState: Codable, Equatable {
  internal let threadId: String
  internal let userId: String
  internal let lastReadMessageId: String?
  internal let lastReadAt: Date?
  internal let muted: Bool
  internal let updatedAt: Date
}

internal struct FriendMessageAttachment: Identifiable, Codable, Equatable {
  internal let id: String
  internal let attachmentIndex: Int
  internal let kind: FriendMessageAttachmentKind
  internal let storageBucket: String
  internal let storagePath: String
  internal let mimeType: String
  internal let byteSize: Int64
  internal let width: Int?
  internal let height: Int?
  internal let createdAt: Date
  internal let reactions: [FriendMessageReaction]

  internal enum CodingKeys: String, CodingKey {
    case id
    case attachmentIndex
    case kind
    case storageBucket
    case storagePath
    case mimeType
    case byteSize
    case width
    case height
    case createdAt
    case reactions
  }

  internal init(
    id: String,
    attachmentIndex: Int,
    kind: FriendMessageAttachmentKind,
    storageBucket: String,
    storagePath: String,
    mimeType: String,
    byteSize: Int64,
    width: Int?,
    height: Int?,
    createdAt: Date,
    reactions: [FriendMessageReaction] = []
  ) {
    self.id = id
    self.attachmentIndex = attachmentIndex
    self.kind = kind
    self.storageBucket = storageBucket
    self.storagePath = storagePath
    self.mimeType = mimeType
    self.byteSize = byteSize
    self.width = width
    self.height = height
    self.createdAt = createdAt
    self.reactions = reactions
  }

  internal init(from decoder: Decoder) throws {
    let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(
      keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    attachmentIndex = try container.decode(Int.self, forKey: .attachmentIndex)
    kind = try container.decode(FriendMessageAttachmentKind.self, forKey: .kind)
    storageBucket = try container.decode(String.self, forKey: .storageBucket)
    storagePath = try container.decode(String.self, forKey: .storagePath)
    mimeType = try container.decode(String.self, forKey: .mimeType)
    byteSize = try container.decode(Int64.self, forKey: .byteSize)
    width = try container.decodeIfPresent(Int.self, forKey: .width)
    height = try container.decodeIfPresent(Int.self, forKey: .height)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    reactions =
      try container.decodeIfPresent([FriendMessageReaction].self, forKey: .reactions) ?? []
  }

  internal func withReactions(_ reactions: [FriendMessageReaction]) -> Self {
    Self(
      id: id,
      attachmentIndex: attachmentIndex,
      kind: kind,
      storageBucket: storageBucket,
      storagePath: storagePath,
      mimeType: mimeType,
      byteSize: byteSize,
      width: width,
      height: height,
      createdAt: createdAt,
      reactions: reactions
    )
  }

  internal func toggledReaction(emoji: String) -> Self {
    withReactions(FriendMessage.toggledReactions(reactions, emoji: emoji))
  }
}

internal struct FriendMessageReaction: Identifiable, Codable, Equatable, Hashable {
  internal var id: String { emoji }

  internal let emoji: String
  internal let count: Int
  internal let viewerHasReacted: Bool
}
