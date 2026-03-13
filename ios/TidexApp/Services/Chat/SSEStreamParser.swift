import Foundation
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SSEStreamParser")

// MARK: - SSE Parsing Errors

/// Errors that can occur during SSE stream parsing
enum SSEParseError: Error, LocalizedError {
  case invalidUTF8Data
  case jsonDecodingFailed(underlying: Error)
  case streamInterrupted
  case connectionClosed

  var errorDescription: String? {
    switch self {
    case .invalidUTF8Data:
      return "Received invalid UTF-8 data in SSE stream"
    case .jsonDecodingFailed(let error):
      return "Failed to decode JSON from SSE event: \(error.localizedDescription)"
    case .streamInterrupted:
      return "SSE stream was interrupted"
    case .connectionClosed:
      return "SSE connection was closed"
    }
  }
}

// MARK: - SSE Stream Parser

/// Parses Server-Sent Events (SSE) from an async byte stream.
///
/// SSE format: `data: {json}\n\n`
///
/// The parser handles:
/// - Partial messages (data arriving in chunks)
/// - Multiple events in a single chunk
/// - UTF-8 encoding
/// - Graceful error handling
///
/// Usage:
/// ```swift
/// let (bytes, _) = try await urlSession.bytes(for: request)
/// for try await chunk in SSEStreamParser.parse(bytes, as: ChatChunk.self) {
///     // Handle each decoded chunk
/// }
/// ```
enum SSEStreamParser {
  /// The prefix for SSE data events
  private static let dataPrefix = "data: "

  /// The event terminator (double newline)
  private static let eventTerminator = "\n\n"

  /// Parse SSE events from URLSession async bytes into decoded objects.
  ///
  /// - Parameters:
  ///   - bytes: The async byte stream from URLSession
  ///   - type: The type to decode each event's JSON payload into
  /// - Returns: An async throwing stream of decoded objects
  static func parse<T: Decodable>(
    _ bytes: URLSession.AsyncBytes,
    as type: T.Type
  ) -> AsyncThrowingStream<T, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        var eventLines: [String] = []
        let decoder = JSONDecoder()

        do {
          for try await line in bytes.lines {
            // Check for task cancellation
            try Task.checkCancellation()

            let normalizedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if normalizedLine.isEmpty {
              if !eventLines.isEmpty {
                let eventData = eventLines.joined(separator: "\n")
                eventLines.removeAll(keepingCapacity: true)

                if let decoded = try parseEvent(eventData, as: type, decoder: decoder) {
                  continuation.yield(decoded)
                }
              }
              continue
            }

            eventLines.append(normalizedLine)
          }

          // Process any remaining data in buffer (incomplete event without terminator)
          if !eventLines.isEmpty {
            let eventData = eventLines.joined(separator: "\n")
            let trimmed = eventData.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
              logger.debug("Stream ended with incomplete buffer: \(trimmed.prefix(100))")
              if let decoded = try parseEvent(trimmed, as: type, decoder: decoder) {
                continuation.yield(decoded)
              }
            }
          }

          logger.info("SSE stream completed normally")
          continuation.finish()

        } catch is CancellationError {
          logger.info("SSE stream parsing was cancelled")
          continuation.finish()
        } catch {
          logger.error("SSE stream error: \(error.localizedDescription)")
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  /// Parse a single SSE event string into a decoded object.
  ///
  /// - Parameters:
  ///   - eventData: The raw event string (may contain "data: " prefix)
  ///   - type: The type to decode into
  ///   - decoder: The JSON decoder to use
  /// - Returns: The decoded object, or nil if the event should be skipped
  private static func parseEvent<T: Decodable>(
    _ eventData: String,
    as type: T.Type,
    decoder: JSONDecoder
  ) throws -> T? {
    // Handle multiple lines within an event
    let lines = eventData.components(separatedBy: "\n")

    for line in lines {
      let trimmedLine = line.trimmingCharacters(in: .whitespaces)

      // Skip empty lines and comments
      if trimmedLine.isEmpty || trimmedLine.hasPrefix(":") {
        continue
      }

      // Handle data lines
      if trimmedLine.hasPrefix(dataPrefix) {
        let jsonString = String(trimmedLine.dropFirst(dataPrefix.count))
        return try decodeJSON(jsonString, as: type, decoder: decoder)
      }

      // Handle lines that are just JSON (some SSE implementations)
      if trimmedLine.hasPrefix("{") {
        return try decodeJSON(trimmedLine, as: type, decoder: decoder)
      }
    }

    return nil
  }

  /// Decode a JSON string into the specified type.
  private static func decodeJSON<T: Decodable>(
    _ jsonString: String,
    as type: T.Type,
    decoder: JSONDecoder
  ) throws -> T {
    guard let data = jsonString.data(using: .utf8) else {
      throw SSEParseError.invalidUTF8Data
    }

    do {
      return try decoder.decode(type, from: data)
    } catch {
      logger.error(
        "JSON decode error: \(error.localizedDescription), input: \(jsonString.prefix(200))")
      throw SSEParseError.jsonDecodingFailed(underlying: error)
    }
  }
}

// MARK: - Wrapper Type for Chunk Parsing

/// Wrapper for the SSE response format: `{ "chunk": {...} }`
///
/// The server sends events in the format:
/// ```json
/// data: {"chunk":{"type":"text","content":"Hello"}}
/// ```
///
/// This wrapper extracts the inner chunk for easier handling.
struct SSEChunkWrapper<T: Decodable>: Decodable {
  let chunk: T
}

// MARK: - Convenience Extension

extension SSEStreamParser {
  /// Parse SSE events that are wrapped in a `{"chunk": ...}` envelope.
  ///
  /// This is a convenience method for the common case where the server
  /// sends events in the format: `data: {"chunk": {...}}`
  ///
  /// - Parameters:
  ///   - bytes: The async byte stream from URLSession
  ///   - chunkType: The type of the inner chunk to decode
  /// - Returns: An async throwing stream of decoded chunk objects
  static func parseChunks<T: Decodable>(
    _ bytes: URLSession.AsyncBytes,
    as chunkType: T.Type
  ) -> AsyncThrowingStream<T, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await wrapper in parse(bytes, as: SSEChunkWrapper<T>.self) {
            continuation.yield(wrapper.chunk)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }
}
