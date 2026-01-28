import Foundation
import SwiftUI
import Combine
import Supabase
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "WageyViewModel")

// MARK: - Wagey Invocations

/// Wagey message usage data from the profiles table
struct WageyInvocations: Codable {
    let count: Int
    let month: String?

    /// Whether the stored month matches the current month
    /// If not, the count should be considered 0 (will reset on next invocation)
    var isCurrentMonth: Bool {
        guard let month = month else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let currentMonth = formatter.string(from: Date())
        return month == currentMonth
    }

    /// Effective count considering month reset
    /// Returns 0 if the month doesn't match current month
    var effectiveCount: Int {
        isCurrentMonth ? count : 0
    }
}

/// Profile data from the profiles table
private struct ProfileData: Codable {
    let wagey_invocations: WageyInvocations?
}

/// ViewModel for the Wagey AI chat feature
/// Manages conversation state, streaming, persistence, and user interactions
@MainActor
@Observable
final class WageyViewModel {
    // MARK: - Shared Instance

    /// Shared instance that persists across view presentations within the same session
    /// This ensures the current conversation is retained when dismissing and reopening Wagey
    static let shared = WageyViewModel()

    // MARK: - Constants

    /// Message limits per tier
    private static let messageLimits: [SubscriptionTier: Int] = [
        .free: 3,
        .pro: 40,
        .max: 90
    ]

    // MARK: - Published State

    /// All conversations for the current user
    private(set) var conversations: [LocalConversation] = []

    /// Current conversation ID (nil for new unsaved conversation)
    private(set) var currentConversationId: String?

    /// Conversation history for the current conversation
    private(set) var messages: [ChatMessage] = []

    /// Content blocks being streamed from the assistant (in chronological order)
    private(set) var activeContentBlocks: [ContentBlock] = []

    /// Whether currently receiving a streaming response
    private(set) var isStreaming: Bool = false

    /// Whether the user has reached their message limit
    private(set) var limitReached: Bool = false

    /// Local count of messages sent this session (used when server data unavailable)
    private(set) var localMessagesSent: Int = 0

    /// Days until limit resets (for showing in limit reached message)
    private(set) var resetDays: Int = 0

    /// Wagey invocations from the profiles table (used to calculate usage)
    private(set) var wageyInvocations: WageyInvocations?

    /// Current error if any
    private(set) var error: Error?

    /// Whether an entitlement sync is in progress (server/StoreKit mismatch detected)
    private(set) var isSyncingEntitlement: Bool = false

    /// Message to show after entitlement sync (success or failure)
    private(set) var entitlementSyncMessage: String?

    /// Whether the user has seen the showcase (per user, stored in UserDefaults)
    private(set) var hasSeenShowcase: Bool = false

    // MARK: - Computed Properties for Usage

    /// The user's current subscription tier
    var currentTier: SubscriptionTier {
        EntitlementService.shared.effectiveTier
    }

    /// The message limit for the current tier
    var messageLimit: Int {
        Self.messageLimits[currentTier] ?? 3
    }

    /// Number of messages used this month
    /// Uses profile data (wagey_invocations) when available, falls back to local session count
    var messagesUsed: Int {
        if let invocations = wageyInvocations {
            // Use profile data - effectiveCount handles month reset
            return invocations.effectiveCount + localMessagesSent
        }
        // Fall back to local session count when profile data unavailable
        return localMessagesSent
    }

    /// Number of messages remaining this month
    var remainingMessagesCount: Int {
        max(0, messageLimit - messagesUsed)
    }

    /// Whether to show the showcase (free tier + hasn't seen it)
    var shouldShowShowcase: Bool {
        currentTier == .free && !hasSeenShowcase
    }

    // MARK: - Computed Properties for Streaming

    /// Current streaming text (concatenated from all text blocks)
    var currentStreamingText: String {
        activeContentBlocks.compactMap { block in
            if case .text(let text) = block { return text }
            return nil
        }.joined()
    }

    /// Active tool calls (extracted from content blocks for UI)
    var activeToolCalls: [ToolCall] {
        activeContentBlocks.compactMap { block in
            if case .toolCall(let toolCall) = block { return toolCall }
            return nil
        }
    }

    /// Whether the sidebar is visible
    var isSidebarVisible: Bool = false

    // MARK: - Private State

    /// Whether any tool calls succeeded during the current stream (triggers sync)
    private var hadSuccessfulToolCalls: Bool = false

    /// Current streaming task (for cancellation)
    private var streamTask: Task<Void, Never>?

    /// ID of the message currently being streamed
    private var currentAssistantMessageId: String?

    /// Repository for conversation persistence
    private let conversationsRepository = ConversationsRepository.shared

    /// Cached user ID for persistence
    private var cachedUserId: String?

    /// Subscription for observing tier changes
    private var tierChangeSubscription: AnyCancellable?

    // MARK: - Initialization

    /// Private initializer to enforce singleton pattern
    private init() {
        loadConversations()
        loadShowcaseState()
        observeTierChanges()
    }

    /// Observe tier changes to reset limit state when user upgrades
    private func observeTierChanges() {
        tierChangeSubscription = EntitlementService.shared.$effectiveTier
            .dropFirst() // Skip initial value
            .sink { [weak self] newTier in
                guard let self = self else { return }
                // If user upgraded to paid tier, reset the limit reached flag
                if newTier != .free && self.limitReached {
                    self.limitReached = false
                    // Also reset local counter since they have new limits now
                    self.localMessagesSent = 0
                    self.wageyInvocations = nil
                }
            }
    }

    // MARK: - Showcase State Management

    /// UserDefaults key for showcase seen state (per user)
    private func showcaseKey(for userId: String) -> String {
        "wagey.hasSeenShowcase.\(userId)"
    }

    /// Load the showcase seen state from UserDefaults
    private func loadShowcaseState() {
        guard let userId = AppCoordinator.shared.userId else {
            hasSeenShowcase = false
            return
        }
        hasSeenShowcase = UserDefaults.standard.bool(forKey: showcaseKey(for: userId))
    }

    /// Mark the showcase as seen and save to UserDefaults
    func markShowcaseSeen() {
        guard let userId = AppCoordinator.shared.userId else { return }
        hasSeenShowcase = true
        UserDefaults.standard.set(true, forKey: showcaseKey(for: userId))
    }

    /// Reset the showcase state (for debugging) - clears UserDefaults and cached state
    func resetShowcaseSeen() {
        guard let userId = AppCoordinator.shared.userId else { return }
        hasSeenShowcase = false
        UserDefaults.standard.removeObject(forKey: showcaseKey(for: userId))
    }

    // MARK: - Conversation Management

    /// Load all conversations for the current user
    func loadConversations() {
        guard let userId = AppCoordinator.shared.userId else { return }
        cachedUserId = userId
        conversations = conversationsRepository.getConversations(for: userId)
        loadShowcaseState()
    }

    /// Fetch wagey usage data from the profiles table
    /// Call this when opening Wagey to get the current usage count
    func fetchWageyUsage() async {
        guard let userId = AppCoordinator.shared.userId else { return }

        do {
            let profile: ProfileData = try await supabase
                .from("profiles")
                .select("wagey_invocations")
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            wageyInvocations = profile.wagey_invocations
            // Reset local counter since we have authoritative server data
            localMessagesSent = 0

            // Check if limit is already reached based on profile data
            if let invocations = wageyInvocations {
                let used = invocations.effectiveCount
                if used >= messageLimit {
                    limitReached = true
                }
            }
        } catch {
            // Non-fatal - we can still use local counter as fallback
            // Don't set self.error since this shouldn't block the user
        }
    }

    /// Load a specific conversation
    /// - Parameter id: Conversation ID to load
    func loadConversation(id: String) {
        guard let conversation = conversationsRepository.getConversation(id: id) else {
            return
        }

        // Cancel any ongoing stream
        cancelStream()

        // Load the conversation
        currentConversationId = id
        messages = conversation.messages.map { $0.toChatMessage() }
        error = nil
    }

    /// Start a new conversation (clears current state)
    func startNewConversation() {
        // Cancel any ongoing stream
        cancelStream()

        // Save current conversation if it has messages
        saveCurrentConversation()

        // Reset state for new conversation
        currentConversationId = nil
        messages = []
        activeContentBlocks = []
        error = nil

        // Reload conversations list
        loadConversations()
    }

    /// Delete a conversation
    /// - Parameter id: Conversation ID to delete
    func deleteConversation(id: String) {
        conversationsRepository.deleteConversation(id: id)

        // If deleting the current conversation, start a new one
        if id == currentConversationId {
            startNewConversation()
        } else {
            loadConversations()
        }
    }

    /// Toggle sidebar visibility
    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    /// Get the current conversation title
    var currentConversationTitle: String {
        if let id = currentConversationId,
           let conversation = conversations.first(where: { $0.id == id }) {
            return conversation.title
        }
        return "New Conversation"
    }

    // MARK: - Public Actions

    /// Send a new message to Wagey
    /// - Parameter content: The message content to send
    func sendMessage(_ content: String) async {
        // Don't send if already streaming or limit reached
        guard !isStreaming && !limitReached else { return }

        // Clear any previous error
        error = nil

        // Add user message to conversation
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: content,
            toolCalls: nil,
            timestamp: Date()
        )
        messages.append(userMessage)

        // Increment local message counter for progress bar
        localMessagesSent += 1

        // Create conversation if this is the first message
        if currentConversationId == nil {
            createNewConversation()
        }

        // Save after adding user message
        saveCurrentConversation()

        // Start streaming
        isStreaming = true
        activeContentBlocks = []
        hadSuccessfulToolCalls = false
        currentAssistantMessageId = UUID().uuidString

        // Create streaming task
        streamTask = Task {
            do {
                // Get user info from AppCoordinator
                let coordinator = AppCoordinator.shared
                guard let userId = coordinator.userId else {
                    throw WageyError.notAuthenticated
                }
                let userName = coordinator.userDisplayName.isEmpty ? nil : coordinator.userDisplayName

                // Start streaming from WageyService
                let stream = WageyService.shared.streamChat(
                    messages: messages,
                    userId: userId,
                    userName: userName
                )

                // Process chunks
                for try await chunk in stream {
                    // Check for cancellation
                    if Task.isCancelled { break }

                    processChunk(chunk)
                }

                // Finalize the message if not cancelled
                if !Task.isCancelled {
                    finalizeStreamingText()
                }
            } catch {
                if !Task.isCancelled {
                    self.error = error
                    finalizeStreamingText()
                }
            }
        }
    }

    /// Cancel the current streaming response
    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil

        // Finalize any partial message
        if isStreaming {
            finalizeStreamingText()
        }
    }

    /// Clear the conversation and start a new chat (legacy method, now calls startNewConversation)
    func clearConversation() {
        startNewConversation()
    }

    /// Dismiss the current error
    func dismissError() {
        error = nil
    }

    /// Reset the limit reached flag (called when user upgrades tier)
    /// This allows paid users to continue chatting even if server cache is stale
    func resetLimitReached() {
        limitReached = false
        localMessagesSent = 0
        wageyInvocations = nil
    }

    // MARK: - Private Helpers

    /// Trigger a background entitlement sync when server/StoreKit mismatch is detected
    /// This uploads the StoreKit subscription to the server to fix the mismatch
    private func triggerEntitlementSync() async {
        logger.info("Triggering entitlement sync due to server/StoreKit mismatch")

        isSyncingEntitlement = true
        entitlementSyncMessage = nil

        do {
            // Restore will sync with Apple and upload any valid entitlements to the server
            try await StoreKitManager.shared.restorePurchases()
            logger.info("Entitlement sync completed successfully")

            // Show brief success feedback
            entitlementSyncMessage = AuthStrings.string(
                "wagey.entitlementSync.success",
                locale: LocalizationManager.shared.currentLocale
            )

            // Auto-dismiss after 3 seconds
            Task {
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    if self.entitlementSyncMessage != nil {
                        self.entitlementSyncMessage = nil
                    }
                }
            }
        } catch {
            logger.error("Entitlement sync failed: \(error.localizedDescription)")

            // Show error with suggestion to restore manually
            entitlementSyncMessage = AuthStrings.string(
                "wagey.entitlementSync.failed",
                locale: LocalizationManager.shared.currentLocale
            )
        }

        isSyncingEntitlement = false
    }

    /// Dismiss the entitlement sync message
    func dismissEntitlementSyncMessage() {
        entitlementSyncMessage = nil
    }

    /// Create a new conversation in the database
    private func createNewConversation() {
        guard let userId = cachedUserId ?? AppCoordinator.shared.userId else { return }

        let conversation = conversationsRepository.createConversation(
            for: userId,
            title: "New Conversation"
        )
        currentConversationId = conversation.id
        loadConversations()
    }

    /// Save the current conversation to the database
    private func saveCurrentConversation() {
        guard let conversationId = currentConversationId else { return }

        let storedMessages = messages.map { StoredChatMessage(from: $0) }
        conversationsRepository.updateMessages(
            conversationId: conversationId,
            messages: storedMessages
        )
        loadConversations()
    }

    /// Process a single chunk from the stream
    private func processChunk(_ chunk: ChatChunk) {
        switch chunk {
        case .text(let content):
            // Append text to the last text block, or create a new one
            if let lastIndex = activeContentBlocks.indices.last,
               case .text(let existingText) = activeContentBlocks[lastIndex] {
                // Append to existing text block
                activeContentBlocks[lastIndex] = .text(existingText + content)
            } else {
                // Create new text block
                activeContentBlocks.append(.text(content))
            }

        case .toolStart(let toolName, let toolCallId, let toolArguments):
            // Add a new tool call in progress
            let toolCall = ToolCall(
                id: toolCallId,
                name: toolName,
                arguments: toolArguments,
                result: nil,
                success: nil
            )
            activeContentBlocks.append(.toolCall(toolCall))

        case .toolResult(let toolName, let toolCallId, let result, let success):
            // Update the tool call with its result (find by id in content blocks)
            if let index = activeContentBlocks.firstIndex(where: { block in
                if case .toolCall(let tc) = block { return tc.id == toolCallId }
                return false
            }), case .toolCall(let existingToolCall) = activeContentBlocks[index] {
                let updatedToolCall = ToolCall(
                    id: toolCallId,
                    name: toolName,
                    arguments: existingToolCall.arguments,
                    result: result,
                    success: success
                )
                activeContentBlocks[index] = .toolCall(updatedToolCall)
            }
            // Track successful tool calls for sync
            if success == true {
                hadSuccessfulToolCalls = true
            }

        case .wageyLimit(let remaining, let days, let exceeded):
            // Update wagey invocations from API response to stay in sync
            // The count is: limit - remaining
            let usedCount = max(0, messageLimit - remaining)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM"
            let currentMonth = formatter.string(from: Date())
            wageyInvocations = WageyInvocations(count: usedCount, month: currentMonth)
            // Reset local counter since we have fresh server data
            localMessagesSent = 0
            resetDays = days
            if remaining <= 0 {
                limitReached = true
            }

            // Entitlement mismatch detection:
            // If server says exceeded but StoreKit has valid entitlements, trigger background sync
            // This handles cases where server doesn't know about a valid Apple subscription
            if exceeded && StoreKitManager.shared.currentTier != .free {
                logger.warning("Entitlement mismatch detected: server says exceeded but StoreKit has tier \(StoreKitManager.shared.currentTier.rawValue)")
                Task {
                    await triggerEntitlementSync()
                }
            }

        case .wageyNoAccess:
            // User doesn't have access to Wagey
            limitReached = true
            error = WageyError.noAccess

        case .done:
            // Stream completed - finalize handled after loop
            break

        case .error(let message):
            // Server-side error
            error = WageyError.serverError(message)
        }
    }

    /// Finalize the streaming text into a message
    private func finalizeStreamingText() {
        // Only create a message if we have content blocks
        if !activeContentBlocks.isEmpty {
            let assistantMessage = ChatMessage(
                id: currentAssistantMessageId ?? UUID().uuidString,
                role: .assistant,
                contentBlocks: activeContentBlocks,
                timestamp: Date()
            )
            messages.append(assistantMessage)

            // Save after assistant responds
            saveCurrentConversation()
        }

        // Trigger sync if any tool calls succeeded (shifts may have changed)
        if hadSuccessfulToolCalls, let userId = cachedUserId ?? AppCoordinator.shared.userId {
            Task {
                await SyncCoordinator.shared.sync(reason: .localChange, userId: userId)
            }
        }

        // Reset streaming state
        activeContentBlocks = []
        hadSuccessfulToolCalls = false
        isStreaming = false
        currentAssistantMessageId = nil
        streamTask = nil
    }
}

// MARK: - Wagey Errors

/// Errors specific to the Wagey feature
enum WageyError: LocalizedError {
    case notAuthenticated
    case noAccess
    case serverError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to use Wagey"
        case .noAccess:
            return "Upgrade to Pro or Max to use Wagey"
        case .serverError(let message):
            return message
        case .networkError(let error):
            return error.localizedDescription
        }
    }
}
