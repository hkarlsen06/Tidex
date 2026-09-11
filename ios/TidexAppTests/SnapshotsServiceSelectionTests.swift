import XCTest

@testable import Tidex

final class SnapshotsServiceSelectionTests: XCTestCase {
  func testSupplementDescriptionsPreserveAgreedDecimalRatesAndCurrencyPlacement() {
    let rule = OnboardingSupplementRule(
      from: SupplementRule(
        days: [1], from: "18:00", to: "21:00", rate: 11.25))
    XCTAssertTrue(
      rule.valueDescription(locale: Locale(identifier: "en_US"), currency: "$")
        .hasPrefix("+$11.25"))
    XCTAssertTrue(
      rule.valueDescription(locale: Locale(identifier: "nb_NO"), currency: "kr")
        .hasPrefix("+11,25 kr"))
    let percent = OnboardingSupplementRule(
      from: SupplementRule(
        days: [1], from: "18:00", to: "21:00", percent: 12.5))
    XCTAssertEqual(percent.valueDescription(locale: Locale(identifier: "en_US")), "+12.5%")
  }

  func testEditingAnExistingNoDeductionMethodKeepsBreakDeductionOff() {
    let snapshot = TestFixtures.wageSnapshot(breakEnabled: true, breakMethod: "none")
    var edit = WageSnapshotEditorInput(from: snapshot)
    edit.taxPercentage = 25
    let inherited = WageSnapshotEditorInput(prefillFrom: snapshot)

    XCTAssertFalse(edit.breakEnabled)
    XCTAssertEqual(edit.breakMethod, .none)
    XCTAssertFalse(inherited.breakEnabled)
    XCTAssertEqual(inherited.breakMethod, .none)
  }

  func testNewPayChangeInheritsSettingsForItsDateAndNotAFutureRaise() throws {
    let baseline = TestFixtures.wageSnapshot(hourlyWage: 200, taxEnabled: true, taxPercentage: 20)
    let future = TestFixtures.wageSnapshot(
      fromDate: "2026-12-01", hourlyWage: 250,
      taxEnabled: true, taxPercentage: 30)
    let date = try XCTUnwrap(Date.fromISODateString("2026-09-10"))
    let input = WageSnapshotEditorInput(effectiveDate: date, snapshots: [future, baseline])

    XCTAssertEqual(input.hourlyWage, 200)
    XCTAssertEqual(input.taxPercentage, 20)
    XCTAssertEqual(input.fromDate?.toISODateString(), "2026-09-10")
  }

  func testMovingNewChangeRebasesUneditedInputsAndKeepsTheUsersRaise() {
    let older = TestFixtures.wageSnapshot(hourlyWage: 200, taxEnabled: true, taxPercentage: 20)
    let newer = TestFixtures.wageSnapshot(
      fromDate: "2026-08-01", hourlyWage: 220,
      supplements: [SupplementRule(days: [1], from: "18:00", to: "21:00", rate: 30)],
      taxEnabled: true, taxPercentage: 30, breakEnabled: false)
    var draft = WageSnapshotEditorInput(from: newer)
    draft.hourlyWage = 240

    let rebased = draft.rebasingUneditedSettings(from: newer, onto: older)

    XCTAssertEqual(rebased.hourlyWage, 240)
    XCTAssertEqual(rebased.taxPercentage, 20)
    XCTAssertEqual(rebased.supplements, older.supplements)
    XCTAssertTrue(rebased.breakEnabled)
  }

  func testMovingNewChangePreservesEditedTaxBreakAndOvertimeSettings() {
    let original = TestFixtures.wageSnapshot(hourlyWage: 200)
    let next = TestFixtures.wageSnapshot(hourlyWage: 220, taxPercentage: 30)
    var draft = WageSnapshotEditorInput(from: original)
    draft.taxEnabled = true
    draft.taxPercentage = 25
    draft.breakDeductionMinutes = 45
    draft.overtime = .seededDefaults

    let rebased = draft.rebasingUneditedSettings(from: original, onto: next)

    XCTAssertEqual(rebased.hourlyWage, 220)
    XCTAssertTrue(rebased.taxEnabled)
    XCTAssertEqual(rebased.taxPercentage, 25)
    XCTAssertEqual(rebased.breakDeductionMinutes, 45)
    XCTAssertEqual(rebased.overtime, .seededDefaults)
  }

  func testPayReviewUsesWorkDateForWagesAndClampedNextMonthPaydayForTax() throws {
    let baseline = TestFixtures.wageSnapshot(
      id: "baseline", hourlyWage: 200,
      taxEnabled: true, taxPercentage: 20)
    let taxChange = TestFixtures.wageSnapshot(
      id: "february", fromDate: "2026-02-01",
      hourlyWage: 250, taxEnabled: true, taxPercentage: 30)
    let context = PaySettingsContext(
      workDate: try XCTUnwrap(Date.fromISODateString("2026-01-31")),
      snapshots: [taxChange, baseline], payrollDay: 31, halfTaxMonth: nil)

    XCTAssertEqual(context.wageSnapshot?.id, "baseline")
    XCTAssertEqual(context.taxSnapshot?.id, "february")
    XCTAssertEqual(context.taxDate, "2026-02-28")
    XCTAssertEqual(context.effectiveTaxPercentage, 30)
  }

  func testPayReviewExplainsHalfTaxAndMissingCoverage() throws {
    let date = try XCTUnwrap(Date.fromISODateString("2026-11-30"))
    let snapshot = TestFixtures.wageSnapshot(taxEnabled: true, taxPercentage: 30)
    let context = PaySettingsContext(
      workDate: date, snapshots: [snapshot],
      payrollDay: 15, halfTaxMonth: 12)
    XCTAssertTrue(context.appliesHalfTax)
    XCTAssertEqual(context.effectiveTaxPercentage, 15)

    let missing = PaySettingsContext(
      workDate: date, snapshots: [],
      payrollDay: 15, halfTaxMonth: nil)
    XCTAssertNil(missing.wageSnapshot)
    XCTAssertNil(missing.taxSnapshot)
    XCTAssertEqual(missing.effectiveTaxPercentage, 0)
  }

  func testTimelineShowsChangesWhenWageAndRuleCountAreUnchanged() throws {
    let baseline = TestFixtures.wageSnapshot(
      id: "baseline",
      supplements: [
        SupplementRule(days: [1], from: "18:00", to: "21:00", rate: 20)
      ])
    let changed = TestFixtures.wageSnapshot(
      id: "changed", fromDate: "2026-08-01",
      supplements: [SupplementRule(days: [1], from: "17:00", to: "21:00", rate: 30)],
      breakThresholdHours: 6, breakDeductionMinutes: 45, overtime: .seededDefaults)
    let future = TestFixtures.wageSnapshot(id: "future", fromDate: "2026-12-01", hourlyWage: 250)
    let entries = WageTimelineProcessor.processSnapshots(
      [baseline, future, changed], locale: Locale(identifier: "en_US"), currency: "$",
      today: try XCTUnwrap(Date.fromISODateString("2026-09-01")))

    XCTAssertEqual(entries.map(\.id), ["future", "changed", "baseline"])
    XCTAssertEqual(entries[0].type, .future)
    XCTAssertEqual(entries[1].type, .current)
    XCTAssertEqual(entries[2].type, .past)
    XCTAssertEqual(entries[1].endDate, "2026-11-30")
    XCTAssertTrue(entries[1].dateRange.contains("Nov"))
    XCTAssertTrue(entries[1].changes.contains { $0.type == .supplements })
    XCTAssertTrue(entries[1].changes.contains { $0.type == .breaks })
    XCTAssertTrue(entries[1].changes.contains { $0.type == .overtime })
  }

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

  func testSnapshotForDateIncludesExactBoundaryAndIgnoresFutureSnapshots() {
    let current = TestFixtures.wageSnapshot(id: "current", fromDate: "2026-01-01")
    let future = TestFixtures.wageSnapshot(id: "future", fromDate: "2026-02-01")

    XCTAssertEqual(
      SnapshotsService.snapshotForDate("2026-01-01", from: [future, current])?.id,
      "current"
    )
  }

  func testSnapshotForDateKeepsLastDuplicateDateAndFirstBaseline() {
    let firstBaseline = TestFixtures.wageSnapshot(id: "first-baseline")
    let secondBaseline = TestFixtures.wageSnapshot(id: "second-baseline")
    let first = TestFixtures.wageSnapshot(id: "first", fromDate: "2026-01-01")
    let last = TestFixtures.wageSnapshot(id: "last", fromDate: "2026-01-01")
    let older = TestFixtures.wageSnapshot(id: "older", fromDate: "2025-12-01")
    let snapshots = [first, firstBaseline, last, older, secondBaseline]

    XCTAssertEqual(
      SnapshotsService.snapshotForDate("2026-01-01", from: snapshots)?.id,
      "last"
    )
    XCTAssertEqual(
      SnapshotsService.snapshotForDate("2025-11-30", from: snapshots)?.id,
      "first-baseline"
    )
  }

  func testSnapshotForDateReturnsNilWithoutApplicableSnapshot() {
    let future = TestFixtures.wageSnapshot(id: "future", fromDate: "2026-02-01")

    XCTAssertNil(SnapshotsService.snapshotForDate("2026-01-01", from: [future]))
    XCTAssertNil(SnapshotsService.snapshotForDate("2026-01-01", from: []))
  }
}
