import SwiftData
import XCTest

@testable import Tidex

@MainActor
internal final class SyncConflictRowTests: XCTestCase {
  private let userId: String = "user-1"
  private let now: Date = Date(timeIntervalSince1970: 1_772_000_000)
  private let snapshot: Data = Data("{}".utf8)

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema([
      LocalJob.self,
      LocalUserShift.self,
      LocalEvent.self,
      LocalRecurringShift.self,
      LocalWageSnapshot.self,
      LocalPayrollAdjustment.self,
      LocalUserSettings.self,
      LocalSyncState.self,
    ])
    let configuration = ModelConfiguration(
      schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
    return try ModelContainer(for: schema, configurations: [configuration])
  }

  private func makeJob(serverSnapshot: Data? = nil) -> LocalJob {
    LocalJob(
      id: "job-1", userId: userId, name: "Cafe", isDefault: true, sortOrder: 0,
      serverUpdatedAt: now, serverRevision: 1, syncStatus: .conflict,
      lastSyncedSnapshot: Data(), localUpdatedAt: now, conflictServerSnapshot: serverSnapshot)
  }

  private func makeShift(serverSnapshot: Data? = nil) -> LocalUserShift {
    LocalUserShift(
      id: "shift-1", userId: userId, jobId: "job-1", shiftDate: now,
      startTime: "09:00:00", endTime: "17:00:00", serverUpdatedAt: now, serverRevision: 1,
      syncStatus: .conflict, lastSyncedSnapshot: Data(), localUpdatedAt: now,
      conflictServerSnapshot: serverSnapshot)
  }

  func testJobRowUsesNameAndSnapshotPresence() {
    let withSnapshot = SyncConflictRow.make(job: makeJob(serverSnapshot: snapshot))
    XCTAssertEqual(withSnapshot.kind, .job)
    XCTAssertEqual(withSnapshot.entityId, "job-1")
    XCTAssertEqual(withSnapshot.title, "Cafe")
    XCTAssertTrue(withSnapshot.hasServerVersion)

    XCTAssertFalse(SyncConflictRow.make(job: makeJob()).hasServerVersion)
  }

  func testShiftRowShowsTimeRangeAndJobName() {
    let row = SyncConflictRow.make(shift: makeShift(), jobName: "Cafe")
    XCTAssertEqual(row.kind, .shift)
    XCTAssertEqual(row.detail, "09:00 - 17:00 · Cafe")
    XCTAssertFalse(row.hasServerVersion)

    let noJob = SyncConflictRow.make(shift: makeShift(serverSnapshot: snapshot), jobName: nil)
    XCTAssertEqual(noJob.detail, "09:00 - 17:00")
    XCTAssertTrue(noJob.hasServerVersion)
  }

  func testEventRowUsesNoteAsTitle() {
    let event = LocalEvent(
      id: "event-1", userId: userId, startDate: now, endDate: now, isAllDay: true,
      startTime: nil, endTime: nil, note: " Dentist ", serverUpdatedAt: now, serverRevision: 1,
      syncStatus: .conflict, lastSyncedSnapshot: Data(), localUpdatedAt: now)
    let row = SyncConflictRow.make(event: event)
    XCTAssertEqual(row.title, "Dentist")
    XCTAssertFalse(row.hasServerVersion)
  }

  func testPayrollAdjustmentRowShowsLabelAndAmount() {
    let adjustment = LocalPayrollAdjustment(
      id: "adj-1", userId: userId, amount: 1_500, currency: "kr", category: .bonus,
      taxTreatment: .grossTaxable, description: "Bonus", payoutDate: now,
      serverUpdatedAt: now, serverRevision: 1, syncStatus: .conflict,
      lastSyncedSnapshot: Data(), localUpdatedAt: now, conflictServerSnapshot: snapshot)
    let row = SyncConflictRow.make(payrollAdjustment: adjustment)
    XCTAssertEqual(row.kind, .payrollAdjustment)
    XCTAssertEqual(row.title, "Bonus")
    XCTAssertTrue(row.detail?.contains("kr") == true)
    XCTAssertTrue(row.hasServerVersion)
  }

  func testSettingsRowUsesUserIdAsEntityId() {
    let settings = LocalUserSettings(
      userId: userId, serverUpdatedAt: now, serverRevision: 1, syncStatus: .conflict,
      lastSyncedSnapshot: Data(), localUpdatedAt: now)
    let row = SyncConflictRow.make(settings: settings)
    XCTAssertEqual(row.kind, .settings)
    XCTAssertEqual(row.entityId, userId)
    XCTAssertFalse(row.hasServerVersion)
  }

  func testRowIdsAreUniqueAcrossKinds() {
    let job = SyncConflictRow.make(job: makeJob())
    let shift = SyncConflictRow.make(shift: makeShift(), jobName: nil)
    XCTAssertNotEqual(job.id, shift.id)
  }

  func testStoreReturnsOnlyConflictedRowsWithJobName() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    context.insert(makeJob())
    context.insert(makeShift(serverSnapshot: snapshot))
    let clean = makeShift()
    clean.id = "shift-clean"
    clean.syncStatusRaw = SyncStatus.clean.rawValue
    context.insert(clean)
    try context.save()

    let store = LocalStoreActor(modelContainer: container)
    let rows = try await store.conflictRows(userId: userId)

    XCTAssertEqual(rows.map(\.id), ["job-job-1", "shift-shift-1"])
    XCTAssertEqual(rows.last?.detail, "09:00 - 17:00 · Cafe")
    XCTAssertEqual(rows.map(\.hasServerVersion), [false, true])
  }
}
