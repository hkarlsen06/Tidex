import CryptoKit
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

internal struct FriendShiftSnapshot: Codable, Equatable {
  private static let ownerInitialsLimit: Int = 2

  internal let schemaVersion: Int
  internal let ownerUserId: String
  internal let ownerDisplayName: String
  internal let ownerAvatarUrl: String?
  internal let shiftId: String
  internal let jobName: String?
  internal let jobColorHex: String?
  internal let shiftDate: String
  internal let startTime: String
  internal let endTime: String
  internal let paidHours: Double
  internal let currency: String
  internal let includesEarnings: Bool
  internal let grossPay: Double?
  internal let netPay: Double?
  internal let taxEnabled: Bool
  internal let source: String

  internal enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case ownerUserId = "owner_user_id"
    case ownerDisplayName = "owner_display_name"
    case ownerAvatarUrl = "owner_avatar_url"
    case shiftId = "shift_id"
    case jobName = "job_name"
    case jobColorHex = "job_color_hex"
    case shiftDate = "shift_date"
    case startTime = "start_time"
    case endTime = "end_time"
    case paidHours = "paid_hours"
    case currency
    case includesEarnings = "includes_earnings"
    case grossPay = "gross_pay"
    case netPay = "net_pay"
    case taxEnabled = "tax_enabled"
    case source
  }

  internal var isSupportedSchemaVersion: Bool {
    schemaVersion == 1
  }

  internal var ownerFirstName: String {
    let trimmed: String = ownerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return "?"
    }
    return trimmed.components(separatedBy: .whitespacesAndNewlines).first ?? trimmed
  }

  internal var ownerInitials: String {
    let letters: ArraySlice<String.Element> =
      ownerFirstName
      .split(whereSeparator: \.isWhitespace)
      .compactMap(\.first)
      .prefix(Self.ownerInitialsLimit)
    let initials: String = letters.map(String.init).joined()
    return initials.isEmpty ? "?" : initials.uppercased()
  }

  internal var normalizedForTransport: Self {
    Self(
      schemaVersion: schemaVersion,
      ownerUserId: SnapshotRichContentIdentifier.normalizedUUIDString(
        primary: ownerUserId,
        fallbackSeed: "owner:\(ownerUserId)"
      ),
      ownerDisplayName: ownerDisplayName,
      ownerAvatarUrl: ownerAvatarUrl,
      shiftId: SnapshotRichContentIdentifier.normalizedUUIDString(
        primary: shiftId,
        fallbackSeed: "shift:\(shiftId):\(shiftDate):\(startTime):\(endTime)"
      ),
      jobName: jobName,
      jobColorHex: jobColorHex,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      paidHours: paidHours,
      currency: currency,
      includesEarnings: includesEarnings,
      grossPay: grossPay,
      netPay: netPay,
      taxEnabled: taxEnabled,
      source: source
    )
  }

  // swiftlint:disable:next type_contents_order
  internal func applyingEarningsVisibility(_ canSeeEarnings: Bool) -> Self {
    guard !canSeeEarnings else {
      return self
    }

    return Self(
      schemaVersion: schemaVersion,
      ownerUserId: ownerUserId,
      ownerDisplayName: ownerDisplayName,
      ownerAvatarUrl: ownerAvatarUrl,
      shiftId: shiftId,
      jobName: jobName,
      jobColorHex: jobColorHex,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      paidHours: paidHours,
      currency: currency,
      includesEarnings: false,
      grossPay: nil,
      netPay: nil,
      taxEnabled: false,
      source: source
    )
  }

  internal var renderableShift: ShiftWithComputations {
    let gross: Double = grossPay ?? netPay ?? 0
    let resolvedTaxEnabled: Bool = includesEarnings ? taxEnabled : false
    let resolvedTaxPercentage: Double

    if resolvedTaxEnabled, gross > 0, let netPay {
      resolvedTaxPercentage = max(0, min((1 - (netPay / gross)) * 100, 100))
    } else {
      resolvedTaxPercentage = 0
    }

    return ShiftWithComputations(
      shift: ShiftRow(
        id: shiftId,
        user_id: ownerUserId,
        job_id: nil,
        shift_date: shiftDate,
        start_time: startTime,
        end_time: endTime,
        custom_supplements: nil
      ),
      computed: ShiftComputed(
        id: shiftId,
        durationHours: paidHours,
        paidHours: paidHours,
        basePay: gross,
        supplementPay: 0,
        gross: gross,
        wagePeriods: [],
        originalWagePeriods: [],
        breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
      ),
      taxEnabled: resolvedTaxEnabled,
      taxPercentage: resolvedTaxPercentage
    )
  }
}

internal enum SnapshotRichContentIdentifier {
  private static let uuidByteCount: Int = 16
  private static let uuidVersionByteIndex: Int = 6
  private static let uuidVariantByteIndex: Int = 8
  private static let uuidVersionMask: UInt8 = 0x0F
  private static let uuidVersionBits: UInt8 = 0x50
  private static let uuidVariantMask: UInt8 = 0x3F
  private static let uuidVariantBits: UInt8 = 0x80
  private static let uuidPattern: String =
    "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"

  internal static func normalizedUUIDString(primary: String, fallbackSeed: String) -> String {
    if let valid = validUUIDString(from: primary) {
      return valid
    }

    return deterministicUUID(seed: fallbackSeed)
  }

  internal static func normalizedUUIDString(
    primary: String?, secondary: String?, fallbackSeed: String
  )
    -> String
  {
    if let primary, let valid = validUUIDString(from: primary) {
      return valid
    }

    if let secondary, let valid = validUUIDString(from: secondary) {
      return valid
    }

    return deterministicUUID(seed: fallbackSeed)
  }

  private static func validUUIDString(from rawValue: String) -> String? {
    let trimmed: String = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.range(of: uuidPattern, options: .regularExpression) != nil
    else {
      return nil
    }
    return trimmed.lowercased()
  }

  private static func deterministicUUID(seed: String) -> String {
    let digest: SHA256.Digest = SHA256.hash(data: Data(seed.utf8))
    var bytes: [UInt8] = Array(digest.prefix(Self.uuidByteCount))
    bytes[Self.uuidVersionByteIndex] =
      (bytes[Self.uuidVersionByteIndex] & Self.uuidVersionMask) | Self.uuidVersionBits
    bytes[Self.uuidVariantByteIndex] =
      (bytes[Self.uuidVariantByteIndex] & Self.uuidVariantMask) | Self.uuidVariantBits

    let uuid: UUID = UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
      ))
    return uuid.uuidString.lowercased()
  }
}

internal struct ComposerShiftSnapshotDraft: Codable, Equatable {
  internal let snapshot: FriendShiftSnapshot

  internal var ownerDisplayName: String {
    snapshot.ownerDisplayName
  }
}

internal enum FriendsComposerAttachmentLimits {
  internal static let maxImagesPerMessage: Int = 4
}

internal enum FriendsComposerAttachmentDraft: Codable, Equatable {
  case image(ImageAttachment)
  case shiftSnapshot(ComposerShiftSnapshotDraft)

  private enum CodingKeys: String, CodingKey {
    case type
    case image
    case shiftSnapshot = "shift_snapshot"
  }

  private enum DraftType: String, Codable {
    case image
    case shiftSnapshot = "shift_snapshot"
  }

  internal init(from decoder: Decoder) throws {
    let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(
      keyedBy: CodingKeys.self)
    let type: DraftType = try container.decode(DraftType.self, forKey: .type)

    switch type {
    case .image:
      self = .image(try container.decode(ImageAttachment.self, forKey: .image))

    case .shiftSnapshot:
      self = .shiftSnapshot(
        try container.decode(ComposerShiftSnapshotDraft.self, forKey: .shiftSnapshot)
      )
    }
  }

  internal func encode(to encoder: Encoder) throws {
    var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .image(let image):
      try container.encode(DraftType.image, forKey: .type)
      try container.encode(image, forKey: .image)

    case .shiftSnapshot(let draft):
      try container.encode(DraftType.shiftSnapshot, forKey: .type)
      try container.encode(draft, forKey: .shiftSnapshot)
    }
  }

  internal var imageAttachment: ImageAttachment? {
    guard case .image(let image) = self else {
      return nil
    }
    return image
  }

  internal var shiftSnapshotDraft: ComposerShiftSnapshotDraft? {
    guard case .shiftSnapshot(let draft) = self else {
      return nil
    }
    return draft
  }

  internal var shiftSnapshot: FriendShiftSnapshot? {
    shiftSnapshotDraft?.snapshot
  }

  internal var previewKind: FriendLastMessagePreviewKind {
    switch self {
    case .image:
      return .image

    case .shiftSnapshot:
      return .shiftSnapshot
    }
  }

  internal var metadataData: Data? {
    guard let shiftSnapshot else {
      return nil
    }
    return try? JSONEncoder().encode(
      FriendRichContentEnvelope(
        content: FriendRichContentEnvelope.Content(
          kind: FriendLastMessagePreviewKind.shiftSnapshot.rawValue,
          shiftSnapshot: shiftSnapshot.normalizedForTransport
        )
      )
    )
  }
}

extension Array where Element == FriendsComposerAttachmentDraft {
  internal var imageAttachments: [ImageAttachment] {
    compactMap(\.imageAttachment)
  }

  internal var shiftSnapshotDraft: ComposerShiftSnapshotDraft? {
    compactMap(\.shiftSnapshotDraft).first
  }

  internal var shiftSnapshot: FriendShiftSnapshot? {
    shiftSnapshotDraft?.snapshot
  }

  internal var hasImageAttachments: Bool {
    contains { $0.imageAttachment != nil }
  }

  internal var hasShiftSnapshot: Bool {
    contains { $0.shiftSnapshot != nil }
  }

  internal var metadataData: Data? {
    compactMap(\.metadataData).first
  }
}

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

internal struct FriendMessage: Identifiable, Codable, Equatable {
  internal let id: String
  internal let threadId: String
  internal let senderUserId: String
  internal let messageType: FriendMessageType
  internal let body: String?
  internal let clientId: String
  internal let replyToMessageId: String?
  internal let createdAt: Date
  internal let editedAt: Date?
  internal let deletedAt: Date?
  internal let metadataData: Data?
  internal let attachments: [FriendMessageAttachment]
  internal let reactions: [FriendMessageReaction]
  internal let sendState: FriendMessageSendState
  internal let failureMessage: String?

  internal init(
    id: String,
    threadId: String,
    senderUserId: String,
    messageType: FriendMessageType,
    body: String?,
    clientId: String,
    replyToMessageId: String?,
    createdAt: Date,
    editedAt: Date?,
    deletedAt: Date?,
    metadataData: Data? = nil,
    attachments: [FriendMessageAttachment] = [],
    reactions: [FriendMessageReaction] = [],
    sendState: FriendMessageSendState = .sent,
    failureMessage: String? = nil
  ) {
    self.id = id
    self.threadId = threadId
    self.senderUserId = senderUserId
    self.messageType = messageType
    self.body = body
    self.clientId = clientId
    self.replyToMessageId = replyToMessageId
    self.createdAt = createdAt
    self.editedAt = editedAt
    self.deletedAt = deletedAt
    self.metadataData = metadataData
    self.attachments = attachments
    self.reactions = reactions
    self.sendState = sendState
    self.failureMessage = failureMessage
  }

  internal var hasImageAttachment: Bool {
    attachments.contains { $0.kind == .image }
  }

  internal var richContentKind: FriendRichContentKind? {
    FriendRichContentDecoder.richContentKind(from: metadataData)
  }

  internal var richContent: FriendRichContent? {
    FriendRichContentDecoder.richContent(from: metadataData)
  }

  internal var shiftSnapshot: FriendShiftSnapshot? {
    guard case .shiftSnapshot(let snapshot) = richContent else {
      return nil
    }
    return snapshot
  }

  internal var sendableMetadataData: Data? {
    guard let shiftSnapshot else {
      return metadataData
    }
    return try? JSONEncoder().encode(
      FriendRichContentEnvelope(
        content: FriendRichContentEnvelope.Content(
          kind: FriendLastMessagePreviewKind.shiftSnapshot.rawValue,
          shiftSnapshot: shiftSnapshot.normalizedForTransport
        )
      )
    )
  }

  internal var replyIconPreviewKind: FriendLastMessagePreviewKind? {
    if shiftSnapshot != nil {
      return .shiftSnapshot
    }

    if hasImageAttachment {
      return .image
    }

    return nil
  }

  internal var previewKind: FriendLastMessagePreviewKind {
    FriendMessagePreviewPolicy.resolvedPreviewKind(
      body: body,
      richContentKind: richContentKind,
      hasImageAttachment: hasImageAttachment
    )
  }

  internal var previewText: String? {
    FriendMessagePreviewPolicy.previewText(body: body, previewKind: previewKind)
  }

  internal var canRetrySend: Bool {
    sendState == .failed
  }

  internal var normalizedBody: String? {
    guard let body else {
      return nil
    }
    let trimmed: String = body.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  internal var paginationCursor: FriendMessageCursor {
    FriendMessageCursor(createdAt: createdAt, messageId: id)
  }

  internal func logicalRowIdentity(viewerUserId: String) -> String {
    let normalizedClientId: String = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    if senderUserId == viewerUserId, !normalizedClientId.isEmpty {
      return "client:\(normalizedClientId)"
    }

    return "message:\(id)"
  }

  // swiftlint:disable:next type_contents_order
  internal func matchesLogicalRow(of other: Self, viewerUserId: String) -> Bool {
    logicalRowIdentity(viewerUserId: viewerUserId)
      == other.logicalRowIdentity(viewerUserId: viewerUserId)
  }

  internal func canEdit(viewerUserId: String) -> Bool {
    senderUserId == viewerUserId
      && messageType == .user
      && deletedAt == nil
      && sendState == .sent
      && normalizedBody != nil
  }

  internal func canDelete(viewerUserId: String) -> Bool {
    senderUserId == viewerUserId
      && messageType == .user
      && deletedAt == nil
      && (sendState == .sent || sendState == .failed)
  }

  internal func withSendState(
    _ sendState: FriendMessageSendState,
    failureMessage: String? = nil
  ) -> Self {
    Self(
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
      reactions: reactions,
      sendState: sendState,
      failureMessage: failureMessage
    )
  }

  // swiftlint:disable:next type_contents_order
  internal func withEditedBody(_ body: String, editedAt: Date?) -> Self {
    Self(
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
      reactions: reactions,
      sendState: sendState,
      failureMessage: failureMessage
    )
  }

  // swiftlint:disable:next type_contents_order
  internal func withReactions(_ reactions: [FriendMessageReaction]) -> Self {
    Self(
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
      reactions: reactions,
      sendState: sendState,
      failureMessage: failureMessage
    )
  }

  // swiftlint:disable:next type_contents_order
  internal func toggledReaction(emoji: String) -> Self {
    withReactions(Self.toggledReactions(reactions, emoji: emoji))
  }

  // swiftlint:disable:next type_contents_order
  internal func toggledReaction(emoji: String, attachmentId: String?) -> Self {
    guard let attachmentId else {
      return toggledReaction(emoji: emoji)
    }

    var updatedAttachments: [FriendMessageAttachment] = attachments
    guard let attachmentIndex = updatedAttachments.firstIndex(where: { $0.id == attachmentId })
    else {
      return self
    }

    updatedAttachments[attachmentIndex] = updatedAttachments[attachmentIndex]
      .toggledReaction(emoji: emoji)

    return Self(
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
      attachments: updatedAttachments,
      reactions: reactions,
      sendState: sendState,
      failureMessage: failureMessage
    )
  }

  internal var canReact: Bool {
    messageType == .user && deletedAt == nil && sendState == .sent
  }

  internal static func toggledReactions(_ reactions: [FriendMessageReaction], emoji: String)
    -> [FriendMessageReaction]
  {
    let normalizedEmoji: String = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedEmoji.isEmpty else {
      return reactions
    }

    var updatedReactions: [FriendMessageReaction] = reactions

    if let existingIndex = updatedReactions.firstIndex(where: { $0.emoji == normalizedEmoji }) {
      let existingReaction: FriendMessageReaction = updatedReactions[existingIndex]
      if existingReaction.viewerHasReacted {
        let updatedCount: Int = existingReaction.count - 1
        if updatedCount <= 0 {
          updatedReactions.remove(at: existingIndex)
        } else {
          updatedReactions[existingIndex] = FriendMessageReaction(
            emoji: existingReaction.emoji,
            count: updatedCount,
            viewerHasReacted: false
          )
        }
      } else {
        updatedReactions[existingIndex] = FriendMessageReaction(
          emoji: existingReaction.emoji,
          count: existingReaction.count + 1,
          viewerHasReacted: true
        )
      }
    } else {
      updatedReactions.append(
        FriendMessageReaction(
          emoji: normalizedEmoji,
          count: 1,
          viewerHasReacted: true
        )
      )
    }

    return sortedReactions(updatedReactions)
  }

  internal static func sortedReactions(_ reactions: [FriendMessageReaction])
    -> [FriendMessageReaction]
  {
    reactions.sorted { lhs, rhs in
      if lhs.viewerHasReacted != rhs.viewerHasReacted {
        return lhs.viewerHasReacted && !rhs.viewerHasReacted
      }
      if lhs.count != rhs.count {
        return lhs.count > rhs.count
      }
      return lhs.emoji < rhs.emoji
    }
  }
}

internal struct FriendOutgoingAttachment: Codable, Equatable {
  internal let attachmentId: String
  internal let storagePath: String
  internal let mimeType: String
  internal let byteSize: Int64
  internal let width: Int?
  internal let height: Int?

  internal enum CodingKeys: String, CodingKey {
    case attachmentId = "attachment_id"
    case storagePath = "storage_path"
    case mimeType = "mime_type"
    case byteSize = "byte_size"
    case width
    case height
  }
}

private struct FriendRichContentEnvelope: Codable {
  private let content: Content?

  private struct Content: Codable {
    let kind: String?
    let shiftSnapshot: FriendShiftSnapshot?

    enum CodingKeys: String, CodingKey {
      case kind
      case shiftSnapshot = "shift_snapshot"
    }
  }
}

private enum FriendRichContentDecoder {
  private static func richContentKind(from metadataData: Data?) -> FriendRichContentKind? {
    guard
      let envelope = decodeEnvelope(from: metadataData),
      let rawKind = envelope.content?.kind?.trimmingCharacters(in: .whitespacesAndNewlines),
      !rawKind.isEmpty
    else {
      return nil
    }

    switch rawKind {
    case FriendLastMessagePreviewKind.shiftSnapshot.rawValue:
      guard let snapshot = envelope.content?.shiftSnapshot, snapshot.isSupportedSchemaVersion else {
        return .unsupported(rawKind)
      }
      return .shiftSnapshot

    default:
      return .unsupported(rawKind)
    }
  }

  private static func richContent(from metadataData: Data?) -> FriendRichContent? {
    guard let envelope = decodeEnvelope(from: metadataData) else {
      return nil
    }
    guard let snapshot = envelope.content?.shiftSnapshot, snapshot.isSupportedSchemaVersion else {
      return nil
    }

    guard envelope.content?.kind == FriendLastMessagePreviewKind.shiftSnapshot.rawValue else {
      return nil
    }

    return .shiftSnapshot(snapshot)
  }

  private static func decodeEnvelope(from metadataData: Data?) -> FriendRichContentEnvelope? {
    guard let metadataData, !metadataData.isEmpty else {
      return nil
    }
    return try? JSONDecoder().decode(FriendRichContentEnvelope.self, from: metadataData)
  }
}

private enum FriendMessagePreviewPolicy {
  private static func resolvedPreviewKind(
    explicitPreviewKind: FriendLastMessagePreviewKind? = nil,
    body: String?,
    richContentKind: FriendRichContentKind? = nil,
    hasImageAttachment: Bool
  ) -> FriendLastMessagePreviewKind {
    if let explicitPreviewKind {
      return explicitPreviewKind
    }

    if normalizedBody(body) != nil {
      return .text
    }

    if hasImageAttachment {
      return .image
    }

    switch richContentKind {
    case .shiftSnapshot:
      return .shiftSnapshot

    case .unsupported:
      return .unknown

    case nil:
      return .unknown
    }
  }

  private static func previewText(
    body: String?,
    previewKind: FriendLastMessagePreviewKind
  ) -> String? {
    if let normalizedBody = normalizedBody(body), previewKind == .text {
      return normalizedBody
    }

    switch previewKind {
    case .text:
      return String(localized: .friendsChatPreviewUnsupported)

    case .image:
      return String(localized: .friendsChatPreviewImage)

    case .shiftSnapshot:
      return String(localized: .friendsChatPreviewSharedShift)

    case .unknown:
      return String(localized: .friendsChatPreviewUnsupported)
    }
  }

  private static func normalizedBody(_ body: String?) -> String? {
    let snippet: String? = body?
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let snippet, !snippet.isEmpty else {
      return nil
    }
    return snippet
  }
}
