import XCTest

@testable import Tidex

final class WageyChatChunkDecodingTests: XCTestCase {
  func testDecodesThinkingStatusChunk() throws {
    let data = Data(
      """
      {
        "type": "status",
        "status": "thinking"
      }
      """.utf8
    )

    let chunk = try JSONDecoder().decode(ChatChunk.self, from: data)

    XCTAssertEqual(chunk, .status(thinking: true))
  }

  func testDecodesLegacyStatusAsNotThinking() throws {
    let data = Data(
      """
      {
        "type": "status",
        "status": "idle"
      }
      """.utf8
    )

    let chunk = try JSONDecoder().decode(ChatChunk.self, from: data)

    XCTAssertEqual(chunk, .status(thinking: false))
  }
}
