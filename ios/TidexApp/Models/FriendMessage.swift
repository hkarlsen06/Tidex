import Foundation

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
}

// MARK: - Reactions

extension FriendMessage {
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
