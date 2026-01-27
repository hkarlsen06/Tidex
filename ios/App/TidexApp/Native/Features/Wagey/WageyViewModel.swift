import Foundation
import SwiftUI

/// ViewModel for the Wagey AI chat feature
/// Manages conversation state, streaming, and user interactions
@MainActor
@Observable
final class WageyViewModel {
    // MARK: - Published State

    /// Conversation history
    private(set) var messages: [ChatMessage] = []

    /// Text being streamed from the assistant
    private(set) var currentStreamingText: String = ""

    /// Whether currently receiving a streaming response
    private(set) var isStreaming: Bool = false

    /// Whether the user has reached their message limit
    private(set) var limitReached: Bool = false

    /// Number of messages remaining this month (nil if unknown)
    private(set) var remainingMessages: Int?

    /// Current error if any
    private(set) var error: Error?

    /// Tool calls in progress for the current streaming message
    private(set) var activeToolCalls: [ToolCall] = []

    // MARK: - Private State

    /// Current streaming task (for cancellation)
    private var streamTask: Task<Void, Never>?

    /// ID of the message currently being streamed
    private var currentAssistantMessageId: String?

    // MARK: - Initialization

    init() {}

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

        // Start streaming
        isStreaming = true
        currentStreamingText = ""
        activeToolCalls = []
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

    /// Clear the conversation and start a new chat
    func clearConversation() {
        // Cancel any ongoing stream
        cancelStream()

        // Reset state
        messages = []
        currentStreamingText = ""
        activeToolCalls = []
        error = nil
        limitReached = false
        currentAssistantMessageId = nil
    }

    /// Dismiss the current error
    func dismissError() {
        error = nil
    }

    // MARK: - Private Helpers

    /// Process a single chunk from the stream
    private func processChunk(_ chunk: ChatChunk) {
        switch chunk {
        case .text(let content):
            // Append text to streaming buffer
            currentStreamingText += content

        case .toolStart(let toolName, let toolCallId, let toolArguments):
            // Add a new tool call in progress
            let toolCall = ToolCall(
                id: toolCallId,
                name: toolName,
                arguments: toolArguments,
                result: nil,
                success: nil
            )
            activeToolCalls.append(toolCall)

        case .toolResult(let toolName, let toolCallId, let result, let success):
            // Update the tool call with its result
            if let index = activeToolCalls.firstIndex(where: { $0.id == toolCallId }) {
                activeToolCalls[index] = ToolCall(
                    id: toolCallId,
                    name: toolName,
                    arguments: activeToolCalls[index].arguments,
                    result: result,
                    success: success
                )
            }

        case .wageyLimit(let remaining, _):
            // Update remaining messages count
            remainingMessages = remaining
            if remaining <= 0 {
                limitReached = true
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
        // Only create a message if we have content or tool calls
        if !currentStreamingText.isEmpty || !activeToolCalls.isEmpty {
            let assistantMessage = ChatMessage(
                id: currentAssistantMessageId ?? UUID().uuidString,
                role: .assistant,
                content: currentStreamingText,
                toolCalls: activeToolCalls.isEmpty ? nil : activeToolCalls,
                timestamp: Date()
            )
            messages.append(assistantMessage)
        }

        // Reset streaming state
        currentStreamingText = ""
        activeToolCalls = []
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
