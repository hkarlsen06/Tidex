import XCTest

@testable import Tidex

final class HomeScheduleLoadingHelperTests: XCTestCase {
  func testShiftChangePayloadParsesTargetedMonthsFromPrimitiveUserInfo() throws {
    let may: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 5)
    )
    let june: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 6)
    )
    let notification = Notification(
      name: .shiftsDidChange,
      object: nil,
      userInfo: [
        ShiftChangeNotificationPayload.affectedMonthsUserInfoKey: [
          ["year": 2_026, "month": 5]
        ],
        ShiftChangeNotificationPayload.affectedDatesUserInfoKey: [
          "2026-06-01",
          "2026-06-18",
        ],
        ShiftChangeNotificationPayload.requiresFullReloadUserInfoKey: false,
      ]
    )

    let payload = ShiftChangeNotificationPayload.parse(from: notification)

    XCTAssertFalse(payload.requiresFullReload)
    XCTAssertTrue(payload.canUseTargetedInvalidation)
    XCTAssertEqual(payload.affectedMonths, [may, june])
  }

  func testShiftChangePayloadFallsBackToFullReloadWithoutUsableMonthMetadata() {
    let notification = Notification(name: .shiftsDidChange)

    let payload = ShiftChangeNotificationPayload.parse(from: notification)

    XCTAssertTrue(payload.requiresFullReload)
    XCTAssertFalse(payload.canUseTargetedInvalidation)
    XCTAssertTrue(payload.affectedMonths.isEmpty)
  }

  func testShiftChangePayloadPreservesExplicitFullReload() throws {
    let may: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 5)
    )
    let notification = Notification(
      name: .shiftsDidChange,
      object: nil,
      userInfo: ShiftChangeNotificationPayload.userInfo(
        affectedMonths: [may],
        requiresFullReload: true
      )
    )

    let payload = ShiftChangeNotificationPayload.parse(from: notification)

    XCTAssertTrue(payload.requiresFullReload)
    XCTAssertFalse(payload.canUseTargetedInvalidation)
    XCTAssertEqual(payload.affectedMonths, [may])
  }

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

  func testLoadingGateDefersHiddenMonthChangesAndLoadsLatestWhenVisible() throws {
    let may: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 5)
    )
    let june: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 6)
    )
    var gate: HomeScheduleMonthLoadingGate = .init(isVisible: false)

    XCTAssertEqual(gate.monthDidChange(to: may), .deferUntilVisible(may))
    XCTAssertEqual(gate.pendingMonth, may)
    XCTAssertEqual(gate.monthDidChange(to: june), .deferUntilVisible(june))
    XCTAssertEqual(gate.pendingMonth, june)

    XCTAssertEqual(gate.setVisible(true), .loadNow(june))
    XCTAssertNil(gate.pendingMonth)
    XCTAssertEqual(gate.setVisible(true), .none)
  }

  func testLoadingGateOnlyReloadsVisibleCurrentMonthForTargetedPayload() throws {
    let may: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 5)
    )
    let june: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 6)
    )
    var gate: HomeScheduleMonthLoadingGate = .init(isVisible: true)

    XCTAssertEqual(
      gate.dataDidChange(
        payload: ShiftChangeNotificationPayload(affectedMonths: [june]),
        currentMonth: may
      ),
      .none
    )
    XCTAssertEqual(
      gate.dataDidChange(
        payload: ShiftChangeNotificationPayload(affectedMonths: [may]),
        currentMonth: may
      ),
      .loadNow(may)
    )
  }

  func testLoadingGateDefersFullReloadWhileHidden() throws {
    let may: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 5)
    )
    var gate: HomeScheduleMonthLoadingGate = .init(isVisible: false)

    XCTAssertEqual(
      gate.dataDidChange(payload: .fullReload, currentMonth: may),
      .deferUntilVisible(may)
    )
    XCTAssertEqual(gate.setVisible(true), .loadNow(may))
  }

  func testDashboardDependencyIncludesDisplayedAndPreviousMonthsOnly() throws {
    let april: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 4)
    )
    let may: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 5)
    )
    let june: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 6)
    )

    XCTAssertTrue(
      HomeScheduleAffectedMonthResolver.dashboardDisplayedMonthDepends(
        on: [april],
        displayYear: 2_026,
        displayMonth: 5
      )
    )
    XCTAssertTrue(
      HomeScheduleAffectedMonthResolver.dashboardDisplayedMonthDepends(
        on: [may],
        displayYear: 2_026,
        displayMonth: 5
      )
    )
    XCTAssertFalse(
      HomeScheduleAffectedMonthResolver.dashboardDisplayedMonthDepends(
        on: [june],
        displayYear: 2_026,
        displayMonth: 5
      )
    )
    // A 16th-to-15th period paid the month after reaches two months back.
    XCTAssertTrue(
      HomeScheduleAffectedMonthResolver.dashboardDisplayedMonthDepends(
        on: [try XCTUnwrap(ShiftChangeAffectedMonth(year: 2_026, month: 3))],
        displayYear: 2_026,
        displayMonth: 5
      )
    )
    XCTAssertFalse(
      HomeScheduleAffectedMonthResolver.dashboardDisplayedMonthDepends(
        on: [try XCTUnwrap(ShiftChangeAffectedMonth(year: 2_026, month: 2))],
        displayYear: 2_026,
        displayMonth: 5
      )
    )
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

  internal func testSyncSummaryIgnoresUnrelatedAndPushOnlyChanges() {
    let unrelatedPull = syncSummary(
      tableResults: [pullResult(table: .notificationPreferences, rowsProcessed: 1)]
    )
    XCTAssertNil(unrelatedPull.dashboardChangeContext)
    XCTAssertNil(unrelatedPull.scheduleChangeContext)

    let pushOnly = syncSummary(
      pushResults: [TablePushResult(table: .userShifts, rowsPushed: 1, newConflicts: 0, rebased: 0)]
    )
    XCTAssertNil(pushOnly.dashboardChangeContext)
    XCTAssertNil(pushOnly.scheduleChangeContext)
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

  func testSyncSummaryFallsBackToFullReloadForBroadRelevantTables() {
    let summary = syncSummary(
      tableResults: [pullResult(table: .userSettings, rowsProcessed: 1)]
    )

    XCTAssertEqual(summary.dashboardChangeContext, .fullReload)
    XCTAssertEqual(summary.scheduleChangeContext, .fullReload)
  }

  func testSyncSummaryScopesPayrollAdjustmentsToDashboard() throws {
    let may: ShiftChangeAffectedMonth = try XCTUnwrap(
      ShiftChangeAffectedMonth(year: 2_026, month: 5)
    )
    let summary = syncSummary(
      tableResults: [
        pullResult(table: .payrollAdjustments, rowsProcessed: 1, affectedMonths: [may])
      ]
    )

    XCTAssertEqual(summary.dashboardChangeContext, .affecting(months: [may]))
    XCTAssertNil(summary.scheduleChangeContext)
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
