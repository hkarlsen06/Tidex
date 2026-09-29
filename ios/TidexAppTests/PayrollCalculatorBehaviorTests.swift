import XCTest

@testable import Tidex

final class PayrollCalculatorBehaviorTests: XCTestCase {
  func testTariffPayRoundsHalfCentsConsistentlyAcrossPeriodSplits() throws {
    let scenarios = [
      HalfCentScenario(184.54, 45, 7, 138.41), HalfCentScenario(185.38, 15, 4, 46.35),
      HalfCentScenario(187.46, 15, 4, 46.87), HalfCentScenario(193.05, 10, 2, 32.18),
      HalfCentScenario(210.81, 30, 9, 105.41), HalfCentScenario(256.14, 45, 3, 192.11),
      HalfCentScenario(193.049999, 10, 2, 32.17),
    ]
    for scenario in scenarios {
      let end = String(format: "08:%02d", scenario.minutes)
      let cut = String(format: "08:%02d", scenario.split)
      let row = TestFixtures.shift(shiftDate: "2026-02-02", startTime: "08:00", endTime: end)
      let snapshot = TestFixtures.wageSnapshot(
        hourlyWage: scenario.rate,
        supplements: [
          SupplementRule(days: [1], from: "08:00", to: cut, rate: scenario.rate),
          SupplementRule(days: [1], from: cut, to: end, rate: scenario.rate),
        ], breakEnabled: false)
      let computed = PayrollCalculator.computeShift(row, snapshot: snapshot)
      XCTAssertEqual(computed.basePay, scenario.expected)
      XCTAssertEqual(computed.supplementPay, scenario.expected)
      XCTAssertEqual(
        PayrollCalculator.payTotals(for: [
          WagePeriod(
            fromMin: 0, toMin: Double(scenario.minutes), baseRate: scenario.rate, supplementRate: 0)
        ]).base, scenario.expected)
      let shared = try sharedComputedShift(row, snapshot: snapshot)
      XCTAssertEqual(shared.computed.basePay, scenario.expected)
      XCTAssertEqual(shared.computed.supplementPay, scenario.expected)
    }
  }

  private func sharedComputedShift(
    _ row: ShiftRow, snapshot: WageSnapshot
  ) throws -> SharingComputedShift {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let payload = SharingRPCPayloadInput(
      ownerId: try XCTUnwrap(row.user_id), showEarnings: true,
      settings: try decoder.decode(SharingRPCUserSettings.self, from: Data("{}".utf8)),
      shifts: [try decoder.decode(SharingRPCShiftRow.self, from: encoder.encode(row))],
      recurringShifts: [],
      snapshots: [
        try decoder.decode(SharingRPCWageSnapshot.self, from: encoder.encode(snapshot))
      ],
      jobs: [])
    return try XCTUnwrap(
      SharingComputeCore.computeShiftsInRange(
        payload: payload, startDate: row.shift_date, endDate: row.shift_date, mode: .visible
      ).first)
  }

  func testOvernightSupplementsFollowTheWeekdayAtEachRuleStart() {
    let saturday = SupplementRule(days: [6], from: "18:00", to: "24:00", rate: 50)
    let sunday = SupplementRule(days: [7], from: "00:00", to: "24:00", rate: 100)
    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200, supplements: [saturday, sunday], breakEnabled: false
    )
    let saturdayNight = PayrollCalculator.computeShift(
      TestFixtures.shift(shiftDate: "2026-02-07", startTime: "22:00", endTime: "02:00"),
      snapshot: snapshot
    )
    let sundayNight = PayrollCalculator.computeShift(
      TestFixtures.shift(shiftDate: "2026-02-08", startTime: "22:00", endTime: "02:00"),
      snapshot: snapshot
    )
    XCTAssertEqual(saturdayNight.supplementPay, 300, accuracy: 0.001)
    XCTAssertEqual(saturdayNight.gross, 1_100, accuracy: 0.001)
    XCTAssertEqual(sundayNight.supplementPay, 200, accuracy: 0.001)
  }

  func testEarlyShiftReceivesPreviousDaysOvernightRule() {
    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      supplements: [
        SupplementRule(days: [6], from: "22:00", to: "06:00", rate: 60)
      ], breakEnabled: false)
    let computed = PayrollCalculator.computeShift(
      TestFixtures.shift(shiftDate: "2026-02-08", startTime: "01:00", endTime: "03:00"),
      snapshot: snapshot
    )
    XCTAssertEqual(computed.supplementPay, 120, accuracy: 0.001)
  }

  func testOverlappingOvernightRulesUseHighestRate() {
    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      supplements: [
        SupplementRule(days: [6], from: "22:00", to: "06:00", rate: 60),
        SupplementRule(days: [7], from: "00:00", to: "24:00", percent: 50),
      ], breakEnabled: false)
    let computed = PayrollCalculator.computeShift(
      TestFixtures.shift(shiftDate: "2026-02-07", startTime: "23:00", endTime: "03:00"),
      snapshot: snapshot
    )
    XCTAssertEqual(computed.supplementPay, 360, accuracy: 0.001)
  }

  func testOvernightSupplementEditorPreservesWeekdayRatesWhenSavingOverrides() {
    let rules = [
      SupplementRule(days: [6], from: "18:00", to: "24:00", rate: 50),
      SupplementRule(days: [7], from: "00:00", to: "24:00", rate: 100),
    ]
    let editable = ApplicableSupplements.getApplicableSupplements(
      startTime: "22:00", endTime: "02:00", weekday: 6, rules: rules
    )
    let saved = CustomSupplementsData(rules: editable.map { $0.toCustomSupplementRule() })
    let computed = PayrollCalculator.computeShift(
      TestFixtures.shift(
        shiftDate: "2026-02-07", startTime: "22:00", endTime: "02:00",
        customSupplements: saved),
      snapshot: TestFixtures.wageSnapshot(hourlyWage: 200, breakEnabled: false)
    )
    XCTAssertEqual(computed.supplementPay, 300, accuracy: 0.001)
    XCTAssertEqual(
      ApplicableSupplements.filterToApplicable(
        rules: editable, startTime: "22:00", endTime: "02:00"
      ).count, 2)
  }

  func testEditorShowsPreviousDaysOvernightRule() {
    let editable = ApplicableSupplements.getApplicableSupplements(
      startTime: "01:00", endTime: "03:00", weekday: 7,
      rules: [SupplementRule(days: [6], from: "22:00", to: "06:00", rate: 60)]
    )
    XCTAssertEqual(editable.count, 1)
    XCTAssertEqual(editable.first?.from, "01:00")
    XCTAssertEqual(editable.first?.to, "03:00")
  }

  func testMinutePrecisionIsPreservedForPayAndAccumulatedHours() {
    let computed = PayrollCalculator.computeShift(
      TestFixtures.shift(shiftDate: "2026-02-02", startTime: "08:00", endTime: "08:01"),
      snapshot: TestFixtures.wageSnapshot(hourlyWage: 200, breakEnabled: false)
    )
    XCTAssertEqual(computed.basePay, 3.33, accuracy: 0.001)
    XCTAssertEqual(computed.paidHours * 60, 1, accuracy: 0.000001)
    XCTAssertEqual(computed.durationHours * 60, 1, accuracy: 0.000001)
    XCTAssertEqual(
      PayrollCalculator.replacingWagePeriods(
        in: computed, with: computed.wagePeriods, overtimeMinutes: 0
      ).basePay, 3.33, accuracy: 0.001)
  }

  func testPeriodSplitsCannotChangeUnchangedRates() {
    let computed = PayrollCalculator.computeShift(
      TestFixtures.shift(shiftDate: "2026-02-02", startTime: "08:00", endTime: "09:00"),
      snapshot: TestFixtures.wageSnapshot(
        hourlyWage: 200,
        supplements: [
          SupplementRule(days: [1], from: "08:00", to: "08:01", rate: 20),
          SupplementRule(days: [1], from: "08:01", to: "08:02", rate: 20),
          SupplementRule(days: [1], from: "08:02", to: "09:00", rate: 20),
        ], breakEnabled: false)
    )
    XCTAssertEqual(computed.basePay, 200, accuracy: 0.001)
    XCTAssertEqual(computed.supplementPay, 20, accuracy: 0.001)
    XCTAssertEqual(computed.gross, 220, accuracy: 0.001)
    XCTAssertEqual(BreakDeductionBreakdown.basePay(for: computed.wagePeriods), 200, accuracy: 0.001)
  }

  func testNoBreakMethodDoesNotClaimUnpaidTime() {
    let computed = PayrollCalculator.computeShift(
      TestFixtures.shift(shiftDate: "2026-02-02", startTime: "08:00", endTime: "16:00"),
      snapshot: TestFixtures.wageSnapshot(
        hourlyWage: 200, breakEnabled: true,
        breakMethod: "none", breakDeductionMinutes: 30)
    )
    XCTAssertEqual(computed.paidHours, 8, accuracy: 0.001)
    XCTAssertEqual(computed.breakAudit.deductedHours, 0, accuracy: 0.001)
    XCTAssertEqual(computed.breakAudit.source, .none)
  }

  func testShortShiftDoesNotClaimAnAutomaticBreak() {
    let computed = PayrollCalculator.computeShift(
      TestFixtures.shift(shiftDate: "2026-02-02", startTime: "08:00", endTime: "10:00"),
      snapshot: TestFixtures.wageSnapshot(hourlyWage: 200, breakEnabled: true)
    )
    XCTAssertEqual(computed.breakAudit.source, .none)
  }

  func testMidnightAndLastMinuteAreDisplayedAccurately() {
    let segment = SupplementSegment(fromMin: 1_440, toMin: 1_560, rate: 50, actualHours: 2)
    XCTAssertEqual(segment.timeRange, "00:00 (+1) – 02:00 (+1)")
    XCTAssertEqual(segment.formatTime(1_439), "23:59")
  }

  func testBreakBreakdownReconcilesRoundedPayComponents() throws {
    let computed = PayrollCalculator.computeShift(
      TestFixtures.shift(shiftDate: "2026-02-02", startTime: "18:00", endTime: "18:02"),
      snapshot: TestFixtures.wageSnapshot(
        hourlyWage: 200,
        supplements: [SupplementRule(days: [1], from: "18:00", to: "24:00", rate: 20)],
        breakEnabled: true, breakMethod: "end_of_shift", breakThresholdHours: 0,
        breakDeductionMinutes: 1
      )
    )
    let beforeBreak = PayrollCalculator.payTotals(for: computed.preBreakWagePeriods)
    let deduction = try XCTUnwrap(
      BreakDeductionBreakdown.make(
        originalPeriods: computed.preBreakWagePeriods, adjustedPeriods: computed.wagePeriods
      ))
    XCTAssertEqual(beforeBreak.gross - deduction.totalAmount, computed.gross, accuracy: 0.001)
  }

  func testOvertimeMetadataDecodesOldSharedPeriodsAndRoundTripsNewPeriods() throws {
    let old = Data(#"{"fromMin":480,"toMin":540,"baseRate":200,"supplementRate":20}"#.utf8)
    let decoded = try JSONDecoder().decode(WagePeriod.self, from: old)
    XCTAssertNil(decoded.isOvertime)
    var current = decoded
    current.isOvertime = true
    XCTAssertEqual(
      try JSONDecoder().decode(WagePeriod.self, from: JSONEncoder().encode(current)), current)
  }

  func testSharedCalculationMatchesOwnerForOvernightMinuteAndBreakCases() throws {
    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      supplements: [
        SupplementRule(days: [6], from: "18:00", to: "24:00", rate: 50),
        SupplementRule(days: [7], from: "00:00", to: "24:00", rate: 100),
      ], breakEnabled: true, breakMethod: "none")
    let rows = [
      TestFixtures.shift(shiftDate: "2026-02-07", startTime: "22:00", endTime: "02:00"),
      TestFixtures.shift(shiftDate: "2026-02-08", startTime: "22:00", endTime: "02:00"),
      TestFixtures.shift(shiftDate: "2026-02-02", startTime: "08:00", endTime: "08:01"),
      TestFixtures.shift(shiftDate: "2026-02-02", startTime: "08:00", endTime: "16:00"),
      TestFixtures.shift(shiftDate: "2026-02-02", startTime: "invalid", endTime: "16:00"),
    ]
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for row in rows {
      let payload = SharingRPCPayloadInput(
        ownerId: try XCTUnwrap(row.user_id), showEarnings: true,
        settings: try decoder.decode(SharingRPCUserSettings.self, from: Data("{}".utf8)),
        shifts: [try decoder.decode(SharingRPCShiftRow.self, from: encoder.encode(row))],
        recurringShifts: [],
        snapshots: [
          try decoder.decode(SharingRPCWageSnapshot.self, from: encoder.encode(snapshot))
        ],
        jobs: []
      )
      let shared = try XCTUnwrap(
        SharingComputeCore.computeShiftsInRange(
          payload: payload, startDate: row.shift_date, endDate: row.shift_date, mode: .visible
        ).first)
      let owner = PayrollCalculator.computeShift(row, snapshot: snapshot)
      XCTAssertEqual(shared.computed.gross, owner.gross, accuracy: 0.001)
      XCTAssertEqual(shared.computed.paidHours, owner.paidHours, accuracy: 0.000001)
      XCTAssertEqual(shared.computed.breakAudit.deductedHours, owner.breakAudit.deductedHours)
      XCTAssertEqual(shared.computed.breakAudit.source, owner.breakAudit.source)
    }
  }

  func testComputeShiftWithEmptyCustomSupplementsDoesNotApplySnapshotSupplements() {
    let shift = TestFixtures.shift(
      shiftDate: "2026-02-02",
      startTime: "19:00",
      endTime: "20:00",
      customSupplements: CustomSupplementsData(rules: [])
    )

    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      supplements: [
        SupplementRule(days: [1], from: "18:00", to: "24:00", rate: 40, percent: nil)
      ]
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

    XCTAssertEqual(computed.basePay, 200, accuracy: 0.01)
    XCTAssertEqual(computed.supplementPay, 0, accuracy: 0.01)
    XCTAssertEqual(computed.gross, 200, accuracy: 0.01)
  }

  func testComputeShiftWithBreakDisabledKeepsPaidHoursEqualToDuration() {
    let shift = TestFixtures.shift(
      shiftDate: "2026-02-03",
      startTime: "08:00",
      endTime: "16:00",
      customSupplements: CustomSupplementsData(rules: [])
    )

    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      breakEnabled: false,
      breakMethod: BreakMethod.proportional.rawValue,
      breakThresholdHours: 0,
      breakDeductionMinutes: 30
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

    XCTAssertEqual(computed.durationHours, 8, accuracy: 0.01)
    XCTAssertEqual(computed.paidHours, 8, accuracy: 0.01)
    XCTAssertEqual(computed.breakAudit.deductedHours, 0, accuracy: 0.001)
  }

  func testComputeShiftWithCustomPauseWindowsUsesExactClippingInsteadOfAutomaticBreaks() {
    let shift = TestFixtures.shift(
      shiftDate: "2026-02-04",
      startTime: "08:00",
      endTime: "16:00",
      customPauseWindows: CustomPauseWindows(windows: [
        PauseWindow(start: "12:00", end: "12:30")
      ]),
      customSupplements: CustomSupplementsData(rules: [])
    )

    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      breakEnabled: true,
      breakMethod: BreakMethod.endOfShift.rawValue,
      breakThresholdHours: 5.5,
      breakDeductionMinutes: 45
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

    XCTAssertEqual(computed.durationHours, 8, accuracy: 0.01)
    XCTAssertEqual(computed.paidHours, 7.5, accuracy: 0.01)
    XCTAssertEqual(computed.breakAudit.source, .customPauseWindows)
    XCTAssertEqual(computed.breakAudit.deductedHours, 0.5, accuracy: 0.001)
    XCTAssertEqual(
      computed.breakAudit.appliedPauseWindows,
      [PauseWindow(start: "12:00", end: "12:30")]
    )
  }

  func testComputeShiftWithInvalidPersistedTimesProducesZeroPayroll() {
    let shift = TestFixtures.shift(
      shiftDate: "2026-02-05",
      startTime: "not-a-time",
      endTime: "17:00",
      customSupplements: CustomSupplementsData(rules: [])
    )

    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      breakEnabled: false
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

    XCTAssertEqual(computed.durationHours, 0, accuracy: 0.01)
    XCTAssertEqual(computed.paidHours, 0, accuracy: 0.01)
    XCTAssertEqual(computed.gross, 0, accuracy: 0.01)
  }

  func testComputeShiftIgnoresNegativePersistedBreakDeduction() {
    let shift = TestFixtures.shift(
      shiftDate: "2026-02-06",
      startTime: "08:00",
      endTime: "16:00",
      customSupplements: CustomSupplementsData(rules: [])
    )

    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: 200,
      breakEnabled: true,
      breakMethod: BreakMethod.proportional.rawValue,
      breakThresholdHours: 0,
      breakDeductionMinutes: -30
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

    XCTAssertEqual(computed.durationHours, 8, accuracy: 0.01)
    XCTAssertEqual(computed.paidHours, 8, accuracy: 0.01)
    XCTAssertEqual(computed.breakAudit.deductedHours, 0, accuracy: 0.001)
  }

  func testComputeShiftFallsBackWhenPersistedHourlyWageIsNotFinite() {
    let shift = TestFixtures.shift(
      shiftDate: "2026-02-07",
      startTime: "08:00",
      endTime: "09:00",
      customSupplements: CustomSupplementsData(rules: [])
    )

    let snapshot = TestFixtures.wageSnapshot(
      hourlyWage: .infinity,
      breakEnabled: false
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

    XCTAssertEqual(computed.basePay, 184.54, accuracy: 0.01)
    XCTAssertEqual(computed.gross, 184.54, accuracy: 0.01)
  }
}

private struct HalfCentScenario {
  let rate: Double
  let minutes: Int
  let split: Int
  let expected: Double

  init(_ rate: Double, _ minutes: Int, _ split: Int, _ expected: Double) {
    self.rate = rate
    self.minutes = minutes
    self.split = split
    self.expected = expected
  }
}
