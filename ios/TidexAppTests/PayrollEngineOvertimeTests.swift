import XCTest

@testable import Tidex

final class PayrollEngineOvertimeTests: XCTestCase {
  func testOvertimeSplitsMidShiftAndUsesTimeSpecificPercent() {
    let result = compute([
      shift(id: "mon", date: "2026-02-02", start: "08:00", end: "17:30"),
      shift(id: "tue", date: "2026-02-03", start: "08:00", end: "17:30"),
      shift(id: "wed", date: "2026-02-04", start: "08:00", end: "17:30"),
      shift(id: "thu", date: "2026-02-05", start: "08:00", end: "17:30"),
      shift(id: "fri", date: "2026-02-06", start: "16:00", end: "22:00"),
    ])

    let friday = result.first { $0.id == "fri" }

    XCTAssertEqual(friday?.computed.overtimeMinutes, 240, accuracy: 0.01)
    XCTAssertEqual(friday?.computed.basePay, 1_200, accuracy: 0.01)
    XCTAssertEqual(friday?.computed.supplementPay, 500, accuracy: 0.01)
    XCTAssertEqual(friday?.computed.gross, 1_700, accuracy: 0.01)
  }

  func testOvertimeReplacesCustomSupplementsAfterThreshold() {
    let customSupplements = CustomSupplementsData(rules: [
      SupplementRule(days: [5], from: "16:00", to: "22:00", rate: 1_000, percent: nil)
    ])
    let result = compute([
      shift(id: "mon", date: "2026-02-02", start: "08:00", end: "17:30"),
      shift(id: "tue", date: "2026-02-03", start: "08:00", end: "17:30"),
      shift(id: "wed", date: "2026-02-04", start: "08:00", end: "17:30"),
      shift(id: "thu", date: "2026-02-05", start: "08:00", end: "17:30"),
      shift(
        id: "fri",
        date: "2026-02-06",
        start: "16:00",
        end: "22:00",
        customSupplements: customSupplements
      ),
    ])

    let friday = result.first { $0.id == "fri" }

    XCTAssertEqual(friday?.computed.overtimeMinutes, 240, accuracy: 0.01)
    XCTAssertEqual(friday?.computed.supplementPay, 2_500, accuracy: 0.01)
    XCTAssertEqual(friday?.computed.gross, 3_700, accuracy: 0.01)
  }

  func testOvertimeIsIndependentPerEffectiveJob() {
    let jobA = TestFixtures.job(id: "job-a", isDefault: true)
    let jobB = TestFixtures.job(id: "job-b", isDefault: false)
    let snapshots = [
      snapshot(jobId: jobA.id),
      snapshot(jobId: jobB.id),
    ]
    let result = compute(
      [
        shift(id: "a-mon", date: "2026-02-02", start: "08:00", end: "18:00", jobId: jobA.id),
        shift(id: "a-tue", date: "2026-02-03", start: "08:00", end: "18:00", jobId: jobA.id),
        shift(id: "a-wed", date: "2026-02-04", start: "08:00", end: "18:00", jobId: jobA.id),
        shift(id: "a-thu", date: "2026-02-05", start: "08:00", end: "18:00", jobId: jobA.id),
        shift(id: "b-fri", date: "2026-02-06", start: "18:00", end: "20:00", jobId: jobB.id),
      ],
      snapshots: snapshots,
      jobs: [jobA, jobB]
    )

    let jobBFriday = result.first { $0.id == "b-fri" }

    XCTAssertEqual(jobBFriday?.computed.overtimeMinutes, 0, accuracy: 0.01)
    XCTAssertEqual(jobBFriday?.computed.supplementPay, 0, accuracy: 0.01)
    XCTAssertEqual(jobBFriday?.computed.gross, 400, accuracy: 0.01)
  }

  func testOvertimeResetsAtIsoWeekBoundary() {
    let result = compute([
      shift(id: "mon", date: "2026-02-02", start: "08:00", end: "16:00"),
      shift(id: "tue", date: "2026-02-03", start: "08:00", end: "16:00"),
      shift(id: "wed", date: "2026-02-04", start: "08:00", end: "16:00"),
      shift(id: "thu", date: "2026-02-05", start: "08:00", end: "16:00"),
      shift(id: "fri", date: "2026-02-06", start: "08:00", end: "16:00"),
      shift(id: "next-mon", date: "2026-02-09", start: "08:00", end: "09:00"),
    ])

    let nextMonday = result.first { $0.id == "next-mon" }

    XCTAssertEqual(nextMonday?.computed.overtimeMinutes, 0, accuracy: 0.01)
    XCTAssertEqual(nextMonday?.computed.supplementPay, 0, accuracy: 0.01)
    XCTAssertEqual(nextMonday?.computed.gross, 200, accuracy: 0.01)
  }

  func testHolidayRuleUsesHolidayPercentAfterThreshold() {
    let config = OvertimeConfig(
      enabled: true,
      weeklyThresholdHours: 0.5,
      rules: OvertimeConfig.seededDefaults.rules
    )
    let result = compute(
      [shift(id: "may-day", date: "2026-05-01", start: "00:00", end: "02:00")],
      snapshots: [snapshot(overtime: config)],
      month: 5
    )

    let shift = result.first { $0.id == "may-day" }

    XCTAssertEqual(shift?.computed.overtimeMinutes, 90, accuracy: 0.01)
    XCTAssertEqual(shift?.computed.supplementPay, 300, accuracy: 0.01)
    XCTAssertEqual(shift?.computed.gross, 700, accuracy: 0.01)
  }

  private func compute(
    _ shifts: [ShiftRow],
    snapshots: [WageSnapshot]? = nil,
    jobs: [Job]? = nil,
    month: Int = 2
  ) -> [ShiftWithComputations] {
    let effectiveJobs = jobs ?? [TestFixtures.job(id: "job-a", isDefault: true)]
    let effectiveSnapshots = snapshots ?? [snapshot(jobId: effectiveJobs[0].id)]
    return PayrollEngine.computeShiftsForMonth(
      PayrollEngine.MonthComputationRequest(
        year: 2_026,
        month: month,
        shifts: shifts,
        recurring: [],
        snapshots: effectiveSnapshots,
        settings: UserSettings.defaults(for: "user-1"),
        jobs: effectiveJobs
      ))
  }

  private func snapshot(
    jobId: String? = nil,
    overtime: OvertimeConfig = OvertimeConfig.seededDefaults
  ) -> WageSnapshot {
    TestFixtures.wageSnapshot(
      hourlyWage: 200,
      breakEnabled: false,
      jobId: jobId,
      overtime: overtime
    )
  }

  private func shift(
    id: String,
    date: String,
    start: String,
    end: String,
    jobId: String? = nil,
    customSupplements: CustomSupplementsData? = nil
  ) -> ShiftRow {
    TestFixtures.shift(
      id: id,
      shiftDate: date,
      startTime: start,
      endTime: end,
      jobId: jobId,
      customSupplements: customSupplements
    )
  }
}
