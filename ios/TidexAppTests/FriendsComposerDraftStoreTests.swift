import SwiftData
import XCTest

@testable import Tidex

@MainActor
final class FriendsComposerDraftStoreTests: XCTestCase {
  func testLoadAndClearAttachmentDraft() async throws {
    let store = try makeStore()
    let attachment = FriendsComposerAttachmentDraft.shiftSnapshot(
      ComposerShiftSnapshotDraft(snapshot: makeShiftSnapshot())
    )

    await store.saveAttachmentDraft(attachment, threadId: "thread-1", viewerUserId: "viewer-1")

    let loadedDraft = await store.loadAttachmentDraft(
      threadId: "thread-1", viewerUserId: "viewer-1")
    XCTAssertEqual(loadedDraft, attachment)

    await store.clearAttachmentDraft(threadId: "thread-1", viewerUserId: "viewer-1")

    let clearedDraft = await store.loadAttachmentDraft(
      threadId: "thread-1", viewerUserId: "viewer-1")
    XCTAssertNil(clearedDraft)
  }

  private func makeStore() throws -> FriendsComposerDraftStore {
    let schema = Schema([LocalPendingFriendComposerDraft.self])
    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      allowsSave: true
    )
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let storeActor = LocalStoreActor(modelContainer: container)
    return FriendsComposerDraftStore(container: container, storeActor: storeActor)
  }
}

private func makeShiftSnapshot() -> FriendShiftSnapshot {
  FriendShiftSnapshot(
    schemaVersion: 1,
    ownerUserId: "viewer-1",
    ownerDisplayName: "Viewer",
    ownerAvatarUrl: nil,
    shiftId: "shift-1",
    jobName: "Cafe",
    jobColorHex: "#FFAA00",
    shiftDate: "2026-03-11",
    startTime: "09:00",
    endTime: "17:00",
    paidHours: 7.5,
    currency: "kr",
    includesEarnings: true,
    grossPay: 1200,
    netPay: 1050,
    taxEnabled: true,
    source: "tests"
  )
}
