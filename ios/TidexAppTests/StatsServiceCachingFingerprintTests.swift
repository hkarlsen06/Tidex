import XCTest

@testable import Tidex

final class StatsServiceCachingFingerprintTests: XCTestCase {
  // swiftlint:disable:next function_body_length
  func testAnnualPayrollCacheMatchesIndependentMonthCalculations() throws {
    let settings = UserSettings.defaults(for: "user-1")
    let jobs = [TestFixtures.job(id: "job-1", isDefault: true)]
    let snapshots = [
      TestFixtures.wageSnapshot(
        id: "snapshot", hourlyWage: 200, taxEnabled: true, taxPercentage: 25,
        breakEnabled: false, jobId: "job-1", overtime: .seededDefaults
      )
    ]
    let recurring = [
      RecurringShiftRow(
        id: "weekly", user_id: "user-1", job_id: "job-1",
        start_time: "08:00", end_time: "17:00", repeat_interval_weeks: 0,
        selected_days: ["1": "2024-01-01"], end_condition: nil,
        exclusions: ["2024-02-12"], date_specific_pause_windows: nil,
        date_specific_supplements: nil
      )
    ]
    let rows = (1...12).flatMap { month in
      (1...5).map { day in
        TestFixtures.shift(
          id: "\(month)-\(day)", shiftDate: String(format: "2024-%02d-%02d", month, day),
          startTime: "08:00", endTime: "17:00", jobId: "job-1"
        )
      } + [
        TestFixtures.shift(
          id: "overnight-\(month)",
          shiftDate: Date.lastDayOfMonth(year: 2_024, month: month),
          startTime: "22:00", endTime: "06:00", jobId: "job-1"
        )
      ]
    }
    let cached = try StatsService.computeFullYearPayrollData(
      year: 2_024, shifts: rows, recurring: recurring,
      snapshots: snapshots, settings: settings, jobs: jobs
    )
    var independentlyComputed: [ShiftWithComputations] = []

    for month in 1...12 {
      let window = PayrollReadWindow.month(year: 2_024, month: month).expandedForOvertime
      let startISO = window.startDate.toISODateString()
      let endISO = window.endDate.toISODateString()
      let request = PayrollEngine.MonthComputationRequest(
        year: 2_024, month: month,
        shifts: rows.filter { $0.shift_date >= startISO && $0.shift_date <= endISO },
        recurring: recurring, snapshots: snapshots, settings: settings, jobs: jobs
      )
      let expected = PayrollEngine.computeShiftsForMonth(request)
      let actual = cached.shifts(for: request)

      XCTAssertEqual(actual, expected, "Payroll changed for month \(month)")
      XCTAssertEqual(
        ConflictExclusion.partition(shifts: actual).includedShifts,
        ConflictExclusion.partition(shifts: expected).includedShifts
      )
      independentlyComputed.append(contentsOf: expected)
    }

    XCTAssertEqual(cached.shifts, independentlyComputed)
    XCTAssertEqual(
      cached.includedShifts,
      ConflictExclusion.partition(shifts: independentlyComputed).includedShifts
    )
    XCTAssertTrue(cached.shifts.contains { $0.shiftDate == "2024-02-29" })
    XCTAssertTrue(cached.shifts.contains { $0.computed.overtimeMinutes > 0 })
    XCTAssertLessThan(cached.includedShifts.count, cached.shifts.count)
  }

  func testAnnualPayrollPreservesOvertimeFromPreviousMonthAndYear() throws {
    let rows = ["2025-12-29", "2025-12-30", "2025-12-31", "2026-01-01", "2026-01-02"]
      .map { date in
        TestFixtures.shift(
          id: date, shiftDate: date, startTime: "08:00", endTime: "18:00", jobId: "job-1"
        )
      }
    let settings = UserSettings.defaults(for: "user-1")
    let jobs = [TestFixtures.job(id: "job-1", isDefault: true)]
    let snapshots = [
      TestFixtures.wageSnapshot(
        hourlyWage: 200, breakEnabled: false, jobId: "job-1", overtime: .seededDefaults
      )
    ]
    let cached = try StatsService.computeFullYearPayrollData(
      year: 2_026, shifts: rows, recurring: [], snapshots: snapshots, settings: settings, jobs: jobs
    )
    let expected = PayrollEngine.computeShiftsForMonth(
      .init(
        year: 2_026, month: 1, shifts: rows, recurring: [],
        snapshots: snapshots, settings: settings, jobs: jobs
      )
    )

    XCTAssertEqual(cached.shiftsByMonth[1], expected)
    XCTAssertEqual(
      cached.shiftsByMonth[1]?.first { $0.id == "2026-01-02" }?.computed.overtimeMinutes, 600)
    XCTAssertEqual(cached.shiftsByMonth[1]?.map(\.id), ["2026-01-01", "2026-01-02"])
    XCTAssertEqual(cached.shiftsByMonth[12], [])
  }

  func testJanuaryComparisonComputesPreviousDecemberOutsideAnnualCache() throws {
    let priorDecember = TestFixtures.shift(
      id: "prior-december", shiftDate: "2025-12-31", startTime: "22:00", endTime: "06:00"
    )
    let thisDecember = TestFixtures.shift(
      id: "this-december", shiftDate: "2026-12-31", startTime: "08:00", endTime: "16:00"
    )
    let settings = UserSettings.defaults(for: "user-1")
    let snapshots = [TestFixtures.wageSnapshot(hourlyWage: 250)]
    let cached = try StatsService.computeFullYearPayrollData(
      year: 2_026, shifts: [thisDecember], recurring: [],
      snapshots: snapshots, settings: settings, jobs: []
    )
    let request = PayrollEngine.MonthComputationRequest(
      year: 2_025, month: 12, shifts: [priorDecember], recurring: [],
      snapshots: snapshots, settings: settings, jobs: []
    )

    XCTAssertEqual(cached.shifts(for: request), PayrollEngine.computeShiftsForMonth(request))
    XCTAssertEqual(cached.shifts(for: request).map(\.id), [priorDecember.id])
    XCTAssertEqual(cached.shiftsByMonth[12]?.map(\.id), [thisDecember.id])
  }

  func testShiftFingerprintChangesWhenShiftDataChanges() {
    let original = TestFixtures.shift(
      id: "same-id",
      shiftDate: "2026-02-05",
      startTime: "08:00",
      endTime: "16:00"
    )
    let updated = TestFixtures.shift(
      id: "same-id",
      shiftDate: "2026-02-05",
      startTime: "10:00",
      endTime: "18:00"
    )

    let originalFingerprint = StatsService.fingerprintShiftsForCaching([original])
    let updatedFingerprint = StatsService.fingerprintShiftsForCaching([updated])

    XCTAssertNotEqual(originalFingerprint, updatedFingerprint)
  }

  func testShiftFingerprintChangesWhenCustomPauseWindowsChange() {
    let original = TestFixtures.shift(
      id: "same-id",
      shiftDate: "2026-02-05",
      startTime: "08:00",
      endTime: "16:00"
    )
    let updated = TestFixtures.shift(
      id: "same-id",
      shiftDate: "2026-02-05",
      startTime: "08:00",
      endTime: "16:00",
      customPauseWindows: CustomPauseWindows(windows: [
        PauseWindow(start: "12:00", end: "12:30")
      ])
    )

    let originalFingerprint = StatsService.fingerprintShiftsForCaching([original])
    let updatedFingerprint = StatsService.fingerprintShiftsForCaching([updated])

    XCTAssertNotEqual(originalFingerprint, updatedFingerprint)
  }

  func testRecurringShiftFingerprintChangesWhenDateSpecificPauseWindowsChange() {
    let original = RecurringShiftRow(
      id: "recurring-1",
      user_id: "user-1",
      job_id: "job-1",
      start_time: "08:00",
      end_time: "16:00",
      repeat_interval_weeks: 0,
      selected_days: ["1": "2026-02-02"],
      end_condition: nil,
      exclusions: nil,
      date_specific_pause_windows: nil,
      date_specific_supplements: nil
    )
    let updated = RecurringShiftRow(
      id: "recurring-1",
      user_id: "user-1",
      job_id: "job-1",
      start_time: "08:00",
      end_time: "16:00",
      repeat_interval_weeks: 0,
      selected_days: ["1": "2026-02-02"],
      end_condition: nil,
      exclusions: nil,
      date_specific_pause_windows: [
        "2026-02-09": CustomPauseWindows(windows: [PauseWindow(start: "12:00", end: "12:30")])
      ],
      date_specific_supplements: nil
    )

    let originalFingerprint = StatsService.fingerprintRecurringShiftsForCaching([original])
    let updatedFingerprint = StatsService.fingerprintRecurringShiftsForCaching([updated])

    XCTAssertNotEqual(originalFingerprint, updatedFingerprint)
  }

  func testSettingsFingerprintTracksOfflinePayrollDayChanges() throws {
    let original = UserSettings.defaults(for: "user-1")
    let data = try JSONEncoder().encode(original)
    var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    payload["payroll_day"] = original.effectivePayrollDay == 1 ? 25 : 1
    let updated = try JSONDecoder().decode(
      UserSettings.self, from: JSONSerialization.data(withJSONObject: payload)
    )

    XCTAssertEqual(original.updated_at, updated.updated_at)
    XCTAssertNotEqual(original.effectivePayrollDay, updated.effectivePayrollDay)
    XCTAssertNotEqual(
      StatsService.fingerprintSettingsForCaching(original),
      StatsService.fingerprintSettingsForCaching(updated)
    )
  }

  func testSnapshotFingerprintDistinguishesDefaultBreakValuesFromZero() {
    let defaultBreak = TestFixtures.wageSnapshot(id: "same-snapshot")
    let zeroThreshold = TestFixtures.wageSnapshot(id: "same-snapshot", breakThresholdHours: 0)
    let zeroDeduction = TestFixtures.wageSnapshot(id: "same-snapshot", breakDeductionMinutes: 0)

    XCTAssertNotEqual(
      StatsService.fingerprintSnapshotsForCaching([defaultBreak]),
      StatsService.fingerprintSnapshotsForCaching([zeroThreshold])
    )
    XCTAssertNotEqual(
      StatsService.fingerprintSnapshotsForCaching([defaultBreak]),
      StatsService.fingerprintSnapshotsForCaching([zeroDeduction])
    )
    XCTAssertNotEqual(
      defaultBreak.effectiveBreakThresholdHours, zeroThreshold.effectiveBreakThresholdHours)
    XCTAssertNotEqual(
      defaultBreak.effectiveBreakDeductionMinutes, zeroDeduction.effectiveBreakDeductionMinutes)
  }

  func testJobsFingerprintChangesWhenCurrencyChanges() {
    let original = [
      TestFixtures.job(id: "job-1", isDefault: true, currency: "kr")
    ]
    let updated = [
      TestFixtures.job(id: "job-1", isDefault: true, currency: "$")
    ]

    let originalFingerprint = StatsService.fingerprintJobsForCaching(original)
    let updatedFingerprint = StatsService.fingerprintJobsForCaching(updated)

    XCTAssertNotEqual(originalFingerprint, updatedFingerprint)
  }
}
