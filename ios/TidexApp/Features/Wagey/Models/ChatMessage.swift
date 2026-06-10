import Foundation

// MARK: - Message Role

/// The role of a message sender in the chat
enum MessageRole: String, Codable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  case user  // swiftlint:disable:this explicit_enum_raw_value sorted_enum_cases
  case assistant  // swiftlint:disable:this explicit_enum_raw_value sorted_enum_cases
}

// MARK: - Chat Message

/// A chat message in the Wagey conversation.
///
/// Messages can be from the user or the assistant. Assistant messages
/// may include tool calls that were executed during the response.
/// Content blocks preserve the chronological order of text and tool calls.
struct ChatMessage: Identifiable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order line_length
  let id: String  // swiftlint:disable:this explicit_acl
  let role: MessageRole  // swiftlint:disable:this explicit_acl
  let timestamp: Date  // swiftlint:disable:this explicit_acl
  let sources: [MessageSource]?  // swiftlint:disable:this discouraged_optional_collection explicit_acl

  /// Ordered content blocks for assistant messages.
  /// Preserves the interleaved order of text and tool calls as they streamed in.
  /// For user messages, this will contain a single text block.
  var contentBlocks: [ContentBlock]  // swiftlint:disable:this explicit_acl

  /// Concatenated text content (for backward compatibility and API requests)
  var content: String {  // swiftlint:disable:this explicit_acl
    WageyTextContent.flatten(
      blocks: contentBlocks.compactMap { block in
        if case .text(let text) = block {
          return text
        }
        return nil
      })  // swiftlint:disable:this multiline_arguments_brackets
  }

  /// All tool calls from the message (for backward compatibility and API requests)
  var toolCalls: [ToolCall]? {  // swiftlint:disable:this discouraged_optional_collection explicit_acl
    let calls = contentBlocks.compactMap { block -> ToolCall? in  // swiftlint:disable:this explicit_type_interface
      if case .toolCall(let toolCall) = block {
        return toolCall
      }
      return nil
    }
    return calls.isEmpty ? nil : calls
  }

  /// Full initializer with content blocks
  init(  // swiftlint:disable:this explicit_acl type_contents_order
    id: String = UUID().uuidString, role: MessageRole, contentBlocks: [ContentBlock],  // swiftlint:disable:this function_default_parameter_at_end line_length
    sources: [MessageSource]? = nil, timestamp: Date = Date()  // swiftlint:disable:this discouraged_optional_collection
  ) {
    self.id = id
    self.role = role
    self.contentBlocks = ContentBlock.normalized(contentBlocks)
    self.sources = sources
    self.timestamp = timestamp
  }

  /// Convenience initializer with separate content and toolCalls (backward compatible)
  /// Tool calls are placed before text for backward compatibility with existing behavior
  init(  // swiftlint:disable:this explicit_acl type_contents_order
    id: String = UUID().uuidString, role: MessageRole, content: String,  // swiftlint:disable:this function_default_parameter_at_end line_length
    toolCalls: [ToolCall]? = nil, sources: [MessageSource]? = nil, timestamp: Date = Date()  // swiftlint:disable:this discouraged_optional_collection line_length
  ) {
    self.id = id
    self.role = role
    self.sources = sources
    self.timestamp = timestamp

    // Build content blocks: tool calls first, then text (matches old rendering order)
    var blocks: [ContentBlock] = []
    if let toolCalls {
      blocks.append(contentsOf: toolCalls.map { .toolCall($0) })
    }
    if !content.isEmpty {
      blocks.append(.text(content))
    }
    self.contentBlocks = blocks
  }

  /// Create a user message
  static func user(_ content: String) -> Self {  // swiftlint:disable:this explicit_acl type_contents_order
    Self(
      id: UUID().uuidString,
      role: .user,
      contentBlocks: [.text(content)],
      timestamp: Date()
    )
  }

  /// Create a user message with an image attachment
  static func user(_ content: String, image: ImageAttachment) -> Self {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    var blocks: [ContentBlock] = [.image(image)]
    if !content.isEmpty {
      blocks.append(.text(content))
    }
    return Self(
      id: UUID().uuidString,
      role: .user,
      contentBlocks: blocks,
      timestamp: Date()
    )
  }

  /// Get all image attachments from the message
  var imageAttachments: [ImageAttachment] {  // swiftlint:disable:this explicit_acl
    contentBlocks.compactMap { block in
      if case .image(let attachment) = block {
        return attachment
      }
      return nil
    }
  }

  /// Whether the message has a visible bubble that should participate in grouped styling.
  var hasGroupedBubbleContent: Bool {  // swiftlint:disable:this explicit_acl
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
  static func assistant(id: String = UUID().uuidString, content: String = "") -> Self {  // swiftlint:disable:this explicit_acl line_length
    Self(
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
enum ContentBlock: Identifiable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  case text(String)  // swiftlint:disable:this sorted_enum_cases
  case toolCall(ToolCall)  // swiftlint:disable:this sorted_enum_cases
  case image(ImageAttachment)  // swiftlint:disable:this sorted_enum_cases
  case thoughtStatus(ThoughtStatus)  // swiftlint:disable:this sorted_enum_cases

  var id: String {  // swiftlint:disable:this explicit_acl
    switch self {
    case .text(let content):
      // Use content length + prefix for a stable, deterministic identity.
      // hashValue is randomized per process and must not be used for Identifiable.
      return "text-\(content.count)-\(content.prefix(32))"  // swiftlint:disable:this no_magic_numbers

    case .toolCall(let toolCall):
      return toolCall.id

    case .image(let attachment):
      return attachment.id

    case .thoughtStatus(let status):
      return status.id
    }
  }

  static func normalized(_ blocks: [Self]) -> [Self] {  // swiftlint:disable:this explicit_acl
    var normalizedBlocks: [Self] = []

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

enum WageyTextContent {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  private static let blockSeparator = "\n\n"  // swiftlint:disable:this explicit_type_interface type_contents_order

  static func flatten(blocks: [String]) -> String {  // swiftlint:disable:this explicit_acl type_contents_order
    blocks
      .filter { !$0.isEmpty }
      .joined(separator: blockSeparator)
  }

  static func trimLeadingBubbleWhitespace(from text: String) -> String {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    trimBubbleWhitespace(
      from: text,
      direction: .leading
    )
  }

  static func trimTrailingBubbleWhitespace(from text: String) -> String {  // swiftlint:disable:this explicit_acl line_length type_contents_order
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
      var trimmed = text[...]  // swiftlint:disable:this explicit_type_interface

      while true {
        let whitespacePrefix = trimmed.prefix { $0 == " " || $0 == "\t" }  // swiftlint:disable:this explicit_type_interface line_length
        let prefixEnd = trimmed.index(trimmed.startIndex, offsetBy: whitespacePrefix.count)  // swiftlint:disable:this explicit_type_interface line_length
        let remainder = trimmed[prefixEnd...]  // swiftlint:disable:this explicit_type_interface

        if remainder.hasPrefix("\r\n") {
          trimmed = remainder.dropFirst(2)  // swiftlint:disable:this no_magic_numbers
        } else if remainder.first == "\n" || remainder.first == "\r" {
          trimmed = remainder.dropFirst()
        } else {
          return String(trimmed)
        }
      }

    case .trailing:
      var trimmed = text[...]  // swiftlint:disable:this explicit_type_interface

      while true {
        let whitespaceSuffix = trimmed.reversed().prefix { $0 == " " || $0 == "\t" }  // swiftlint:disable:this explicit_type_interface line_length
        let suffixStart = trimmed.index(  // swiftlint:disable:this explicit_type_interface
          trimmed.endIndex,
          offsetBy: -whitespaceSuffix.count
        )
        let candidate = trimmed[..<suffixStart]  // swiftlint:disable:this explicit_type_interface

        if candidate.hasSuffix("\r\n") {
          trimmed = candidate.dropLast(2)  // swiftlint:disable:this no_magic_numbers
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
struct ImageAttachment: Identifiable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let id: String  // swiftlint:disable:this explicit_acl
  /// Compressed image data (JPEG format for API compatibility)
  let data: Data  // swiftlint:disable:this explicit_acl
  /// MIME type of the image (e.g., "image/jpeg")
  let mediaType: String  // swiftlint:disable:this explicit_acl

  init(id: String = UUID().uuidString, data: Data, mediaType: String = "image/jpeg") {  // swiftlint:disable:this explicit_acl function_default_parameter_at_end line_length type_contents_order
    self.id = id
    self.data = data
    self.mediaType = mediaType
  }

  /// Base64 encoded image data for API transmission
  var base64String: String {  // swiftlint:disable:this explicit_acl
    data.base64EncodedString()
  }

  func hasSamePayload(as other: Self) -> Bool {  // swiftlint:disable:this explicit_acl
    mediaType == other.mediaType && data == other.data
  }
}

struct ThoughtStatus: Identifiable, Codable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let id: String  // swiftlint:disable:this explicit_acl
  let durationSeconds: Int  // swiftlint:disable:this explicit_acl

  init(id: String = UUID().uuidString, durationSeconds: Int) {  // swiftlint:disable:this explicit_acl function_default_parameter_at_end line_length type_contents_order
    self.id = id
    self.durationSeconds = durationSeconds
  }

  var localizedLabel: String {  // swiftlint:disable:this explicit_acl
    guard durationSeconds > 1 else {
      return String(localized: .wageyStreamingThoughtShort)
    }

    return String(localized: .wageyStreamingThoughtDuration(durationSeconds))
  }
}

extension Array where Element == ImageAttachment {  // swiftlint:disable:this file_types_order
  func uniquePayloads() -> [ImageAttachment] {  // swiftlint:disable:this explicit_acl
    reduce(into: []) { result, attachment in
      guard !result.contains(where: { $0.hasSamePayload(as: attachment) }) else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
      result.append(attachment)
    }
  }
}

// MARK: - Message Source

struct MessageSource: Identifiable, Equatable, Codable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let id: String  // swiftlint:disable:this explicit_acl
  let title: String  // swiftlint:disable:this explicit_acl
  let url: String  // swiftlint:disable:this explicit_acl
  let domain: String  // swiftlint:disable:this explicit_acl
}

enum ToolCallKind: String, Codable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  case function  // swiftlint:disable:this explicit_enum_raw_value sorted_enum_cases
  case builtIn = "built_in"  // swiftlint:disable:this sorted_enum_cases
}

// MARK: - Tool Call

/// A tool call that was executed during an assistant response.
///
/// Tool calls represent actions the AI takes to fulfill the user's request,
/// such as creating a shift or checking the schedule.
struct ToolCall: Identifiable, Equatable, Codable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let id: String  // swiftlint:disable:this explicit_acl
  let name: String  // swiftlint:disable:this explicit_acl
  let kind: ToolCallKind?  // swiftlint:disable:this explicit_acl
  var arguments: String?  // swiftlint:disable:this explicit_acl
  var result: String?  // swiftlint:disable:this explicit_acl
  var success: Bool?  // swiftlint:disable:this discouraged_optional_boolean explicit_acl

  init(  // swiftlint:disable:this explicit_acl type_contents_order
    id: String,
    name: String,
    kind: ToolCallKind? = nil,
    arguments: String? = nil,
    result: String? = nil,
    success: Bool? = nil  // swiftlint:disable:this discouraged_optional_boolean
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.arguments = arguments
    self.result = result
    self.success = success
  }

  /// Whether the tool call is still executing (no result yet)
  var isExecuting: Bool {  // swiftlint:disable:this explicit_acl
    result == nil
  }

  /// Whether the tool call completed successfully
  var isSuccess: Bool {  // swiftlint:disable:this explicit_acl
    success == true
  }

  /// Whether the tool call failed
  var isFailed: Bool {  // swiftlint:disable:this explicit_acl
    success == false
  }

  var isBuiltIn: Bool {  // swiftlint:disable:this explicit_acl
    kind == .builtIn
  }
}

// MARK: - Chat Chunk

/// A chunk from the streaming chat API.
///
/// The API streams responses as Server-Sent Events, with each event
/// containing a chunk of one of these types.
enum ChatChunk: Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  /// Backend status signal indicating the model is actively working
  case status(thinking: Bool)  // swiftlint:disable:this sorted_enum_cases

  /// Start of a new visible text block from the provider stream
  case textStart  // swiftlint:disable:this sorted_enum_cases

  /// Explicit boundary telling the client to start the next visible text in a new bubble
  case messageBreak  // swiftlint:disable:this sorted_enum_cases

  /// Text content to append to the current message
  case text(content: String)  // swiftlint:disable:this sorted_enum_cases

  /// A tool execution has started
  case toolStart(toolName: String, toolCallId: String, toolArguments: String?)  // swiftlint:disable:this line_length sorted_enum_cases

  /// A tool execution has completed
  case toolResult(  // swiftlint:disable:this enum_case_associated_values_count sorted_enum_cases
    toolName: String, toolCallId: String, toolArguments: String?, result: String, success: Bool)

  /// A provider built-in tool execution has started
  case builtInToolStart(toolName: String, toolCallId: String, toolArguments: String?)  // swiftlint:disable:this line_length sorted_enum_cases

  /// A provider built-in tool execution has completed
  case builtInToolResult(toolName: String, toolCallId: String, result: String, success: Bool)  // swiftlint:disable:this enum_case_associated_values_count line_length sorted_enum_cases

  /// The stream has completed successfully
  case done  // swiftlint:disable:this sorted_enum_cases

  /// An error occurred during processing
  case error(message: String)  // swiftlint:disable:this sorted_enum_cases

  /// Usage limit information (may include exceeded warning and bonus messages)
  case wageyLimit(remaining: Int, resetDays: Int, exceeded: Bool, bonus: Int)  // swiftlint:disable:this enum_case_associated_values_count line_length sorted_enum_cases

  /// User does not have access to Wagey
  case wageyNoAccess  // swiftlint:disable:this sorted_enum_cases

  /// Rich source metadata for capable clients
  case sources(items: [MessageSource])  // swiftlint:disable:this sorted_enum_cases

  /// Latest server-authored compaction summary for reuse on subsequent turns.
  case compaction(content: String)  // swiftlint:disable:this sorted_enum_cases

  /// Future-compatible fallback for chunk types this app version does not understand.
  case unknown(type: String)  // swiftlint:disable:this sorted_enum_cases
}

// MARK: - ChatChunk Decodable

extension ChatChunk: Decodable {  // swiftlint:disable:this file_types_order no_grouping_extension
  private enum CodingKeys: String, CodingKey {
    case type  // swiftlint:disable:this explicit_enum_raw_value
    case content  // swiftlint:disable:this explicit_enum_raw_value
    case status  // swiftlint:disable:this explicit_enum_raw_value
    case toolName  // swiftlint:disable:this explicit_enum_raw_value
    case toolCallId  // swiftlint:disable:this explicit_enum_raw_value
    case toolArguments  // swiftlint:disable:this explicit_enum_raw_value
    case result  // swiftlint:disable:this explicit_enum_raw_value
    case success  // swiftlint:disable:this explicit_enum_raw_value
    case error  // swiftlint:disable:this explicit_enum_raw_value
    case remaining  // swiftlint:disable:this explicit_enum_raw_value
    case resetDays  // swiftlint:disable:this explicit_enum_raw_value
    case exceeded  // swiftlint:disable:this explicit_enum_raw_value
    case bonus  // swiftlint:disable:this explicit_enum_raw_value
    case items  // swiftlint:disable:this explicit_enum_raw_value
  }

  init(from decoder: Decoder) throws {  // swiftlint:disable:this cyclomatic_complexity explicit_acl function_body_length
    let container = try decoder.container(keyedBy: CodingKeys.self)  // swiftlint:disable:this explicit_type_interface
    let type = try container.decode(String.self, forKey: .type)  // swiftlint:disable:this explicit_type_interface

    switch type {
    case "status":
      let status = try container.decode(String.self, forKey: .status)  // swiftlint:disable:this explicit_type_interface
      self = .status(thinking: status == "thinking")

    case "text_start":
      self = .textStart

    case "message_break":
      self = .messageBreak

    case "text":
      let content = try container.decode(String.self, forKey: .content)  // swiftlint:disable:this explicit_type_interface line_length
      self = .text(content: content)

    case "tool_start":
      let toolName = try container.decode(String.self, forKey: .toolName)  // swiftlint:disable:this explicit_type_interface line_length
      let toolCallId = try container.decode(String.self, forKey: .toolCallId)  // swiftlint:disable:this explicit_type_interface line_length
      let toolArguments = try container.decodeIfPresent(String.self, forKey: .toolArguments)  // swiftlint:disable:this explicit_type_interface line_length
      self = .toolStart(toolName: toolName, toolCallId: toolCallId, toolArguments: toolArguments)

    case "tool_result":
      let toolName = try container.decode(String.self, forKey: .toolName)  // swiftlint:disable:this explicit_type_interface line_length
      let toolCallId = try container.decode(String.self, forKey: .toolCallId)  // swiftlint:disable:this explicit_type_interface line_length
      let toolArguments = try container.decodeIfPresent(String.self, forKey: .toolArguments)  // swiftlint:disable:this explicit_type_interface line_length
      let result = try container.decode(String.self, forKey: .result)  // swiftlint:disable:this explicit_type_interface
      let success = try container.decode(Bool.self, forKey: .success)  // swiftlint:disable:this explicit_type_interface
      self = .toolResult(
        toolName: toolName,
        toolCallId: toolCallId,
        toolArguments: toolArguments,
        result: result,
        success: success)  // swiftlint:disable:this multiline_arguments_brackets

    case "wagey_built_in_tool_start":
      let toolName = try container.decode(String.self, forKey: .toolName)  // swiftlint:disable:this explicit_type_interface line_length
      let toolCallId = try container.decode(String.self, forKey: .toolCallId)  // swiftlint:disable:this explicit_type_interface line_length
      let toolArguments = try container.decodeIfPresent(String.self, forKey: .toolArguments)  // swiftlint:disable:this explicit_type_interface line_length
      self = .builtInToolStart(
        toolName: toolName, toolCallId: toolCallId, toolArguments: toolArguments)  // swiftlint:disable:this line_length multiline_arguments_brackets

    case "wagey_built_in_tool_result":
      let toolName = try container.decode(String.self, forKey: .toolName)  // swiftlint:disable:this explicit_type_interface line_length
      let toolCallId = try container.decode(String.self, forKey: .toolCallId)  // swiftlint:disable:this explicit_type_interface line_length
      let result = try container.decode(String.self, forKey: .result)  // swiftlint:disable:this explicit_type_interface
      let success = try container.decode(Bool.self, forKey: .success)  // swiftlint:disable:this explicit_type_interface
      self = .builtInToolResult(
        toolName: toolName, toolCallId: toolCallId, result: result, success: success)  // swiftlint:disable:this line_length multiline_arguments_brackets

    case "done":
      self = .done

    case "error":
      let message = try container.decode(String.self, forKey: .error)  // swiftlint:disable:this explicit_type_interface
      self = .error(message: message)

    case "wagey_limit":
      let remaining = try container.decode(Int.self, forKey: .remaining)  // swiftlint:disable:this explicit_type_interface line_length
      let resetDays = try container.decode(Int.self, forKey: .resetDays)  // swiftlint:disable:this explicit_type_interface line_length
      let exceeded = try container.decodeIfPresent(Bool.self, forKey: .exceeded) ?? false  // swiftlint:disable:this explicit_type_interface line_length
      let bonus = try container.decodeIfPresent(Int.self, forKey: .bonus) ?? 0  // swiftlint:disable:this explicit_type_interface line_length
      self = .wageyLimit(
        remaining: remaining, resetDays: resetDays, exceeded: exceeded, bonus: bonus)  // swiftlint:disable:this line_length multiline_arguments_brackets

    case "wagey_no_access":
      self = .wageyNoAccess

    case "wagey_sources":
      let items = try container.decode([MessageSource].self, forKey: .items)  // swiftlint:disable:this explicit_type_interface line_length
      self = .sources(items: items)

    case "wagey_compaction":
      let content = try container.decode(String.self, forKey: .content)  // swiftlint:disable:this explicit_type_interface line_length
      self = .compaction(content: content)

    default:
      self = .unknown(type: type)
    }
  }
}

// MARK: - Wagey Access Info

/// Information about the user's Wagey access level and remaining messages.
struct WageyAccessInfo: Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  /// Whether the user has access to Wagey
  let hasAccess: Bool  // swiftlint:disable:this explicit_acl type_contents_order

  /// The user's subscription tier (e.g., "pro", "max", "free")
  let tier: String?  // swiftlint:disable:this explicit_acl type_contents_order

  /// Number of messages remaining this period
  let remaining: Int?  // swiftlint:disable:this explicit_acl type_contents_order

  /// Number of days until the limit resets
  let resetDays: Int?  // swiftlint:disable:this explicit_acl type_contents_order

  /// Whether the user has reached their message limit
  var isLimitReached: Bool {  // swiftlint:disable:this explicit_acl type_contents_order
    guard let remaining else { return false }  // swiftlint:disable:this conditional_returns_on_newline
    return remaining <= 0
  }

  /// Create an access info indicating no access
  static let noAccess = Self(  // swiftlint:disable:this explicit_acl explicit_type_interface
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
struct APIMessage: Codable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let role: String  // swiftlint:disable:this explicit_acl type_contents_order
  let content: String  // swiftlint:disable:this explicit_acl type_contents_order
  let toolCalls: [APIToolCall]?  // swiftlint:disable:this discouraged_optional_collection explicit_acl line_length type_contents_order
  let toolCallId: String?  // swiftlint:disable:this explicit_acl type_contents_order
  let name: String?  // swiftlint:disable:this explicit_acl type_contents_order

  private enum CodingKeys: String, CodingKey {
    case role  // swiftlint:disable:this explicit_enum_raw_value
    case content  // swiftlint:disable:this explicit_enum_raw_value
    case toolCalls = "tool_calls"
    case toolCallId = "tool_call_id"
    case name  // swiftlint:disable:this explicit_enum_raw_value
  }

  /// Create an API message from a ChatMessage
  static func from(_ message: ChatMessage) -> Self {  // swiftlint:disable:this explicit_acl
    let functionToolCalls = message.toolCalls?.filter { !$0.isBuiltIn }  // swiftlint:disable:this explicit_type_interface line_length

    return Self(
      role: message.role.rawValue,
      content: message.content,
      toolCalls: functionToolCalls?.map { APIToolCall.from($0) },
      toolCallId: nil,
      name: nil
    )
  }
}

/// Tool call format for the API
struct APIToolCall: Codable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let id: String  // swiftlint:disable:this explicit_acl
  let type: String  // swiftlint:disable:this explicit_acl
  let function: APIFunctionCall  // swiftlint:disable:this explicit_acl

  static func from(_ toolCall: ToolCall) -> Self {  // swiftlint:disable:this explicit_acl
    Self(
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
struct APIFunctionCall: Codable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let name: String  // swiftlint:disable:this explicit_acl
  let arguments: String  // swiftlint:disable:this explicit_acl
}

// MARK: - Preview Data

extension ChatMessage {  // swiftlint:disable:this no_grouping_extension
  /// Sample messages for previews
  static let previewConversation: [ChatMessage] = [  // swiftlint:disable:this explicit_acl
    .user("Add a shift tomorrow from 9 to 17"),
    ChatMessage(
      id: "assistant-1",
      role: .assistant,
      content:
        "I've added a shift for tomorrow (January 28th) from 09:00 to 17:00. That's an 8-hour shift. Is there anything else you'd like me to help you with?",  // swiftlint:disable:this line_length
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
        "Based on your current shifts this month, you'll earn approximately 15,200 kr before tax. With your 7.5% tax rate, that's about 14,060 kr net.",  // swiftlint:disable:this line_length
      toolCalls: nil,
      timestamp: Date()
    ),
  ]
}

extension WageyAccessInfo {  // swiftlint:disable:this no_grouping_extension
  /// Preview data for testing
  static let previewPro = WageyAccessInfo(  // swiftlint:disable:this explicit_acl explicit_type_interface
    hasAccess: true,
    tier: "pro",
    remaining: 45,  // swiftlint:disable:this no_magic_numbers
    resetDays: 12  // swiftlint:disable:this no_magic_numbers
  )

  static let previewMax = WageyAccessInfo(  // swiftlint:disable:this explicit_acl explicit_type_interface
    hasAccess: true,
    tier: "max",
    remaining: nil,
    resetDays: nil
  )

  static let previewLimitReached = WageyAccessInfo(  // swiftlint:disable:this explicit_acl explicit_type_interface
    hasAccess: true,
    tier: "pro",
    remaining: 0,
    resetDays: 5  // swiftlint:disable:this no_magic_numbers
  )
}  // swiftlint:disable:this file_length
