import Foundation
import Supabase
import XCTest

@testable import Tidex

@MainActor
final class FriendsMessagingRealtimeCoordinatorTests: XCTestCase {
  func testExtractThreadIdPrefersThreadIdFieldForMessageActions() {
    let action = AnyAction.insert(
      InsertAction(
        columns: [],
        commitTimestamp: Date(),
        record: [
          "id": "message-1",
          "thread_id": "thread-1",
        ],
        rawMessage: Self.rawMessage()
      ))

    XCTAssertEqual(FriendsMessagingRealtimeCoordinator.extractThreadId(from: action), "thread-1")
    XCTAssertEqual(FriendsMessagingRealtimeCoordinator.extractMessageId(from: action), "message-1")
  }

  func testExtractThreadIdFallsBackToPrimaryIdForThreadActions() {
    let action = AnyAction.update(
      UpdateAction(
        columns: [],
        commitTimestamp: Date(),
        record: [
          "id": "thread-22",
          "kind": "direct",
        ],
        oldRecord: [:],
        rawMessage: Self.rawMessage()
      ))

    XCTAssertEqual(FriendsMessagingRealtimeCoordinator.extractThreadId(from: action), "thread-22")
    XCTAssertEqual(FriendsMessagingRealtimeCoordinator.extractMessageId(from: action), "thread-22")
  }

  func testDecodeThreadUserStateParsesInsertedPayload() {
    let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let lastReadAt = Date(timeIntervalSince1970: 1_699_999_900)

    let action = AnyAction.insert(
      InsertAction(
        columns: [],
        commitTimestamp: updatedAt,
        record: [
          "thread_id": "thread-1",
          "user_id": "viewer-1",
          "last_read_message_id": "message-9",
          "last_read_at": .string(ISO8601DateFormatter().string(from: lastReadAt)),
          "muted": true,
          "updated_at": .string(ISO8601DateFormatter().string(from: updatedAt)),
        ],
        rawMessage: Self.rawMessage()
      ))

    let state = FriendsMessagingRealtimeCoordinator.decodeThreadUserState(from: action)

    XCTAssertEqual(state?.threadId, "thread-1")
    XCTAssertEqual(state?.userId, "viewer-1")
    XCTAssertEqual(state?.lastReadMessageId, "message-9")
    XCTAssertEqual(state?.muted, true)
    XCTAssertEqual(
      state?.lastReadAt?.timeIntervalSince1970, lastReadAt.timeIntervalSince1970, accuracy: 1)
    XCTAssertEqual(
      state?.updatedAt.timeIntervalSince1970, updatedAt.timeIntervalSince1970, accuracy: 1)
  }

  func testDecodeThreadUserStateIgnoresDeletePayloads() {
    let action = AnyAction.delete(
      DeleteAction(
        columns: [],
        commitTimestamp: Date(),
        oldRecord: [
          "thread_id": "thread-1",
          "user_id": "viewer-1",
        ],
        rawMessage: Self.rawMessage()
      ))

    XCTAssertNil(FriendsMessagingRealtimeCoordinator.decodeThreadUserState(from: action))
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

  private static func rawMessage() -> RealtimeMessageV2 {
    RealtimeMessageV2(
      joinRef: nil,
      ref: nil,
      topic: "realtime:public:messages",
      event: .postgresChanges,
      payload: [:]
    )
  }
}
