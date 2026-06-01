import Foundation

// MARK: - Message Role

/// The role of a message sender in the chat
enum MessageRole: String, Codable, Equatable {
  case user
  case assistant
}

// MARK: - Chat Message

/// A chat message in the Wagey conversation.
///
/// Messages can be from the user or the assistant. Assistant messages
/// may include tool calls that were executed during the response.
/// Content blocks preserve the chronological order of text and tool calls.
struct ChatMessage: Identifiable, Equatable {
  let id: String
  let role: MessageRole
  let timestamp: Date
  let sources: [MessageSource]?

  /// Ordered content blocks for assistant messages.
  /// Preserves the interleaved order of text and tool calls as they streamed in.
  /// For user messages, this will contain a single text block.
  var contentBlocks: [ContentBlock]

  /// Concatenated text content (for backward compatibility and API requests)
  var content: String {
    WageyTextContent.flatten(
      blocks: contentBlocks.compactMap { block in
        if case .text(let text) = block {
          return text
        }
        return nil
      })
  }

  /// All tool calls from the message (for backward compatibility and API requests)
  var toolCalls: [ToolCall]? {
    let calls = contentBlocks.compactMap { block -> ToolCall? in
      if case .toolCall(let toolCall) = block {
        return toolCall
      }
      return nil
    }
    return calls.isEmpty ? nil : calls
  }

  /// Full initializer with content blocks
  init(
    id: String = UUID().uuidString, role: MessageRole, contentBlocks: [ContentBlock],
    sources: [MessageSource]? = nil, timestamp: Date = Date()
  ) {
    self.id = id
    self.role = role
    self.contentBlocks = ContentBlock.normalized(contentBlocks)
    self.sources = sources
    self.timestamp = timestamp
  }

  /// Convenience initializer with separate content and toolCalls (backward compatible)
  /// Tool calls are placed before text for backward compatibility with existing behavior
  init(
    id: String = UUID().uuidString, role: MessageRole, content: String,
    toolCalls: [ToolCall]? = nil, sources: [MessageSource]? = nil, timestamp: Date = Date()
  ) {
    self.id = id
    self.role = role
    self.sources = sources
    self.timestamp = timestamp

    // Build content blocks: tool calls first, then text (matches old rendering order)
    var blocks: [ContentBlock] = []
    if let toolCalls = toolCalls {
      blocks.append(contentsOf: toolCalls.map { .toolCall($0) })
    }
    if !content.isEmpty {
      blocks.append(.text(content))
    }
    self.contentBlocks = blocks
  }

  /// Create a user message
  static func user(_ content: String) -> ChatMessage {
    ChatMessage(
      id: UUID().uuidString,
      role: .user,
      contentBlocks: [.text(content)],
      timestamp: Date()
    )
  }

  /// Create a user message with an image attachment
  static func user(_ content: String, image: ImageAttachment) -> ChatMessage {
    var blocks: [ContentBlock] = [.image(image)]
    if !content.isEmpty {
      blocks.append(.text(content))
    }
    return ChatMessage(
      id: UUID().uuidString,
      role: .user,
      contentBlocks: blocks,
      timestamp: Date()
    )
  }

  /// Get all image attachments from the message
  var imageAttachments: [ImageAttachment] {
    contentBlocks.compactMap { block in
      if case .image(let attachment) = block {
        return attachment
      }
      return nil
    }
  }

  /// Whether the message has a visible bubble that should participate in grouped styling.
  var hasGroupedBubbleContent: Bool {
    contentBlocks.contains { block in
      switch block {
      case .text(let text):
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      case .image:
        return true
      case .toolCall, .thoughtStatus:
        return false
      }
    }
  }

  /// Create an assistant message (typically starts empty for streaming)
  static func assistant(id: String = UUID().uuidString, content: String = "") -> ChatMessage {
    ChatMessage(
      id: id,
      role: .assistant,
      contentBlocks: content.isEmpty ? [] : [.text(content)],
      timestamp: Date()
    )
  }
}

// MARK: - Content Block

/// A block of content in a message.
/// Preserves the chronological order of text, images, and tool calls as they stream in.
enum ContentBlock: Identifiable, Equatable {
  case text(String)
  case toolCall(ToolCall)
  case image(ImageAttachment)
  case thoughtStatus(ThoughtStatus)

  var id: String {
    switch self {
    case .text(let content):
      // Use content length + prefix for a stable, deterministic identity.
      // hashValue is randomized per process and must not be used for Identifiable.
      return "text-\(content.count)-\(content.prefix(32))"
    case .toolCall(let toolCall):
      return toolCall.id
    case .image(let attachment):
      return attachment.id
    case .thoughtStatus(let status):
      return status.id
    }
  }

  static func normalized(_ blocks: [ContentBlock]) -> [ContentBlock] {
    var normalizedBlocks: [ContentBlock] = []

    for block in blocks {
      switch block {
      case .text(let text):
        guard !text.isEmpty else { continue }

        if let lastIndex = normalizedBlocks.indices.last,
          case .text(let existingText) = normalizedBlocks[lastIndex]
        {
          normalizedBlocks[lastIndex] = .text(
            WageyTextContent.flatten(blocks: [existingText, text])
          )
        } else {
          normalizedBlocks.append(.text(text))
        }

      case .toolCall, .image, .thoughtStatus:
        normalizedBlocks.append(block)
      }
    }

    return normalizedBlocks
  }
}

enum WageyTextContent {
  private static let blockSeparator = "\n\n"

  static func flatten(blocks: [String]) -> String {
    blocks
      .filter { !$0.isEmpty }
      .joined(separator: blockSeparator)
  }

  static func trimLeadingBubbleWhitespace(from text: String) -> String {
    trimBubbleWhitespace(
      from: text,
      direction: .leading
    )
  }

  static func trimTrailingBubbleWhitespace(from text: String) -> String {
    trimBubbleWhitespace(
      from: text,
      direction: .trailing
    )
  }

  private enum BoundaryDirection {
    case leading
    case trailing
  }

  private static func trimBubbleWhitespace(
    from text: String,
    direction: BoundaryDirection
  ) -> String {
    switch direction {
    case .leading:
      var trimmed = text[...]

      while true {
        let whitespacePrefix = trimmed.prefix { $0 == " " || $0 == "\t" }
        let prefixEnd = trimmed.index(trimmed.startIndex, offsetBy: whitespacePrefix.count)
        let remainder = trimmed[prefixEnd...]

        if remainder.hasPrefix("\r\n") {
          trimmed = remainder.dropFirst(2)
        } else if remainder.first == "\n" || remainder.first == "\r" {
          trimmed = remainder.dropFirst()
        } else {
          return String(trimmed)
        }
      }

    case .trailing:
      var trimmed = text[...]

      while true {
        let whitespaceSuffix = trimmed.reversed().prefix { $0 == " " || $0 == "\t" }
        let suffixStart = trimmed.index(
          trimmed.endIndex,
          offsetBy: -whitespaceSuffix.count
        )
        let candidate = trimmed[..<suffixStart]

        if candidate.hasSuffix("\r\n") {
          trimmed = candidate.dropLast(2)
        } else if candidate.last == "\n" || candidate.last == "\r" {
          trimmed = candidate.dropLast()
        } else {
          return String(trimmed)
        }
      }
    }
  }
}

// MARK: - Image Attachment

/// An image attached to a message.
/// Stores the compressed image data for display and API transmission.
struct ImageAttachment: Identifiable, Equatable {
  let id: String
  /// Compressed image data (JPEG format for API compatibility)
  let data: Data
  /// MIME type of the image (e.g., "image/jpeg")
  let mediaType: String

  init(id: String = UUID().uuidString, data: Data, mediaType: String = "image/jpeg") {
    self.id = id
    self.data = data
    self.mediaType = mediaType
  }

  /// Base64 encoded image data for API transmission
  var base64String: String {
    data.base64EncodedString()
  }

  func hasSamePayload(as other: ImageAttachment) -> Bool {
    mediaType == other.mediaType && data == other.data
  }
}

struct ThoughtStatus: Identifiable, Codable, Equatable {
  let id: String
  let durationSeconds: Int

  init(id: String = UUID().uuidString, durationSeconds: Int) {
    self.id = id
    self.durationSeconds = durationSeconds
  }

  var localizedLabel: String {
    guard durationSeconds > 1 else {
      return String(localized: .wageyStreamingThoughtShort)
    }

    return String(localized: .wageyStreamingThoughtDuration(durationSeconds))
  }
}

extension Array where Element == ImageAttachment {
  func uniquePayloads() -> [ImageAttachment] {
    reduce(into: []) { result, attachment in
      guard !result.contains(where: { $0.hasSamePayload(as: attachment) }) else { return }
      result.append(attachment)
    }
  }
}

// MARK: - Message Source

struct MessageSource: Identifiable, Equatable, Codable {
  let id: String
  let title: String
  let url: String
  let domain: String
}

enum ToolCallKind: String, Codable, Equatable {
  case function
  case builtIn = "built_in"
}

// MARK: - Tool Call

/// A tool call that was executed during an assistant response.
///
/// Tool calls represent actions the AI takes to fulfill the user's request,
/// such as creating a shift or checking the schedule.
struct ToolCall: Identifiable, Equatable, Codable {
  let id: String
  let name: String
  let kind: ToolCallKind?
  var arguments: String?
  var result: String?
  var success: Bool?

  init(
    id: String,
    name: String,
    kind: ToolCallKind? = nil,
    arguments: String? = nil,
    result: String? = nil,
    success: Bool? = nil
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.arguments = arguments
    self.result = result
    self.success = success
  }

  /// Whether the tool call is still executing (no result yet)
  var isExecuting: Bool {
    result == nil
  }

  /// Whether the tool call completed successfully
  var isSuccess: Bool {
    success == true
  }

  /// Whether the tool call failed
  var isFailed: Bool {
    success == false
  }

  var isBuiltIn: Bool {
    kind == .builtIn
  }
}

// MARK: - Chat Chunk

/// A chunk from the streaming chat API.
///
/// The API streams responses as Server-Sent Events, with each event
/// containing a chunk of one of these types.
enum ChatChunk: Equatable {
  /// Backend status signal indicating the model is actively working
  case status(thinking: Bool)

  /// Start of a new visible text block from the provider stream
  case textStart

  /// Explicit boundary telling the client to start the next visible text in a new bubble
  case messageBreak

  /// Text content to append to the current message
  case text(content: String)

  /// A tool execution has started
  case toolStart(toolName: String, toolCallId: String, toolArguments: String?)

  /// A tool execution has completed
  case toolResult(
    toolName: String, toolCallId: String, toolArguments: String?, result: String, success: Bool)

  /// A provider built-in tool execution has started
  case builtInToolStart(toolName: String, toolCallId: String, toolArguments: String?)

  /// A provider built-in tool execution has completed
  case builtInToolResult(toolName: String, toolCallId: String, result: String, success: Bool)

  /// The stream has completed successfully
  case done

  /// An error occurred during processing
  case error(message: String)

  /// Usage limit information (may include exceeded warning and bonus messages)
  case wageyLimit(remaining: Int, resetDays: Int, exceeded: Bool, bonus: Int)

  /// User does not have access to Wagey
  case wageyNoAccess

  /// Rich source metadata for capable clients
  case sources(items: [MessageSource])

  /// Latest server-authored compaction summary for reuse on subsequent turns.
  case compaction(content: String)

  /// Future-compatible fallback for chunk types this app version does not understand.
  case unknown(type: String)
}

// MARK: - ChatChunk Decodable

extension ChatChunk: Decodable {
  private enum CodingKeys: String, CodingKey {
    case type
    case content
    case status
    case toolName
    case toolCallId
    case toolArguments
    case result
    case success
    case error
    case remaining
    case resetDays
    case exceeded
    case bonus
    case items
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)

    switch type {
    case "status":
      let status = try container.decode(String.self, forKey: .status)
      self = .status(thinking: status == "thinking")

    case "text_start":
      self = .textStart

    case "message_break":
      self = .messageBreak

    case "text":
      let content = try container.decode(String.self, forKey: .content)
      self = .text(content: content)

    case "tool_start":
      let toolName = try container.decode(String.self, forKey: .toolName)
      let toolCallId = try container.decode(String.self, forKey: .toolCallId)
      let toolArguments = try container.decodeIfPresent(String.self, forKey: .toolArguments)
      self = .toolStart(toolName: toolName, toolCallId: toolCallId, toolArguments: toolArguments)

    case "tool_result":
      let toolName = try container.decode(String.self, forKey: .toolName)
      let toolCallId = try container.decode(String.self, forKey: .toolCallId)
      let toolArguments = try container.decodeIfPresent(String.self, forKey: .toolArguments)
      let result = try container.decode(String.self, forKey: .result)
      let success = try container.decode(Bool.self, forKey: .success)
      self = .toolResult(
        toolName: toolName,
        toolCallId: toolCallId,
        toolArguments: toolArguments,
        result: result,
        success: success)

    case "wagey_built_in_tool_start":
      let toolName = try container.decode(String.self, forKey: .toolName)
      let toolCallId = try container.decode(String.self, forKey: .toolCallId)
      let toolArguments = try container.decodeIfPresent(String.self, forKey: .toolArguments)
      self = .builtInToolStart(
        toolName: toolName, toolCallId: toolCallId, toolArguments: toolArguments)

    case "wagey_built_in_tool_result":
      let toolName = try container.decode(String.self, forKey: .toolName)
      let toolCallId = try container.decode(String.self, forKey: .toolCallId)
      let result = try container.decode(String.self, forKey: .result)
      let success = try container.decode(Bool.self, forKey: .success)
      self = .builtInToolResult(
        toolName: toolName, toolCallId: toolCallId, result: result, success: success)

    case "done":
      self = .done

    case "error":
      let message = try container.decode(String.self, forKey: .error)
      self = .error(message: message)

    case "wagey_limit":
      let remaining = try container.decode(Int.self, forKey: .remaining)
      let resetDays = try container.decode(Int.self, forKey: .resetDays)
      let exceeded = try container.decodeIfPresent(Bool.self, forKey: .exceeded) ?? false
      let bonus = try container.decodeIfPresent(Int.self, forKey: .bonus) ?? 0
      self = .wageyLimit(
        remaining: remaining, resetDays: resetDays, exceeded: exceeded, bonus: bonus)

    case "wagey_no_access":
      self = .wageyNoAccess

    case "wagey_sources":
      let items = try container.decode([MessageSource].self, forKey: .items)
      self = .sources(items: items)

    case "wagey_compaction":
      let content = try container.decode(String.self, forKey: .content)
      self = .compaction(content: content)

    default:
      self = .unknown(type: type)
    }
  }
}

// MARK: - Wagey Access Info

/// Information about the user's Wagey access level and remaining messages.
struct WageyAccessInfo: Equatable {
  /// Whether the user has access to Wagey
  let hasAccess: Bool

  /// The user's subscription tier (e.g., "pro", "max", "free")
  let tier: String?

  /// Number of messages remaining this period
  let remaining: Int?

  /// Number of days until the limit resets
  let resetDays: Int?

  /// Whether the user has reached their message limit
  var isLimitReached: Bool {
    guard let remaining = remaining else { return false }
    return remaining <= 0
  }

  /// Create an access info indicating no access
  static let noAccess = WageyAccessInfo(
    hasAccess: false,
    tier: nil,
    remaining: nil,
    resetDays: nil
  )
}

// MARK: - API Message Format

/// Message format for sending to the API.
///
/// This matches the expected format of the /api/chat endpoint.
struct APIMessage: Codable, Equatable {
  let role: String
  let content: String
  let toolCalls: [APIToolCall]?
  let toolCallId: String?
  let name: String?

  private enum CodingKeys: String, CodingKey {
    case role
    case content
    case toolCalls = "tool_calls"
    case toolCallId = "tool_call_id"
    case name
  }

  /// Create an API message from a ChatMessage
  static func from(_ message: ChatMessage) -> APIMessage {
    let functionToolCalls = message.toolCalls?.filter { !$0.isBuiltIn }

    return APIMessage(
      role: message.role.rawValue,
      content: message.content,
      toolCalls: functionToolCalls?.map { APIToolCall.from($0) },
      toolCallId: nil,
      name: nil
    )
  }
}

/// Tool call format for the API
struct APIToolCall: Codable, Equatable {
  let id: String
  let type: String
  let function: APIFunctionCall

  static func from(_ toolCall: ToolCall) -> APIToolCall {
    APIToolCall(
      id: toolCall.id,
      type: "function",
      function: APIFunctionCall(
        name: toolCall.name,
        arguments: toolCall.arguments ?? "{}"
      )
    )
  }
}

/// Function call details for the API
struct APIFunctionCall: Codable, Equatable {
  let name: String
  let arguments: String
}

// MARK: - Preview Data

extension ChatMessage {
  /// Sample messages for previews
  static let previewConversation: [ChatMessage] = [
    .user("Add a shift tomorrow from 9 to 17"),
    ChatMessage(
      id: "assistant-1",
      role: .assistant,
      content:
        "I've added a shift for tomorrow (January 28th) from 09:00 to 17:00. That's an 8-hour shift. Is there anything else you'd like me to help you with?",
      toolCalls: [
        ToolCall(
          id: "call_123",
          name: "manage_shift",
          arguments:
            "{\"action\":\"create\",\"date\":\"2025-01-28\",\"start\":\"09:00\",\"end\":\"17:00\"}",
          result: "{\"success\":true,\"shiftId\":\"abc123\"}",
          success: true
        )
      ],
      timestamp: Date()
    ),
    .user("How much will I earn this month?"),
    ChatMessage(
      id: "assistant-2",
      role: .assistant,
      content:
        "Based on your current shifts this month, you'll earn approximately 15,200 kr before tax. With your 7.5% tax rate, that's about 14,060 kr net.",
      toolCalls: nil,
      timestamp: Date()
    ),
  ]
}

extension WageyAccessInfo {
  /// Preview data for testing
  static let previewPro = WageyAccessInfo(
    hasAccess: true,
    tier: "pro",
    remaining: 45,
    resetDays: 12
  )

  static let previewMax = WageyAccessInfo(
    hasAccess: true,
    tier: "max",
    remaining: nil,
    resetDays: nil
  )

  static let previewLimitReached = WageyAccessInfo(
    hasAccess: true,
    tier: "pro",
    remaining: 0,
    resetDays: 5
  )
}
