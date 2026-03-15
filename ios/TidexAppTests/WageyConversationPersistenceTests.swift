import XCTest

@testable import Tidex

final class WageyConversationPersistenceTests: XCTestCase {
  func testStoredChatMessageRoundTripsSources() throws {
    let message = ChatMessage(
      id: "assistant-1",
      role: .assistant,
      contentBlocks: [.text("Here are the sources.")],
      sources: [
        MessageSource(
          id: "src_1",
          title: "OpenAI",
          url: "https://openai.com",
          domain: "openai.com"
        )
      ],
      timestamp: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let stored = StoredChatMessage(from: message)
    let data = try JSONEncoder().encode(stored)
    let decoded = try JSONDecoder().decode(StoredChatMessage.self, from: data)
    let roundTrip = decoded.toChatMessage()

    XCTAssertEqual(roundTrip.sources, message.sources)
    XCTAssertEqual(roundTrip.content, message.content)
  }

  func testStoredChatMessageDecodesLegacyPayloadWithoutSources() throws {
    let data = Data(
      """
      {
        "id": "assistant-legacy",
        "role": "assistant",
        "timestamp": 1700000000,
        "content": "Legacy message",
        "toolCalls": null
      }
      """.utf8
    )

    let decoded = try JSONDecoder().decode(StoredChatMessage.self, from: data)
    let message = decoded.toChatMessage()

    XCTAssertNil(message.sources)
    XCTAssertEqual(message.content, "Legacy message")
  }

  func testStoredChatMessageRoundTripsBuiltInToolKind() throws {
    let message = ChatMessage(
      id: "assistant-built-in",
      role: .assistant,
      contentBlocks: [
        .toolCall(
          ToolCall(
            id: "search_1",
            name: "web_search",
            kind: .builtIn,
            result: "{\"status\":\"completed\"}",
            success: true
          ))
      ],
      timestamp: Date(timeIntervalSince1970: 1_700_000_100)
    )

    let stored = StoredChatMessage(from: message)
    let data = try JSONEncoder().encode(stored)
    let decoded = try JSONDecoder().decode(StoredChatMessage.self, from: data)
    let roundTrip = decoded.toChatMessage()

    XCTAssertEqual(roundTrip.toolCalls?.first?.kind, .builtIn)
    XCTAssertTrue(roundTrip.toolCalls?.first?.isBuiltIn == true)
  }

  func testChatMessageFlattensSeparateTextBlocksWithParagraphBreaks() {
    let message = ChatMessage(
      id: "assistant-text-blocks",
      role: .assistant,
      contentBlocks: [
        .text("La meg sjekke tilleggssatsene også."),
        .text("Nå har jeg det jeg trenger."),
      ],
      timestamp: Date(timeIntervalSince1970: 1_700_000_200)
    )

    XCTAssertEqual(
      message.content,
      "La meg sjekke tilleggssatsene også.\n\nNå har jeg det jeg trenger."
    )
  }

  func testStoredChatMessageTextContentPreservesSeparateTextBlocks() throws {
    let message = ChatMessage(
      id: "assistant-persisted-text-blocks",
      role: .assistant,
      contentBlocks: [
        .text("Første blokk."),
        .text("Andre blokk."),
      ],
      timestamp: Date(timeIntervalSince1970: 1_700_000_300)
    )

    let stored = StoredChatMessage(from: message)

    XCTAssertEqual(stored.textContent, "Første blokk.\n\nAndre blokk.")
  }

  func testLocalConversationStoresCompactionSummary() {
    let conversation = LocalConversation(
      userId: "USER",
      title: "New Conversation",
      messages: [],
      compaction: "<summary>Condensed history</summary>"
    )

    XCTAssertEqual(conversation.compaction, "<summary>Condensed history</summary>")
  }
}
