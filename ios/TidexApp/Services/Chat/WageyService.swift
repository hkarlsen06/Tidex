import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "WageyService")
private let wageyEdgeFunctionName = "wagey-chat"

private struct WageyStreamRequestContext {
  let messages: [ChatMessage]
  let userId: String
  let userName: String?
  let compaction: String?
  let clientCapabilities: [String]
  let appVersion: String?
}

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
    let client: ClientContext?
  }

  struct ClientContext: Encodable {
    let platform: String
    let appVersion: String?
    let capabilities: [String]
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

/// Service for communicating with the Wagey chat edge function.
/// Handles streaming SSE responses from the Supabase Functions endpoint.
@MainActor
final class WageyService: ObservableObject {
  static let shared = WageyService()
  private static let clientCapabilities = [
    "rich_sources_v1",
    "rich_built_in_tool_events_v1",
  ]

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
  private lazy var streamWorker = WageyStreamWorker(urlSession: urlSession)

  private init() {}

  // MARK: - Public API

  /// Stream chat responses from the Wagey API
  ///
  /// Sends messages to the Wagey edge function and returns a stream of chunks.
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
        self.setStreamingState(isStreaming: true, error: nil)
        defer {
          Task { @MainActor in
            self.isStreaming = false
          }
        }

        await streamWorker.performStreamRequest(
          WageyStreamRequestContext(
            messages: messages,
            userId: userId,
            userName: userName,
            compaction: compaction,
            clientCapabilities: Self.clientCapabilities,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
          ),
          continuation: continuation
        )
      }

      // Handle cancellation from the consumer side
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  private func setStreamingState(isStreaming: Bool, error: Error?) {
    self.isStreaming = isStreaming
    self.error = error
  }

  fileprivate func handleWorkerError(
    _ error: Error, continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation
  ) {
    if let serviceError = error as? WageyServiceError {
      logger.error("Chat stream service error: \(serviceError.localizedDescription)")
      self.error = serviceError
      continuation.finish(throwing: serviceError)
      return
    }

    logger.error("Chat stream error: \(error.localizedDescription)")
    let wrappedError = WageyServiceError.networkError(underlying: error)
    self.error = wrappedError
    continuation.finish(throwing: wrappedError)
  }
}

private actor WageyStreamWorker {
  private let urlSession: URLSession

  init(urlSession: URLSession) {
    self.urlSession = urlSession
  }

  func performStreamRequest(
    _ context: WageyStreamRequestContext,
    continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation
  ) async {
    do {
      try Task.checkCancellation()

      let session = try await AuthSessionManager.shared.getSession()
      let accessToken = session.accessToken

      let url = APIConfiguration.supabaseURL
        .appendingPathComponent("functions")
        .appendingPathComponent("v1")
        .appendingPathComponent(wageyEdgeFunctionName)
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
      request.setValue(APIConfiguration.supabaseAnonKey, forHTTPHeaderField: "apikey")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
      request.httpBody = try JSONEncoder().encode(
        makeRequestBody(
          context: context
        ))

      let (bytes, response) = try await urlSession.bytes(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw WageyServiceError.networkError(underlying: URLError(.badServerResponse))
      }

      switch httpResponse.statusCode {
      case 200:
        break
      case 401:
        throw WageyServiceError.notAuthenticated
      default:
        throw WageyServiceError.httpError(
          statusCode: httpResponse.statusCode,
          message: "Unexpected response status"
        )
      }

      var chunkCount = 0
      var receivedRenderableChunk = false

      for try await wrapper in SSEStreamParser.parse(bytes, as: WageyChunkWrapper.self) {
        try Task.checkCancellation()

        guard wrapper.type == "chunk", let rawChunk = wrapper.chunk else {
          continue
        }

        chunkCount += 1

        if let chatChunk = Self.mapToChatChunk(rawChunk) {
          switch chatChunk {
          case .status, .done:
            break
          default:
            receivedRenderableChunk = true
          }

          continuation.yield(chatChunk)

          if case .done = chatChunk {
            break
          }
          if case .error = chatChunk {
            break
          }
        }
      }

      if !receivedRenderableChunk {
        throw WageyServiceError.streamError(message: "Empty Wagey stream response")
      }
      continuation.finish()
    } catch is CancellationError {
      continuation.finish(throwing: WageyServiceError.cancelled)
    } catch {
      await MainActor.run {
        WageyService.shared.handleWorkerError(error, continuation: continuation)
      }
    }
  }

  private func makeRequestBody(
    context: WageyStreamRequestContext
  ) -> ChatAPIRequest {
    var apiMessages: [ChatAPIRequest.APIMessage] = []

    for message in context.messages {
      let content: ChatAPIRequest.APIMessageContent
      if !message.imageAttachments.isEmpty {
        var blocks: [ChatAPIRequest.APIContentBlock] = message.imageAttachments.map { image in
          .image(mediaType: image.mediaType, base64Data: image.base64String)
        }

        if !message.content.isEmpty {
          blocks.append(.text(message.content))
        }

        content = .blocks(blocks)
      } else {
        content = .text(message.content)
      }

      let functionToolCalls = message.toolCalls?.filter { !$0.isBuiltIn }
      let apiMessage = ChatAPIRequest.APIMessage(
        role: message.role.rawValue,
        content: content,
        toolCalls: functionToolCalls?.map { toolCall in
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

      if message.role == .assistant, let toolCalls = functionToolCalls {
        for toolCall in toolCalls {
          let resultContent =
            toolCall.result
            ?? "{\"success\":false,\"message\":\"Tool call timed out or was interrupted\"}"
          apiMessages.append(
            ChatAPIRequest.APIMessage(
              role: "tool",
              content: .text(resultContent),
              toolCalls: nil,
              toolCallId: toolCall.id,
              name: toolCall.name
            ))
        }
      }
    }

    logger.debug("Sending \(apiMessages.count) messages to chat API")

    return ChatAPIRequest(
      routerStreamKey: "wagey",
      input: ChatAPIRequest.ChatInput(
        messages: apiMessages,
        userId: context.userId,
        userName: context.userName,
        compaction: context.compaction,
        client: ChatAPIRequest.ClientContext(
          platform: "ios",
          appVersion: context.appVersion,
          capabilities: context.clientCapabilities
        )
      )
    )
  }

  private static func mapToChatChunk(_ raw: RawChatChunk) -> ChatChunk? {
    switch raw.type {
    case "status":
      return .status(thinking: raw.status == "thinking")
    case "text":
      guard let content = raw.content else { return nil }
      return .text(content: content)
    case "tool_start":
      guard let toolName = raw.toolName, let toolCallId = raw.toolCallId else { return nil }
      return .toolStart(
        toolName: toolName, toolCallId: toolCallId, toolArguments: raw.toolArguments)
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
    case "wagey_built_in_tool_start":
      guard let toolName = raw.toolName, let toolCallId = raw.toolCallId else { return nil }
      return .builtInToolStart(toolName: toolName, toolCallId: toolCallId)
    case "wagey_built_in_tool_result":
      guard let toolName = raw.toolName,
        let toolCallId = raw.toolCallId,
        let result = raw.result
      else { return nil }
      return .builtInToolResult(
        toolName: toolName,
        toolCallId: toolCallId,
        result: result,
        success: raw.success ?? true
      )
    case "wagey_limit":
      guard let remaining = raw.remaining, let resetDays = raw.resetDays else { return nil }
      return .wageyLimit(
        remaining: remaining,
        resetDays: resetDays,
        exceeded: raw.exceeded ?? false,
        bonus: raw.bonus ?? 0
      )
    case "wagey_no_access":
      return .wageyNoAccess
    case "wagey_sources":
      return .sources(items: raw.items ?? [])
    case "wagey_compaction":
      guard let content = raw.content else { return nil }
      return .compaction(content: content)
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
  let items: [MessageSource]?
}
