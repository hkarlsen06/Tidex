import SwiftData
import XCTest

@testable import Tidex

/// Regression tests for sync behavior when the network or the server misbehaves.
@MainActor
// swiftlint:disable:next type_body_length
internal final class SyncOfflineBehaviorTests: XCTestCase {
  private let userId: String = "user-1"

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema([
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
    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      allowsSave: true
    )
    return try ModelContainer(for: schema, configurations: [configuration])
  }

  private func makeShift(id: String, in store: LocalStoreActor) async throws -> LocalUserShift {
    _ = try await store.createUserShift(
      id: id,
      userId: userId,
      jobId: "job-1",
      shiftDate: Date.fromDateAndTime("2026-03-02", time: "00:00") ?? Date(),
      startTime: "09:00",
      endTime: "17:00",
      customSupplements: nil
    )
    let record = try await store.getUserShift(id: id)
    return try XCTUnwrap(record)
  }

  private func makeAdjustment(in store: LocalStoreActor) async throws -> LocalPayrollAdjustment {
    let created = try await store.createPayrollAdjustment(
      userId: userId,
      jobId: nil,
      amount: 500,
      currency: "kr",
      category: .other,
      taxTreatment: .grossTaxable,
      description: "Bonus",
      note: nil,
      earnedFromDate: nil,
      earnedToDate: nil,
      payoutDate: Date()
    )
    let record = try await store.getPayrollAdjustment(id: created.id)
    return try XCTUnwrap(record)
  }

  private func serverShiftRow(id: String, startTime: String, revision: Int64) -> SyncShiftRow {
    SyncShiftRow(
      id: id,
      user_id: userId,
      job_id: "job-1",
      shift_date: "2026-03-02",
      start_time: startTime,
      end_time: "17:00",
      note: nil,
      custom_pause_windows: nil,
      custom_supplements: nil,
      created_at: nil,
      updated_at: ISO8601Timestamp.string(from: Date()),
      revision: revision,
      deleted_at: nil
    )
  }

  private func serverShiftSnapshot(startTime: String, revision: Int64) -> UserShiftServerSnapshot {
    UserShiftServerSnapshot.from(
      jobId: "job-1",
      shiftDate: "2026-03-02",
      startTime: startTime,
      endTime: "17:00",
      note: nil,
      customPauseWindows: nil,
      customSupplements: nil,
      updatedAt: Date(),
      revision: revision,
      deletedAt: nil
    )
  }

  // MARK: - Interval guard after a failed sync

  internal func testFailedSyncClearsIntervalGuard() async {
    let store = SyncStateStore()

    let first = await store.beginSync(reason: .foreground, userId: userId, minimumSyncInterval: 60)
    XCTAssertEqual(first, .started)
    _ = await store.endSync(success: false)

    let second = await store.beginSync(
      reason: .foreground, userId: userId, minimumSyncInterval: 60)
    XCTAssertEqual(second, .started, "A failed sync must not suppress the next foreground sync")
  }

  internal func testSuccessfulSyncKeepsIntervalGuard() async {
    let store = SyncStateStore()

    _ = await store.beginSync(reason: .foreground, userId: userId, minimumSyncInterval: 60)
    _ = await store.endSync(success: true)

    let foreground = await store.beginSync(
      reason: .foreground, userId: userId, minimumSyncInterval: 60)
    XCTAssertEqual(foreground, .skippedInterval)
    _ = await store.endSync(success: true)

    let manual = await store.beginSync(
      reason: .manualRefresh, userId: userId, minimumSyncInterval: 60)
    XCTAssertEqual(manual, .started, "A manual refresh ignores the interval guard")
  }

  internal func testSecondSyncCannotStartWhileOneRuns() async {
    let store = SyncStateStore()

    let first = await store.beginSync(reason: .foreground, userId: userId, minimumSyncInterval: 60)
    let second = await store.beginSync(
      reason: .localChange, userId: userId, minimumSyncInterval: 60)

    XCTAssertEqual(first, .started)
    XCTAssertEqual(second, .alreadySyncing)
    let followUp = await store.endSync(success: true)
    XCTAssertTrue(followUp, "A local change during a sync queues a follow-up sync")
  }

  // MARK: - Sign-out guard

  internal func testConflictWithServerRevisionCountsAsPendingChange() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    _ = try await makeShift(id: "shift-1", in: store)
    await store.resolveShiftConflictKeepServer(
      id: "shift-1", serverSnapshot: serverShiftSnapshot(startTime: "09:00", revision: 3))
    let cleanHasPending = try await store.hasPendingChanges(userId: userId)
    XCTAssertFalse(cleanHasPending)

    await store.markShiftConflict(id: "shift-1", serverSnapshot: nil)

    let hasPending = try await store.hasPendingChanges(userId: userId)
    XCTAssertTrue(hasPending, "A conflicted row holds a local edit that sign-out would delete")
  }

  internal func testPayrollAdjustmentConflictIsCounted() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let adjustment = try await makeAdjustment(in: store)
    await store.markPayrollAdjustmentClean(id: adjustment.id)
    let cleanCount = try await store.countConflicts(userId: userId)
    XCTAssertEqual(cleanCount, 0)

    await store.markPayrollAdjustmentConflict(id: adjustment.id, serverSnapshot: nil)

    let conflicts = try await store.getConflicts(userId: userId)
    XCTAssertEqual(conflicts.payrollAdjustments.map(\.id), [adjustment.id])
    let count = try await store.countConflicts(userId: userId)
    XCTAssertEqual(count, 1)
    let hasConflicts = try await store.hasConflicts(userId: userId)
    XCTAssertTrue(hasConflicts)
    let hasPending = try await store.hasPendingChanges(userId: userId)
    XCTAssertTrue(hasPending)
  }

  internal func testDirtyNotificationPreferencesCountAsPendingChange() async throws {
    let container = try makeContainer()
    let store = LocalStoreActor(modelContainer: container)
    let context = ModelContext(container)
    // The repository stores the user id in upper case.
    context.insert(LocalNotificationPreferences(userId: "USER-1", syncStatus: .dirty))
    try context.save()

    let hasPending = try await store.hasPendingChanges(userId: userId)

    XCTAssertTrue(hasPending)
  }

  internal func testCleanNotificationPreferencesAreNotPending() async throws {
    let container = try makeContainer()
    let store = LocalStoreActor(modelContainer: container)
    let context = ModelContext(container)
    context.insert(LocalNotificationPreferences(userId: "USER-1", syncStatus: .clean))
    try context.save()

    let hasPending = try await store.hasPendingChanges(userId: userId)

    XCTAssertFalse(hasPending)
  }

  internal func testUnsentMessagesCountAsPendingChange() async throws {
    let container = try makeContainer()
    let store = LocalStoreActor(modelContainer: container)
    let context = ModelContext(container)
    for (index, state) in [FriendMessageSendState.sent, .sending, .failed].enumerated() {
      context.insert(
        LocalMessage(
          id: "message-\(index)",
          viewerUserId: userId,
          threadId: "thread-1",
          senderUserId: userId,
          messageTypeRaw: "text",
          body: "Hi",
          clientId: "client-\(index)",
          replyToMessageId: nil,
          createdAt: Date(),
          editedAt: nil,
          deletedAt: nil,
          sendStateRaw: state.rawValue
        ))
    }
    try context.save()

    let hasUnsent = try await store.hasUnsentMessages(userId: userId)
    XCTAssertTrue(hasUnsent)
    let otherUser = try await store.hasUnsentMessages(userId: "user-2")
    XCTAssertFalse(otherUser)
  }

  internal func testSentMessagesAreNotPending() async throws {
    let container = try makeContainer()
    let store = LocalStoreActor(modelContainer: container)
    let context = ModelContext(container)
    context.insert(
      LocalMessage(
        id: "message-1",
        viewerUserId: userId,
        threadId: "thread-1",
        senderUserId: userId,
        messageTypeRaw: "text",
        body: "Hi",
        clientId: "client-1",
        replyToMessageId: nil,
        createdAt: Date(),
        editedAt: nil,
        deletedAt: nil,
        sendStateRaw: FriendMessageSendState.sent.rawValue
      ))
    try context.save()

    let hasPending = try await store.hasPendingChanges(userId: userId)

    XCTAssertFalse(hasPending)
  }

  // MARK: - Never pushed delete

  internal func testRetiredNeverPushedShiftIsNoLongerDirty() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let shift = try await makeShift(id: "shift-1", in: store)
    _ = try await store.markShiftPendingDelete(id: "shift-1")
    let dirtyBefore = try await store.getDirtyUserShifts(userId: userId)
    XCTAssertEqual(dirtyBefore.map(\.id), ["shift-1"])
    XCTAssertEqual(shift.serverRevision, 0)

    // This is what the push does for a pending delete with serverRevision 0.
    let deletedAt = Date()
    await store.markShiftDeleted(
      id: "shift-1", serverUpdatedAt: deletedAt, serverRevision: 0, serverDeletedAt: deletedAt)

    let dirtyAfter = try await store.getDirtyUserShifts(userId: userId)
    XCTAssertTrue(dirtyAfter.isEmpty)
    XCTAssertEqual(shift.syncStatus, .clean)
    XCTAssertNotNil(shift.serverDeletedAt)
    let hasPending = try await store.hasPendingChanges(userId: userId)
    XCTAssertFalse(hasPending)
  }

  // MARK: - Pull does not overwrite a row that became dirty

  internal func testPullDoesNotOverwriteDirtyShift() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let shift = try await makeShift(id: "shift-1", in: store)
    XCTAssertEqual(shift.syncStatus, .dirty)

    let applied = await store.updateShiftFromServer(
      id: "shift-1",
      serverRow: serverShiftRow(id: "shift-1", startTime: "08:00", revision: 2),
      serverUpdatedAt: Date(),
      serverRevision: 2,
      serverDeletedAt: nil,
      snapshot: serverShiftSnapshot(startTime: "08:00", revision: 2)
    )

    XCTAssertFalse(applied, "The overwrite must be refused for a dirty row")
    XCTAssertEqual(shift.startTime, "09:00")
    XCTAssertEqual(shift.syncStatus, .dirty)
    XCTAssertEqual(shift.serverRevision, 0)
  }

  internal func testPullOverwritesCleanShift() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let shift = try await makeShift(id: "shift-1", in: store)
    await store.markShiftClean(id: "shift-1")

    let applied = await store.updateShiftFromServer(
      id: "shift-1",
      serverRow: serverShiftRow(id: "shift-1", startTime: "08:00", revision: 2),
      serverUpdatedAt: Date(),
      serverRevision: 2,
      serverDeletedAt: nil,
      snapshot: serverShiftSnapshot(startTime: "08:00", revision: 2)
    )

    XCTAssertTrue(applied)
    XCTAssertEqual(shift.startTime, "08:00")
    XCTAssertEqual(shift.serverRevision, 2)
  }

  internal func testPullDoesNotOverwriteDirtyPayrollAdjustment() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let adjustment = try await makeAdjustment(in: store)
    let row = SyncPayrollAdjustmentRow(
      id: adjustment.id,
      user_id: userId,
      job_id: nil,
      amount: 900,
      currency: "kr",
      category: .other,
      tax_treatment: .grossTaxable,
      description: "Bonus",
      note: nil,
      curated_note: nil,
      curated_description: nil,
      curated_link: nil,
      curated_link_title: nil,
      earned_from_date: nil,
      earned_to_date: nil,
      payout_date: "2026-03-02",
      created_at: nil,
      updated_at: ISO8601Timestamp.string(from: Date()),
      revision: 2,
      deleted_at: nil
    )
    let snapshot = PayrollAdjustmentServerSnapshot.from(
      row: row, updatedAt: Date(), deletedAt: nil)

    let applied = await store.updatePayrollAdjustmentFromServer(
      id: adjustment.id,
      serverRow: row,
      serverUpdatedAt: Date(),
      serverDeletedAt: nil,
      snapshot: snapshot,
      onlyIfClean: true
    )

    XCTAssertFalse(applied)
    XCTAssertEqual(adjustment.amount, 500)
    XCTAssertEqual(adjustment.syncStatus, .dirty)
  }

  // swiftlint:disable:next function_body_length
  internal func testPayrollAdjustmentEditKeepsAnotherDevicesChangeToOtherFields() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let adjustment = try await makeAdjustment(in: store)
    await store.markPayrollAdjustmentClean(id: adjustment.id)

    // The editor saves every field, but only the note changed.
    _ = try await store.updatePayrollAdjustment(
      id: adjustment.id,
      jobId: nil,
      amount: 500,
      currency: "kr",
      category: .other,
      taxTreatment: .grossTaxable,
      description: "Bonus",
      note: "Local note",
      earnedFromDate: nil,
      earnedToDate: nil,
      payoutDate: adjustment.payoutDate
    )
    XCTAssertEqual(adjustment.dirtyFieldKeys, [.note])

    // Another device changed the amount. The merge takes it and keeps the unpushed note.
    let row = SyncPayrollAdjustmentRow(
      id: adjustment.id,
      user_id: userId,
      job_id: nil,
      amount: 900,
      currency: "kr",
      category: .other,
      tax_treatment: .grossTaxable,
      description: "Bonus",
      note: nil,
      curated_note: nil,
      curated_description: nil,
      curated_link: nil,
      curated_link_title: nil,
      earned_from_date: nil,
      earned_to_date: nil,
      payout_date: adjustment.payoutDateString,
      created_at: nil,
      updated_at: ISO8601Timestamp.string(from: Date()),
      revision: 2,
      deleted_at: nil
    )
    await store.mergePayrollAdjustmentFromServer(
      id: adjustment.id,
      serverRow: row,
      serverUpdatedAt: Date(),
      serverDeletedAt: nil,
      snapshot: PayrollAdjustmentServerSnapshot.from(row: row, updatedAt: Date(), deletedAt: nil)
    )

    XCTAssertEqual(adjustment.amount, 900)
    XCTAssertEqual(adjustment.note, "Local note")
    XCTAssertEqual(adjustment.dirtyFieldKeys, [.note])
    XCTAssertEqual(adjustment.syncStatus, .dirty)
    XCTAssertEqual(adjustment.serverRevision, 2)
  }

  // MARK: - Payroll adjustment conflict resolution

  internal func testKeepLocalRequeuesPayrollAdjustmentAsWholeRow() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let adjustment = try await makeAdjustment(in: store)
    await store.markPayrollAdjustmentClean(id: adjustment.id)
    await store.markPayrollAdjustmentConflict(id: adjustment.id, serverSnapshot: nil)

    await store.resolvePayrollAdjustmentConflictKeepLocal(id: adjustment.id, serverRevision: 4)

    XCTAssertEqual(adjustment.syncStatus, .dirty)
    XCTAssertEqual(adjustment.serverRevision, 4)
    XCTAssertEqual(adjustment.dirtyFieldKeys, Set(PayrollAdjustmentField.allCases))
    XCTAssertNil(adjustment.conflictServerSnapshot)
  }

  internal func testKeepServerRestoresPayrollAdjustmentFromSnapshot() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let adjustment = try await makeAdjustment(in: store)
    let snapshot = PayrollAdjustmentServerSnapshot(
      jobId: nil,
      amount: 900,
      currency: "kr",
      category: .other,
      taxTreatment: .grossTaxable,
      description: "Server bonus",
      note: nil,
      curatedNote: nil,
      curatedDescription: nil,
      curatedLink: nil,
      curatedLinkTitle: nil,
      earnedFromDate: nil,
      earnedToDate: nil,
      payoutDate: "2026-03-02",
      updatedAt: Date(),
      revision: 5,
      deletedAt: nil
    )
    await store.markPayrollAdjustmentConflict(id: adjustment.id, serverSnapshot: snapshot)

    await store.resolvePayrollAdjustmentConflictKeepServer(
      id: adjustment.id, serverSnapshot: snapshot)

    XCTAssertEqual(adjustment.amount, 900)
    XCTAssertEqual(adjustment.descriptionText, "Server bonus")
    XCTAssertEqual(adjustment.serverRevision, 5)
    XCTAssertEqual(adjustment.syncStatus, .clean)
    XCTAssertEqual(adjustment.dirtyFieldKeys, [])
  }

  // MARK: - Notification preferences edited during a push

  internal func testEditDuringPushKeepsNotificationPreferencesDirty() {
    let pushedAt = Date(timeIntervalSince1970: 1_000)
    let preferences = LocalNotificationPreferences(
      userId: "USER-1", syncStatus: .dirty, localUpdatedAt: pushedAt)

    // The user edits the preferences after the push request was built.
    preferences.markDirty()
    preferences.markPushed(serverUpdatedAt: Date(), pushedLocalUpdatedAt: pushedAt)

    XCTAssertEqual(preferences.syncStatus, .dirty)
  }

  internal func testUnchangedNotificationPreferencesBecomeCleanAfterPush() {
    let pushedAt = Date(timeIntervalSince1970: 1_000)
    let preferences = LocalNotificationPreferences(
      userId: "USER-1", syncStatus: .dirty, localUpdatedAt: pushedAt)

    preferences.markPushed(serverUpdatedAt: Date(), pushedLocalUpdatedAt: pushedAt)

    XCTAssertEqual(preferences.syncStatus, .clean)
  }

  // MARK: - Pull poison row

  internal func testCursorSkipsTrailingRowWithBadTimestamp() throws {
    let good = "2026-03-02T09:00:00.000Z"
    let position = SyncCoordinator.lastParseableCursorPosition(
      [(updatedAt: good, id: "a"), (updatedAt: "not-a-date", id: "b")],
      table: .userShifts
    )

    XCTAssertEqual(position?.id, "a")
    XCTAssertEqual(position?.updatedAt, ISO8601Timestamp.date(from: good))
  }

  internal func testCursorIsNilWhenNoTimestampParses() {
    let position = SyncCoordinator.lastParseableCursorPosition(
      [(updatedAt: "bad", id: "a"), (updatedAt: "worse", id: "b")],
      table: .userShifts
    )

    XCTAssertNil(position)
  }

  internal func testOnlyDataErrorsCountAsUnreadableRows() {
    XCTAssertTrue(
      SyncCoordinator.isUnreadableRowError(
        SyncError.dateParsingFailed(table: .userShifts, id: "a", rawValue: "bad")))
    XCTAssertTrue(
      SyncCoordinator.isUnreadableRowError(SyncEncodingError.emptyUpdatePayload(type: "x")))
    XCTAssertFalse(
      SyncCoordinator.isUnreadableRowError(
        SyncError.localSaveFailed(table: .userShifts, message: "disk full")))
    XCTAssertFalse(SyncCoordinator.isUnreadableRowError(URLError(.notConnectedToInternet)))
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
