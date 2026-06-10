import Foundation
import SwiftData

// MARK: - Local Conversation

/// SwiftData model for locally persisted Wagey conversations
/// Conversations are stored locally only and not synced to server
@Model
final class LocalConversation {
  // MARK: - Primary Key

  /// Unique identifier
  @Attribute(.unique)
  var id: String

  /// User who owns this conversation
  var userId: String

  // MARK: - Conversation Data

  /// Title of the conversation (derived from first user message or auto-generated)
  var title: String

  /// Messages stored as JSON Data
  var messagesData: Data

  /// Latest server-authored conversation compaction summary, if available.
  /// Optional so lightweight migration can populate legacy rows.
  var compaction: String?

  /// When the conversation was created
  var createdAt: Date

  /// When the conversation was last updated (new message added)
  var updatedAt: Date

  // MARK: - Computed Properties

  /// Decoded messages
  var messages: [StoredChatMessage] {
    get {
      guard !messagesData.isEmpty else { return [] }
      return (try? JSONDecoder().decode([StoredChatMessage].self, from: messagesData)) ?? []
    }
    set {
      messagesData = (try? JSONEncoder().encode(newValue)) ?? Data()
    }
  }

  /// Preview of the conversation (first user message content, truncated)
  var preview: String {
    let firstUserMessage = messages.first { $0.role == .user }
    let content = firstUserMessage?.textContent ?? ""
    if content.count > 50 {
      return String(content.prefix(47)) + "..."
    }
    return content
  }

  /// Number of messages in the conversation
  var messageCount: Int {
    messages.count
  }

  // MARK: - Initialization

  init(
    id: String = UUID().uuidString,
    userId: String,
    title: String,
    messages: [StoredChatMessage] = [],
    compaction: String? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.userId = userId
    self.title = title
    self.messagesData = (try? JSONEncoder().encode(messages)) ?? Data()
    self.compaction = compaction
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

// MARK: - Stored Content Block

/// Codable version of ContentBlock for persistence
enum StoredContentBlock: Codable, Equatable {
  case text(String)
  case toolCall(StoredToolCall)
  case image(StoredImageAttachment)
  case thoughtStatus(ThoughtStatus)

  private enum CodingKeys: String, CodingKey {
    case type
    case content
    case toolCall
    case image
    case thoughtStatus
  }

  private enum BlockType: String, Codable {
    case text
    case toolCall
    case image
    case thoughtStatus
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(BlockType.self, forKey: .type)

    switch type {
    case .text:
      let content = try container.decode(String.self, forKey: .content)
      self = .text(content)

    case .toolCall:
      let toolCall = try container.decode(StoredToolCall.self, forKey: .toolCall)
      self = .toolCall(toolCall)

    case .image:
      let image = try container.decode(StoredImageAttachment.self, forKey: .image)
      self = .image(image)

    case .thoughtStatus:
      let thoughtStatus = try container.decode(ThoughtStatus.self, forKey: .thoughtStatus)
      self = .thoughtStatus(thoughtStatus)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .text(let content):
      try container.encode(BlockType.text, forKey: .type)
      try container.encode(content, forKey: .content)

    case .toolCall(let toolCall):
      try container.encode(BlockType.toolCall, forKey: .type)
      try container.encode(toolCall, forKey: .toolCall)

    case .image(let image):
      try container.encode(BlockType.image, forKey: .type)
      try container.encode(image, forKey: .image)

    case .thoughtStatus(let thoughtStatus):
      try container.encode(BlockType.thoughtStatus, forKey: .type)
      try container.encode(thoughtStatus, forKey: .thoughtStatus)
    }
  }
}

// MARK: - Stored Chat Message

/// Codable version of ChatMessage for persistence
struct StoredChatMessage: Codable, Identifiable, Equatable {
  let id: String
  let role: StoredMessageRole
  let timestamp: Date
  let sources: [MessageSource]?

  /// Ordered content blocks (new format)
  let contentBlocks: [StoredContentBlock]?

  /// Legacy: concatenated text content (for backward compatibility)
  let content: String?

  /// Legacy: tool calls (for backward compatibility)
  let toolCalls: [StoredToolCall]?

  init(
    id: String,
    role: StoredMessageRole,
    contentBlocks: [StoredContentBlock],
    sources: [MessageSource]?,
    timestamp: Date
  ) {
    self.id = id
    self.role = role
    self.contentBlocks = contentBlocks
    self.sources = sources
    self.timestamp = timestamp
    // Set legacy fields to nil when using new format
    self.content = nil
    self.toolCalls = nil
  }

  /// Legacy initializer for backward compatibility
  init(
    id: String, role: StoredMessageRole, content: String, toolCalls: [StoredToolCall]?,
    timestamp: Date
  ) {
    self.id = id
    self.role = role
    self.sources = nil
    self.content = content
    self.toolCalls = toolCalls
    self.timestamp = timestamp
    self.contentBlocks = nil
  }

  /// Returns the text content from either contentBlocks (new format) or content (legacy format)
  var textContent: String {
    // Try new format first
    if let blocks = contentBlocks {
      return WageyTextContent.flatten(
        blocks: blocks.compactMap { block in
          if case .text(let text) = block { return text }
          return nil
        })
    }
    // Fall back to legacy format
    return content ?? ""
  }
}

// MARK: - Stored Message Role

enum StoredMessageRole: String, Codable {
  case user
  case assistant
}

// MARK: - Stored Tool Call

/// Codable version of ToolCall for persistence
struct StoredToolCall: Codable, Identifiable, Equatable {
  let id: String
  let name: String
  let kind: ToolCallKind?
  let arguments: String?
  let result: String?
  let success: Bool?
}

// MARK: - Stored Image Attachment

/// Codable version of ImageAttachment for persistence
struct StoredImageAttachment: Codable, Identifiable, Equatable {
  let id: String
  let data: Data
  let mediaType: String
}

// MARK: - Conversion Extensions

extension StoredChatMessage {
  /// Convert from ChatMessage (runtime model) - uses new contentBlocks format
  init(from message: ChatMessage) {
    self.id = message.id
    self.role = StoredMessageRole(rawValue: message.role.rawValue) ?? .user
    self.timestamp = message.timestamp
    self.sources = message.sources
    let normalizedBlocks = ContentBlock.normalized(message.contentBlocks)

    // Store content blocks in new format
    self.contentBlocks = normalizedBlocks.map { block in
      switch block {
      case .text(let text):
        return .text(text)

      case .toolCall(let toolCall):
        return .toolCall(StoredToolCall(from: toolCall))

      case .image(let attachment):
        return .image(StoredImageAttachment(from: attachment))

      case .thoughtStatus(let thoughtStatus):
        return .thoughtStatus(thoughtStatus)
      }
    }

    // Set legacy fields to nil
    self.content = nil
    self.toolCalls = nil
  }

  /// Convert to ChatMessage (runtime model) - handles both old and new formats
  func toChatMessage() -> ChatMessage {
    let messageRole = MessageRole(rawValue: role.rawValue) ?? .user

    // New format: use contentBlocks if available
    if let storedBlocks = contentBlocks, !storedBlocks.isEmpty {
      let blocks: [ContentBlock] = storedBlocks.map { storedBlock in
        switch storedBlock {
        case .text(let text):
          return .text(text)

        case .toolCall(let storedToolCall):
          return .toolCall(storedToolCall.toToolCall())

        case .image(let storedImage):
          return .image(storedImage.toImageAttachment())

        case .thoughtStatus(let thoughtStatus):
          return .thoughtStatus(thoughtStatus)
        }
      }
      return ChatMessage(
        id: id,
        role: messageRole,
        contentBlocks: blocks,
        sources: sources,
        timestamp: timestamp
      )
    }

    // Legacy format: use content and toolCalls (tool calls first, then text)
    return ChatMessage(
      id: id,
      role: messageRole,
      content: content ?? "",
      toolCalls: toolCalls?.map { $0.toToolCall() },
      sources: sources,
      timestamp: timestamp
    )
  }
}

extension StoredToolCall {
  /// Convert from ToolCall (runtime model)
  init(from toolCall: ToolCall) {
    self.id = toolCall.id
    self.name = toolCall.name
    self.kind = toolCall.kind
    self.arguments = toolCall.arguments
    self.result = toolCall.result
    self.success = toolCall.success
  }

  /// Convert to ToolCall (runtime model)
  func toToolCall() -> ToolCall {
    ToolCall(
      id: id,
      name: name,
      kind: kind,
      arguments: arguments,
      result: result,
      success: success
    )
  }
}

extension StoredImageAttachment {
  /// Convert from ImageAttachment (runtime model)
  init(from attachment: ImageAttachment) {
    self.id = attachment.id
    self.data = attachment.data
    self.mediaType = attachment.mediaType
  }

  /// Convert to ImageAttachment (runtime model)
  func toImageAttachment() -> ImageAttachment {
    ImageAttachment(
      id: id,
      data: data,
      mediaType: mediaType
    )
  }
}
