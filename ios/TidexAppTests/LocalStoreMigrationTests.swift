import CoreData
import SwiftData
import XCTest

@testable import Tidex

@MainActor
internal final class LocalStoreMigrationTests: XCTestCase {
  private let userId = "migration-user"
  private let savedSnapshot = Data("""
    {"shiftDate":"2026-03-02","startTime":"08:00","endTime":"17:00",
    "updatedAt":"2026-03-01T12:00:00Z","revision":41}
    """.utf8)

  internal func testUnversionedStorePreservesOfflineWorkAndRemainsPersistent() throws {
    let storeURL = try temporaryStoreURL()
    try writeUnversionedStore(at: storeURL)
    let originalHashes = try modelHashes(at: storeURL)

    try autoreleasepool {
      let store = LocalStore(configuration: ModelConfiguration(url: storeURL))
      XCTAssertFalse(store.isStorageUnavailable)
      XCTAssertEqual(store.container.configurations.first?.url, storeURL)
      XCTAssertEqual(store.container.configurations.first?.isStoredInMemoryOnly, false)
      let context = store.mainContext
      let shifts = try context.fetch(FetchDescriptor<LocalUserShift>())
      XCTAssertEqual(shifts.count, 2)
      let dirtyShift = try XCTUnwrap(shifts.first { $0.id == "dirty-shift" })
      XCTAssertEqual(dirtyShift.syncStatus, .dirty)
      XCTAssertEqual(dirtyShift.dirtyFieldKeys, [.startTime, .note])
      XCTAssertEqual(dirtyShift.note, "Offline note")
      XCTAssertEqual(dirtyShift.lastSyncedSnapshot, savedSnapshot)
      let pendingDelete = try XCTUnwrap(shifts.first { $0.id == "deleted-shift" })
      XCTAssertEqual(pendingDelete.syncStatus, .pendingDelete)
      XCTAssertEqual(pendingDelete.serverRevision, 41)

      let message = try XCTUnwrap(context.fetch(FetchDescriptor<LocalMessage>()).first)
      XCTAssertEqual(message.body, "Queued offline")
      XCTAssertEqual(message.clientId, "offline-client-id")
      XCTAssertEqual(message.sendStateRaw, FriendMessageSendState.sending.rawValue)
      let draft = try XCTUnwrap(context.fetch(FetchDescriptor<LocalPendingFriendComposerDraft>()).first)
      XCTAssertEqual(draft.draftText, "Unsent draft")
      XCTAssertEqual(draft.attachmentData, Data([1, 2, 3]))
      let state = try XCTUnwrap(context.fetch(FetchDescriptor<LocalSyncState>()).first)
      XCTAssertEqual(state.lastRevisionUserShifts, 91)
      XCTAssertEqual(state.lastRevisionJobs, 92)

      dirtyShift.note = "Saved after adopting V1"
      try context.save()
    }

    XCTAssertEqual(try modelHashes(at: storeURL), originalHashes)
    let reopened = LocalStore(configuration: ModelConfiguration(url: storeURL))
    XCTAssertFalse(reopened.isStorageUnavailable)
    let shifts = try reopened.mainContext.fetch(FetchDescriptor<LocalUserShift>())
    XCTAssertEqual(shifts.first { $0.id == "dirty-shift" }?.note, "Saved after adopting V1")
    XCTAssertEqual(shifts.first { $0.id == "deleted-shift" }?.syncStatus, .pendingDelete)
  }

  internal func testFailedStoreIsUntouchedAndReplacementRejectsEditsAndSyncState() async throws {
    let storeURL = try temporaryStoreURL()
    let originalBytes = Data("Unreadable store with offline data".utf8)
    try originalBytes.write(to: storeURL)

    let store = LocalStore(configuration: ModelConfiguration(url: storeURL))
    XCTAssertTrue(store.isStorageUnavailable)
    XCTAssertEqual(try Data(contentsOf: storeURL), originalBytes)
    let context = store.mainContext
    context.insert(makeShift(id: "must-not-be-accepted", status: .dirty))
    XCTAssertThrowsError(try context.save())

    do {
      _ = try await store.storeActor.syncStateCopyCreatingIfNeeded(userId: userId)
      XCTFail("An unavailable store must reject sync state creation before pull or push")
    } catch {
      XCTAssertEqual(try Data(contentsOf: storeURL), originalBytes)
    }
  }

  private func temporaryStoreURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try FileManager.default.removeItem(at: directory) }
    return directory.appendingPathComponent("default.store")
  }

  private func modelHashes(at url: URL) throws -> [String: Data] {
    let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
      ofType: NSSQLiteStoreType, at: url, options: nil)
    return try XCTUnwrap(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
  }

  // LocalStore.makeSchema from main at 4f45c9dd. Keep this independent of SchemaV1.
  private var unversionedSchema: Schema {
    Schema([
      LocalJob.self,
      LocalUserShift.self,
      LocalEvent.self,
      LocalRecurringShift.self,
      LocalWageSnapshot.self,
      LocalPayrollAdjustment.self,
      LocalUserSettings.self,
      LocalNotificationPreferences.self,
      LocalSyncState.self,
      LocalSharedShift.self,
      LocalSharer.self,
      LocalShiftPreview.self,
      LocalSharedShiftFetchRecord.self,
      LocalPendingFriendComposerDraft.self,
      LocalThread.self,
      LocalThreadState.self,
      LocalThreadFeedPlacement.self,
      LocalMessage.self,
      LocalMessageAttachment.self,
      LocalMessageReaction.self,
      LocalFriendMessagingSyncState.self,
    ])
  }

  private func writeUnversionedStore(at url: URL) throws {
    try autoreleasepool {
      let schema = unversionedSchema
      let configuration = ModelConfiguration(schema: schema, url: url)
      let container = try ModelContainer(for: schema, configurations: [configuration])
      let context = ModelContext(container)
      let dirtyShift = makeShift(id: "dirty-shift", status: .dirty)
      dirtyShift.dirtyFieldKeys = [.startTime, .note]
      context.insert(dirtyShift)
      context.insert(makeShift(id: "deleted-shift", status: .pendingDelete))
      context.insert(LocalMessage(
        id: "queued-message", viewerUserId: userId, threadId: "thread", senderUserId: userId,
        messageTypeRaw: "text", body: "Queued offline", clientId: "offline-client-id",
        replyToMessageId: nil, createdAt: Date(), editedAt: nil, deletedAt: nil,
        sendStateRaw: FriendMessageSendState.sending.rawValue
      ))
      context.insert(LocalPendingFriendComposerDraft(
        viewerUserId: userId, threadId: "thread", draftText: "Unsent draft",
        attachmentData: Data([1, 2, 3])
      ))
      context.insert(LocalSyncState(
        userId: userId, lastRevisionUserShifts: 91, lastRevisionJobs: 92
      ))
      try context.save()
    }
  }

  private func makeShift(id: String, status: SyncStatus) -> LocalUserShift {
    LocalUserShift(
      id: id, userId: userId, shiftDate: Date(), startTime: "09:00", endTime: "17:00",
      note: "Offline note", serverUpdatedAt: Date(), serverRevision: 41, syncStatus: status,
      lastSyncedSnapshot: savedSnapshot, localUpdatedAt: Date()
    )
  }
}
