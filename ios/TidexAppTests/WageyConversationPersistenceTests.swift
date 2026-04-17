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
    XCTAssertEqual(
      message.contentBlocks,
      [.text("La meg sjekke tilleggssatsene også.\n\nNå har jeg det jeg trenger.")]
    )
  }

  func testStoredChatMessageNormalizesAdjacentTextBlocksBeforePersistence() throws {
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
    XCTAssertEqual(
      stored.contentBlocks,
      [.text("Første blokk.\n\nAndre blokk.")]
    )
  }

  func testChatMessageKeepsToolBoundariesWhenNormalizingTextBlocks() {
    let message = ChatMessage(
      id: "assistant-tool-boundary",
      role: .assistant,
      contentBlocks: [
        .text("Jeg sjekker dette."),
        .toolCall(
          ToolCall(
            id: "tool_1",
            name: "manage_shift",
            result: "{\"success\":true}",
            success: true
          )),
        .text("Ferdig."),
      ],
      timestamp: Date(timeIntervalSince1970: 1_700_000_301)
    )

    XCTAssertEqual(message.contentBlocks.count, 3)
    XCTAssertEqual(message.content, "Jeg sjekker dette.\n\nFerdig.")
  }

  func testStoredChatMessageRoundTripsThoughtStatusWithoutAffectingTextContent() throws {
    let message = ChatMessage(
      id: "assistant-thought-status",
      role: .assistant,
      contentBlocks: [
        .thoughtStatus(ThoughtStatus(id: "thought-1", durationSeconds: 2)),
        .text("Her er svaret mitt."),
      ],
      timestamp: Date(timeIntervalSince1970: 1_700_000_302)
    )

    let stored = StoredChatMessage(from: message)
    let data = try JSONEncoder().encode(stored)
    let decoded = try JSONDecoder().decode(StoredChatMessage.self, from: data)
    let roundTrip = decoded.toChatMessage()

    XCTAssertEqual(roundTrip.content, "Her er svaret mitt.")
    XCTAssertEqual(roundTrip.contentBlocks.count, 2)
    XCTAssertEqual(
      roundTrip.contentBlocks.first,
      .thoughtStatus(ThoughtStatus(id: "thought-1", durationSeconds: 2))
    )
  }

  func testThoughtStatusUsesShortLabelForOneSecond() {
    let status = ThoughtStatus(durationSeconds: 1)

    XCTAssertEqual(status.localizedLabel, String(localized: "wagey.streaming.thought_short"))
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
