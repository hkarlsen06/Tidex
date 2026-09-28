import Supabase
import SwiftData
import XCTest

@testable import Tidex

@MainActor
internal final class SyncPushMergeTests: XCTestCase {
  private let userId: String = "user-1"
  private let shiftId: String = "shift-1"

  private func makeStoreActor() throws -> LocalStoreActor {
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
    ])
    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      allowsSave: true
    )
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return LocalStoreActor(modelContainer: container)
  }

  private func makeShift(in store: LocalStoreActor) async throws -> LocalUserShift {
    _ = try await store.createUserShift(
      id: shiftId,
      userId: userId,
      jobId: "job-1",
      shiftDate: Date.fromDateAndTime("2026-03-02", time: "00:00") ?? Date(),
      startTime: "09:00",
      endTime: "17:00",
      customSupplements: nil
    )
    let record = try await store.getUserShift(id: shiftId)
    return try XCTUnwrap(record)
  }

  private func serverShift(
    startTime: String,
    revision: Int64,
    updatedAt: Date
  ) -> (row: SyncShiftRow, snapshot: UserShiftServerSnapshot) {
    let row = SyncShiftRow(
      id: shiftId,
      user_id: userId,
      job_id: "job-1",
      shift_date: "2026-03-02",
      start_time: startTime,
      end_time: "17:00",
      note: nil,
      custom_pause_windows: nil,
      custom_supplements: nil,
      created_at: nil,
      updated_at: ISO8601DateFormatter().string(from: updatedAt),
      revision: revision,
      deleted_at: nil
    )
    let snapshot = UserShiftServerSnapshot.from(
      jobId: row.job_id,
      shiftDate: row.shift_date,
      startTime: row.start_time,
      endTime: row.end_time,
      note: row.note,
      customPauseWindows: nil,
      customSupplements: nil,
      updatedAt: updatedAt,
      revision: revision,
      deletedAt: nil
    )
    return (row, snapshot)
  }

  private func markPushed(
    _ store: LocalStoreActor,
    startTime: String,
    revision: Int64,
    baseline: SyncPushBaseline
  ) async {
    let server = serverShift(startTime: startTime, revision: revision, updatedAt: Date())
    await store.markShiftPushed(
      id: shiftId,
      serverRow: server.row,
      serverUpdatedAt: server.snapshot.updatedAt,
      serverRevision: revision,
      snapshot: server.snapshot,
      baseline: baseline
    )
  }

  // MARK: - A: push completion versus local changes in flight

  internal func testPushCompletionMarksUnchangedRowClean() async throws {
    let store = try makeStoreActor()
    let shift = try await makeShift(in: store)

    await markPushed(store, startTime: "09:00", revision: 1, baseline: SyncPushBaseline(shift))

    XCTAssertEqual(shift.syncStatus, .clean)
    XCTAssertEqual(shift.dirtyFieldKeys, [])
    XCTAssertEqual(shift.serverRevision, 1)
  }

  internal func testPushCompletionKeepsEditMadeWhileInFlight() async throws {
    let store = try makeStoreActor()
    let shift = try await makeShift(in: store)
    let baseline = SyncPushBaseline(shift)

    // The user edits the shift while the insert request is in flight.
    _ = try await store.updateUserShift(
      id: shiftId,
      shiftDate: nil,
      startTime: "10:00",
      endTime: nil,
      customSupplements: nil
    )
    await markPushed(store, startTime: "09:00", revision: 1, baseline: baseline)

    XCTAssertEqual(shift.startTime, "10:00")
    XCTAssertEqual(shift.syncStatus, .dirty)
    XCTAssertTrue(shift.dirtyFieldKeys.contains(.startTime))
    XCTAssertEqual(shift.serverRevision, 1, "The next push must update, not insert again")
  }

  internal func testPushCompletionKeepsDeleteMadeWhileInFlight() async throws {
    let store = try makeStoreActor()
    let shift = try await makeShift(in: store)
    let baseline = SyncPushBaseline(shift)

    _ = try await store.markShiftPendingDelete(id: shiftId)
    await markPushed(store, startTime: "09:00", revision: 1, baseline: baseline)

    XCTAssertEqual(shift.syncStatus, .pendingDelete)
    XCTAssertEqual(shift.serverRevision, 1, "The delete must target the inserted revision")
  }

  // MARK: - B: row rejections do not stop the sync

  internal func testServerDataRejectionsAreRowLevel() {
    for code in ["P0001", "23505", "23503", "22P02", "42501"] {
      XCTAssertTrue(
        SyncCoordinator.isRowRejection(PostgrestError(code: code, message: "rejected")), code)
    }
    XCTAssertTrue(
      SyncCoordinator.isRowRejection(SyncEncodingError.emptyUpdatePayload(type: "user_shifts")))
  }

  internal func testTransportAndAuthErrorsStillStopTheSync() {
    XCTAssertFalse(
      SyncCoordinator.isRowRejection(PostgrestError(code: "PGRST301", message: "JWT expired")))
    XCTAssertFalse(SyncCoordinator.isRowRejection(PostgrestError(message: "no code")))
    XCTAssertFalse(SyncCoordinator.isRowRejection(URLError(.timedOut)))
    XCTAssertFalse(SyncCoordinator.isRowRejection(CancellationError()))
  }

  // MARK: - C: merging a newer server row into a dirty row

  private func makeEditedSyncedShift(in store: LocalStoreActor) async throws -> LocalUserShift {
    let shift = try await makeShift(in: store)
    await markPushed(store, startTime: "09:00", revision: 1, baseline: SyncPushBaseline(shift))
    _ = try await store.updateUserShift(
      id: shiftId,
      shiftDate: nil,
      startTime: "10:00",
      endTime: nil,
      customSupplements: nil
    )
    return shift
  }

  private func merge(
    _ store: LocalStoreActor,
    _ shift: LocalUserShift,
    serverStartTime: String,
    serverUpdatedAt: Date
  ) async {
    let server = serverShift(startTime: serverStartTime, revision: 2, updatedAt: serverUpdatedAt)
    await store.autoMergeShift(
      id: shiftId,
      serverRow: server.row,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: 2,
      serverDeletedAt: nil,
      newSnapshot: server.snapshot,
      localDirtyFields: SyncMerge.fieldsToKeepLocally(shift, server: server.snapshot)
    )
  }

  internal func testIdenticalValuesOnBothSidesAreNotAConflict() async throws {
    let store = try makeStoreActor()
    let shift = try await makeEditedSyncedShift(in: store)

    // The edit was pushed and committed, but the request timed out locally.
    await merge(store, shift, serverStartTime: "10:00", serverUpdatedAt: Date())

    XCTAssertEqual(shift.syncStatus, .clean)
    XCTAssertEqual(shift.dirtyFieldKeys, [])
    XCTAssertEqual(shift.startTime, "10:00")
    XCTAssertEqual(shift.serverRevision, 2)
  }

  internal func testRealConflictKeepsNewerLocalEdit() async throws {
    let store = try makeStoreActor()
    let shift = try await makeEditedSyncedShift(in: store)

    await merge(
      store, shift, serverStartTime: "11:00",
      serverUpdatedAt: shift.localUpdatedAt.addingTimeInterval(-60))

    XCTAssertEqual(shift.syncStatus, .dirty)
    XCTAssertEqual(shift.dirtyFieldKeys, [.startTime])
    XCTAssertEqual(shift.startTime, "10:00")
    XCTAssertEqual(shift.serverRevision, 2)
  }

  internal func testNewerServerTimestampDoesNotDiscardUnacknowledgedEdit() async throws {
    let store = try makeStoreActor()
    let shift = try await makeEditedSyncedShift(in: store)

    await merge(
      store, shift, serverStartTime: "11:00",
      serverUpdatedAt: shift.localUpdatedAt.addingTimeInterval(60))

    XCTAssertEqual(shift.syncStatus, .dirty)
    XCTAssertEqual(shift.dirtyFieldKeys, [.startTime])
    XCTAssertEqual(shift.startTime, "10:00")
  }

  internal func testTimedOutPushKeepsSubsequentEditAndSettlesOnAcknowledgement() async throws {
    let store = try makeStoreActor()
    let shift = try await makeEditedSyncedShift(in: store)

    // A push of 10:00 is in flight. The user edits again before it reaches the server.
    _ = try await store.updateUserShift(
      id: shiftId, shiftDate: nil, startTime: "11:00", endTime: nil, customSupplements: nil)
    let serverUpdatedAt = shift.localUpdatedAt.addingTimeInterval(60)

    // The response is lost. A later pull sees the delayed 10:00 write.
    await merge(store, shift, serverStartTime: "10:00", serverUpdatedAt: serverUpdatedAt)

    XCTAssertEqual(shift.startTime, "11:00")
    XCTAssertEqual(shift.syncStatus, .dirty)
    XCTAssertEqual(shift.dirtyFieldKeys, [.startTime])
    XCTAssertEqual(shift.serverRevision, 2)

    await markPushed(store, startTime: "11:00", revision: 3, baseline: SyncPushBaseline(shift))

    XCTAssertEqual(shift.startTime, "11:00")
    XCTAssertEqual(shift.syncStatus, .clean)
    XCTAssertEqual(shift.dirtyFieldKeys, [])
  }
}
