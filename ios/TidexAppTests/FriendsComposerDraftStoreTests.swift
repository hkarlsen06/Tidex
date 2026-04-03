import SwiftData
import XCTest

@testable import Tidex

@MainActor
final class FriendsComposerDraftStoreTests: XCTestCase {
  func testLoadAndClearTextDraft() async throws {
    let store = try makeStore()

    await store.saveDraftText("Draft message", threadId: "thread-1", viewerUserId: "viewer-1")

    let loadedText = await store.loadDraftText(threadId: "thread-1", viewerUserId: "viewer-1")
    XCTAssertEqual(loadedText, "Draft message")

    await store.saveDraftText("", threadId: "thread-1", viewerUserId: "viewer-1")

    let clearedText = await store.loadDraftText(threadId: "thread-1", viewerUserId: "viewer-1")
    XCTAssertEqual(clearedText, "")
  }

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

  func testClearingAttachmentPreservesSavedTextDraft() async throws {
    let store = try makeStore()
    let attachment = FriendsComposerAttachmentDraft.shiftSnapshot(
      ComposerShiftSnapshotDraft(snapshot: makeShiftSnapshot())
    )

    await store.saveDraftText("Draft message", threadId: "thread-1", viewerUserId: "viewer-1")
    await store.saveAttachmentDraft(attachment, threadId: "thread-1", viewerUserId: "viewer-1")
    await store.clearAttachmentDraft(threadId: "thread-1", viewerUserId: "viewer-1")

    let restoredDraft = await store.loadDraft(threadId: "thread-1", viewerUserId: "viewer-1")
    XCTAssertEqual(restoredDraft?.text, "Draft message")
    XCTAssertNil(restoredDraft?.attachment)
  }

  func testLoadAndSaveMultipleAttachmentDrafts() async throws {
    let store = try makeStore()
    let attachments: [FriendsComposerAttachmentDraft] = [
      .image(ImageAttachment(id: "image-1", data: Data([0x00]), mediaType: "image/jpeg")),
      .image(ImageAttachment(id: "image-2", data: Data([0x01]), mediaType: "image/jpeg")),
    ]

    await store.saveAttachmentDrafts(attachments, threadId: "thread-1", viewerUserId: "viewer-1")

    let restoredDraft = await store.loadDraft(threadId: "thread-1", viewerUserId: "viewer-1")

    XCTAssertEqual(restoredDraft?.attachments, attachments)
  }

  func testClearingImageAttachmentDraftRemovesPersistedFiles() async throws {
    let attachmentsDirectory = makeAttachmentsDirectory()
    let store = try makeStore(attachmentsDirectory: attachmentsDirectory)
    let attachments: [FriendsComposerAttachmentDraft] = [
      .image(ImageAttachment(id: "image-1", data: Data([0x00]), mediaType: "image/jpeg")),
      .image(ImageAttachment(id: "image-2", data: Data([0x01]), mediaType: "image/jpeg")),
    ]

    await store.saveAttachmentDrafts(attachments, threadId: "thread-1", viewerUserId: "viewer-1")

    let draftDirectory =
      attachmentsDirectory
      .appendingPathComponent("viewer-1", isDirectory: true)
      .appendingPathComponent("thread-1", isDirectory: true)
    XCTAssertTrue(FileManager.default.fileExists(atPath: draftDirectory.path))

    await store.clearAttachmentDraft(threadId: "thread-1", viewerUserId: "viewer-1")

    XCTAssertFalse(FileManager.default.fileExists(atPath: draftDirectory.path))
  }

  func testResolvedAttachmentsDirectoryUsesApplicationSupportFallback() {
    let fallbackBaseURL = URL(
      filePath: "/fallback/Application Support", directoryHint: .isDirectory)

    let resolvedDirectory = FriendsComposerDraftStore.resolvedAttachmentsDirectory(
      appGroupURL: nil,
      fallbackBaseURL: fallbackBaseURL
    )

    XCTAssertEqual(
      resolvedDirectory,
      fallbackBaseURL.appendingPathComponent(
        "FriendsComposerDraftAttachments",
        isDirectory: true
      )
    )
  }

  private func makeStore(attachmentsDirectory: URL? = nil) throws -> FriendsComposerDraftStore {
    let schema = Schema([LocalPendingFriendComposerDraft.self])
    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      allowsSave: true
    )
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let storeActor = LocalStoreActor(modelContainer: container)
    return FriendsComposerDraftStore(
      container: container,
      storeActor: storeActor,
      attachmentsDirectory: attachmentsDirectory
    )
  }

  private func makeAttachmentsDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
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
