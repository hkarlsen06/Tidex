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
  private static let dataField = "data"

  /// Parse SSE events from URLSession async bytes into decoded objects.
  ///
  /// - Parameters:
  ///   - bytes: The async byte stream from URLSession
  ///   - type: The type to decode each event's JSON payload into
  /// - Returns: An async throwing stream of decoded objects
  static func parse<Bytes: AsyncSequence, T: Decodable>(
    _ bytes: Bytes,
    as type: T.Type
  ) -> AsyncThrowingStream<T, Error> where Bytes.Element == UInt8 {
    AsyncThrowingStream { continuation in
      let task = Task {
        var buffer = Data()
        let decoder = JSONDecoder()

        do {
          for try await byte in bytes {
            // Check for task cancellation
            try Task.checkCancellation()
            buffer.append(byte)

            if let boundaryLength = eventBoundaryLength(atEndOf: buffer) {
              let eventData = buffer.dropLast(boundaryLength)

              if let decoded = try parseEventData(eventData, as: type, decoder: decoder) {
                continuation.yield(decoded)
              }
              buffer.removeAll(keepingCapacity: true)
            }
          }

          // Process any remaining data in buffer (incomplete event without terminator)
          if !buffer.isEmpty {
            if let eventText = String(data: buffer, encoding: .utf8) {
              let trimmed = eventText.trimmingCharacters(in: .whitespacesAndNewlines)
              if !trimmed.isEmpty {
                logger.debug("Stream ended with incomplete buffer: \(trimmed.prefix(100))")
                if let decoded = try parseEventData(buffer, as: type, decoder: decoder) {
                  continuation.yield(decoded)
                }
              }
            } else {
              throw SSEParseError.invalidUTF8Data
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

  private static func eventBoundaryLength(atEndOf buffer: Data) -> Int? {
    // Every earlier byte was already checked. Only a delimiter ending at the newly
    // appended byte can be new, so inspect at most four bytes without copying.
    let end = buffer.endIndex
    guard buffer.count >= 2 else { return nil }

    if buffer[end - 1] == 10 {
      if buffer[end - 2] == 10 {
        return 2
      }
      if buffer.count >= 4,
        buffer[end - 4] == 13,
        buffer[end - 3] == 10,
        buffer[end - 2] == 13
      {
        return 4
      }
    } else if buffer[end - 1] == 13 {
      if buffer[end - 2] == 13 {
        return 2
      }
      if buffer[end - 2] == 10 {
        // SSE permits each line to use CR, LF, or CRLF independently. A CR
        // after LF terminates the blank line, even before its optional LF.
        return buffer.count >= 3 && buffer[end - 3] == 13 ? 3 : 2
      }
    }

    return nil
  }

  private static func parseEventData<T: Decodable>(
    _ eventData: Data,
    as type: T.Type,
    decoder: JSONDecoder
  ) throws -> T? {
    guard let eventText = String(data: eventData, encoding: .utf8) else {
      throw SSEParseError.invalidUTF8Data
    }

    let normalized =
      eventText
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    return try parseEvent(normalized, as: type, decoder: decoder)
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
    var dataLines: [String] = []

    for line in lines {
      let trimmedLine = line.trimmingCharacters(in: .whitespaces)

      // Skip empty lines and comments
      if trimmedLine.isEmpty || trimmedLine.hasPrefix(":") {
        continue
      }

      if trimmedLine.hasPrefix("\(dataField):") {
        let fieldValue = String(trimmedLine.dropFirst(dataField.count + 1))
        dataLines.append(fieldValue.hasPrefix(" ") ? String(fieldValue.dropFirst()) : fieldValue)
        continue
      }

      if trimmedLine == dataField {
        dataLines.append("")
        continue
      }

      // Handle lines that are just JSON (some SSE implementations)
      if dataLines.isEmpty, trimmedLine.hasPrefix("{") {
        return try decodeJSON(trimmedLine, as: type, decoder: decoder)
      }
    }

    if !dataLines.isEmpty {
      return try decodeJSON(dataLines.joined(separator: "\n"), as: type, decoder: decoder)
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
    as _: T.Type
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
