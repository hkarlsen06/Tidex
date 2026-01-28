import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ConversationsRepository")

// MARK: - Conversations Repository

/// Local repository for Wagey conversations
/// Conversations are stored locally only and not synced to server
@MainActor
final class ConversationsRepository: ObservableObject {
    static let shared = ConversationsRepository()

    private let localStore: LocalStore

    private init(localStore: LocalStore? = nil) {
        self.localStore = localStore ?? LocalStore.shared
    }

    // MARK: - Read Operations

    /// Get all conversations for a user, sorted by most recent first
    /// - Parameter userId: User ID
    /// - Returns: Array of conversations
    func getConversations(for userId: String) -> [LocalConversation] {
        let context = localStore.mainContext
        let normalizedUserId = userId.uppercased()

        var descriptor = FetchDescriptor<LocalConversation>(
            predicate: #Predicate { $0.userId == normalizedUserId },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100 // Limit to most recent 100 conversations

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch conversations: \(error.localizedDescription)")
            return []
        }
    }

    /// Get a specific conversation by ID
    /// - Parameter id: Conversation ID
    /// - Returns: Conversation if found
    func getConversation(id: String) -> LocalConversation? {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalConversation>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            return try context.fetch(descriptor).first
        } catch {
            logger.error("Failed to fetch conversation: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Write Operations

    /// Create a new conversation
    /// - Parameters:
    ///   - userId: User ID
    ///   - title: Conversation title
    ///   - messages: Initial messages (optional)
    /// - Returns: Created conversation
    @discardableResult
    func createConversation(
        for userId: String,
        title: String,
        messages: [StoredChatMessage] = []
    ) -> LocalConversation {
        let context = localStore.mainContext
        let normalizedUserId = userId.uppercased()

        let conversation = LocalConversation(
            userId: normalizedUserId,
            title: title,
            messages: messages
        )

        context.insert(conversation)

        do {
            try context.save()
            logger.info("Created conversation: \(conversation.id)")
        } catch {
            logger.error("Failed to save new conversation: \(error.localizedDescription)")
        }

        return conversation
    }

    /// Update a conversation's messages
    /// - Parameters:
    ///   - id: Conversation ID
    ///   - messages: Updated messages array
    /// - Returns: Updated conversation if successful
    @discardableResult
    func updateMessages(
        conversationId id: String,
        messages: [StoredChatMessage]
    ) -> LocalConversation? {
        guard let conversation = getConversation(id: id) else {
            logger.warning("Conversation not found for update: \(id)")
            return nil
        }

        conversation.messages = messages
        conversation.updatedAt = Date()

        // Auto-update title from first user message if it was the default
        if conversation.title == "New Conversation" || conversation.title.isEmpty {
            if let firstUserMessage = messages.first(where: { $0.role == .user }) {
                conversation.title = generateTitle(from: firstUserMessage.content)
            }
        }

        guard let context = conversation.modelContext else {
            logger.error("Conversation has no model context")
            return nil
        }

        do {
            try context.save()
            logger.debug("Updated conversation messages: \(id)")
        } catch {
            logger.error("Failed to update conversation: \(error.localizedDescription)")
            return nil
        }

        return conversation
    }

    /// Update a conversation's title
    /// - Parameters:
    ///   - id: Conversation ID
    ///   - title: New title
    /// - Returns: Updated conversation if successful
    @discardableResult
    func updateTitle(
        conversationId id: String,
        title: String
    ) -> LocalConversation? {
        guard let conversation = getConversation(id: id) else {
            logger.warning("Conversation not found for title update: \(id)")
            return nil
        }

        conversation.title = title

        guard let context = conversation.modelContext else {
            logger.error("Conversation has no model context")
            return nil
        }

        do {
            try context.save()
            logger.debug("Updated conversation title: \(id)")
        } catch {
            logger.error("Failed to update conversation title: \(error.localizedDescription)")
            return nil
        }

        return conversation
    }

    /// Delete a conversation
    /// - Parameter id: Conversation ID
    /// - Returns: True if deleted successfully
    @discardableResult
    func deleteConversation(id: String) -> Bool {
        guard let conversation = getConversation(id: id) else {
            logger.warning("Conversation not found for deletion: \(id)")
            return false
        }

        guard let context = conversation.modelContext else {
            logger.error("Conversation has no model context")
            return false
        }

        context.delete(conversation)

        do {
            try context.save()
            logger.info("Deleted conversation: \(id)")
            return true
        } catch {
            logger.error("Failed to delete conversation: \(error.localizedDescription)")
            return false
        }
    }

    /// Delete all conversations for a user (on logout)
    /// - Parameter userId: User ID
    func deleteAll(for userId: String) {
        let conversations = getConversations(for: userId)

        guard !conversations.isEmpty else { return }

        let context = localStore.mainContext

        for conversation in conversations {
            context.delete(conversation)
        }

        do {
            try context.save()
            logger.info("Deleted \(conversations.count) conversations for user: \(userId)")
        } catch {
            logger.error("Failed to delete conversations: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// Generate a title from the first user message
    private func generateTitle(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Truncate to reasonable length
        if trimmed.count > 40 {
            return String(trimmed.prefix(37)) + "..."
        }

        return trimmed.isEmpty ? "New Conversation" : trimmed
    }
}
