import AppIntents
import Foundation
import GeoToolbox
import LinkPresentation

// The messages schema requires these types for the message that SendFriendMessageIntent returns.

@available(iOS 27, *)
@AppEntity(schema: .messages.message)
struct SentMessageEntity {
  static let defaultQuery = SentMessageQuery()

  let id: String
  var messageType: AssistantMessageType
  var author: MessageRecipientEntity
  var isRead: Bool
  var attributes: Set<AssistantMessageAttribute>
  var conversation: AssistantConversationEntity
  var date: Date
  var subject: AttributedString?
  var body: AttributedString?
  var attachments: [IntentFile]
  var audioMessage: IntentFile?
  var customAttachments: [AssistantMessageAttachmentEntity]
  var locations: [PlaceDescriptor]
  var links: [LinkMetadata]
  var messageEffect: AssistantMessageEffect?
  var reaction: AssistantMessageReaction?
  var referencedMessage: SentMessageEntity?
  var notificationIdentifier: String?

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(body.map { String($0.characters) } ?? "")")
  }

  init(id: String, author: MessageRecipientEntity, recipient: ShareRecipient, body: AttributedString)
  {
    self.id = id
    messageType = .unspecified
    self.author = author
    isRead = true
    attributes = []
    conversation = AssistantConversationEntity(recipient)
    date = Date()
    self.body = body
    attachments = []
    customAttachments = []
    locations = []
    links = []
  }
}

/// Sent messages live in the chat, so Siri can't look them up again by ID.
@available(iOS 27, *)
struct SentMessageQuery: EntityQuery {
  func entities(for identifiers: [SentMessageEntity.ID]) -> [SentMessageEntity] {
    []
  }
}

/// A direct chat. Its ID is the friend's user ID, because a friend has one direct chat.
@available(iOS 27, *)
@AppEntity(schema: .messages.conversation)
struct AssistantConversationEntity {
  static let defaultQuery = AssistantConversationQuery()

  let id: String
  var recipients: [MessageRecipientEntity]
  var displayName: String
  var previewText: AttributedString
  var conversationName: String?
  var isRead: Bool
  var attributes: Set<AssistantConversationAttribute>
  var dateLastActive: Date?

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(displayName)")
  }

  init(_ recipient: ShareRecipient) {
    id = recipient.id
    recipients = [MessageRecipientEntity(recipient)]
    displayName = recipient.displayName
    previewText = AttributedString()
    isRead = true
    attributes = []
  }
}

@available(iOS 27, *)
struct AssistantConversationQuery: EntityQuery {
  @MainActor
  func entities(for identifiers: [AssistantConversationEntity.ID]) async throws
    -> [AssistantConversationEntity]
  {
    let ids = Set(identifiers.map { $0.lowercased() })
    return try await MessageRecipients.load()
      .filter { ids.contains($0.id.lowercased()) }
      .map(AssistantConversationEntity.init)
  }
}

/// Tidex messages have no custom attachments. The schema requires the type.
@available(iOS 27, *)
@AppEntity(schema: .messages.customAttachment)
struct AssistantMessageAttachmentEntity {
  static let defaultQuery = AssistantMessageAttachmentQuery()

  let id: String
  var sourceName: AttributedString?
  var description: AttributedString?

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(id)")
  }
}

@available(iOS 27, *)
struct AssistantMessageAttachmentQuery: EntityQuery {
  func entities(for identifiers: [AssistantMessageAttachmentEntity.ID])
    -> [AssistantMessageAttachmentEntity]
  {
    []
  }
}

@available(iOS 27, *)
@AppEnum(schema: .messages.messageType)
enum AssistantMessageType: String {
  case unspecified

  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .unspecified: "assistant.message.type.unspecified"
  ]
}

// The schema leaves the cases below to the app. Tidex sets none of them.

@available(iOS 27, *)
@AppEnum(schema: .messages.messageAttribute)
enum AssistantMessageAttribute: String {
  case reply

  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .reply: "assistant.message.attribute.reply"
  ]
}

@available(iOS 27, *)
@AppEnum(schema: .messages.conversationAttribute)
enum AssistantConversationAttribute: String {
  case muted

  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .muted: "assistant.message.conversation.muted"
  ]
}

@available(iOS 27, *)
@AppEnum(schema: .messages.messageEffect)
enum AssistantMessageEffect: String {
  case standard

  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .standard: "assistant.message.effect.standard"
  ]
}

@available(iOS 27, *)
@AppEnum(schema: .messages.customReaction)
enum AssistantMessageTapback: String {
  case heart

  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .heart: "assistant.message.reaction.heart"
  ]
}

@available(iOS 27, *)
@UnionValue
enum AssistantMessageReaction {
  case customReaction(AssistantMessageTapback)
  case attributedString(AttributedString)
}
