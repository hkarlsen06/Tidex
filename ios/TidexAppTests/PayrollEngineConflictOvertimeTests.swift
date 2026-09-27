import XCTest

@testable import Tidex

/// Conflict-excluded shifts are not paid, so they must not push other shifts into overtime.
final class PayrollEngineConflictOvertimeTests: XCTestCase {
  func testExcludedDuplicateHoursDoNotCountTowardWeeklyOvertime() throws {
    // 30 h Mon-Wed, then a 5 h Thursday shift entered twice. Only one Thursday counts: 35 h.
    let result = compute([
      shift("mon", "2026-02-02", "08:00", "18:00"),
      shift("tue", "2026-02-03", "08:00", "18:00"),
      shift("wed", "2026-02-04", "08:00", "18:00"),
      shift("thu-a", "2026-02-05", "08:00", "13:00"),
      shift("thu-b", "2026-02-05", "08:00", "13:00"),
      shift("fri", "2026-02-06", "08:00", "12:00"),
    ])

    let friday = try XCTUnwrap(result.first { $0.id == "fri" })
    XCTAssertEqual(friday.computed.overtimeMinutes, 0, accuracy: 0.001)
    XCTAssertEqual(ConflictExclusion.partition(shifts: result).includedShifts.count, 5)
  }

  func testOvertimeOnKeptShiftDoesNotFlipWhichDuplicateIsExcluded() throws {
    let result = compute([
      shift("mon", "2026-02-02", "08:00", "18:00"),
      shift("tue", "2026-02-03", "08:00", "18:00"),
      shift("wed", "2026-02-04", "08:00", "18:00"),
      shift("thu", "2026-02-05", "08:00", "18:00"),
      shift("fri-a", "2026-02-06", "08:00", "10:00"),
      shift("fri-b", "2026-02-06", "08:00", "10:00"),
    ])

    let kept = try XCTUnwrap(result.first { $0.id == "fri-a" })
    let duplicate = try XCTUnwrap(result.first { $0.id == "fri-b" })
    XCTAssertEqual(kept.computed.overtimeMinutes, 120, accuracy: 0.001)
    XCTAssertEqual(duplicate.computed.overtimeMinutes, 0, accuracy: 0.001)

    let partition = ConflictExclusion.partition(shifts: result)
    XCTAssertEqual(partition.analysis.excludedIds, ["fri-b"])
    XCTAssertTrue(partition.includedShifts.contains { $0.id == "fri-a" })
  }

  private func compute(_ shifts: [ShiftRow]) -> [ShiftWithComputations] {
    PayrollEngine.computeShiftsForMonth(
      PayrollEngine.MonthComputationRequest(
        year: 2_026,
        month: 2,
        shifts: shifts,
        recurring: [],
        snapshots: [
          TestFixtures.wageSnapshot(
            hourlyWage: 200, breakEnabled: false, jobId: "job-a",
            overtime: OvertimeConfig.seededDefaults)
        ],
        settings: UserSettings.defaults(for: "user-1"),
        jobs: [TestFixtures.job(id: "job-a", isDefault: true)]
      ))
  }

  private func shift(_ id: String, _ date: String, _ start: String, _ end: String) -> ShiftRow {
    TestFixtures.shift(id: id, shiftDate: date, startTime: start, endTime: end)
  }
}
