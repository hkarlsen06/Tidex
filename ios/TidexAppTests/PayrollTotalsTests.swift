import XCTest

@testable import Tidex

final class PayrollTotalsTests: XCTestCase {
  func testSharedShiftsUseTheSamePayoutTaxAsTheirOwner() throws {
    let scenarios: [(jobs: [Job], jobId: String?, halfTaxMonth: Int?, expectedRate: Double)] = [
      ([TestFixtures.job(id: "job", isDefault: true, halfTaxMonth: 11)], "job", nil, 15),
      ([TestFixtures.job(id: "job", isDefault: true, halfTaxMonth: nil)], "job", 11, 30),
      ([TestFixtures.job(id: "job", isDefault: true, halfTaxMonth: 11)], nil, nil, 15),
      ([], nil, 11, 15),
      ([], nil, 12, 30),
      ([TestFixtures.job(
        id: "job", isDefault: true, halfTaxMonth: 11,
        payPeriod: .monthly(startDay: 1, payoutMonthOffset: 0))], "job", nil, 20),
      ([TestFixtures.job(
        id: "job", isDefault: true, halfTaxMonth: 11,
        payPeriod: .monthly(startDay: 16, payoutMonthOffset: 1))], "job", nil, 30),
      ([TestFixtures.job(
        id: "job", isDefault: true, halfTaxMonth: 11,
        payPeriod: .biweekly(anchorEnd: "2026-10-31", payoutDelayDays: 0))], "job", nil, 20),
    ]
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for scenario in scenarios {
      let settings = try decoder.decode(
        UserSettings.self,
        from: JSONSerialization.data(withJSONObject: [
          "user_id": "user-1", "theme": "system",
          "half_tax_month": scenario.halfTaxMonth.map { $0 as Any } ?? NSNull(),
        ]))
      let snapshots = [
        TestFixtures.wageSnapshot(
          taxEnabled: true, taxPercentage: 20, breakEnabled: false,
          jobId: scenario.jobs.first?.id),
        TestFixtures.wageSnapshot(
          fromDate: "2026-11-01", taxEnabled: true, taxPercentage: 30,
          breakEnabled: false, jobId: scenario.jobs.first?.id),
      ]
      let row = TestFixtures.shift(
        shiftDate: "2026-10-31", startTime: "22:00", endTime: "02:00",
        jobId: scenario.jobId)
      let owner = try XCTUnwrap(
        PayrollEngine.computeShiftsForMonth(
          .init(
            year: 2026, month: 10, shifts: [row], recurring: [], snapshots: snapshots,
            settings: settings, jobs: scenario.jobs)
        ).first)
      let payload = SharingRPCPayloadInput(
        ownerId: try XCTUnwrap(row.user_id), showEarnings: true,
        settings: try decoder.decode(SharingRPCUserSettings.self, from: encoder.encode(settings)),
        shifts: [try decoder.decode(SharingRPCShiftRow.self, from: encoder.encode(row))],
        recurringShifts: [],
        snapshots: try snapshots.map {
          try decoder.decode(SharingRPCWageSnapshot.self, from: encoder.encode($0))
        },
        jobs: try scenario.jobs.map {
          try decoder.decode(SharingRPCJobRow.self, from: encoder.encode($0))
        })
      let shared = try XCTUnwrap(
        SharingComputeCore.computeShiftsInRange(
          payload: payload, startDate: row.shift_date, endDate: row.shift_date, mode: .visible
        ).first)
      XCTAssertEqual(shared.taxPercentage, scenario.expectedRate)
      XCTAssertEqual(shared.taxPercentage, owner.effectiveTaxPercentage)
      XCTAssertEqual(
        shared.computed.gross * (1 - shared.taxPercentage / 100), owner.netPay, accuracy: 0.001)

      let hidden = try XCTUnwrap(
        SharingComputeCore.computeShiftsInRange(
          payload: payload, startDate: row.shift_date, endDate: row.shift_date, mode: .hidden
        ).first)
      XCTAssertFalse(hidden.taxEnabled)
      XCTAssertEqual(hidden.taxPercentage, 0)
      XCTAssertEqual(hidden.computed.gross, 0)
    }
  }

  func testWorkplaceTaxSettingsMatchShiftTotalsAndWidgetAmounts() throws {
    let jobs = [
      TestFixtures.job(id: "half-tax", isDefault: true, currency: "kr", halfTaxMonth: 11),
      TestFixtures.job(id: "full-tax", isDefault: false, currency: "$", halfTaxMonth: nil),
    ]
    let snapshots = jobs.map {
      TestFixtures.wageSnapshot(
        id: $0.id, taxEnabled: true, taxPercentage: 30,
        breakEnabled: false, jobId: $0.id)
    }
    let shifts = jobs.enumerated().map { index, job in
      TestFixtures.shift(
        id: job.id, shiftDate: "2026-10-0\(index + 1)",
        startTime: "08:00", endTime: "16:00", jobId: job.id)
    }
    let settings = try JSONDecoder().decode(
      UserSettings.self,
      from: Data(
        #"{"user_id":"user-1","theme":"system","half_tax_month":11}"#.utf8))
    let result = PayrollEngine.computeShiftsForMonth(
      .init(
        year: 2026, month: 10, shifts: shifts, recurring: [], snapshots: snapshots,
        settings: settings, jobs: jobs))
    let half = try XCTUnwrap(result.first { $0.id == "half-tax" })
    let full = try XCTUnwrap(result.first { $0.id == "full-tax" })

    XCTAssertEqual(half.netPay, 1360, accuracy: 0.001)
    XCTAssertEqual(half.taxAmount, 240, accuracy: 0.001)
    XCTAssertEqual(full.netPay, 1120, accuracy: 0.001)
    XCTAssertEqual(half.calculationContext?.wageSnapshotId, "half-tax")
    XCTAssertEqual(half.calculationContext?.scheduledPayoutDate, "2026-11-25")
    XCTAssertEqual(half.calculationContext?.halfTaxApplied, true)
    XCTAssertEqual(full.calculationContext?.halfTaxApplied, false)

    let totals = PayrollEngine.summarizeShiftTotals(
      shifts: result, halfTaxMonth: 11, earningsMonth: 10)
    XCTAssertEqual(totals.net, half.netPay + full.netPay, accuracy: 0.001)

    let widget = NativeWidgetStorage.storedShift(full, jobs: jobs, fallbackCurrency: "kr")
    XCTAssertEqual(widget.currencySymbol, "$")
    XCTAssertEqual(widget.taxRate, 0.3)
    XCTAssertEqual(
      widget.totalGrossEstimate * (1 - (widget.taxRate ?? 0)), full.netPay,
      accuracy: 0.001)
  }

  func testPayoutTaxContextSurvivesOvertimeCalculation() throws {
    let job = TestFixtures.job(id: "job", isDefault: true, halfTaxMonth: 11)
    let snapshot = TestFixtures.wageSnapshot(
      taxEnabled: true, taxPercentage: 20,
      breakEnabled: false, jobId: job.id,
      overtime: OvertimeConfig(
        enabled: true, weeklyThresholdHours: 1,
        rules: OvertimeConfig.seededDefaults.rules))
    let result = PayrollEngine.computeShiftsForMonth(
      .init(
        year: 2026, month: 10,
        shifts: [
          TestFixtures.shift(
            shiftDate: "2026-10-01", startTime: "08:00", endTime: "10:00",
            jobId: job.id)
        ], recurring: [], snapshots: [snapshot], settings: nil, jobs: [job]))
    let shift = try XCTUnwrap(result.first)
    XCTAssertEqual(shift.grossPay, 500, accuracy: 0.001)
    XCTAssertEqual(shift.effectiveTaxPercentage, 10)
    XCTAssertEqual(shift.netPay, 450, accuracy: 0.001)
  }

  func testSummarizeShiftTotalsAppliesHalfTaxOnPayoutMonth() {
    let taxedOne = TestFixtures.computedShift(
      id: "s1",
      shiftDate: "2026-10-01",
      startTime: "08:00",
      endTime: "16:00",
      gross: 1_000,
      taxEnabled: true,
      taxPercentage: 20
    )
    let taxedTwo = TestFixtures.computedShift(
      id: "s2",
      shiftDate: "2026-10-02",
      startTime: "08:00",
      endTime: "16:00",
      gross: 1_000,
      taxEnabled: true,
      taxPercentage: 20
    )

    let now = Date.fromDateAndTime("2026-10-15", time: "12:00") ?? Date()

    let totals = PayrollEngine.summarizeShiftTotals(
      shifts: [taxedOne, taxedTwo],
      halfTaxMonth: 11,
      earningsMonth: 10,
      now: now
    )

    XCTAssertLessThan(abs(totals.gross - 2_000), 0.01)
    XCTAssertLessThan(abs(totals.net - 1_800), 0.01)
    XCTAssertLessThan(abs(totals.completedGross - 2_000), 0.01)
    XCTAssertLessThan(abs(totals.completedNet - 1_800), 0.01)
  }

  func testSummarizeShiftTotalsRespectsExcludedShiftIds() {
    let first = TestFixtures.computedShift(
      id: "keep",
      shiftDate: "2026-10-01",
      startTime: "08:00",
      endTime: "16:00",
      gross: 1_000,
      taxEnabled: false
    )
    let second = TestFixtures.computedShift(
      id: "exclude",
      shiftDate: "2026-10-01",
      startTime: "12:00",
      endTime: "18:00",
      gross: 900,
      taxEnabled: false
    )

    let now = Date.fromDateAndTime("2026-10-31", time: "12:00") ?? Date()

    let totals = PayrollEngine.summarizeShiftTotals(
      shifts: [first, second],
      excludedShiftIds: ["exclude"],
      halfTaxMonth: nil,
      earningsMonth: 10,
      now: now
    )

    XCTAssertLessThan(abs(totals.gross - 1_000), 0.01)
    XCTAssertLessThan(abs(totals.net - 1_000), 0.01)
  }

  func testSummarizeShiftTotalsClampsInvalidTaxPercentages() {
    let overTaxed = TestFixtures.computedShift(
      id: "over-taxed",
      shiftDate: "2026-10-01",
      startTime: "08:00",
      endTime: "16:00",
      gross: 1_000,
      taxEnabled: true,
      taxPercentage: 150
    )
    let negativeTaxed = TestFixtures.computedShift(
      id: "negative-taxed",
      shiftDate: "2026-10-02",
      startTime: "08:00",
      endTime: "16:00",
      gross: 1_000,
      taxEnabled: true,
      taxPercentage: -20
    )

    let now = Date.fromDateAndTime("2026-10-31", time: "12:00") ?? Date()

    let totals = PayrollEngine.summarizeShiftTotals(
      shifts: [overTaxed, negativeTaxed],
      halfTaxMonth: nil,
      earningsMonth: 10,
      now: now
    )

    XCTAssertLessThan(abs(totals.gross - 2_000), 0.01)
    XCTAssertLessThan(abs(totals.net - 1_000), 0.01)
  }
}
