import Foundation
import XCTest

@testable import Tidex

final class JobsRepositoryTests: XCTestCase {
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
