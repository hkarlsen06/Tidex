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

    /// Ordered content blocks for assistant messages.
    /// Preserves the interleaved order of text and tool calls as they streamed in.
    /// For user messages, this will contain a single text block.
    var contentBlocks: [ContentBlock]

    /// Concatenated text content (for backward compatibility and API requests)
    var content: String {
        contentBlocks.compactMap { block in
            if case .text(let text) = block {
                return text
            }
            return nil
        }.joined()
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
    init(id: String = UUID().uuidString, role: MessageRole, contentBlocks: [ContentBlock], timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.contentBlocks = contentBlocks
        self.timestamp = timestamp
    }

    /// Convenience initializer with separate content and toolCalls (backward compatible)
    /// Tool calls are placed before text for backward compatibility with existing behavior
    init(id: String = UUID().uuidString, role: MessageRole, content: String, toolCalls: [ToolCall]? = nil, timestamp: Date = Date()) {
        self.id = id
        self.role = role
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

/// A block of content in an assistant message.
/// Preserves the chronological order of text and tool calls as they stream in.
enum ContentBlock: Identifiable, Equatable {
    case text(String)
    case toolCall(ToolCall)

    var id: String {
        switch self {
        case .text(let content):
            // Use a hash of the text for identity (text blocks don't have natural IDs)
            return "text-\(content.hashValue)"
        case .toolCall(let toolCall):
            return toolCall.id
        }
    }
}

// MARK: - Tool Call

/// A tool call that was executed during an assistant response.
///
/// Tool calls represent actions the AI takes to fulfill the user's request,
/// such as creating a shift or checking the schedule.
struct ToolCall: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    var arguments: String?
    var result: String?
    var success: Bool?

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
}

// MARK: - Chat Chunk

/// A chunk from the streaming chat API.
///
/// The API streams responses as Server-Sent Events, with each event
/// containing a chunk of one of these types.
enum ChatChunk: Equatable {
    /// Text content to append to the current message
    case text(content: String)

    /// A tool execution has started
    case toolStart(toolName: String, toolCallId: String, toolArguments: String?)

    /// A tool execution has completed
    case toolResult(toolName: String, toolCallId: String, result: String, success: Bool)

    /// The stream has completed successfully
    case done

    /// An error occurred during processing
    case error(message: String)

    /// Usage limit information (may include exceeded warning)
    case wageyLimit(remaining: Int, resetDays: Int, exceeded: Bool)

    /// User does not have access to Wagey
    case wageyNoAccess
}

// MARK: - ChatChunk Decodable

extension ChatChunk: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case content
        case toolName
        case toolCallId
        case toolArguments
        case result
        case success
        case error
        case remaining
        case resetDays
        case exceeded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
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
            let result = try container.decode(String.self, forKey: .result)
            let success = try container.decode(Bool.self, forKey: .success)
            self = .toolResult(toolName: toolName, toolCallId: toolCallId, result: result, success: success)

        case "done":
            self = .done

        case "error":
            let message = try container.decode(String.self, forKey: .error)
            self = .error(message: message)

        case "wagey_limit":
            let remaining = try container.decode(Int.self, forKey: .remaining)
            let resetDays = try container.decode(Int.self, forKey: .resetDays)
            let exceeded = try container.decodeIfPresent(Bool.self, forKey: .exceeded) ?? false
            self = .wageyLimit(remaining: remaining, resetDays: resetDays, exceeded: exceeded)

        case "wagey_no_access":
            self = .wageyNoAccess

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown chunk type: \(type)"
            )
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
        APIMessage(
            role: message.role.rawValue,
            content: message.content,
            toolCalls: message.toolCalls?.map { APIToolCall.from($0) },
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
            content: "I've added a shift for tomorrow (January 28th) from 09:00 to 17:00. That's an 8-hour shift. Is there anything else you'd like me to help you with?",
            toolCalls: [
                ToolCall(
                    id: "call_123",
                    name: "manage_shift",
                    arguments: "{\"action\":\"create\",\"date\":\"2025-01-28\",\"start\":\"09:00\",\"end\":\"17:00\"}",
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
            content: "Based on your current shifts this month, you'll earn approximately 15,200 kr before tax. With your 7.5% tax rate, that's about 14,060 kr net.",
            toolCalls: nil,
            timestamp: Date()
        )
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
