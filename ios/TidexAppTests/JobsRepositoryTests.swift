import Foundation
import SwiftData
import XCTest

@testable import Tidex

final class JobsRepositoryTests: XCTestCase {
  // MARK: - upsertJob as a SwiftData unique-attribute upsert

  private func makeJobStoreActor() throws -> LocalStoreActor {
    let schema = Schema([LocalJob.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return LocalStoreActor(modelContainer: container)
  }

  private func makeUpsertTestJob(
    id: String,
    name: String,
    sortOrder: Int,
    updatedAt: Date
  ) -> LocalJob {
    LocalJob(
      id: id,
      userId: "user-1",
      name: name,
      isDefault: false,
      sortOrder: sortOrder,
      serverUpdatedAt: updatedAt,
      serverRevision: 1,
      lastSyncedSnapshot: Data(),
      localUpdatedAt: updatedAt
    )
  }

  func testUpsertJobTwiceBeforeSaveKeepsOneRowWithLatestValues() async throws {
    let store = try makeJobStoreActor()
    let first = makeUpsertTestJob(
      id: "job-1", name: "First", sortOrder: 0, updatedAt: Date(timeIntervalSince1970: 1))
    let second = makeUpsertTestJob(
      id: "job-1", name: "Second", sortOrder: 1, updatedAt: Date(timeIntervalSince1970: 2))

    try await store.upsertJob(first)
    try await store.upsertJob(second)
    try await store.save()

    let jobs = try await store.getAllJobs(userId: "user-1")
    XCTAssertEqual(jobs.count, 1)
    XCTAssertEqual(jobs.first?.name, "Second")
    XCTAssertEqual(jobs.first?.sortOrder, 1)
  }

  func testUpsertJobAcrossSeparateSavesKeepsOneRowWithLatestValues() async throws {
    let store = try makeJobStoreActor()
    let first = makeUpsertTestJob(
      id: "job-2", name: "First", sortOrder: 0, updatedAt: Date(timeIntervalSince1970: 1))

    try await store.upsertJob(first)
    try await store.save()

    let second = makeUpsertTestJob(
      id: "job-2", name: "Second", sortOrder: 1, updatedAt: Date(timeIntervalSince1970: 2))
    try await store.upsertJob(second)
    try await store.save()

    let jobs = try await store.getAllJobs(userId: "user-1")
    XCTAssertEqual(jobs.count, 1)
    XCTAssertEqual(jobs.first?.name, "Second")
    XCTAssertEqual(jobs.first?.sortOrder, 1)
  }

  func testJobDeletionPolicyAllowsJobsWithoutDependencies() {
    let counts = JobDeletionDependencyCounts(
      userShifts: 0,
      recurringShifts: 0,
      payrollAdjustments: 0
    )

    XCTAssertFalse(JobDeletionPolicy.shouldBlockDeletion(dependencyCounts: counts))
  }

  func testJobDeletionPolicyBlocksJobsWithShiftHistory() {
    let counts = JobDeletionDependencyCounts(
      userShifts: 1,
      recurringShifts: 0,
      payrollAdjustments: 0
    )

    XCTAssertTrue(JobDeletionPolicy.shouldBlockDeletion(dependencyCounts: counts))
  }

  func testJobDeletionPolicyBlocksJobsWithRecurringShiftHistory() {
    let counts = JobDeletionDependencyCounts(
      userShifts: 0,
      recurringShifts: 1,
      payrollAdjustments: 0
    )

    XCTAssertTrue(JobDeletionPolicy.shouldBlockDeletion(dependencyCounts: counts))
  }

  func testJobDeletionPolicyBlocksJobsWithPayrollAdjustments() {
    let counts = JobDeletionDependencyCounts(
      userShifts: 0,
      recurringShifts: 0,
      payrollAdjustments: 1
    )

    XCTAssertTrue(JobDeletionPolicy.shouldBlockDeletion(dependencyCounts: counts))
  }

  func testJobDeletionPolicyCountsServerBackedPendingDeletesUntilSynced() {
    XCTAssertTrue(
      JobDeletionPolicy.shouldCountBlockingDependency(
        syncStatusRaw: SyncStatus.pendingDelete.rawValue,
        serverRevision: 3,
        serverDeletedAt: nil
      )
    )
  }

  func testJobDeletionPolicyIgnoresUnsyncedPendingDeletes() {
    XCTAssertFalse(
      JobDeletionPolicy.shouldCountBlockingDependency(
        syncStatusRaw: SyncStatus.pendingDelete.rawValue,
        serverRevision: 0,
        serverDeletedAt: nil
      )
    )
  }

  func testJobDeletionPolicyIgnoresServerDeletedDependencies() {
    XCTAssertFalse(
      JobDeletionPolicy.shouldCountBlockingDependency(
        syncStatusRaw: SyncStatus.clean.rawValue,
        serverRevision: 3,
        serverDeletedAt: Date()
      )
    )
  }
}
