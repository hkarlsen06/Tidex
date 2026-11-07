import SwiftData
import XCTest

@testable import Tidex

/// Conflict-excluded shifts are not paid, so they must not push other shifts into overtime.
final class PayrollEngineConflictOvertimeTests: XCTestCase {
  func testExcludedDuplicateHoursDoNotCountTowardWeeklyOvertime() throws {
    // 30 h Mon-Wed, then a 5 h Thursday shift entered twice. Only one Thursday counts: 35 h.
    let result = try compute([
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
    let result = try compute([
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

  private func compute(_ shifts: [ShiftRow]) throws -> [ShiftWithComputations] {
    let owner = PayrollEngine.computeShiftsForMonth(
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
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let payload = SharingRPCPayloadInput(
      ownerId: "user-1", showEarnings: true,
      settings: try decoder.decode(SharingRPCUserSettings.self, from: Data("{}".utf8)),
      shifts: try shifts.map { try decoder.decode(SharingRPCShiftRow.self, from: encoder.encode($0)) },
      recurringShifts: [],
      snapshots: [try decoder.decode(
        SharingRPCWageSnapshot.self, from: encoder.encode(TestFixtures.wageSnapshot(
          hourlyWage: 200, breakEnabled: false, jobId: "job-a",
          overtime: .seededDefaults)))],
      jobs: [try decoder.decode(
        SharingRPCJobRow.self, from: encoder.encode(TestFixtures.job(id: "job-a", isDefault: true)))])
    let shared = SharingComputeCore.computeMonthShifts(
      payload: payload, year: 2_026, month: 2, mode: .visible)
    XCTAssertEqual(shared.map(\.id), owner.map(\.id))
    XCTAssertEqual(shared.map { $0.computed.gross }, owner.map { $0.computed.gross })
    XCTAssertEqual(shared.map { $0.computed.overtimeMinutes }, owner.map { $0.computed.overtimeMinutes })
    XCTAssertEqual(
      SharingComputeCore.excludedShiftIds(in: shared), ConflictExclusion.analyze(shifts: owner).excludedIds)
    return owner
  }

  private func shift(_ id: String, _ date: String, _ start: String, _ end: String) -> ShiftRow {
    TestFixtures.shift(id: id, shiftDate: date, startTime: start, endTime: end)
  }
}

extension PayrollEngineConflictOvertimeTests {
  @MainActor
  func testSharedResponseAndPersistedCacheKeepTheOvertimeWinnerAndNetTotals() async throws {
    let rows = [
      shift("mon", "2026-02-02", "08:00", "18:00"),
      shift("tue", "2026-02-03", "08:00", "18:00"),
      shift("wed", "2026-02-04", "08:00", "18:00"),
      shift("thu", "2026-02-05", "08:00", "18:00"),
      shift("fri-a", "2026-02-06", "08:00", "10:00"),
      shift("fri-b", "2026-02-06", "08:00", "10:00"),
    ]
    let payload = try sharedPayload(for: rows)
    let response = await SharingService.computeSharedShiftsResponseOffMain(
      payloadRow: payload, year: 2_026, month: 2)
    let restored = try JSONDecoder().decode(SharedShiftsResponse.self, from: JSONEncoder().encode(response))
    let container = try ModelContainer(
      for: LocalSharedShift.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    for value in restored.shifts {
      context.insert(LocalSharedShift.from(
        apiShift: value, ownerId: "user-1", viewerId: "viewer", showEarnings: true))
    }
    try context.save()
    let cached = try ModelContext(container).fetch(FetchDescriptor<LocalSharedShift>())
      .map { $0.toShiftWithComputations() }
    for shifts in [restored.shifts.map { $0.toShiftWithComputations() }, cached, Array(cached.reversed())] {
      let partition = ConflictExclusion.partition(shifts: shifts)
      XCTAssertEqual(partition.analysis.excludedIds, ["fri-b"])
      let totals = PayrollEngine.summarizeShiftTotals(shifts: shifts, halfTaxMonth: nil, earningsMonth: 2)
      XCTAssertEqual(totals.gross, 8_600)
      XCTAssertEqual(totals.net, 6_880)
    }
  }

  private func sharedPayload(for rows: [ShiftRow]) throws -> SharingRPCMonthPayloadRow {
    let encoder = JSONEncoder()
    return try JSONDecoder().decode(SharingRPCMonthPayloadRow.self, from: JSONSerialization.data(
      withJSONObject: [
        "owner_id": "user-1", "show_earnings": true, "settings": [:],
        "shifts": try JSONSerialization.jsonObject(with: encoder.encode(rows)),
        "snapshots": try JSONSerialization.jsonObject(with: encoder.encode([
          TestFixtures.wageSnapshot(
            hourlyWage: 200, taxEnabled: true, taxPercentage: 20, breakEnabled: false,
            jobId: "job-a", overtime: .seededDefaults)
        ])),
        "jobs": try JSONSerialization.jsonObject(with: encoder.encode([
          TestFixtures.job(id: "job-a", isDefault: true)
        ])),
      ]))
  }
}
