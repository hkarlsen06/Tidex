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
