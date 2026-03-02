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
}
