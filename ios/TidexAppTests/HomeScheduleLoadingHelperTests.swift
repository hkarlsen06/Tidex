import XCTest

@testable import Tidex

final class HomeScheduleLoadingHelperTests: XCTestCase {

  func testShiftChangeContextBuildsAllAffectedMonthsForDateRange() throws {
    let january: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 1)
    )
    let february: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 2)
    )
    let march: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 3)
    )

    let context = ShiftChangeContext.affecting(
      isoDateRangeStart: "2026-01-31",
      end: "2026-03-01"
    )

    XCTAssertFalse(context.requiresFullReload)
    XCTAssertEqual(context.affectedMonths, [january, february, march])
  }

  func testDashboardDependencyIncludesDisplayedAndPreviousMonthsOnly() throws {
    func dependsOn(month: Int) throws -> Bool {
      HomeScheduleAffectedMonthResolver.dashboardDisplayedMonthDepends(
        on: [try XCTUnwrap(ShiftChangeAffectedMonth(year: 2_026, month: month))],
        displayYear: 2_026,
        displayMonth: 5
      )
    }

    XCTAssertTrue(try dependsOn(month: 4))
    XCTAssertTrue(try dependsOn(month: 5))
    XCTAssertFalse(try dependsOn(month: 6))
    // A 16th-to-15th period paid the month after reaches two months back.
    XCTAssertTrue(try dependsOn(month: 3))
    XCTAssertFalse(try dependsOn(month: 2))
  }

  func testScheduleInvalidatesAffectedMonthAndAdjacentDisplayMonths() throws {
    let april: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 4)
    )
    let may: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 5)
    )
    let june: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 6)
    )

    let affectedDisplayMonths = HomeScheduleAffectedMonthResolver.scheduleDisplayMonthsAffected(
      by: [may]
    )

    XCTAssertEqual(affectedDisplayMonths, [april, may, june])
  }

  func testSyncSummaryBuildsTargetedContextsForDatedTables() throws {
    let may: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 5)
    )
    let summary = syncSummary(
      tableResults: [
        pullResult(table: .userShifts, rowsProcessed: 1, affectedMonths: [may])
      ]
    )

    XCTAssertEqual(summary.dashboardChangeContext, .affecting(months: [may]))
    XCTAssertEqual(summary.scheduleChangeContext, .affecting(months: [may]))
  }

  private func syncSummary(
    tableResults: [TablePullResult] = [],
    pushResults: [TablePushResult] = []
  ) -> SyncCompletionSummary {
    SyncCompletionSummary(
      reason: .foreground,
      userId: "user-1",
      tableResults: tableResults,
      pushResults: pushResults
    )
  }

  private func pullResult(
    table: SyncTable,
    rowsProcessed: Int,
    affectedMonths: Set<ShiftChangeAffectedMonth> = []
  ) -> TablePullResult {
    TablePullResult(
      table: table,
      rowsProcessed: rowsProcessed,
      lastUpdatedAt: nil,
      lastUpdatedAtTieId: nil,
      maxRevision: 0,
      newConflicts: 0,
      autoMerged: 0,
      affectedMonths: affectedMonths
    )
  }
}
