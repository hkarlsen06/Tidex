import XCTest

@testable import Tidex

final class PayrollEngineOvertimeTests: XCTestCase {
  func testOvertimeSplitsMidShiftAndUsesTimeSpecificPercent() throws {
    let result = compute([
      shift(id: "mon", date: "2026-02-02", start: "08:00", end: "17:30"),
      shift(id: "tue", date: "2026-02-03", start: "08:00", end: "17:30"),
      shift(id: "wed", date: "2026-02-04", start: "08:00", end: "17:30"),
      shift(id: "thu", date: "2026-02-05", start: "08:00", end: "17:30"),
      shift(id: "fri", date: "2026-02-06", start: "16:00", end: "22:00"),
    ])

    let friday = try XCTUnwrap(result.first { $0.id == "fri" })

    XCTAssertEqual(friday.computed.overtimeMinutes, 240, accuracy: 0.01)
    XCTAssertEqual(friday.computed.basePay, 1_200, accuracy: 0.01)
    XCTAssertEqual(friday.computed.supplementPay, 500, accuracy: 0.01)
    XCTAssertEqual(friday.computed.gross, 1_700, accuracy: 0.01)
  }

  func testOvertimeReplacesCustomSupplementsAfterThreshold() throws {
    let customSupplements = CustomSupplementsData(rules: [
      CustomSupplementRule(from: "16:00", to: "22:00", rate: 1_000, percent: nil, isCustom: true)
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

    let friday = try XCTUnwrap(result.first { $0.id == "fri" })

    XCTAssertEqual(friday.computed.overtimeMinutes, 240, accuracy: 0.01)
    XCTAssertEqual(friday.computed.supplementPay, 2_500, accuracy: 0.01)
    XCTAssertEqual(friday.computed.gross, 3_700, accuracy: 0.01)
  }

  func testOvertimeIsIndependentPerEffectiveJob() throws {
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

    let jobBFriday = try XCTUnwrap(result.first { $0.id == "b-fri" })

    XCTAssertEqual(jobBFriday.computed.overtimeMinutes, 0, accuracy: 0.01)
    XCTAssertEqual(jobBFriday.computed.supplementPay, 0, accuracy: 0.01)
    XCTAssertEqual(jobBFriday.computed.gross, 400, accuracy: 0.01)
  }

  func testOvertimeResetsAtIsoWeekBoundary() throws {
    let result = compute([
      shift(id: "mon", date: "2026-02-02", start: "08:00", end: "16:00"),
      shift(id: "tue", date: "2026-02-03", start: "08:00", end: "16:00"),
      shift(id: "wed", date: "2026-02-04", start: "08:00", end: "16:00"),
      shift(id: "thu", date: "2026-02-05", start: "08:00", end: "16:00"),
      shift(id: "fri", date: "2026-02-06", start: "08:00", end: "16:00"),
      shift(id: "next-mon", date: "2026-02-09", start: "08:00", end: "09:00"),
    ])

    let nextMonday = try XCTUnwrap(result.first { $0.id == "next-mon" })

    XCTAssertEqual(nextMonday.computed.overtimeMinutes, 0, accuracy: 0.01)
    XCTAssertEqual(nextMonday.computed.supplementPay, 0, accuracy: 0.01)
    XCTAssertEqual(nextMonday.computed.gross, 200, accuracy: 0.01)
  }

  func testHolidayRuleUsesHolidayPercentAfterThreshold() throws {
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

    let shift = try XCTUnwrap(result.first { $0.id == "may-day" })

    XCTAssertEqual(shift.computed.overtimeMinutes, 90, accuracy: 0.01)
    XCTAssertEqual(shift.computed.supplementPay, 300, accuracy: 0.01)
    XCTAssertEqual(shift.computed.gross, 700, accuracy: 0.01)
  }

  func testPriorMonthRecurringHoursCountTowardWeeklyOvertime() throws {
    let recurring = recurringShift(selectedDays: [
      "1": "2026-04-27", "2": "2026-04-28",
      "3": "2026-04-29", "4": "2026-04-30",
    ])
    let result = compute(
      [shift(id: "friday", date: "2026-05-01", start: "08:00", end: "18:00")],
      recurring: [recurring], month: 5
    )

    let friday = try XCTUnwrap(result.first { $0.id == "friday" })
    XCTAssertEqual(friday.computed.overtimeMinutes, 600, accuracy: 0.01)
    XCTAssertTrue(result.allSatisfy { $0.shiftDate.hasPrefix("2026-05-") })
  }

  func testPriorYearRecurringHoursRespectExclusionsBeforeOvertime() throws {
    let selectedDays = ["1": "2025-12-29", "2": "2025-12-30", "3": "2025-12-31"]
    let rows = [
      shift(id: "thursday", date: "2026-01-01", start: "08:00", end: "18:00"),
      shift(id: "friday", date: "2026-01-02", start: "08:00", end: "18:00"),
    ]
    let result = compute(rows, recurring: [recurringShift(selectedDays: selectedDays)], month: 1)
    let excludingMonday = compute(
      rows,
      recurring: [recurringShift(selectedDays: selectedDays, exclusions: ["2025-12-29"])],
      month: 1
    )

    let friday = try XCTUnwrap(result.first { $0.id == "friday" })
    let fridayWithExclusion = try XCTUnwrap(excludingMonday.first { $0.id == "friday" })
    XCTAssertEqual(friday.computed.overtimeMinutes, 600, accuracy: 0.01)
    XCTAssertEqual(fridayWithExclusion.computed.overtimeMinutes, 0, accuracy: 0.01)
    XCTAssertTrue(result.allSatisfy { $0.shiftDate.hasPrefix("2026-01-") })
  }

  func testPriorSundayRecurringOvernightHoursCountInMondayWeek() throws {
    let recurring = recurringShift(
      selectedDays: ["0": "2026-05-31"], start: "22:00", end: "06:00")
    let rows = (1...4).map { day in
      shift(id: "june-\(day)", date: "2026-06-0\(day)", start: "08:00", end: "18:00")
    }
    let result = compute(rows, recurring: [recurring], month: 6)

    let thursday = try XCTUnwrap(result.first { $0.id == "june-4" })
    let monday = try XCTUnwrap(result.first { $0.id == "june-1" })
    XCTAssertEqual(thursday.computed.overtimeMinutes, 360, accuracy: 0.01)
    XCTAssertEqual(monday.computed.overtimeMinutes, 0, accuracy: 0.01)
    XCTAssertTrue(result.allSatisfy { $0.shiftDate.hasPrefix("2026-06-") })
  }

  func testRecurringOvertimeContextPreservesRequestedVisibleRange() throws {
    let recurring = recurringShift(selectedDays: [
      "1": "2026-04-27", "2": "2026-04-28",
      "3": "2026-04-29", "4": "2026-04-30", "5": "2026-05-01",
    ])
    let visibleDate = try XCTUnwrap(Date.fromISODateString("2026-05-01"))
    let result = PayrollEngine.computeShiftsForMonth(
      .init(
        year: 2_026, month: 5, shifts: [], recurring: [recurring],
        snapshots: [snapshot(jobId: "job-a")], settings: UserSettings.defaults(for: "user-1"),
        visibleRange: (start: visibleDate, end: visibleDate),
        jobs: [TestFixtures.job(id: "job-a", isDefault: true)]
      )
    )

    XCTAssertEqual(result.map(\.shiftDate), ["2026-05-01"])
    XCTAssertEqual(try XCTUnwrap(result.first).computed.overtimeMinutes, 600, accuracy: 0.01)
  }

  private func compute(
    _ shifts: [ShiftRow],
    snapshots: [WageSnapshot]? = nil,
    jobs: [Job]? = nil,
    recurring: [RecurringShiftRow] = [],
    month: Int = 2
  ) -> [ShiftWithComputations] {
    let effectiveJobs = jobs ?? [TestFixtures.job(id: "job-a", isDefault: true)]
    let effectiveSnapshots = snapshots ?? [snapshot(jobId: effectiveJobs[0].id)]
    return PayrollEngine.computeShiftsForMonth(
      PayrollEngine.MonthComputationRequest(
        year: 2_026,
        month: month,
        shifts: shifts,
        recurring: recurring,
        snapshots: effectiveSnapshots,
        settings: UserSettings.defaults(for: "user-1"),
        jobs: effectiveJobs
      ))
  }

  private func recurringShift(
    selectedDays: [String: String],
    start: String = "08:00",
    end: String = "18:00",
    exclusions: [String]? = nil
  ) -> RecurringShiftRow {
    RecurringShiftRow(
      id: "weekly", user_id: "user-1", job_id: "job-a",
      start_time: start, end_time: end, repeat_interval_weeks: 0,
      selected_days: selectedDays, end_condition: nil, exclusions: exclusions,
      date_specific_pause_windows: nil, date_specific_supplements: nil
    )
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
