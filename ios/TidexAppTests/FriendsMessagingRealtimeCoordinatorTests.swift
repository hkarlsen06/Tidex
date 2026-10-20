import Foundation
import XCTest

@testable import Tidex

@MainActor
final class FriendsMessagingRealtimeCoordinatorTests: XCTestCase {
  @MainActor
  private final class RefreshRecorder {
    var startedCalls = 0
    var passes: [Bool] = []
    var didOverlap = false
    var holdsFirstPass = true
    var releaseFirstPass: CheckedContinuation<Void, Never>?
    private var isRunning = false

    func refresh(_ allowIncrementalSync: Bool) async {
      didOverlap = didOverlap || isRunning
      isRunning = true
      passes.append(allowIncrementalSync)
      if holdsFirstPass, passes.count == 1 {
        await withCheckedContinuation { releaseFirstPass = $0 }
      }
      isRunning = false
    }
  }

  func testSerializedRefreshRunnerMergesCallsDuringARefreshIntoOneMorePass() async {
    let runner = SerializedRefreshRunner()
    let recorder = RefreshRecorder()

    let first = Task {
      recorder.startedCalls += 1
      await runner.run(key: "inbox", allowIncrementalSync: true, recorder.refresh)
    }
    while recorder.releaseFirstPass == nil { await Task.yield() }

    let second = Task {
      recorder.startedCalls += 1
      await runner.run(key: "inbox", allowIncrementalSync: true, recorder.refresh)
    }
    let third = Task {
      recorder.startedCalls += 1
      await runner.run(key: "inbox", allowIncrementalSync: false, recorder.refresh)
    }
    while recorder.startedCalls < 3 { await Task.yield() }

    recorder.releaseFirstPass?.resume()
    await first.value
    await second.value
    await third.value

    // The two calls that arrived during the first pass share one pass, and it takes the full
    // snapshot the third call asked for.
    XCTAssertEqual(recorder.passes, [true, false])
    XCTAssertFalse(recorder.didOverlap)
  }

  // MARK: - Convex payloads

  private func decode<T: Decodable>(_ json: String, as _: T.Type = T.self) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
  }

  private static let liveMessageJSON = """
    {"id":"m-1","thread_id":"t-1","sender_user_id":"u-1","message_type":"user","body":"Hei",
     "client_id":"C-1","reply_to_message_id":null,"created_at":"2026-10-20T12:00:00.123Z",
     "edited_at":null,"deleted_at":null,"metadata":{},"revision":41.0,
     "attachments":[{"id":"a-1","attachment_index":0.0,"kind":"image",
       "url":"https://actions.example/attachments/a-1","mime_type":"image/jpeg",
       "byte_size":2048.0,"width":640.0,"height":null,"created_at":"2026-10-20T12:00:00.123Z",
       "reactions":[{"emoji":"x","count":1.0,"viewer_has_reacted":true}]}],
    "reactions":[]}
    """

  func testMessagePayloadDecodesConvexShape() throws {
    let message = try decode(Self.liveMessageJSON, as: MessagingMessageRow.self).toFriendMessage()

    XCTAssertEqual(message.clientId, "c-1")
    XCTAssertEqual(message.createdAt.timeIntervalSince1970, 1_792_497_600.123, accuracy: 0.001)
    XCTAssertNil(message.deletedAt)
    let attachment = try XCTUnwrap(message.attachments.first)
    XCTAssertEqual(attachment.storagePath, "https://actions.example/attachments/a-1")
    XCTAssertEqual(attachment.byteSize, 2048)
    XCTAssertEqual(attachment.width, 640)
    XCTAssertNil(attachment.height)
    XCTAssertEqual(attachment.reactions.map(\.viewerHasReacted), [true])
  }

  func testChangesPageTurnsDeletedMessagesIntoDeleteEvents() throws {
    let deleted = Self.liveMessageJSON
      .replacingOccurrences(of: "\"id\":\"m-1\"", with: "\"id\":\"m-2\"")
      .replacingOccurrences(
        of: "\"deleted_at\":null", with: "\"deleted_at\":\"2026-10-20T12:05:00.000Z\"")
      .replacingOccurrences(of: "\"revision\":41.0", with: "\"revision\":42.0")
    let page = try decode(
      "{\"messages\":[\(Self.liveMessageJSON),\(deleted)],\"cursor\":42.0,\"done\":false}",
      as: MessagingThreadChangesRow.self
    ).toFriendThreadSyncEventsPage()

    XCTAssertEqual(page.events.map(\.eventType), [.messageUpserted, .messageDeleted])
    XCTAssertEqual(page.events.map(\.version), [41, 42])
    XCTAssertEqual(page.events.last?.deletedMessageId, "m-2")
    XCTAssertEqual(page.latestVersion, 42)
    XCTAssertTrue(page.hasMore)
    XCTAssertFalse(page.requiresSnapshot)
  }

  func testInboxPayloadKeepsViewerStateTimeAndUnreadCount() throws {
    let json = """
      {"threads":[{"thread_id":"t-1","kind":"direct","title":null,"avatar_url":null,"metadata":{},
        "counterpart_user_id":"u-2","counterpart_display_name":"Kari",
        "counterpart_profile_picture_url":null,"counterpart_oauth_avatar_url":null,
        "last_message_id":"m-1","last_message_sender_id":"u-2","last_message_at":"2026-10-20T12:00:00.123Z",
        "last_message_body":"Hei","last_message_preview_kind":"text","last_message_has_image":false,
        "unread_count":2.0,"muted":false,"created_at":"2026-10-01T08:00:00.000Z",
        "viewer_state_updated_at":"2026-10-20T12:00:00.200Z"}],
       "unread_direct_message_count":2.0,"has_more":false,"next_cursor":null}
      """
    let snapshot = try decode(json, as: MessagingInboxRow.self).toFriendInboxSyncSnapshot()

    XCTAssertEqual(snapshot.unreadDirectMessageCount, 2)
    XCTAssertNil(snapshot.nextCursor)
    let thread = try XCTUnwrap(snapshot.threads.first)
    XCTAssertEqual(thread.unreadCount, 2)
    XCTAssertEqual(thread.lastMessagePreviewKind, .text)
    XCTAssertEqual(
      try XCTUnwrap(thread.viewerStateUpdatedAt).timeIntervalSince1970, 1_792_497_600.2,
      accuracy: 0.001)
  }

  func testCursorTimestampKeepsTheServersMillisecondFormat() throws {
    let stamp = "2026-10-20T12:00:00.123Z"
    let date = try XCTUnwrap(ISO8601Timestamp.date(from: stamp))

    XCTAssertEqual(ConvexTimestamp.string(from: date), stamp)
  }
}
