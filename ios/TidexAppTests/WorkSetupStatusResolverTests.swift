import XCTest

@testable import Tidex

final class WorkSetupStatusResolverTests: XCTestCase {
  func testResolveReturnsIncompleteStatusWhenNoActiveJobsExist() {
    let status = WorkSetupStatusResolver.resolve(activeJobs: []) { _ in
      XCTFail("Baseline lookup should not run without an active job")
      return false
    }

    XCTAssertFalse(status.isWorkSetupComplete)
    XCTAssertFalse(status.hasActiveJob)
    XCTAssertFalse(status.hasBaselineSnapshotForActiveSetupJob)
    XCTAssertNil(status.activeSetupJobId)
  }

  func testResolvePrefersDefaultActiveJob() {
    let defaultJob = TestFixtures.job(id: "job-default", isDefault: true)
    let secondaryJob = TestFixtures.job(id: "job-secondary", isDefault: false)

    let status = WorkSetupStatusResolver.resolve(activeJobs: [secondaryJob, defaultJob]) { jobId in
      jobId == "job-default"
    }

    XCTAssertTrue(status.isWorkSetupComplete)
    XCTAssertTrue(status.hasActiveJob)
    XCTAssertTrue(status.hasBaselineSnapshotForActiveSetupJob)
    XCTAssertEqual(status.activeSetupJobId, "job-default")
  }

  func testResolveFallsBackToFirstActiveJobWhenNoDefaultExists() {
    let firstJob = TestFixtures.job(id: "job-first", isDefault: false)
    let secondJob = TestFixtures.job(id: "job-second", isDefault: false)

    let status = WorkSetupStatusResolver.resolve(activeJobs: [firstJob, secondJob]) { jobId in
      jobId == "job-first"
    }

    XCTAssertTrue(status.isWorkSetupComplete)
    XCTAssertEqual(status.activeSetupJobId, "job-first")
  }

  func testResolveRequiresBaselineSnapshotForChosenSetupJob() {
    let defaultJob = TestFixtures.job(id: "job-default", isDefault: true)
    let secondaryJob = TestFixtures.job(id: "job-secondary", isDefault: false)

    let status = WorkSetupStatusResolver.resolve(activeJobs: [defaultJob, secondaryJob]) { jobId in
      jobId == "job-secondary"
    }

    XCTAssertFalse(status.isWorkSetupComplete)
    XCTAssertTrue(status.hasActiveJob)
    XCTAssertFalse(status.hasBaselineSnapshotForActiveSetupJob)
    XCTAssertEqual(status.activeSetupJobId, "job-default")
  }

  func testPresentationStateStaysLoadingWhileInitialSyncIsIncomplete() {
    let status = WorkSetupStatus(
      isWorkSetupComplete: false,
      hasActiveJob: false,
      hasBaselineSnapshotForActiveSetupJob: false,
      activeSetupJobId: nil
    )

    XCTAssertEqual(
      WorkSetupPresentationStateResolver.resolve(status: status, initialSyncComplete: false),
      .loading
    )
  }

  func testPresentationStateShowsIncompleteAfterInitialSyncCompletes() {
    let status = WorkSetupStatus(
      isWorkSetupComplete: false,
      hasActiveJob: false,
      hasBaselineSnapshotForActiveSetupJob: false,
      activeSetupJobId: nil
    )

    XCTAssertEqual(
      WorkSetupPresentationStateResolver.resolve(status: status, initialSyncComplete: true),
      .incomplete(status)
    )
  }

  func testPresentationStatePrefersReadyEvenBeforeInitialSyncCompletes() {
    let status = WorkSetupStatus(
      isWorkSetupComplete: true,
      hasActiveJob: true,
      hasBaselineSnapshotForActiveSetupJob: true,
      activeSetupJobId: "job-default"
    )

    XCTAssertEqual(
      WorkSetupPresentationStateResolver.resolve(status: status, initialSyncComplete: false),
      .ready(status)
    )
  }
}
