import Foundation
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "WageyService")

// MARK: - API Request Types

/// Request body for the chat API endpoint
private struct ChatAPIRequest: Encodable {
  let routerStreamKey: String
  let input: ChatInput

  struct ChatInput: Encodable {
    let messages: [APIMessage]
    let userId: String
    let userName: String?
    let compaction: String?
  }

  struct APIMessage: Encodable {
    let role: String
    /// Content can be a string or array of content blocks (for multimodal messages)
    let content: APIMessageContent
    let toolCalls: [APIToolCall]?
    let toolCallId: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
      case role, content
      case toolCalls = "tool_calls"
      case toolCallId = "tool_call_id"
      case name
    }
  }

  /// Message content that can be either a string or array of content blocks
  enum APIMessageContent: Encodable {
    case text(String)
    case blocks([APIContentBlock])

    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .text(let text):
        try container.encode(text)
      case .blocks(let blocks):
        try container.encode(blocks)
      }
    }
  }

  /// Content block for multimodal messages
  enum APIContentBlock: Encodable {
    case text(String)
    case image(mediaType: String, base64Data: String)

    private enum CodingKeys: String, CodingKey {
      case type, text, source
    }

    private enum SourceKeys: String, CodingKey {
      case type, mediaType = "media_type", data
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case .text(let text):
        try container.encode("text", forKey: .type)
        try container.encode(text, forKey: .text)
      case .image(let mediaType, let base64Data):
        try container.encode("image", forKey: .type)
        var sourceContainer = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
        try sourceContainer.encode("base64", forKey: .type)
        try sourceContainer.encode(mediaType, forKey: .mediaType)
        try sourceContainer.encode(base64Data, forKey: .data)
      }
    }
  }

  struct APIToolCall: Encodable {
    let id: String
    let type: String
    let function: APIFunction

    struct APIFunction: Encodable {
      let name: String
      let arguments: String
    }
  }
}

// MARK: - Errors

enum WageyServiceError: Error, LocalizedError {
  case notAuthenticated
  case networkError(underlying: Error)
  case httpError(statusCode: Int, message: String?)
  case streamError(message: String)
  case cancelled

  var errorDescription: String? {
    switch self {
    case .notAuthenticated:
      return "Not authenticated"
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .httpError(let code, let message):
      return "HTTP \(code): \(message ?? "Unknown error")"
    case .streamError(let message):
      return "Stream error: \(message)"
    case .cancelled:
      return "Request was cancelled"
    }
  }
}

// MARK: - Wagey Service

/// Service for communicating with the Wagey chat API
/// Handles streaming SSE responses from the chat endpoint
@MainActor
final class WageyService: ObservableObject {
  static let shared = WageyService()

  @Published private(set) var isStreaming = false
  @Published private(set) var error: Error?

  /// Long-running URLSession for streaming requests
  /// Uses longer timeouts since chat responses can take time
  private let urlSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 120
    config.timeoutIntervalForResource = 300
    return URLSession(configuration: config)
  }()

  private init() {}

  // MARK: - Public API

  /// Stream chat responses from the Wagey API
  ///
  /// Sends messages to the `/api/chat` endpoint and returns a stream of chunks.
  /// The stream will emit text content, tool execution events, and completion/error events.
  ///
  /// - Parameters:
  ///   - messages: The conversation history to send
  ///   - userId: The current user's ID
  ///   - userName: The user's display name (optional, for personalization)
  ///   - compaction: Optional summary of older conversation context
  /// - Returns: An async stream of ChatChunk events
  func streamChat(
    messages: [ChatMessage],
    userId: String,
    userName: String?,
    compaction: String? = nil
  ) -> AsyncThrowingStream<ChatChunk, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        await self.performStreamRequest(
          messages: messages,
          userId: userId,
          userName: userName,
          compaction: compaction,
          continuation: continuation
        )
      }

      // Handle cancellation from the consumer side
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  // MARK: - Private Implementation

  /// Performs the actual streaming request
  private func performStreamRequest(
    messages: [ChatMessage],
    userId: String,
    userName: String?,
    compaction: String?,
    continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation
  ) async {
    isStreaming = true
    error = nil

    defer {
      Task { @MainActor in
        self.isStreaming = false
      }
    }

    do {
      // Check for cancellation
      try Task.checkCancellation()

      // Get the current session token
      let session = try await AuthSessionManager.shared.getSession()
      let accessToken = session.accessToken

      // Build the request
      let url = APIConfiguration.webAppBaseURL.appendingPathComponent("/api/chat")
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

      // Build request body - convert ChatMessages to API format
      // When assistant messages have tool calls, we need to also send tool result messages
      var apiMessages: [ChatAPIRequest.APIMessage] = []

      for message in messages {
        // Check if message has images
        let images = message.imageAttachments

        // Build content - use blocks if there are images, otherwise use plain text
        let content: ChatAPIRequest.APIMessageContent
        if !images.isEmpty {
          // Multimodal message with images
          var blocks: [ChatAPIRequest.APIContentBlock] = []

          // Add images first (Claude best practice)
          for image in images {
            blocks.append(
              .image(
                mediaType: image.mediaType,
                base64Data: image.base64String
              ))
          }

          // Add text content if present
          let textContent = message.content
          if !textContent.isEmpty {
            blocks.append(.text(textContent))
          }

          content = .blocks(blocks)
        } else {
          // Text-only message
          content = .text(message.content)
        }

        // Add the main message
        let apiMessage = ChatAPIRequest.APIMessage(
          role: message.role.rawValue,
          content: content,
          toolCalls: message.toolCalls?.map { toolCall in
            ChatAPIRequest.APIToolCall(
              id: toolCall.id,
              type: "function",
              function: ChatAPIRequest.APIToolCall.APIFunction(
                name: toolCall.name,
                arguments: toolCall.arguments ?? "{}"
              )
            )
          },
          toolCallId: nil,
          name: nil
        )
        apiMessages.append(apiMessage)

        // If this assistant message had tool calls, add tool result messages
        // IMPORTANT: We must send a tool_result for EVERY tool_use, or Claude API fails
        // If a tool call has no result (timed out), send a synthetic failure result
        if message.role == .assistant, let toolCalls = message.toolCalls {
          for toolCall in toolCalls {
            let resultContent: String
            if let result = toolCall.result {
              resultContent = result
            } else {
              // Tool call never got a result (timeout, connection lost, etc.)
              // Send a synthetic failure result so Claude knows it failed
              resultContent =
                "{\"success\":false,\"message\":\"Tool call timed out or was interrupted\"}"
            }
            let toolResultMessage = ChatAPIRequest.APIMessage(
              role: "tool",
              content: .text(resultContent),
              toolCalls: nil,
              toolCallId: toolCall.id,
              name: toolCall.name
            )
            apiMessages.append(toolResultMessage)
          }
        }
      }

      // Debug log the messages being sent
      logger.debug("Sending \(apiMessages.count) messages to chat API")
      for (index, msg) in apiMessages.enumerated() {
        let contentInfo: String
        switch msg.content {
        case .text(let text):
          contentInfo = "text(\(text.count) chars)"
        case .blocks(let blocks):
          let imageCount = blocks.filter {
            if case .image = $0 { return true } else { return false }
          }.count
          let textCount = blocks.filter { if case .text = $0 { return true } else { return false } }
            .count
          contentInfo = "blocks(\(imageCount) images, \(textCount) texts)"
        }
        logger.debug(
          "  [\(index)] role=\(msg.role), content=\(contentInfo), toolCalls=\(msg.toolCalls?.count ?? 0), toolCallId=\(msg.toolCallId ?? "nil")"
        )
      }

      let requestBody = ChatAPIRequest(
        routerStreamKey: "wagey",
        input: ChatAPIRequest.ChatInput(
          messages: apiMessages,
          userId: userId,
          userName: userName,
          compaction: compaction
        )
      )

      let encoder = JSONEncoder()
      request.httpBody = try encoder.encode(requestBody)

      logger.info("Starting chat stream to \(url.absoluteString)")

      // Execute streaming request
      let (bytes, response) = try await urlSession.bytes(for: request)

      // Check HTTP response
      guard let httpResponse = response as? HTTPURLResponse else {
        throw WageyServiceError.networkError(underlying: URLError(.badServerResponse))
      }

      logger.info("Chat stream response status: \(httpResponse.statusCode)")

      // Handle HTTP errors
      switch httpResponse.statusCode {
      case 200:
        break  // Success, continue to stream
      case 401:
        throw WageyServiceError.notAuthenticated
      default:
        throw WageyServiceError.httpError(
          statusCode: httpResponse.statusCode,
          message: "Unexpected response status"
        )
      }

      // Parse the SSE stream
      for try await wrapper in SSEStreamParser.parse(bytes, as: WageyChunkWrapper.self) {
        try Task.checkCancellation()

        // Only process "chunk" type events, skip "special" events
        guard wrapper.type == "chunk", let rawChunk = wrapper.chunk else {
          continue
        }

        // Map the API chunk to our ChatChunk type
        if let chatChunk = mapToChatChunk(rawChunk) {
          continuation.yield(chatChunk)

          // If we got a done or error chunk, finish the stream
          if case .done = chatChunk {
            break
          }
          if case .error = chatChunk {
            break
          }
        }
      }

      logger.info("Chat stream completed successfully")
      continuation.finish()

    } catch is CancellationError {
      logger.info("Chat stream was cancelled")
      continuation.finish(throwing: WageyServiceError.cancelled)
    } catch let serviceError as WageyServiceError {
      logger.error("Chat stream service error: \(serviceError.localizedDescription)")
      self.error = serviceError
      continuation.finish(throwing: serviceError)
    } catch {
      logger.error("Chat stream error: \(error.localizedDescription)")
      let wrappedError = WageyServiceError.networkError(underlying: error)
      self.error = wrappedError
      continuation.finish(throwing: wrappedError)
    }
  }

  /// Maps the raw API chunk to our ChatChunk type
  private func mapToChatChunk(_ raw: RawChatChunk) -> ChatChunk? {
    switch raw.type {
    case "status":
      return .status(thinking: raw.status == "thinking")

    case "text":
      guard let content = raw.content else { return nil }
      return .text(content: content)

    case "tool_start":
      guard let toolName = raw.toolName,
        let toolCallId = raw.toolCallId
      else { return nil }
      return .toolStart(
        toolName: toolName,
        toolCallId: toolCallId,
        toolArguments: raw.toolArguments
      )

    case "tool_result":
      guard let toolName = raw.toolName,
        let toolCallId = raw.toolCallId,
        let result = raw.result
      else { return nil }
      return .toolResult(
        toolName: toolName,
        toolCallId: toolCallId,
        result: result,
        success: raw.success ?? true
      )

    case "wagey_limit":
      guard let remaining = raw.remaining,
        let resetDays = raw.resetDays
      else { return nil }
      return .wageyLimit(
        remaining: remaining, resetDays: resetDays, exceeded: raw.exceeded ?? false,
        bonus: raw.bonus ?? 0)

    case "wagey_no_access":
      return .wageyNoAccess

    case "done":
      return .done

    case "error":
      return .error(message: raw.error ?? "Unknown error")

    default:
      logger.warning("Unknown chunk type: \(raw.type)")
      return nil
    }
  }
}

// MARK: - SSE Response Types

/// Wrapper for SSE data events from River streaming framework
/// River sends: `data: {"type": "chunk", "chunk": {...}}\n\n`
/// or: `data: {"type": "special", "special": {...}}\n\n`
private struct WageyChunkWrapper: Decodable {
  let type: String
  let chunk: RawChatChunk?

  private enum CodingKeys: String, CodingKey {
    case type
    case chunk
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.type = try container.decode(String.self, forKey: .type)

    // Only decode chunk if type is "chunk"
    if type == "chunk" {
      self.chunk = try container.decodeIfPresent(RawChatChunk.self, forKey: .chunk)
    } else {
      self.chunk = nil
    }
  }
}

/// Raw chunk data from the API
private struct RawChatChunk: Decodable {
  let type: String

  // Text chunk
  let content: String?

  // Status chunk
  let status: String?

  // Tool chunks
  let toolName: String?
  let toolCallId: String?
  let toolArguments: String?
  let result: String?
  let success: Bool?

  // Limit chunk
  let remaining: Int?
  let resetDays: Int?
  let exceeded: Bool?
  let bonus: Int?

  // Error chunk
  let error: String?
}
