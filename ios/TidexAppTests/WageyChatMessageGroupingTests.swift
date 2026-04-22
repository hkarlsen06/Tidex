import XCTest

@testable import Tidex

final class WageyChatMessageGroupingTests: XCTestCase {
  func testShouldGroupMessagesFromSameRoleWithinFiveMinutes() {
    let first = makeMessage(
      id: "message-1",
      role: .assistant,
      timestamp: 1_700_000_000
    )
    let second = makeMessage(
      id: "message-2",
      role: .assistant,
      timestamp: 1_700_000_240
    )

    XCTAssertTrue(WageyChatMessageGrouping.shouldGroup(first, second))
  }

  func testShouldNotGroupMessagesFromDifferentRoles() {
    let first = makeMessage(
      id: "message-1",
      role: .user,
      timestamp: 1_700_000_000
    )
    let second = makeMessage(
      id: "message-2",
      role: .assistant,
      timestamp: 1_700_000_030
    )

    XCTAssertFalse(WageyChatMessageGrouping.shouldGroup(first, second))
  }

  func testShouldNotGroupToolOnlyMessages() {
    let first = ChatMessage(
      id: "message-1",
      role: .assistant,
      contentBlocks: [
        .toolCall(
          ToolCall(
            id: "tool-1",
            name: "query_shifts",
            arguments: nil,
            result: nil,
            success: nil
          )
        )
      ],
      timestamp: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let second = makeMessage(
      id: "message-2",
      role: .assistant,
      timestamp: 1_700_000_030
    )

    XCTAssertFalse(WageyChatMessageGrouping.shouldGroup(first, second))
  }

  func testContextUsesLeadingAndTrailingPositionsForGroupedAssistantMessages() {
    let first = makeMessage(
      id: "message-1",
      role: .assistant,
      timestamp: 1_700_000_000
    )
    let second = makeMessage(
      id: "message-2",
      role: .assistant,
      timestamp: 1_700_000_120
    )

    let leadingContext = WageyChatMessageGrouping.context(
      for: first,
      previous: nil,
      next: second
    )
    let trailingContext = WageyChatMessageGrouping.context(
      for: second,
      previous: first,
      next: nil
    )

    XCTAssertEqual(leadingContext.position, .leading)
    XCTAssertEqual(trailingContext.position, .trailing)
    XCTAssertFalse(leadingContext.isCurrentUser)
    XCTAssertFalse(trailingContext.isCurrentUser)
  }

  private func makeMessage(
    id: String,
    role: MessageRole,
    timestamp: TimeInterval
  ) -> ChatMessage {
    ChatMessage(
      id: id,
      role: role,
      contentBlocks: [.text("Hello")],
      timestamp: Date(timeIntervalSince1970: timestamp)
    )
  }
}
