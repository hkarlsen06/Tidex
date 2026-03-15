import XCTest

@testable import Tidex

final class WageyChatChunkDecodingTests: XCTestCase {
  func testDecodesTextStartChunk() throws {
    let data = Data(
      """
      {
        "type": "text_start"
      }
      """.utf8
    )

    let chunk = try JSONDecoder().decode(ChatChunk.self, from: data)

    XCTAssertEqual(chunk, .textStart)
  }

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

  func testDecodesSourcesChunk() throws {
    let data = Data(
      """
      {
        "type": "wagey_sources",
        "items": [
          {
            "id": "src_1",
            "title": "OpenAI",
            "url": "https://openai.com",
            "domain": "openai.com"
          }
        ]
      }
      """.utf8
    )

    let chunk = try JSONDecoder().decode(ChatChunk.self, from: data)

    XCTAssertEqual(
      chunk,
      .sources(
        items: [
          MessageSource(
            id: "src_1",
            title: "OpenAI",
            url: "https://openai.com",
            domain: "openai.com"
          )
        ]
      )
    )
  }

  func testDecodesCompactionChunk() throws {
    let data = Data(
      """
      {
        "type": "wagey_compaction",
        "content": "<summary>Keep only the recent context.</summary>"
      }
      """.utf8
    )

    let chunk = try JSONDecoder().decode(ChatChunk.self, from: data)

    XCTAssertEqual(
      chunk,
      .compaction(content: "<summary>Keep only the recent context.</summary>")
    )
  }

  func testDecodesBuiltInToolChunks() throws {
    let startData = Data(
      """
      {
        "type": "wagey_built_in_tool_start",
        "toolName": "web_search",
        "toolCallId": "search_1"
      }
      """.utf8
    )

    let resultData = Data(
      """
      {
        "type": "wagey_built_in_tool_result",
        "toolName": "web_search",
        "toolCallId": "search_1",
        "result": "{\"status\":\"completed\"}",
        "success": true
      }
      """.utf8
    )

    let startChunk = try JSONDecoder().decode(ChatChunk.self, from: startData)
    let resultChunk = try JSONDecoder().decode(ChatChunk.self, from: resultData)

    XCTAssertEqual(
      startChunk,
      .builtInToolStart(toolName: "web_search", toolCallId: "search_1")
    )
    XCTAssertEqual(
      resultChunk,
      .builtInToolResult(
        toolName: "web_search",
        toolCallId: "search_1",
        result: "{\"status\":\"completed\"}",
        success: true
      )
    )
  }

  func testDecodesWebFetchBuiltInToolChunks() throws {
    let startData = Data(
      """
      {
        "type": "wagey_built_in_tool_start",
        "toolName": "web_fetch",
        "toolCallId": "fetch_1"
      }
      """.utf8
    )

    let resultData = Data(
      """
      {
        "type": "wagey_built_in_tool_result",
        "toolName": "web_fetch",
        "toolCallId": "fetch_1",
        "result": "{\"type\":\"web_fetch_tool_result\",\"tool_use_id\":\"fetch_1\",\"content\":{\"url\":\"https://example.com/tariff.pdf\",\"title\":\"Tariff PDF\",\"content\":\"Fetched text\"}}",
        "success": true
      }
      """.utf8
    )

    let startChunk = try JSONDecoder().decode(ChatChunk.self, from: startData)
    let resultChunk = try JSONDecoder().decode(ChatChunk.self, from: resultData)

    XCTAssertEqual(
      startChunk,
      .builtInToolStart(toolName: "web_fetch", toolCallId: "fetch_1")
    )
    XCTAssertEqual(
      resultChunk,
      .builtInToolResult(
        toolName: "web_fetch",
        toolCallId: "fetch_1",
        result:
          "{\"type\":\"web_fetch_tool_result\",\"tool_use_id\":\"fetch_1\",\"content\":{\"url\":\"https://example.com/tariff.pdf\",\"title\":\"Tariff PDF\",\"content\":\"Fetched text\"}}",
        success: true
      )
    )
  }

  func testDecodesUnknownChunkWithoutThrowing() throws {
    let data = Data(
      """
      {
        "type": "wagey_future_feature",
        "value": true
      }
      """.utf8
    )

    let chunk = try JSONDecoder().decode(ChatChunk.self, from: data)

    XCTAssertEqual(chunk, .unknown(type: "wagey_future_feature"))
  }
}
