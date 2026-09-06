import Foundation
import XCTest

@testable import Tidex

final class SSEStreamParserTests: XCTestCase {
  private struct Event: Decodable, Equatable {
    let text: String
  }

  func testRecognizesEachDelimiterAcrossIndividualBytes() async throws {
    for delimiter in ["\n\n", "\r\n\r\n", "\r\r", "\n\r", "\n\r\n", "\r\n\r", "\r\n\n", "\r\r\n"] {
      let input = "data: {\"text\":\"first\"}\(delimiter)data: {\"text\":\"second\"}\(delimiter)"
      let events = try await parse(Data(input.utf8))
      XCTAssertEqual(events, [Event(text: "first"), Event(text: "second")])
    }
  }

  func testPreservesMultilineDataUnicodeAndCommentHandling() async throws {
    let input = ": heartbeat\r\n\r\ndata: {\r\ndata: \"text\": \"Blåbær 👋\"}\r\n\r\n"
    let events = try await parse(Data(input.utf8))
    XCTAssertEqual(events, [Event(text: "Blåbær 👋")])
  }

  func testParsesFinalEventWithoutTerminator() async throws {
    let events = try await parse(Data("data: {\"text\":\"last\"}".utf8))
    XCTAssertEqual(events, [Event(text: "last")])
  }

  func testNormalizesMultilineFinalEventWithoutTerminator() async throws {
    for lineEnding in ["\r", "\r\n", "\n"] {
      let input = "data: {\(lineEnding)data: \"text\": \"last\"}"
      let events = try await parse(Data(input.utf8))
      XCTAssertEqual(events, [Event(text: "last")])
    }
  }

  func testPreservesLargeEventAndFollowingEvent() async throws {
    let text = String(repeating: "long tool result ", count: 4_096)
    let input = "data: {\"text\":\"\(text)\"}\n\ndata: {\"text\":\"after\"}\r\r"
    let events = try await parse(Data(input.utf8))
    XCTAssertEqual(events, [Event(text: text), Event(text: "after")])
  }

  func testRejectsInvalidUTF8WithAndWithoutTerminator() async {
    for suffix: [UInt8] in [[], [10, 10]] {
      do {
        _ = try await parse(Data([255] + suffix))
        XCTFail("Expected invalid UTF-8 to fail")
      } catch SSEParseError.invalidUTF8Data {
        // Expected for both terminated and trailing events.
      } catch {
        XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testRejectsMalformedJSON() async {
    do {
      _ = try await parse(Data("data: {bad json}\n\n".utf8))
      XCTFail("Expected malformed JSON to fail")
    } catch SSEParseError.jsonDecodingFailed {
      // Preserve the parser's error wrapping.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testPropagatesTransportFailure() async {
    let bytes = AsyncThrowingStream<UInt8, Error> { continuation in
      continuation.finish(throwing: URLError(.networkConnectionLost))
    }
    do {
      for try await _ in SSEStreamParser.parse(bytes, as: Event.self) {
        XCTFail("A failed transport must not produce events")
      }
      XCTFail("Expected the transport error")
    } catch let error as URLError {
      XCTAssertEqual(error.code, .networkConnectionLost)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testCancellationTerminatesByteStream() async {
    let receivedEvent = expectation(description: "Received the first event")
    let terminated = expectation(description: "Cancelled the byte stream")
    let bytes = AsyncThrowingStream<UInt8, Error> { continuation in
      continuation.onTermination = { _ in terminated.fulfill() }
      for byte in "data: {\"text\":\"first\"}\n\n".utf8 {
        continuation.yield(byte)
      }
    }
    let task = Task {
      for try await _ in SSEStreamParser.parse(bytes, as: Event.self) {
        receivedEvent.fulfill()
      }
    }
    await fulfillment(of: [receivedEvent], timeout: 2)
    task.cancel()
    _ = await task.result
    await fulfillment(of: [terminated], timeout: 2)
  }

  private func parse(_ data: Data) async throws -> [Event] {
    let bytes = AsyncStream<UInt8> { continuation in
      for byte in data {
        continuation.yield(byte)
      }
      continuation.finish()
    }
    var events: [Event] = []
    for try await event in SSEStreamParser.parse(bytes, as: Event.self) {
      events.append(event)
    }
    return events
  }
}
