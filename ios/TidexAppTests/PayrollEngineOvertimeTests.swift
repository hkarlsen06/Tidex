import XCTest

@testable import Tidex

final class PayrollEngineOvertimeTests: XCTestCase {
  func testBreakBreakdownDoesNotTreatReplacedSupplementsAsUnpaidTime() throws {
    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      supplements: [SupplementRule(days: [1], from: "00:00", to: "24:00", rate: 20)],
      breakEnabled: true, breakMethod: "end_of_shift", breakThresholdHours: 0,
      breakDeductionMinutes: 30, jobId: "job-a",
      overtime: OvertimeConfig(
        enabled: true, weeklyThresholdHours: 1,
        rules: OvertimeConfig.seededDefaults.rules)
    )
    let computed = try XCTUnwrap(
      compute(
        [shift(id: "shift", date: "2026-02-02", start: "08:00", end: "12:00")],
        snapshots: [snapshot]
      ).first
    ).computed
    let beforeBreak = PayrollCalculator.payTotals(for: computed.preBreakWagePeriods)
    let deduction = try XCTUnwrap(
      BreakDeductionBreakdown.make(
        originalPeriods: computed.preBreakWagePeriods, adjustedPeriods: computed.wagePeriods
      ))
    XCTAssertEqual(computed.gross, 970, accuracy: 0.001)
    XCTAssertEqual(deduction.totalAmount, 110, accuracy: 0.001)
    XCTAssertEqual(beforeBreak.gross - deduction.totalAmount, computed.gross, accuracy: 0.001)
    let regular = computed.preBreakWagePeriods.filter { $0.isOvertime != true }
    XCTAssertEqual(PayrollCalculator.payTotals(for: regular).supplement, 30, accuracy: 0.001)
  }

  func testSundayOvertimeIsIdentifiedBeforeMondayWeeklyReset() throws {
    let result = compute([
      shift(id: "mon", date: "2026-02-02", start: "08:00", end: "18:00"),
      shift(id: "tue", date: "2026-02-03", start: "08:00", end: "18:00"),
      shift(id: "wed", date: "2026-02-04", start: "08:00", end: "18:00"),
      shift(id: "thu", date: "2026-02-05", start: "08:00", end: "18:00"),
      shift(id: "sun", date: "2026-02-08", start: "22:00", end: "02:00"),
    ])
    let computed = try XCTUnwrap(result.first { $0.id == "sun" }).computed
    let overtime = computed.classifiedWagePeriods.filter { $0.isOvertime == true }
    XCTAssertEqual(computed.overtimeMinutes, 120, accuracy: 0.001)
    XCTAssertEqual(overtime.first?.fromMin, 22 * 60)
    XCTAssertEqual(overtime.last?.toMin, 24 * 60)
    XCTAssertEqual(PayrollCalculator.payTotals(for: overtime).supplement, 400, accuracy: 0.001)
  }

  func testOvertimeRemainsIdentifiableWhenOrdinarySupplementHasSameRate() throws {
    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      supplements: [SupplementRule(days: [7], from: "00:00", to: "24:00", rate: 200)],
      breakEnabled: false, jobId: "job-a",
      overtime: OvertimeConfig(
        enabled: true, weeklyThresholdHours: 1,
        rules: OvertimeConfig.seededDefaults.rules)
    )
    let computed = try XCTUnwrap(
      compute(
        [shift(id: "sun", date: "2026-02-08", start: "08:00", end: "10:00")],
        snapshots: [snapshot]
      ).first
    ).computed
    XCTAssertEqual(computed.wagePeriods.count, 2)
    XCTAssertEqual(computed.wagePeriods.first?.isOvertime, false)
    XCTAssertEqual(computed.wagePeriods.last?.isOvertime, true)
  }

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
    month: Int = 2,
    year: Int = 2_026
  ) -> [ShiftWithComputations] {
    let effectiveJobs = jobs ?? [TestFixtures.job(id: "job-a", isDefault: true)]
    let effectiveSnapshots = snapshots ?? [snapshot(jobId: effectiveJobs[0].id)]
    return PayrollEngine.computeShiftsForMonth(
      PayrollEngine.MonthComputationRequest(
        year: year,
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

extension PayrollEngineOvertimeTests {
  func testRemovingAllShiftSupplementsAlsoRemovesRetainedOvertimeAdditions() throws {
    let holiday = SupplementRule(
      days: Array(1...7), from: "00:00", to: "24:00", percent: 100,
      dates: ["2027-03-27"])
    let wage = TestFixtures.wageSnapshot(
      hourlyWage: 195.8, supplements: [holiday], breakEnabled: false, jobId: "job-a",
      overtime: OvertimeConfig(
        enabled: true, weeklyThresholdHours: 1, rules: OvertimeConfig.seededDefaults.rules,
        retainedSupplements: [holiday]))
    try assertOwnerAndSharedPay(
      rows: [
        shift(id: "ordinary", date: "2027-03-27", start: "09:00", end: "10:00"),
        shift(
          id: "removed", date: "2027-03-27", start: "10:00", end: "11:00",
          customSupplements: CustomSupplementsData(rules: [])),
      ],
      wage: wage, expected: [391.6, 293.7], year: 2_027, month: 3)
  }

  func testRiksavtalenKeepsOrdinarySupplementsDuringOvertime() throws {
    let overtime = OvertimeConfig(
      enabled: true, weeklyThresholdHours: 1, rules: OvertimeConfig.seededDefaults.rules,
      retainSupplements: true)
    let wage = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      supplements: [SupplementRule(days: [1], from: "08:00", to: "10:00", rate: 20)],
      breakEnabled: false, jobId: "job-a", overtime: overtime)
    let row = shift(id: "riks", date: "2026-02-02", start: "08:00", end: "10:00")
    let computed = try XCTUnwrap(compute([row], snapshots: [wage]).first).computed
    XCTAssertEqual(computed.overtimeMinutes, 60)
    XCTAssertEqual(computed.gross, 540, accuracy: 0.001)

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let payload = SharingRPCPayloadInput(
      ownerId: "user-1", showEarnings: true,
      settings: try decoder.decode(SharingRPCUserSettings.self, from: Data("{}".utf8)),
      shifts: [try decoder.decode(SharingRPCShiftRow.self, from: encoder.encode(row))],
      recurringShifts: [],
      snapshots: [try decoder.decode(SharingRPCWageSnapshot.self, from: encoder.encode(wage))],
      jobs: [
        try decoder.decode(
          SharingRPCJobRow.self,
          from: encoder.encode(TestFixtures.job(id: "job-a", isDefault: true)))
      ])
    let shared = try XCTUnwrap(
      SharingComputeCore.computeShiftsInRange(
        payload: payload, startDate: "2026-02-02", endDate: "2026-02-02", mode: .visible
      ).first)
    XCTAssertEqual(shared.computed.gross, computed.gross, accuracy: 0.001)
  }

  func testLegacyOvertimeDecodingKeepsReplacementPolicy() throws {
    let json = Data(
      """
      {"enabled":true,"weeklyThresholdHours":1,"rules":[
        {"days":[1,2,3,4,5,6,7],"appliesOnHolidays":true,"from":"00:00","to":"24:00","percent":50}
      ]}
      """.utf8)
    let decoded = try JSONDecoder().decode(OvertimeConfig.self, from: json)
    let wage = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      supplements: [SupplementRule(days: [1], from: "08:00", to: "10:00", rate: 20)],
      breakEnabled: false, jobId: "job-a",
      overtime: OvertimeConfig(
        enabled: decoded.enabled, weeklyThresholdHours: decoded.weeklyThresholdHours,
        rules: OvertimeConfig.seededDefaults.rules, retainSupplements: decoded.retainSupplements))
    let result = try XCTUnwrap(
      compute(
        [shift(id: "legacy", date: "2026-02-02", start: "08:00", end: "10:00")],
        snapshots: [wage]
      ).first)
    XCTAssertEqual(result.computed.gross, 520, accuracy: 0.001)
  }

  func testOvertimePremiumUsesAgreementDivisorWithoutIncreasingOrdinaryPay() throws {
    let wage = TestFixtures.wageSnapshot(
      hourlyWage: 200, breakEnabled: false, jobId: "job-a",
      overtime: OvertimeConfig(
        enabled: true, weeklyThresholdHours: 1, rules: OvertimeConfig.seededDefaults.rules,
        premiumBaseMultiplier: 1_950.0 / 1_850.0))
    let result = try XCTUnwrap(
      compute(
        [shift(id: "pbl", date: "2026-02-02", start: "08:00", end: "10:00")],
        snapshots: [wage]
      ).first)
    XCTAssertEqual(result.computed.basePay, 400, accuracy: 0.001)
    XCTAssertEqual(result.computed.supplementPay, 105.41, accuracy: 0.001)
  }

  func testDatedOvertimePreservesHolidayEveNoonThroughEditingAndSharing() throws {
    let dates = ["2026-12-24"]
    let eveRule = OvertimeRule(
      days: Array(1...7), appliesOnHolidays: true, from: "12:00", to: "24:00",
      percent: 400.0 / 3.0, dates: dates)
    let holidayRule = OvertimeRule(
      days: Array(1...7), appliesOnHolidays: false, from: "00:00", to: "24:00",
      percent: 400.0 / 3.0, dates: ["2026-12-25"])
    let overtime = OvertimeConfig(
      enabled: true, weeklyThresholdHours: 0.5,
      rules: OvertimeConfig.seededDefaults.rules + [
        OvertimeRuleDraft(eveRule).toRule(), holidayRule,
      ])
    let wage = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      supplements: [SupplementRule(days: Array(1...7), from: "00:00", to: "24:00", rate: 20)],
      breakEnabled: false, jobId: "job-a", overtime: overtime)
    for (date, expected) in [("2026-12-23", 560.0), ("2026-12-24", 726.67), ("2026-12-25", 810.0)] {
      let row = shift(id: "dated", date: date, start: "11:00", end: "13:00")
      let result = try XCTUnwrap(compute([row], snapshots: [wage], month: 12).first)
      XCTAssertEqual(result.computed.gross, expected, accuracy: 0.001)
      let encoder = JSONEncoder()
      let decoder = JSONDecoder()
      let payload = SharingRPCPayloadInput(
        ownerId: "user-1", showEarnings: true,
        settings: try decoder.decode(SharingRPCUserSettings.self, from: Data("{}".utf8)),
        shifts: [try decoder.decode(SharingRPCShiftRow.self, from: encoder.encode(row))],
        recurringShifts: [],
        snapshots: [try decoder.decode(SharingRPCWageSnapshot.self, from: encoder.encode(wage))],
        jobs: [
          try decoder.decode(
            SharingRPCJobRow.self,
            from: encoder.encode(TestFixtures.job(id: "job-a", isDefault: true)))
        ])
      let shared = try XCTUnwrap(
        SharingComputeCore.computeShiftsInRange(
          payload: payload, startDate: date, endDate: date, mode: .visible
        ).first)
      XCTAssertEqual(shared.computed.gross, expected, accuracy: 0.001)
    }
  }

}

extension PayrollEngineOvertimeTests {
  func testHandelRetainsHolidayEvePremiumButRemovesOrdinaryUBDuringOvertime() throws {
    let holiday = SupplementRule(
      days: Array(1...7), from: "00:00", to: "24:00", percent: 100,
      stackingGroup: "holiday", dates: ["2027-03-27"])
    let wage = TestFixtures.wageSnapshot(
      hourlyWage: 195.8,
      supplements: [
        holiday,
        SupplementRule(
          days: Array(1...7), from: "00:00", to: "24:00", rate: 30, stackingGroup: "ordinary"),
      ],
      breakEnabled: false, jobId: "job-a",
      overtime: OvertimeConfig(
        enabled: true, weeklyThresholdHours: 1, rules: OvertimeConfig.seededDefaults.rules,
        retainedSupplements: [holiday]))
    try assertOwnerAndSharedPay(
      rows: [
        shift(id: "ordinary", date: "2027-03-27", start: "09:00", end: "10:00"),
        shift(id: "overtime", date: "2027-03-27", start: "10:00", end: "11:00"),
      ],
      wage: wage, expected: [421.6, 489.5], year: 2_027, month: 3)
  }

  func testRetainedDatedOvernightRulesSplitIndependentlyOfOrdinaryPeriods() throws {
    let retained = SupplementRule(
      days: Array(1...7), from: "23:00", to: "01:00", rate: 100, dates: ["2026-02-02"])
    let wage = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      supplements: [SupplementRule(days: Array(1...7), from: "00:00", to: "24:00", rate: 20)],
      breakEnabled: false, jobId: "job-a",
      overtime: OvertimeConfig(
        enabled: true, weeklyThresholdHours: 1,
        rules: [
          OvertimeRule(
            days: Array(1...7), appliesOnHolidays: false,
            from: "00:00", to: "24:00", percent: 50),
          OvertimeRule(
            days: Array(1...7), appliesOnHolidays: true,
            from: "00:00", to: "24:00", percent: 50),
        ],
        retainedSupplements: [retained]))
    try assertOwnerAndSharedPay(
      rows: [shift(id: "overnight", date: "2026-02-02", start: "22:00", end: "02:00")],
      wage: wage, expected: [1_320])
  }

  func testCleaningApprenticeOvertimePaysAdultBaseForEntireOvertimeHour() throws {
    let wage = TestFixtures.wageSnapshot(
      hourlyWage: 133.08, breakEnabled: false, jobId: "job-a",
      overtime: OvertimeConfig(
        enabled: true, weeklyThresholdHours: 1, rules: OvertimeConfig.seededDefaults.rules,
        baseRate: 247.29))
    try assertOwnerAndSharedPay(
      rows: [
        shift(id: "ordinary", date: "2026-02-02", start: "08:00", end: "09:00"),
        shift(id: "overtime", date: "2026-02-02", start: "09:00", end: "10:00"),
      ],
      wage: wage, expected: [133.08, 370.94])
  }

  func testCleaningRetainedPercentageUBUsesAdultOvertimeWage() throws {
    let holiday = SupplementRule(days: Array(1...7), from: "00:00", to: "24:00", percent: 100)
    let wage = TestFixtures.wageSnapshot(
      hourlyWage: 133.08, supplements: [holiday], breakEnabled: false, jobId: "job-a",
      overtime: OvertimeConfig(
        enabled: true, weeklyThresholdHours: 1, rules: OvertimeConfig.seededDefaults.rules,
        baseRate: 247.29, retainedSupplements: [holiday]))
    try assertOwnerAndSharedPay(
      rows: [
        shift(id: "ordinary", date: "2026-05-01", start: "07:00", end: "08:00"),
        shift(id: "overtime", date: "2026-05-01", start: "08:00", end: "09:00"),
      ],
      wage: wage, expected: [266.16, 741.87], month: 5)
  }

  func testNightGuardHolidayPayFollowsOriginalStartBeforeSixForWholeShift() throws {
    let holiday = SupplementRule(
      days: Array(1...7), from: "00:00", to: "24:00", percent: 100,
      shiftStartDates: ["2027-01-02"], shiftStartBefore: "06:00")
    let supplements = [
      holiday,
      SupplementRule(
        days: Array(1...7), from: "21:00", to: "06:00", rate: 28),
    ]
    for (start, end, expected) in [
      ("00:00", "08:00", 3_200.0),
      ("22:00", "06:00", 1_824.0), ("06:00", "08:00", 400.0),
    ] {
      let wage = TestFixtures.wageSnapshot(
        hourlyWage: 200, supplements: supplements, breakEnabled: false, jobId: "job-a")
      try assertOwnerAndSharedPay(
        rows: [shift(id: "guard", date: "2027-01-02", start: start, end: end)],
        wage: wage, expected: [expected], year: 2_027, month: 1)
    }
    let wage = TestFixtures.wageSnapshot(
      hourlyWage: 200, supplements: supplements, breakEnabled: false, jobId: "job-a",
      overtime: OvertimeConfig(
        enabled: true, weeklyThresholdHours: 1,
        rules: [
          OvertimeRule(
            days: Array(1...7), appliesOnHolidays: false,
            from: "00:00", to: "24:00", percent: 50),
          OvertimeRule(
            days: Array(1...7), appliesOnHolidays: true,
            from: "00:00", to: "24:00", percent: 50),
        ],
        retainSupplements: true, retainedSupplements: [holiday]))
    try assertOwnerAndSharedPay(
      rows: [shift(id: "guard", date: "2027-01-02", start: "05:00", end: "08:00")],
      wage: wage, expected: [1_400], year: 2_027, month: 1)
  }

  private func assertOwnerAndSharedPay(
    rows: [ShiftRow], wage: WageSnapshot, expected: [Double], year: Int = 2_026, month: Int = 2
  ) throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let restored = try decoder.decode(WageSnapshot.self, from: encoder.encode(wage))
    let owner = compute(rows, snapshots: [restored], month: month, year: year)
    let payload = SharingRPCPayloadInput(
      ownerId: "user-1", showEarnings: true,
      settings: try decoder.decode(SharingRPCUserSettings.self, from: Data("{}".utf8)),
      shifts: try rows.map {
        try decoder.decode(SharingRPCShiftRow.self, from: encoder.encode($0))
      },
      recurringShifts: [],
      snapshots: [try decoder.decode(SharingRPCWageSnapshot.self, from: encoder.encode(restored))],
      jobs: [
        try decoder.decode(
          SharingRPCJobRow.self,
          from: encoder.encode(TestFixtures.job(id: "job-a", isDefault: true)))
      ])
    let shared = SharingComputeCore.computeShiftsInRange(
      payload: payload, startDate: try XCTUnwrap(rows.map(\.shift_date).min()),
      endDate: try XCTUnwrap(rows.map(\.shift_date).max()), mode: .visible)
    for (row, gross) in zip(rows, expected) {
      XCTAssertEqual(
        try XCTUnwrap(owner.first { $0.id == row.id }).computed.gross, gross, accuracy: 0.001)
      XCTAssertEqual(
        try XCTUnwrap(shared.first { $0.id == row.id }).computed.gross, gross, accuracy: 0.001)
    }
  }
}
