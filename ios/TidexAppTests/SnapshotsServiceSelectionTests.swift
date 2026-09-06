import XCTest

@testable import Tidex

final class SnapshotsServiceSelectionTests: XCTestCase {
  func testSnapshotForDateReturnsLatestDatedSnapshotWhenAvailable() {
    let baseline = TestFixtures.wageSnapshot(id: "baseline", fromDate: nil, hourlyWage: 100)
    let jan = TestFixtures.wageSnapshot(id: "jan", fromDate: "2026-01-01", hourlyWage: 110)
    let feb = TestFixtures.wageSnapshot(id: "feb", fromDate: "2026-02-01", hourlyWage: 120)

    let snapshots = [feb, baseline, jan]

    let selected = SnapshotsService.snapshotForDate("2026-01-15", from: snapshots)

    XCTAssertEqual(selected?.id, "jan")
    XCTAssertEqual(selected?.hourly_wage, 110)
  }

  func testSnapshotForDateFallsBackToBaselineBeforeFirstDatedSnapshot() {
    let baseline = TestFixtures.wageSnapshot(id: "baseline", fromDate: nil, hourlyWage: 100)
    let jan = TestFixtures.wageSnapshot(id: "jan", fromDate: "2026-01-01", hourlyWage: 110)

    let selected = SnapshotsService.snapshotForDate("2025-12-31", from: [jan, baseline])

    XCTAssertEqual(selected?.id, "baseline")
    XCTAssertEqual(selected?.hourly_wage, 100)
  }

  func testSnapshotForDateIncludesExactBoundaryAndIgnoresFutureSnapshots() {
    let current = TestFixtures.wageSnapshot(id: "current", fromDate: "2026-01-01")
    let future = TestFixtures.wageSnapshot(id: "future", fromDate: "2026-02-01")

    XCTAssertEqual(
      SnapshotsService.snapshotForDate("2026-01-01", from: [future, current])?.id,
      "current"
    )
  }

  func testSnapshotForDateKeepsLastDuplicateDateAndFirstBaseline() {
    let firstBaseline = TestFixtures.wageSnapshot(id: "first-baseline")
    let secondBaseline = TestFixtures.wageSnapshot(id: "second-baseline")
    let first = TestFixtures.wageSnapshot(id: "first", fromDate: "2026-01-01")
    let last = TestFixtures.wageSnapshot(id: "last", fromDate: "2026-01-01")
    let older = TestFixtures.wageSnapshot(id: "older", fromDate: "2025-12-01")
    let snapshots = [first, firstBaseline, last, older, secondBaseline]

    XCTAssertEqual(
      SnapshotsService.snapshotForDate("2026-01-01", from: snapshots)?.id,
      "last"
    )
    XCTAssertEqual(
      SnapshotsService.snapshotForDate("2025-11-30", from: snapshots)?.id,
      "first-baseline"
    )
  }

  func testSnapshotForDateReturnsNilWithoutApplicableSnapshot() {
    let future = TestFixtures.wageSnapshot(id: "future", fromDate: "2026-02-01")

    XCTAssertNil(SnapshotsService.snapshotForDate("2026-01-01", from: [future]))
    XCTAssertNil(SnapshotsService.snapshotForDate("2026-01-01", from: []))
  }
}
