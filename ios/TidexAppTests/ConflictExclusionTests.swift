import XCTest

@testable import Tidex

final class ConflictExclusionTests: XCTestCase {
  func testAnalyzeExcludesHigherGrossShiftInOverlapCluster() {
    let keep = TestFixtures.computedShift(
      id: "keep",
      shiftDate: "2026-02-10",
      startTime: "09:00",
      endTime: "17:00",
      gross: 1_000
    )
    let exclude = TestFixtures.computedShift(
      id: "exclude",
      shiftDate: "2026-02-10",
      startTime: "12:00",
      endTime: "16:00",
      gross: 2_000
    )
    let separate = TestFixtures.computedShift(
      id: "separate",
      shiftDate: "2026-02-10",
      startTime: "18:00",
      endTime: "20:00",
      gross: 500
    )

    let analysis = ConflictExclusion.analyze(shifts: [keep, exclude, separate])

    XCTAssertEqual(analysis.excludedIds, Set(["exclude"]))
    XCTAssertEqual(analysis.conflictingIds, Set(["keep", "exclude"]))
    XCTAssertEqual(analysis.conflictDates, Set(["2026-02-10"]))
  }

  func testShiftsOverlapReturnsFalseWhenIntervalsOnlyTouchBoundary() {
    let first = TestFixtures.computedShift(
      id: "first",
      shiftDate: "2026-02-11",
      startTime: "09:00",
      endTime: "12:00",
      gross: 500
    )
    let second = TestFixtures.computedShift(
      id: "second",
      shiftDate: "2026-02-11",
      startTime: "12:00",
      endTime: "15:00",
      gross: 500
    )

    XCTAssertFalse(ConflictExclusion.shiftsOverlap(first, second))
  }
}
