import CryptoKit
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

struct FriendInboxSyncSnapshot: Equatable {
  let threads: [FriendThread]
  let unreadDirectMessageCount: Int
  let nextCursor: FriendThreadCursor?
  let snapshotVersion: Int64
  let retainedFromVersion: Int64
  let hasMore: Bool
}

struct FriendThreadCounterpartPresence: Equatable {
  let userId: String
  let displayName: String?
  let profilePictureUrl: String?
  let oauthAvatarUrl: String?
}

struct FriendThreadSyncSnapshot: Equatable {
  let thread: FriendThread
  let viewerState: FriendThreadState
  let counterpartPresence: FriendThreadCounterpartPresence?
  let messages: [FriendMessage]
  let nextCursor: FriendMessageCursor?
  let snapshotVersion: Int64
  let retainedFromVersion: Int64
  let hasMore: Bool
}

enum FriendMessagingSyncScope: Equatable {
  case inbox
  case thread(threadId: String)
}

struct FriendMessagingSyncState: Equatable {
  let viewerUserId: String
  let scope: FriendMessagingSyncScope
  let version: Int64
  let retainedFromVersion: Int64
  let updatedAt: Date
}

struct FriendInboxSyncEvent: Equatable {
  enum EventType: String, Equatable {
    case threadUpserted = "thread_upserted"
    case threadRemoved = "thread_removed"
  }

  let id: String
  let version: Int64
  let threadId: String?
  let eventType: EventType
  let thread: FriendThread?
}

struct FriendInboxSyncEventsPage: Equatable {
  let requiresSnapshot: Bool
  let latestVersion: Int64
  let retainedFromVersion: Int64
  let hasMore: Bool
  let events: [FriendInboxSyncEvent]
}

struct FriendThreadSyncEvent: Equatable {
  enum EventType: String, Equatable {
    case messageUpserted = "message_upserted"
    case messageDeleted = "message_deleted"
  }

  let id: String
  let version: Int64
  let eventType: EventType
  let message: FriendMessage?
  let deletedMessageId: String?
}

struct FriendThreadSyncEventsPage: Equatable {
  let requiresSnapshot: Bool
  let latestVersion: Int64
  let retainedFromVersion: Int64
  let hasMore: Bool
  let events: [FriendThreadSyncEvent]
}

struct FriendThreadMessagesPage: Equatable {
  let messages: [FriendMessage]
  let nextCursor: FriendMessageCursor?
  let hasMore: Bool
}

enum FriendLastMessagePreviewKind: String, Codable, Equatable {
  case text
  case image
  case shiftSnapshot = "shift_snapshot"
  case unknown
}

enum FriendRichContentKind: Equatable {
  case shiftSnapshot
  case unsupported(String)
}

enum FriendRichContent: Equatable {
  case shiftSnapshot(FriendShiftSnapshot)
}

extension ImageAttachment: Codable {
  private enum CodingKeys: String, CodingKey {
    case id
    case data
    case mediaType
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(String.self, forKey: .id)
    let data = try container.decode(Data.self, forKey: .data)
    let mediaType = try container.decode(String.self, forKey: .mediaType)
    self.init(id: id, data: data, mediaType: mediaType)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(data, forKey: .data)
    try container.encode(mediaType, forKey: .mediaType)
  }
}

struct FriendShiftSnapshot: Codable, Equatable {
  let schemaVersion: Int
  let ownerUserId: String
  let ownerDisplayName: String
  let ownerAvatarUrl: String?
  let shiftId: String
  let jobName: String?
  let jobColorHex: String?
  let shiftDate: String
  let startTime: String
  let endTime: String
  let paidHours: Double
  let currency: String
  let includesEarnings: Bool
  let grossPay: Double?
  let netPay: Double?
  let taxEnabled: Bool
  let source: String

  enum CodingKeys: String, CodingKey {
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

  var isSupportedSchemaVersion: Bool {
    schemaVersion == 1
  }

  var ownerFirstName: String {
    let trimmed = ownerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "?" }
    return trimmed.components(separatedBy: .whitespacesAndNewlines).first ?? trimmed
  }

  var ownerInitials: String {
    let letters =
      ownerFirstName
      .split(whereSeparator: \.isWhitespace)
      .compactMap(\.first)
      .prefix(2)
    let initials = letters.map(String.init).joined()
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
    guard !canSeeEarnings else { return self }

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

  var renderableShift: ShiftWithComputations {
    let gross = grossPay ?? netPay ?? 0
    let resolvedTaxEnabled = includesEarnings ? taxEnabled : false
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

enum SnapshotRichContentIdentifier {
  private static let uuidPattern =
    "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"

  static func normalizedUUIDString(primary: String, fallbackSeed: String) -> String {
    if let valid = validUUIDString(from: primary) {
      return valid
    }

    return deterministicUUID(seed: fallbackSeed)
  }

  static func normalizedUUIDString(primary: String?, secondary: String?, fallbackSeed: String)
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
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.range(of: uuidPattern, options: .regularExpression) != nil
    else {
      return nil
    }
    return trimmed.lowercased()
  }

  private static func deterministicUUID(seed: String) -> String {
    let digest = SHA256.hash(data: Data(seed.utf8))
    var bytes = Array(digest.prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80

    let uuid = UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
      ))
    return uuid.uuidString.lowercased()
  }
}

struct ComposerShiftSnapshotDraft: Codable, Equatable {
  let snapshot: FriendShiftSnapshot

  var ownerDisplayName: String {
    snapshot.ownerDisplayName
  }
}

enum FriendsComposerAttachmentLimits {
  static let maxImagesPerMessage = 4
}

enum FriendsComposerAttachmentDraft: Codable, Equatable {
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

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(DraftType.self, forKey: .type)

    switch type {
    case .image:
      self = .image(try container.decode(ImageAttachment.self, forKey: .image))

    case .shiftSnapshot:
      self = .shiftSnapshot(
        try container.decode(ComposerShiftSnapshotDraft.self, forKey: .shiftSnapshot)
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .image(let image):
      try container.encode(DraftType.image, forKey: .type)
      try container.encode(image, forKey: .image)

    case .shiftSnapshot(let draft):
      try container.encode(DraftType.shiftSnapshot, forKey: .type)
      try container.encode(draft, forKey: .shiftSnapshot)
    }
  }

  var imageAttachment: ImageAttachment? {
    guard case .image(let image) = self else { return nil }
    return image
  }

  var shiftSnapshotDraft: ComposerShiftSnapshotDraft? {
    guard case .shiftSnapshot(let draft) = self else { return nil }
    return draft
  }

  var shiftSnapshot: FriendShiftSnapshot? {
    shiftSnapshotDraft?.snapshot
  }

  var previewKind: FriendLastMessagePreviewKind {
    switch self {
    case .image:
      return .image

    case .shiftSnapshot:
      return .shiftSnapshot
    }
  }

  var metadataData: Data? {
    guard let shiftSnapshot else { return nil }
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
  var imageAttachments: [ImageAttachment] {
    compactMap(\.imageAttachment)
  }

  var shiftSnapshotDraft: ComposerShiftSnapshotDraft? {
    compactMap(\.shiftSnapshotDraft).first
  }

  var shiftSnapshot: FriendShiftSnapshot? {
    shiftSnapshotDraft?.snapshot
  }

  var hasImageAttachments: Bool {
    contains { $0.imageAttachment != nil }
  }

  var hasShiftSnapshot: Bool {
    contains { $0.shiftSnapshot != nil }
  }

  var metadataData: Data? {
    compactMap(\.metadataData).first
  }
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
  let lastMessagePreviewKind: FriendLastMessagePreviewKind?
  let lastMessageHasImage: Bool
  let unreadCount: Int
  let muted: Bool
  let createdAt: Date

  init(
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

  var counterpartAvatarUrl: String? {
    counterpartProfilePictureUrl ?? counterpartOAuthAvatarUrl
  }

  var resolvedLastMessagePreviewKind: FriendLastMessagePreviewKind {
    FriendMessagePreviewPolicy.resolvedPreviewKind(
      explicitPreviewKind: lastMessagePreviewKind,
      body: lastMessageBody,
      hasImageAttachment: lastMessageHasImage
    )
  }

  var lastMessagePreviewText: String? {
    guard lastMessageId != nil else { return nil }
    return FriendMessagePreviewPolicy.previewText(
      body: lastMessageBody,
      previewKind: resolvedLastMessagePreviewKind
    )
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
  let reactions: [FriendMessageReaction]

  enum CodingKeys: String, CodingKey {
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

  init(
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

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
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

struct FriendMessageReaction: Identifiable, Codable, Equatable, Hashable {
  var id: String { emoji }

  let emoji: String
  let count: Int
  let viewerHasReacted: Bool
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
  let reactions: [FriendMessageReaction]
  let sendState: FriendMessageSendState
  let failureMessage: String?

  init(
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

  var hasImageAttachment: Bool {
    attachments.contains { $0.kind == .image }
  }

  var richContentKind: FriendRichContentKind? {
    FriendRichContentDecoder.richContentKind(from: metadataData)
  }

  var richContent: FriendRichContent? {
    FriendRichContentDecoder.richContent(from: metadataData)
  }

  var shiftSnapshot: FriendShiftSnapshot? {
    guard case .shiftSnapshot(let snapshot) = richContent else { return nil }
    return snapshot
  }

  var sendableMetadataData: Data? {
    guard let shiftSnapshot else { return metadataData }
    return try? JSONEncoder().encode(
      FriendRichContentEnvelope(
        content: FriendRichContentEnvelope.Content(
          kind: FriendLastMessagePreviewKind.shiftSnapshot.rawValue,
          shiftSnapshot: shiftSnapshot.normalizedForTransport
        )
      )
    )
  }

  var replyIconPreviewKind: FriendLastMessagePreviewKind? {
    if shiftSnapshot != nil {
      return .shiftSnapshot
    }

    if hasImageAttachment {
      return .image
    }

    return nil
  }

  var previewKind: FriendLastMessagePreviewKind {
    FriendMessagePreviewPolicy.resolvedPreviewKind(
      body: body,
      richContentKind: richContentKind,
      hasImageAttachment: hasImageAttachment
    )
  }

  var previewText: String? {
    FriendMessagePreviewPolicy.previewText(body: body, previewKind: previewKind)
  }

  var canRetrySend: Bool {
    sendState == .failed
  }

  var normalizedBody: String? {
    guard let body else { return nil }
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  var paginationCursor: FriendMessageCursor {
    FriendMessageCursor(createdAt: createdAt, messageId: id)
  }

  func logicalRowIdentity(viewerUserId: String) -> String {
    let normalizedClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
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

  func canEdit(viewerUserId: String) -> Bool {
    senderUserId == viewerUserId
      && messageType == .user
      && deletedAt == nil
      && sendState == .sent
      && normalizedBody != nil
  }

  func canDelete(viewerUserId: String) -> Bool {
    senderUserId == viewerUserId
      && messageType == .user
      && deletedAt == nil
      && (sendState == .sent || sendState == .failed)
  }

  func withSendState(
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

    var updatedAttachments = attachments
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

  var canReact: Bool {
    messageType == .user && deletedAt == nil && sendState == .sent
  }

  static func toggledReactions(_ reactions: [FriendMessageReaction], emoji: String)
    -> [FriendMessageReaction]
  {
    let normalizedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedEmoji.isEmpty else { return reactions }

    var updatedReactions = reactions

    if let existingIndex = updatedReactions.firstIndex(where: { $0.emoji == normalizedEmoji }) {
      let existingReaction = updatedReactions[existingIndex]
      if existingReaction.viewerHasReacted {
        let updatedCount = existingReaction.count - 1
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

  static func sortedReactions(_ reactions: [FriendMessageReaction])
    -> [FriendMessageReaction]
  {
    reactions.sorted {
      if $0.viewerHasReacted != $1.viewerHasReacted {
        return $0.viewerHasReacted && !$1.viewerHasReacted
      }
      if $0.count != $1.count {
        return $0.count > $1.count
      }
      return $0.emoji < $1.emoji
    }
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

private struct FriendRichContentEnvelope: Codable {
  let content: Content?

  struct Content: Codable {
    let kind: String?
    let shiftSnapshot: FriendShiftSnapshot?

    enum CodingKeys: String, CodingKey {
      case kind
      case shiftSnapshot = "shift_snapshot"
    }
  }
}

private enum FriendRichContentDecoder {
  static func richContentKind(from metadataData: Data?) -> FriendRichContentKind? {
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

  static func richContent(from metadataData: Data?) -> FriendRichContent? {
    guard let envelope = decodeEnvelope(from: metadataData) else { return nil }
    guard let snapshot = envelope.content?.shiftSnapshot, snapshot.isSupportedSchemaVersion else {
      return nil
    }

    guard envelope.content?.kind == FriendLastMessagePreviewKind.shiftSnapshot.rawValue else {
      return nil
    }

    return .shiftSnapshot(snapshot)
  }

  private static func decodeEnvelope(from metadataData: Data?) -> FriendRichContentEnvelope? {
    guard let metadataData, !metadataData.isEmpty else { return nil }
    return try? JSONDecoder().decode(FriendRichContentEnvelope.self, from: metadataData)
  }
}

private enum FriendMessagePreviewPolicy {
  static func resolvedPreviewKind(
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

  static func previewText(
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

  static func normalizedBody(_ body: String?) -> String? {
    let snippet = body?
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let snippet, !snippet.isEmpty else { return nil }
    return snippet
  }
}
