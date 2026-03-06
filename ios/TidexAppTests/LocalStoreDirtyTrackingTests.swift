import SwiftData
import XCTest

@testable import Tidex

@MainActor
final class LocalStoreDirtyTrackingTests: XCTestCase {
  private let userId = "user-1"

  private func makeStoreActor() throws -> LocalStoreActor {
    let schema = Schema([
      LocalJob.self,
      LocalUserShift.self,
      LocalRecurringShift.self,
      LocalWageSnapshot.self,
      LocalUserSettings.self,
      LocalNotificationPreferences.self,
      LocalSyncState.self,
      LocalEntitlementCache.self,
      LocalPendingJWSUpload.self,
      LocalSharedShift.self,
      LocalSharer.self,
      LocalShiftPreview.self,
      LocalSharedShiftFetchRecord.self,
      LocalConversation.self,
    ])

    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      allowsSave: true
    )

    let container = try ModelContainer(for: schema, configurations: [configuration])
    return LocalStoreActor(modelContainer: container)
  }

  private func makeDate(_ date: String, _ time: String = "00:00") -> Date {
    Date.fromDateAndTime(date, time: time) ?? Date()
  }

  func testCreateUserShiftMarksAllFieldsDirty() async throws {
    let store = try makeStoreActor()

    _ = try await store.createUserShift(
      id: "shift-1",
      userId: userId,
      jobId: "job-1",
      shiftDate: makeDate("2026-03-02"),
      startTime: "09:00",
      endTime: "17:00",
      customSupplements: nil
    )

    let localRecord = try await store.getUserShift(id: "shift-1")

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.dirtyFieldKeys, Set(UserShiftField.allCases))
  }

  func testUpdateUserShiftTracksOnlyChangedFieldsAfterClean() async throws {
    let store = try makeStoreActor()

    _ = try await store.createUserShift(
      id: "shift-2",
      userId: userId,
      jobId: "job-1",
      shiftDate: makeDate("2026-03-02"),
      startTime: "09:00",
      endTime: "17:00",
      customSupplements: nil
    )

    await store.markShiftClean(id: "shift-2")
    try await store.save()

    _ = try await store.updateUserShift(
      id: "shift-2",
      jobId: nil,
      shiftDate: nil,
      startTime: "10:00",
      endTime: nil,
      customSupplements: nil
    )

    let localRecord = try await store.getUserShift(id: "shift-2")

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.startTime, "10:00")
    XCTAssertEqual(local.dirtyFieldKeys, Set([.startTime]))
  }

  func testMarkShiftPendingDeleteSetsPendingDeleteStatus() async throws {
    let store = try makeStoreActor()

    _ = try await store.createUserShift(
      id: "shift-3",
      userId: userId,
      jobId: nil,
      shiftDate: makeDate("2026-03-02"),
      startTime: "09:00",
      endTime: "17:00",
      customSupplements: nil
    )

    _ = try await store.markShiftPendingDelete(id: "shift-3")

    let localRecord = try await store.getUserShift(id: "shift-3")

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .pendingDelete)
  }

  func testResolveStoredShiftConflictKeepServerOverwritesLocal() async throws {
    let store = try makeStoreActor()

    _ = try await store.createUserShift(
      id: "shift-4",
      userId: userId,
      jobId: "job-local",
      shiftDate: makeDate("2026-03-02"),
      startTime: "08:00",
      endTime: "16:00",
      customSupplements: nil
    )

    let serverUpdatedAt = makeDate("2026-03-04", "14:00")
    let serverSnapshot = UserShiftServerSnapshot.from(
      jobId: "job-server",
      shiftDate: "2026-03-10",
      startTime: "12:00",
      endTime: "20:00",
      customSupplements: CustomSupplementsData(
        rules: [
          CustomSupplementRule(from: "18:00", to: "20:00", rate: 40, percent: nil, isCustom: true)
        ]
      ),
      updatedAt: serverUpdatedAt,
      revision: 7,
      deletedAt: nil
    )

    await store.markShiftConflict(id: "shift-4", serverSnapshot: serverSnapshot)
    try await store.save()

    try await store.resolveStoredShiftConflictKeepServer(id: "shift-4")

    let localRecord = try await store.getUserShift(id: "shift-4")

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .clean)
    XCTAssertEqual(local.jobId, "job-server")
    XCTAssertEqual(local.shiftDateString, "2026-03-10")
    XCTAssertEqual(local.startTime, "12:00")
    XCTAssertEqual(local.endTime, "20:00")
    XCTAssertEqual(local.serverRevision, 7)
    XCTAssertEqual(local.serverUpdatedAt, serverUpdatedAt)
    XCTAssertNil(local.conflictServerSnapshot)
    XCTAssertEqual(local.dirtyFieldKeys, [])

    let syncedSnapshot = try XCTUnwrap(
      UserShiftServerSnapshot.decode(from: local.lastSyncedSnapshot))
    XCTAssertEqual(syncedSnapshot, serverSnapshot)
  }

  func testResolveStoredShiftConflictKeepLocalKeepsLocalValuesAndUpdatesServerMetadata()
    async throws
  {
    let store = try makeStoreActor()

    _ = try await store.createUserShift(
      id: "shift-5",
      userId: userId,
      jobId: "job-local",
      shiftDate: makeDate("2026-03-02"),
      startTime: "08:00",
      endTime: "16:00",
      customSupplements: nil
    )

    await store.markShiftClean(id: "shift-5")
    try await store.save()

    _ = try await store.updateUserShift(
      id: "shift-5",
      jobId: nil,
      shiftDate: nil,
      startTime: "09:30",
      endTime: nil,
      customSupplements: nil
    )

    let serverUpdatedAt = makeDate("2026-03-04", "16:00")
    let serverSnapshot = UserShiftServerSnapshot.from(
      jobId: "job-server",
      shiftDate: "2026-03-02",
      startTime: "07:00",
      endTime: "15:00",
      customSupplements: nil,
      updatedAt: serverUpdatedAt,
      revision: 9,
      deletedAt: nil
    )

    await store.markShiftConflict(id: "shift-5", serverSnapshot: serverSnapshot)
    try await store.save()

    try await store.resolveStoredShiftConflictKeepLocal(id: "shift-5")

    let localRecord = try await store.getUserShift(id: "shift-5")

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.startTime, "09:30")
    XCTAssertEqual(local.serverRevision, 9)
    XCTAssertEqual(local.serverUpdatedAt, serverUpdatedAt)
    XCTAssertNil(local.conflictServerSnapshot)
  }

  func testCreateJobMarksAllFieldsDirty() async throws {
    let store = try makeStoreActor()

    let created = try await store.createJob(
      userId: userId,
      name: "Store",
      color: "#00AA00",
      currency: "kr",
      isDefault: true,
      sortOrder: 0,
      payrollDay: 25,
      halfTaxMonth: 12,
      monthlyGoal: 30000
    )

    let localRecord = try await store.getJob(id: created.id)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.dirtyFieldKeys, Set(JobField.allCases))
  }

  func testUpdateJobMetadataTracksChangedFieldsAfterClean() async throws {
    let store = try makeStoreActor()

    let created = try await store.createJob(
      userId: userId,
      name: "Store",
      color: nil,
      currency: "kr",
      isDefault: false,
      sortOrder: 0,
      payrollDay: 25,
      halfTaxMonth: nil,
      monthlyGoal: nil
    )

    await store.markJobClean(id: created.id)
    try await store.save()

    _ = try await store.updateJobMetadata(
      id: created.id,
      name: "Store Updated",
      color: nil
    )

    let localRecord = try await store.getJob(id: created.id)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.name, "Store Updated")
    XCTAssertEqual(local.dirtyFieldKeys, Set([.name]))
  }

  func testUpdateJobMetadataTracksCurrencyChangesAfterClean() async throws {
    let store = try makeStoreActor()

    let created = try await store.createJob(
      userId: userId,
      name: "Store",
      color: nil,
      currency: "kr",
      isDefault: false,
      sortOrder: 0,
      payrollDay: 25,
      halfTaxMonth: nil,
      monthlyGoal: nil
    )

    await store.markJobClean(id: created.id)
    try await store.save()

    _ = try await store.updateJobCurrency(
      id: created.id,
      currency: "$"
    )

    let localRecord = try await store.getJob(id: created.id)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.currency, "$")
    XCTAssertEqual(local.dirtyFieldKeys, Set([.currency]))
  }

  func testMarkJobPendingDeleteMarksDeletedAtAndPendingStatus() async throws {
    let store = try makeStoreActor()

    let created = try await store.createJob(
      userId: userId,
      name: "Store",
      color: nil,
      currency: "kr",
      isDefault: true,
      sortOrder: 0,
      payrollDay: 25,
      halfTaxMonth: nil,
      monthlyGoal: nil
    )

    _ = try await store.markJobPendingDelete(id: created.id)

    let localRecord = try await store.getJob(id: created.id)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .pendingDelete)
    XCTAssertFalse(local.isDefault)
    XCTAssertNotNil(local.deletedAt)
    XCTAssertTrue(local.dirtyFieldKeys.contains(.deletedAt))
    XCTAssertTrue(local.dirtyFieldKeys.contains(.isDefault))
  }

  func testResolveStoredJobConflictKeepServerOverwritesLocal() async throws {
    let store = try makeStoreActor()

    let created = try await store.createJob(
      userId: userId,
      name: "Local Job",
      color: "#111111",
      currency: "kr",
      isDefault: false,
      sortOrder: 0,
      payrollDay: 25,
      halfTaxMonth: nil,
      monthlyGoal: 25000
    )

    let serverUpdatedAt = makeDate("2026-03-06", "12:00")
    let serverSnapshot = JobServerSnapshot(
      name: "Server Job",
      color: "#222222",
      currency: "kr",
      isDefault: true,
      sortOrder: 2,
      payrollDay: 20,
      halfTaxMonth: 11,
      monthlyGoal: 35000,
      archivedAt: nil,
      deletedAt: nil,
      updatedAt: serverUpdatedAt,
      revision: 5
    )

    await store.markJobConflict(id: created.id, serverSnapshot: serverSnapshot)
    try await store.save()

    try await store.resolveStoredJobConflictKeepServer(id: created.id)

    let localRecord = try await store.getJob(id: created.id)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .clean)
    XCTAssertEqual(local.name, "Server Job")
    XCTAssertEqual(local.color, "#222222")
    XCTAssertTrue(local.isDefault)
    XCTAssertEqual(local.sortOrder, 2)
    XCTAssertEqual(local.payrollDay, 20)
    XCTAssertEqual(local.halfTaxMonth, 11)
    XCTAssertEqual(local.monthlyGoal, 35000)
    XCTAssertEqual(local.serverRevision, 5)
    XCTAssertEqual(local.serverUpdatedAt, serverUpdatedAt)
    XCTAssertNil(local.conflictServerSnapshot)
    XCTAssertEqual(local.dirtyFieldKeys, [])

    let syncedSnapshot = try XCTUnwrap(JobServerSnapshot.decode(from: local.lastSyncedSnapshot))
    XCTAssertEqual(syncedSnapshot, serverSnapshot)
  }

  func testResolveStoredJobConflictKeepLocalKeepsLocalValuesAndUpdatesServerMetadata() async throws
  {
    let store = try makeStoreActor()

    let created = try await store.createJob(
      userId: userId,
      name: "Local Job",
      color: "#111111",
      currency: "kr",
      isDefault: false,
      sortOrder: 0,
      payrollDay: 25,
      halfTaxMonth: nil,
      monthlyGoal: nil
    )

    await store.markJobClean(id: created.id)
    try await store.save()

    _ = try await store.updateJobMetadata(
      id: created.id,
      name: "Local Edited Job",
      color: "#111111"
    )

    let serverUpdatedAt = makeDate("2026-03-06", "17:00")
    let serverSnapshot = JobServerSnapshot(
      name: "Server Job",
      color: "#222222",
      currency: "kr",
      isDefault: true,
      sortOrder: 4,
      payrollDay: 20,
      halfTaxMonth: 11,
      monthlyGoal: 40000,
      archivedAt: nil,
      deletedAt: nil,
      updatedAt: serverUpdatedAt,
      revision: 8
    )

    await store.markJobConflict(id: created.id, serverSnapshot: serverSnapshot)
    try await store.save()

    try await store.resolveStoredJobConflictKeepLocal(id: created.id)

    let localRecord = try await store.getJob(id: created.id)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.name, "Local Edited Job")
    XCTAssertEqual(local.serverRevision, 8)
    XCTAssertEqual(local.serverUpdatedAt, serverUpdatedAt)
    XCTAssertNil(local.conflictServerSnapshot)
  }

  func testCreateWageSnapshotMarksAllFieldsDirty() async throws {
    let store = try makeStoreActor()

    let created = try await store.createWageSnapshot(
      userId: userId,
      jobId: "job-1",
      fromDate: makeDate("2026-03-01"),
      hourlyWage: 215,
      wageLevel: nil,
      tariffTypeId: nil,
      supplements: SupplementRulesSnapshot(rules: []),
      taxEnabled: true,
      taxPercentage: 20,
      breakEnabled: true,
      breakMethod: "proportional",
      breakThresholdHours: 5.5,
      breakDeductionMinutes: 30
    )

    let localRecord = try await store.getWageSnapshot(id: created.id)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.dirtyFieldKeys, Set(WageSnapshotField.allCases))
  }

  func testUpdateWageSnapshotTracksChangedFieldsAfterClean() async throws {
    let store = try makeStoreActor()

    let created = try await store.createWageSnapshot(
      userId: userId,
      jobId: nil,
      fromDate: nil,
      hourlyWage: 200,
      wageLevel: nil,
      tariffTypeId: nil,
      supplements: SupplementRulesSnapshot(rules: []),
      taxEnabled: nil,
      taxPercentage: nil,
      breakEnabled: nil,
      breakMethod: nil,
      breakThresholdHours: nil,
      breakDeductionMinutes: nil
    )

    await store.markWageSnapshotClean(id: created.id)
    try await store.save()

    _ = try await store.updateWageSnapshot(
      id: created.id,
      jobId: nil,
      hourlyWage: 230,
      wageLevel: nil,
      supplements: nil,
      taxEnabled: nil,
      taxPercentage: nil,
      breakEnabled: nil,
      breakMethod: nil,
      breakThresholdHours: nil,
      breakDeductionMinutes: nil
    )

    let localRecord = try await store.getWageSnapshot(id: created.id)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.hourlyWage, 230)
    XCTAssertEqual(local.dirtyFieldKeys, Set([.hourlyWage]))
  }

  func testMarkWageSnapshotPendingDeleteSetsPendingDeleteStatus() async throws {
    let store = try makeStoreActor()

    let created = try await store.createWageSnapshot(
      userId: userId,
      jobId: nil,
      fromDate: nil,
      hourlyWage: 200,
      wageLevel: nil,
      tariffTypeId: nil,
      supplements: SupplementRulesSnapshot(rules: []),
      taxEnabled: nil,
      taxPercentage: nil,
      breakEnabled: nil,
      breakMethod: nil,
      breakThresholdHours: nil,
      breakDeductionMinutes: nil
    )

    try await store.markWageSnapshotPendingDelete(id: created.id)

    let localRecord = try await store.getWageSnapshot(id: created.id)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .pendingDelete)
  }

  func testResolveStoredWageSnapshotConflictKeepServerOverwritesLocal() async throws {
    let store = try makeStoreActor()

    let created = try await store.createWageSnapshot(
      userId: userId,
      jobId: "job-local",
      fromDate: makeDate("2026-03-01"),
      hourlyWage: 200,
      wageLevel: nil,
      tariffTypeId: nil,
      supplements: SupplementRulesSnapshot(rules: []),
      taxEnabled: true,
      taxPercentage: 20,
      breakEnabled: true,
      breakMethod: "proportional",
      breakThresholdHours: 5.5,
      breakDeductionMinutes: 30
    )

    let serverUpdatedAt = makeDate("2026-03-09", "10:00")
    let serverSnapshot = WageSnapshotServerSnapshot(
      jobId: "job-server",
      fromDate: "2026-03-15",
      hourlyWage: 260,
      wageLevel: 4,
      tariffTypeId: "hk_retail",
      supplements: try canonicalJSONEncoder.encode(
        SupplementRulesSnapshot(
          rules: [SupplementRule(days: [1], from: "18:00", to: "24:00", rate: 22)]
        )
      ),
      taxEnabled: false,
      taxPercentage: 0,
      breakEnabled: false,
      breakMethod: "none",
      breakThresholdHours: 6.0,
      breakDeductionMinutes: 0,
      updatedAt: serverUpdatedAt,
      revision: 11,
      deletedAt: nil
    )

    await store.markWageSnapshotConflict(id: created.id, serverSnapshot: serverSnapshot)
    try await store.save()

    try await store.resolveStoredWageSnapshotConflictKeepServer(id: created.id)

    let localRecord = try await store.getWageSnapshot(id: created.id)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .clean)
    XCTAssertEqual(local.jobId, "job-server")
    XCTAssertEqual(local.fromDateString, "2026-03-15")
    XCTAssertEqual(local.hourlyWage, 260)
    XCTAssertEqual(local.wageLevel, 4)
    XCTAssertEqual(local.tariffTypeId, "hk_retail")
    XCTAssertEqual(local.taxEnabled, false)
    XCTAssertEqual(local.taxPercentage, 0)
    XCTAssertEqual(local.breakEnabled, false)
    XCTAssertEqual(local.breakMethod, "none")
    XCTAssertEqual(local.breakThresholdHours, 6.0)
    XCTAssertEqual(local.breakDeductionMinutes, 0)
    XCTAssertEqual(local.serverRevision, 11)
    XCTAssertEqual(local.serverUpdatedAt, serverUpdatedAt)
    XCTAssertNil(local.conflictServerSnapshot)
    XCTAssertEqual(local.dirtyFieldKeys, [])

    let syncedSnapshot = try XCTUnwrap(
      WageSnapshotServerSnapshot.decode(from: local.lastSyncedSnapshot)
    )
    XCTAssertEqual(syncedSnapshot, serverSnapshot)
  }

  func testCreateUserSettingsMarksExpectedInitialDirtyFields() async throws {
    let store = try makeStoreActor()

    _ = try await store.createUserSettings(
      userId: userId,
      payrollDay: 25,
      currency: "NOK",
      theme: "dark",
      calendarAnimationStyle: "vertical",
      showDashboardClockButtons: false,
      monthlyGoal: 30000,
      monthlyGoalsByMonth: ["2026-03": 32000],
      defaultShiftsView: "list",
      halfTaxMonth: 12,
      defaultStartupTab: "stats"
    )

    let localRecord = try await store.getUserSettings(userId: userId)

    let local = try XCTUnwrap(localRecord)

    let expected: Set<UserSettingsField> = [
      .theme,
      .calendarAnimationStyle,
      .showDashboardClockButtons,
      .lastActive,
      .payrollDay,
      .currency,
      .monthlyGoal,
      .monthlyGoalsByMonth,
      .defaultShiftsView,
      .halfTaxMonth,
      .defaultStartupTab,
    ]

    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.dirtyFieldKeys, expected)
  }

  func testUpdateUserSettingsMarksThemeDirtyEvenWhenValueIsUnchanged() async throws {
    let store = try makeStoreActor()

    _ = try await store.createUserSettings(
      userId: userId,
      payrollDay: nil,
      currency: nil,
      theme: "dark"
    )

    await store.markUserSettingsClean(userId: userId)
    try await store.save()

    _ = try await store.updateUserSettings(
      userId: userId,
      monthlyGoal: nil,
      monthlyGoalsByMonth: nil,
      defaultShiftsView: nil,
      profilePictureUrl: nil,
      payrollDay: nil,
      theme: "dark",
      calendarAnimationStyle: nil,
      showDashboardClockButtons: nil,
      halfTaxMonth: nil,
      currency: nil,
      defaultStartupTab: nil
    )

    let localRecord = try await store.getUserSettings(userId: userId)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.theme, "dark")
    XCTAssertEqual(local.dirtyFieldKeys, Set([.theme]))
  }

  func testResolveStoredUserSettingsConflictKeepServerOverwritesLocal() async throws {
    let store = try makeStoreActor()

    _ = try await store.createUserSettings(
      userId: userId,
      payrollDay: 25,
      currency: "NOK",
      theme: "dark",
      calendarAnimationStyle: "vertical",
      showDashboardClockButtons: false,
      monthlyGoal: 30000,
      monthlyGoalsByMonth: ["2026-03": 32000],
      defaultShiftsView: "list",
      halfTaxMonth: 12,
      defaultStartupTab: "stats"
    )

    let serverUpdatedAt = makeDate("2026-03-08", "11:00")
    let serverSnapshot = UserSettingsServerSnapshot(
      monthlyGoal: 42000,
      monthlyGoalsByMonth: ["2026-03": 43000],
      defaultShiftsView: "calendar",
      profilePictureUrl: "https://tidex.no/avatar.png",
      payrollDay: 20,
      theme: "light",
      calendarAnimationStyle: "horizontal",
      showDashboardClockButtons: true,
      halfTaxMonth: nil,
      currency: "SEK",
      defaultStartupTab: "home",
      lastActive: serverUpdatedAt,
      updatedAt: serverUpdatedAt,
      revision: 12
    )

    await store.markUserSettingsConflict(userId: userId, serverSnapshot: serverSnapshot)
    try await store.save()

    try await store.resolveStoredUserSettingsConflictKeepServer(userId: userId)

    let localRecord = try await store.getUserSettings(userId: userId)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .clean)
    XCTAssertEqual(local.monthlyGoal, 42000)
    XCTAssertEqual(local.monthlyGoalsByMonth, ["2026-03": 43000])
    XCTAssertEqual(local.defaultShiftsView, "calendar")
    XCTAssertEqual(local.profilePictureUrl, "https://tidex.no/avatar.png")
    XCTAssertEqual(local.payrollDay, 20)
    XCTAssertEqual(local.theme, "light")
    XCTAssertEqual(local.calendarAnimationStyle, "horizontal")
    XCTAssertEqual(local.showDashboardClockButtons, true)
    XCTAssertNil(local.halfTaxMonth)
    XCTAssertEqual(local.currency, "SEK")
    XCTAssertEqual(local.defaultStartupTab, "home")
    XCTAssertEqual(local.lastActive, serverUpdatedAt)
    XCTAssertEqual(local.serverRevision, 12)
    XCTAssertEqual(local.serverUpdatedAt, serverUpdatedAt)
    XCTAssertNil(local.conflictServerSnapshot)
    XCTAssertEqual(local.dirtyFieldKeys, [])

    let syncedSnapshot = try XCTUnwrap(
      UserSettingsServerSnapshot.decode(from: local.lastSyncedSnapshot))
    XCTAssertEqual(syncedSnapshot, serverSnapshot)
  }

  func testResolveStoredUserSettingsConflictKeepLocalKeepsLocalValuesAndUpdatesServerMetadata()
    async throws
  {
    let store = try makeStoreActor()

    _ = try await store.createUserSettings(
      userId: userId,
      payrollDay: 25,
      currency: "NOK",
      theme: "dark"
    )

    await store.markUserSettingsClean(userId: userId)
    try await store.save()

    _ = try await store.updateUserSettings(
      userId: userId,
      monthlyGoal: nil,
      monthlyGoalsByMonth: nil,
      defaultShiftsView: nil,
      profilePictureUrl: nil,
      payrollDay: nil,
      theme: "dark",
      calendarAnimationStyle: nil,
      showDashboardClockButtons: nil,
      halfTaxMonth: nil,
      currency: "NOK",
      defaultStartupTab: nil
    )

    let serverUpdatedAt = makeDate("2026-03-08", "18:00")
    let serverSnapshot = UserSettingsServerSnapshot(
      monthlyGoal: 45000,
      monthlyGoalsByMonth: [:],
      defaultShiftsView: "calendar",
      profilePictureUrl: nil,
      payrollDay: 20,
      theme: "light",
      calendarAnimationStyle: "horizontal",
      showDashboardClockButtons: true,
      halfTaxMonth: nil,
      currency: "SEK",
      defaultStartupTab: "home",
      lastActive: serverUpdatedAt,
      updatedAt: serverUpdatedAt,
      revision: 14
    )

    await store.markUserSettingsConflict(userId: userId, serverSnapshot: serverSnapshot)
    try await store.save()

    try await store.resolveStoredUserSettingsConflictKeepLocal(userId: userId)

    let localRecord = try await store.getUserSettings(userId: userId)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.theme, "dark")
    XCTAssertEqual(local.currency, "NOK")
    XCTAssertEqual(local.serverRevision, 14)
    XCTAssertEqual(local.serverUpdatedAt, serverUpdatedAt)
    XCTAssertNil(local.conflictServerSnapshot)
  }
}
