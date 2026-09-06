import Foundation
import SwiftData
import XCTest

@testable import Tidex

@MainActor
final class LocalStoreShiftReadTests: XCTestCase {
  private let userId = "user-1"
  private let startDate = Date(timeIntervalSince1970: 1_700_000_000)
  private let endDate = Date(timeIntervalSince1970: 1_700_086_400)

  func testJobScopedReadPreservesAccountDeletionAndInclusiveDateFilters() async throws {
    let store = try makeStore(
      jobs: [makeJob(id: "default-job", isDefault: true)],
      shifts: [
        makeShift(id: "start", jobId: "selected-job", date: startDate, status: .dirty),
        makeShift(id: "end", jobId: "selected-job", date: endDate, status: .conflict),
        makeShift(id: "other-job", jobId: "default-job"),
        makeShift(id: "legacy", jobId: nil),
        makeShift(id: "other-user", jobId: "selected-job", ownerId: "user-2"),
        makeShift(id: "pending-delete", jobId: "selected-job", status: .pendingDelete),
        makeShift(id: "server-deleted", jobId: "selected-job", deletedAt: startDate),
        makeShift(id: "before", jobId: "selected-job", date: startDate.addingTimeInterval(-1)),
        makeShift(id: "after", jobId: "selected-job", date: endDate.addingTimeInterval(1)),
      ]
    )

    let shifts = await store.fetchShifts(
      userId: userId, startDate: startDate, endDate: endDate, jobId: "selected-job")

    XCTAssertEqual(shifts.map(\.id), ["end", "start"])
  }

  func testActiveDefaultJobIncludesLegacyShifts() async throws {
    let store = try makeStore(
      jobs: [makeJob(id: "default-job", isDefault: true)],
      shifts: [
        makeShift(id: "assigned", jobId: "default-job", date: endDate),
        makeShift(id: "legacy", jobId: nil),
        makeShift(id: "other-job", jobId: "other-job"),
      ]
    )

    let shifts = await store.fetchShifts(
      userId: userId, startDate: startDate, endDate: endDate, jobId: "default-job")

    XCTAssertEqual(shifts.map(\.id), ["assigned", "legacy"])
  }

  func testLegacyShiftsRequireAnActiveDefaultJobForTheSameAccount() async throws {
    let invalidDefaultJobs = [
      makeJob(id: "selected-job", isDefault: false),
      makeJob(id: "selected-job", isDefault: true, archivedAt: startDate),
      makeJob(id: "selected-job", isDefault: true, deletedAt: startDate),
      makeJob(id: "selected-job", isDefault: true, ownerId: "user-2"),
    ]

    for job in invalidDefaultJobs {
      let store = try makeStore(
        jobs: [job],
        shifts: [
          makeShift(id: "assigned", jobId: "selected-job"),
          makeShift(id: "legacy", jobId: nil),
        ]
      )

      let shifts = await store.fetchShifts(
        userId: userId, startDate: startDate, endDate: endDate, jobId: "selected-job")

      XCTAssertEqual(shifts.map(\.id), ["assigned"])
    }
  }

  func testUnscopedReadIncludesAllJobsAndLegacyRowsWithoutADefaultJob() async throws {
    let store = try makeStore(
      shifts: [
        makeShift(id: "first-job", jobId: "job-1", date: endDate),
        makeShift(id: "second-job", jobId: "job-2", date: startDate.addingTimeInterval(1)),
        makeShift(id: "legacy", jobId: nil),
        makeShift(id: "other-user", jobId: nil, ownerId: "user-2"),
        makeShift(id: "pending-delete", jobId: nil, status: .pendingDelete),
      ]
    )

    let shifts = await store.fetchShifts(
      userId: userId, startDate: startDate, endDate: endDate)

    XCTAssertEqual(shifts.map(\.id), ["first-job", "second-job", "legacy"])
  }

  func testScopedReadWithoutAMatchingJobReturnsNoRows() async throws {
    let store = try makeStore(shifts: [makeShift(id: "legacy", jobId: nil)])

    let shifts = await store.fetchShifts(
      userId: userId, startDate: startDate, endDate: endDate, jobId: "missing-job")

    XCTAssertTrue(shifts.isEmpty)
  }

  private func makeStore(jobs: [LocalJob] = [], shifts: [LocalUserShift]) throws -> LocalStoreActor
  {
    let schema = Schema([LocalJob.self, LocalUserShift.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    for job in jobs {
      context.insert(job)
    }
    for shift in shifts {
      context.insert(shift)
    }
    try context.save()
    return LocalStoreActor(modelContainer: container)
  }

  private func makeJob(
    id: String,
    isDefault: Bool,
    archivedAt: Date? = nil,
    deletedAt: Date? = nil,
    ownerId: String? = nil
  ) -> LocalJob {
    LocalJob(
      id: id,
      userId: ownerId ?? userId,
      name: id,
      isDefault: isDefault,
      sortOrder: 0,
      archivedAt: archivedAt,
      deletedAt: deletedAt,
      serverUpdatedAt: startDate,
      serverRevision: 1,
      lastSyncedSnapshot: Data(),
      localUpdatedAt: startDate
    )
  }

  private func makeShift(
    id: String,
    jobId: String?,
    date: Date? = nil,
    ownerId: String? = nil,
    status: SyncStatus = .clean,
    deletedAt: Date? = nil
  ) -> LocalUserShift {
    LocalUserShift(
      id: id,
      userId: ownerId ?? userId,
      jobId: jobId,
      shiftDate: date ?? startDate,
      startTime: "09:00",
      endTime: "17:00",
      serverUpdatedAt: startDate,
      serverRevision: 1,
      serverDeletedAt: deletedAt,
      syncStatus: status,
      lastSyncedSnapshot: Data(),
      localUpdatedAt: startDate
    )
  }
}
