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
        let content = firstUserMessage?.content ?? ""
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
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.messagesData = (try? JSONEncoder().encode(messages)) ?? Data()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Stored Chat Message

/// Codable version of ChatMessage for persistence
struct StoredChatMessage: Codable, Identifiable, Equatable {
    let id: String
    let role: StoredMessageRole
    let content: String
    let toolCalls: [StoredToolCall]?
    let timestamp: Date

    init(id: String, role: StoredMessageRole, content: String, toolCalls: [StoredToolCall]?, timestamp: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.timestamp = timestamp
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
    let arguments: String?
    let result: String?
    let success: Bool?
}

// MARK: - Conversion Extensions

extension StoredChatMessage {
    /// Convert from ChatMessage (runtime model)
    init(from message: ChatMessage) {
        self.id = message.id
        self.role = StoredMessageRole(rawValue: message.role.rawValue) ?? .user
        self.content = message.content
        self.toolCalls = message.toolCalls?.map { StoredToolCall(from: $0) }
        self.timestamp = message.timestamp
    }

    /// Convert to ChatMessage (runtime model)
    func toChatMessage() -> ChatMessage {
        ChatMessage(
            id: id,
            role: MessageRole(rawValue: role.rawValue) ?? .user,
            content: content,
            toolCalls: toolCalls?.map { $0.toToolCall() },
            timestamp: timestamp
        )
    }
}

extension StoredToolCall {
    /// Convert from ToolCall (runtime model)
    init(from toolCall: ToolCall) {
        self.id = toolCall.id
        self.name = toolCall.name
        self.arguments = toolCall.arguments
        self.result = toolCall.result
        self.success = toolCall.success
    }

    /// Convert to ToolCall (runtime model)
    func toToolCall() -> ToolCall {
        ToolCall(
            id: id,
            name: name,
            arguments: arguments,
            result: result,
            success: success
        )
    }
}
