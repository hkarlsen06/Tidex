import Foundation
import Supabase
import XCTest

@testable import Tidex

@MainActor
final class FriendsMessagingRealtimeCoordinatorTests: XCTestCase {
  func testExtractThreadIdPrefersThreadIdFieldForMessageActions() {
    let record: JSONObject = [
        "id": "message-1",
        "thread_id": "thread-1",
      ]

    XCTAssertEqual(FriendsMessagingRealtimeCoordinator.extractThreadId(fromRecord: record), "thread-1")
    XCTAssertEqual(FriendsMessagingRealtimeCoordinator.extractMessageId(fromRecord: record), "message-1")
  }

  func testExtractThreadIdFallsBackToPrimaryIdForThreadActions() {
    let record: JSONObject = [
        "id": "thread-22",
        "kind": "direct",
      ]

    XCTAssertEqual(FriendsMessagingRealtimeCoordinator.extractThreadId(fromRecord: record), "thread-22")
    XCTAssertEqual(FriendsMessagingRealtimeCoordinator.extractMessageId(fromRecord: record), "thread-22")
  }

  func testExtractReactionMessageIdUsesMessageIdInsteadOfReactionPrimaryId() {
    let record: JSONObject = [
        "id": "reaction-1",
        "thread_id": "thread-1",
        "message_id": "message-1",
      ]

    XCTAssertEqual(
      FriendsMessagingRealtimeCoordinator.extractReactionMessageId(fromRecord: record),
      "message-1"
    )
  }

  func testDecodeThreadUserStateParsesInsertedPayload() throws {
    let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let lastReadAt = Date(timeIntervalSince1970: 1_699_999_900)

    let record: JSONObject = [
        "thread_id": "thread-1",
        "user_id": "viewer-1",
        "last_read_message_id": "message-9",
        "last_read_at": .string(ISO8601DateFormatter().string(from: lastReadAt)),
        "muted": true,
        "updated_at": .string(ISO8601DateFormatter().string(from: updatedAt)),
      ]

    let state = FriendsMessagingRealtimeCoordinator.decodeThreadUserState(fromRecord: record)

    XCTAssertEqual(state?.threadId, "thread-1")
    XCTAssertEqual(state?.userId, "viewer-1")
    XCTAssertEqual(state?.lastReadMessageId, "message-9")
    XCTAssertEqual(state?.muted, true)
    XCTAssertEqual(
      try XCTUnwrap(state?.lastReadAt).timeIntervalSince1970, lastReadAt.timeIntervalSince1970,
      accuracy: 1)
    XCTAssertEqual(
      try XCTUnwrap(state?.updatedAt).timeIntervalSince1970, updatedAt.timeIntervalSince1970,
      accuracy: 1)
  }

  func testDecodeTypingPayloadParsesRealtimeBroadcastEnvelope() throws {
    let payload: JSONObject = [
      "event": "typing_start",
      "payload": [
        "thread_id": "thread-1",
        "user_id": "user-1",
        "sent_at_ms": 1_775_000_000_000,
      ],
      "type": "broadcast",
    ]

    let typingPayload = try FriendsMessagingRealtimeCoordinator.decodeTypingPayload(from: payload)

    XCTAssertEqual(typingPayload.threadId, "thread-1")
    XCTAssertEqual(typingPayload.userId, "user-1")
    XCTAssertEqual(typingPayload.sentAtMs, 1_775_000_000_000)
  }

  func testDecodeTypingPayloadParsesRawBroadcastPayload() throws {
    let payload: JSONObject = [
      "thread_id": "thread-2",
      "user_id": "user-2",
      "sent_at_ms": 1_775_000_000_001,
    ]

    let typingPayload = try FriendsMessagingRealtimeCoordinator.decodeTypingPayload(from: payload)

    XCTAssertEqual(typingPayload.threadId, "thread-2")
    XCTAssertEqual(typingPayload.userId, "user-2")
    XCTAssertEqual(typingPayload.sentAtMs, 1_775_000_000_001)
  }

  func testTypingChannelHealthRequiresExpectedTopicSubscribedStatusAndListeners() {
    XCTAssertTrue(
      FriendsMessagingRealtimeCoordinator.TypingChannelHealth.isHealthy(
        threadId: "thread-1",
        topic: "realtime:friends-thread-typing:thread-1",
        status: .subscribed,
        listenerTaskCount: FriendsMessagingRealtimeCoordinator.TypingChannelHealth
          .listenerTaskCount,
        hasSubscriptionTask: false
      )
    )

    XCTAssertFalse(
      FriendsMessagingRealtimeCoordinator.TypingChannelHealth.isHealthy(
        threadId: "thread-1",
        topic: "realtime:friends-thread-detail:thread-1",
        status: .subscribed,
        listenerTaskCount: FriendsMessagingRealtimeCoordinator.TypingChannelHealth
          .listenerTaskCount,
        hasSubscriptionTask: false
      )
    )

    XCTAssertFalse(
      FriendsMessagingRealtimeCoordinator.TypingChannelHealth.isHealthy(
        threadId: "thread-1",
        topic: "realtime:friends-thread-typing:thread-1",
        status: .unsubscribed,
        listenerTaskCount: FriendsMessagingRealtimeCoordinator.TypingChannelHealth
          .listenerTaskCount,
        hasSubscriptionTask: false
      )
    )

    XCTAssertFalse(
      FriendsMessagingRealtimeCoordinator.TypingChannelHealth.isHealthy(
        threadId: "thread-1",
        topic: "realtime:friends-thread-typing:thread-1",
        status: .subscribed,
        listenerTaskCount: FriendsMessagingRealtimeCoordinator.TypingChannelHealth
          .listenerTaskCount - 1,
        hasSubscriptionTask: false
      )
    )

    XCTAssertFalse(
      FriendsMessagingRealtimeCoordinator.TypingChannelHealth.isHealthy(
        threadId: "thread-1",
        topic: "realtime:friends-thread-typing:thread-1",
        status: .subscribed,
        listenerTaskCount: FriendsMessagingRealtimeCoordinator.TypingChannelHealth
          .listenerTaskCount,
        hasSubscriptionTask: true
      )
    )
  }

  func testThreadListRefreshesForViewerStateUpdates() {
    XCTAssertTrue(
      FriendsMessagingRealtimeCoordinator.shouldRefreshThreadList(
        forThreadStateUserId: "viewer-1",
        viewerUserId: "viewer-1"
      )
    )
  }

  func testThreadListDoesNotRefreshForCounterpartStateUpdates() {
    XCTAssertFalse(
      FriendsMessagingRealtimeCoordinator.shouldRefreshThreadList(
        forThreadStateUserId: "friend-1",
        viewerUserId: "viewer-1"
      )
    )
  }

}
