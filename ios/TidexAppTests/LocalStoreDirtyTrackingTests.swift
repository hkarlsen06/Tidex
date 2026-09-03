import Nimble
import SwiftData
import XCTest

@testable import Tidex

@MainActor
internal final class LocalStoreDirtyTrackingTests: XCTestCase {
  private let userId: String = "user-1"

  private func makeStoreActor() throws -> LocalStoreActor {
    let schema: _ = Schema([
      LocalJob.self,
      LocalUserShift.self,
      LocalEvent.self,
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

    let configuration: _ = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      allowsSave: true
    )

    let container: _ = try ModelContainer(for: schema, configurations: [configuration])
    return LocalStoreActor(modelContainer: container)
  }

  private func makeDate(_ date: String, _ time: String = "00:00") -> Date {
    Date.fromDateAndTime(date, time: time) ?? Date()
  }

  internal func testCreateUserShiftMarksAllFieldsDirty() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createUserShift(
      id: "shift-1",
      userId: userId,
      jobId: "job-1",
      shiftDate: makeDate("2026-03-02"),
      startTime: "09:00",
      endTime: "17:00",
      customSupplements: nil
    )

    let localRecord: _ = try await store.getUserShift(id: "shift-1")

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.dirtyFieldKeys) == Set(UserShiftField.allCases)
  }

  internal func testUpdateUserShiftTracksOnlyChangedFieldsAfterClean() async throws {
    let store: _ = try makeStoreActor()

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

    let localRecord: _ = try await store.getUserShift(id: "shift-2")

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.startTime) == "10:00"
    expect(local.dirtyFieldKeys) == Set([.startTime])
  }

  internal func testUpdateUserShiftCustomPauseWindowsMarksOnlyPauseFieldDirty() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createUserShift(
      id: "shift-pause-1",
      userId: userId,
      jobId: "job-1",
      shiftDate: makeDate("2026-03-02"),
      startTime: "09:00",
      endTime: "17:00",
      customSupplements: nil
    )

    await store.markShiftClean(id: "shift-pause-1")
    try await store.save()

    _ = try await store.updateUserShiftCustomPauseWindows(
      id: "shift-pause-1",
      customPauseWindows: CustomPauseWindows(windows: [
        PauseWindow(start: "12:00", end: "12:30")
      ])
    )

    let localRecord: _ = try await store.getUserShift(id: "shift-pause-1")
    let local: _ = try XCTUnwrap(localRecord)

    expect(local.syncStatus) == .dirty
    expect(local.dirtyFieldKeys) == Set([.customPauseWindows])
    expect(local.decodedCustomPauseWindows)
      == CustomPauseWindows(
        windows: [PauseWindow(start: "12:00", end: "12:30")]
      )
  }

  internal func testMarkShiftPendingDeleteSetsPendingDeleteStatus() async throws {
    let store: _ = try makeStoreActor()

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

    let localRecord: _ = try await store.getUserShift(id: "shift-3")

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .pendingDelete
  }

  internal func testResolveStoredShiftConflictKeepServerOverwritesLocal() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createUserShift(
      id: "shift-4",
      userId: userId,
      jobId: "job-local",
      shiftDate: makeDate("2026-03-02"),
      startTime: "08:00",
      endTime: "16:00",
      customSupplements: nil
    )

    let serverUpdatedAt: _ = makeDate("2026-03-04", "14:00")
    let serverSnapshot: _ = UserShiftServerSnapshot.from(
      jobId: "job-server",
      shiftDate: "2026-03-10",
      startTime: "12:00",
      endTime: "20:00",
      note: "Server note",
      customPauseWindows: nil,
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

    let localRecord: _ = try await store.getUserShift(id: "shift-4")

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .clean
    expect(local.jobId) == "job-server"
    expect(local.shiftDateString) == "2026-03-10"
    expect(local.startTime) == "12:00"
    expect(local.endTime) == "20:00"
    expect(local.note) == "Server note"
    expect(local.serverRevision) == 7
    expect(local.serverUpdatedAt) == serverUpdatedAt
    expect(local.conflictServerSnapshot) == nil
    expect(local.dirtyFieldKeys.isEmpty) == true

    let syncedSnapshot: _ = try XCTUnwrap(
      UserShiftServerSnapshot.decode(from: local.lastSyncedSnapshot)
    )
    expect(syncedSnapshot) == serverSnapshot
  }

  internal func testResolveStoredShiftConflictKeepLocalKeepsLocalValuesAndUpdatesServerMetadata()
    async throws
  {
    let store: _ = try makeStoreActor()

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

    let serverUpdatedAt: _ = makeDate("2026-03-04", "16:00")
    let serverSnapshot: _ = UserShiftServerSnapshot.from(
      jobId: "job-server",
      shiftDate: "2026-03-02",
      startTime: "07:00",
      endTime: "15:00",
      note: "Server note",
      customPauseWindows: nil,
      customSupplements: nil,
      updatedAt: serverUpdatedAt,
      revision: 9,
      deletedAt: nil
    )

    await store.markShiftConflict(id: "shift-5", serverSnapshot: serverSnapshot)
    try await store.save()

    try await store.resolveStoredShiftConflictKeepLocal(id: "shift-5")

    let localRecord: _ = try await store.getUserShift(id: "shift-5")

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.startTime) == "09:30"
    expect(local.note) == nil
    expect(local.serverRevision) == 9
    expect(local.serverUpdatedAt) == serverUpdatedAt
    expect(local.conflictServerSnapshot) == nil
  }

  internal func testUpdateUserShiftNoteMarksOnlyNoteDirty() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createUserShift(
      id: "shift-note-1",
      userId: userId,
      jobId: "job-1",
      shiftDate: makeDate("2026-03-02"),
      startTime: "09:00",
      endTime: "17:00",
      note: nil,
      customSupplements: nil
    )

    await store.markShiftClean(id: "shift-note-1")
    try await store.save()

    _ = try await store.updateUserShift(
      id: "shift-note-1",
      jobId: nil,
      shiftDate: nil,
      startTime: nil,
      endTime: nil,
      note: " Dentist ",
      noteWasEdited: true,
      customSupplements: nil
    )

    let localRecord: _ = try await store.getUserShift(id: "shift-note-1")
    let local: _ = try XCTUnwrap(localRecord)
    expect(local.note) == "Dentist"
    expect(local.dirtyFieldKeys) == Set([.note])
  }

  internal func testUpdateUserShiftNoteCanBeClearedExplicitly() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createUserShift(
      id: "shift-note-2",
      userId: userId,
      jobId: "job-1",
      shiftDate: makeDate("2026-03-02"),
      startTime: "09:00",
      endTime: "17:00",
      note: "Trip",
      customSupplements: nil
    )

    await store.markShiftClean(id: "shift-note-2")
    try await store.save()

    _ = try await store.updateUserShift(
      id: "shift-note-2",
      jobId: nil,
      shiftDate: nil,
      startTime: nil,
      endTime: nil,
      note: "   ",
      noteWasEdited: true,
      customSupplements: nil
    )

    let localRecord: _ = try await store.getUserShift(id: "shift-note-2")
    let local: _ = try XCTUnwrap(localRecord)
    expect(local.note) == nil
    expect(local.dirtyFieldKeys) == Set([.note])
  }

  internal func testAddRecurringShiftExclusionsAddsMultipleDatesInSingleMutation() async throws {
    let store: _ = try makeStoreActor()

    let created: _ = try await store.createRecurringShift(
      userId: userId,
      jobId: "job-1",
      startTime: "09:00",
      endTime: "17:00",
      repeatIntervalWeeks: 1,
      selectedDays: ["1": "2026-03-02"],
      endCondition: nil,
      exclusions: ["2026-03-09"],
      dateSpecificPauseWindows: nil,
      dateSpecificSupplements: nil,
      dateSpecificNotes: nil
    )

    await store.markRecurringShiftClean(id: created.id)
    try await store.save()

    let addedCount: _ = try await store.addRecurringShiftExclusions(
      id: created.id,
      dates: ["2026-03-16", "2026-03-23", "2026-03-16"]
    )

    let localRecord: _ = try await store.getRecurringShift(id: created.id)
    let local: _ = try XCTUnwrap(localRecord)
    expect(addedCount) == 2
    expect(local.decodedExclusions) == ["2026-03-09", "2026-03-16", "2026-03-23"]
    expect(local.syncStatus) == .dirty
    expect(local.dirtyFieldKeys) == Set([.exclusions])
  }

  internal func testUpdateRecurringShiftEndConditionPreservesOverrides() async throws {
    let store: _ = try makeStoreActor()
    let supplements: _ = [
      "2026-03-16": CustomSupplementsData(
        rules: [
          CustomSupplementRule(
            from: "18:00",
            to: "22:00",
            rate: 45,
            percent: nil,
            isCustom: true
          )
        ]
      )
    ]
    let notes: _ = ["2026-03-16": "Late shift"]

    let created: _ = try await store.createRecurringShift(
      userId: userId,
      jobId: "job-1",
      startTime: "09:00",
      endTime: "17:00",
      repeatIntervalWeeks: 1,
      selectedDays: ["1": "2026-03-02"],
      endCondition: nil,
      exclusions: ["2026-03-09"],
      dateSpecificPauseWindows: nil,
      dateSpecificSupplements: supplements,
      dateSpecificNotes: notes
    )

    await store.markRecurringShiftClean(id: created.id)
    try await store.save()

    _ = try await store.updateRecurringShift(
      id: created.id,
      jobId: nil,
      startTime: nil,
      endTime: nil,
      repeatIntervalWeeks: nil,
      selectedDays: nil,
      endCondition: .endDate(date: "2026-03-16"),
      exclusions: nil,
      dateSpecificSupplements: nil
    )

    let localRecord: _ = try await store.getRecurringShift(id: created.id)
    let local: _ = try XCTUnwrap(localRecord)
    expect(local.decodedEndCondition) == .endDate(date: "2026-03-16")
    expect(local.decodedExclusions) == ["2026-03-09"]
    expect(local.decodedDateSpecificSupplements) == supplements
    expect(local.decodedDateSpecificNotes) == notes
    expect(local.syncStatus) == .dirty
    expect(local.dirtyFieldKeys) == Set([.endCondition])
    expect(local.serverDeletedAt) == nil
  }

  internal func testUpdateRecurringShiftDateSpecificNotesMarksOnlyNoteFieldDirty() async throws {
    let store: _ = try makeStoreActor()

    let created: _ = try await store.createRecurringShift(
      userId: userId,
      jobId: "job-1",
      startTime: "09:00",
      endTime: "17:00",
      repeatIntervalWeeks: 1,
      selectedDays: ["1": "2026-03-02"],
      endCondition: nil,
      exclusions: nil,
      dateSpecificPauseWindows: nil,
      dateSpecificSupplements: nil,
      dateSpecificNotes: nil
    )

    await store.markRecurringShiftClean(id: created.id)
    try await store.save()

    _ = try await store.updateRecurringShiftDateSpecificNotes(
      id: created.id,
      dateSpecificNotes: ["2026-03-09": " Swap shift "]
    )

    let localRecord: _ = try await store.getRecurringShift(id: created.id)
    let local: _ = try XCTUnwrap(localRecord)
    expect(local.decodedDateSpecificNotes) == ["2026-03-09": "Swap shift"]
    expect(local.dirtyFieldKeys) == Set([.dateSpecificNotes])
  }

  internal func testUpdateRecurringShiftDateSpecificNotesCanRemoveOnlyTargetedDate() async throws {
    let store: _ = try makeStoreActor()

    let created: _ = try await store.createRecurringShift(
      userId: userId,
      jobId: "job-1",
      startTime: "09:00",
      endTime: "17:00",
      repeatIntervalWeeks: 1,
      selectedDays: ["1": "2026-03-02"],
      endCondition: nil,
      exclusions: nil,
      dateSpecificPauseWindows: nil,
      dateSpecificSupplements: nil,
      dateSpecificNotes: [
        "2026-03-09": "Swap shift",
        "2026-03-16": "Leave early",
      ]
    )

    await store.markRecurringShiftClean(id: created.id)
    try await store.save()

    _ = try await store.updateRecurringShiftDateSpecificNotes(
      id: created.id,
      dateSpecificNotes: ["2026-03-16": "Leave early"]
    )

    let localRecord: _ = try await store.getRecurringShift(id: created.id)
    let local: _ = try XCTUnwrap(localRecord)
    expect(local.decodedDateSpecificNotes) == ["2026-03-16": "Leave early"]
    expect(local.dirtyFieldKeys) == Set([.dateSpecificNotes])
  }

  internal func testCreateEventMarksAllFieldsDirty() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createEvent(
      id: "event-1",
      userId: userId,
      startDate: makeDate("2026-03-02"),
      endDate: makeDate("2026-03-02"),
      isAllDay: false,
      startTime: "09:00",
      endTime: "11:00",
      note: "Doctor",
      notificationMinutesArray: [60, 300]
    )

    let localRecord: _ = try await store.getEvent(id: "event-1")

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.dirtyFieldKeys) == Set(EventField.allCases)
    expect(local.notificationMinutesArray) == [300, 60]
    expect(local.notificationAnchorTime) == nil
  }

  internal func testUpdateEventTracksOnlyChangedFieldsAfterClean() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createEvent(
      id: "event-2",
      userId: userId,
      startDate: makeDate("2026-03-02"),
      endDate: makeDate("2026-03-02"),
      isAllDay: false,
      startTime: "09:00",
      endTime: "11:00",
      note: "Doctor"
    )

    await store.markEventClean(id: "event-2")
    try await store.save()

    _ = try await store.updateEvent(
      id: "event-2",
      startDate: nil,
      endDate: nil,
      isAllDay: nil,
      startTime: "10:00",
      endTime: "12:00",
      note: " Dentist "
    )

    let localRecord: _ = try await store.getEvent(id: "event-2")

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.startTime) == "10:00"
    expect(local.endTime) == "12:00"
    expect(local.note) == "Dentist"
    expect(local.dirtyFieldKeys) == Set([.startTime, .endTime, .note])
  }

  internal func testUpdateEventTracksReminderFieldsAfterClean() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createEvent(
      id: "event-2b",
      userId: userId,
      startDate: makeDate("2026-03-02"),
      endDate: makeDate("2026-03-04"),
      isAllDay: true,
      startTime: nil,
      endTime: nil,
      note: "Trip"
    )

    await store.markEventClean(id: "event-2b")
    try await store.save()

    _ = try await store.updateEvent(
      id: "event-2b",
      startDate: nil,
      endDate: nil,
      isAllDay: true,
      startTime: nil,
      endTime: nil,
      note: nil,
      notificationMinutesArray: [15, 120],
      notificationAnchorTime: "09:30"
    )

    let localRecord: _ = try await store.getEvent(id: "event-2b")
    let local: _ = try XCTUnwrap(localRecord)

    expect(local.notificationMinutesArray) == [120, 15]
    expect(local.notificationAnchorTime) == "09:30"
    expect(local.dirtyFieldKeys)
      == Set([
        .notificationMinutesArray,
        .notificationAnchorTime,
      ])
  }

  internal func testMarkEventPendingDeleteSetsPendingDeleteStatus() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createEvent(
      id: "event-3",
      userId: userId,
      startDate: makeDate("2026-03-04"),
      endDate: makeDate("2026-03-06"),
      isAllDay: true,
      startTime: nil,
      endTime: nil,
      note: "Trip"
    )

    _ = try await store.markEventPendingDelete(id: "event-3")

    let localRecord: _ = try await store.getEvent(id: "event-3")

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .pendingDelete
  }

  internal func testResolveStoredEventConflictKeepServerOverwritesLocal() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createEvent(
      id: "event-4",
      userId: userId,
      startDate: makeDate("2026-03-02"),
      endDate: makeDate("2026-03-02"),
      isAllDay: false,
      startTime: "09:00",
      endTime: "11:00",
      note: "Doctor"
    )

    let serverUpdatedAt: _ = makeDate("2026-03-04", "14:00")
    let serverSnapshot: _ = EventServerSnapshot.from(
      eventRow: EventRow(
        id: "event-4",
        user_id: userId,
        start_date: "2026-03-05",
        end_date: "2026-03-07",
        is_all_day: true,
        start_time: nil,
        end_time: nil,
        note: "Conference",
        notification_minutes_array: [120],
        notification_anchor_time: "08:30"
      ),
      updatedAt: serverUpdatedAt,
      revision: 7,
      deletedAt: nil
    )

    await store.markEventConflict(id: "event-4", serverSnapshot: serverSnapshot)
    try await store.save()

    try await store.resolveStoredEventConflictKeepServer(id: "event-4")

    let localRecord: _ = try await store.getEvent(id: "event-4")

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .clean
    expect(local.startDateString) == "2026-03-05"
    expect(local.endDateString) == "2026-03-07"
    expect(local.isAllDay) == true
    expect(local.startTime) == nil
    expect(local.endTime) == nil
    expect(local.note) == "Conference"
    expect(local.notificationMinutesArray) == [120]
    expect(local.notificationAnchorTime) == "08:30"
    expect(local.serverRevision) == 7
    expect(local.serverUpdatedAt) == serverUpdatedAt
    expect(local.conflictServerSnapshot) == nil
    expect(local.dirtyFieldKeys.isEmpty) == true

    let syncedSnapshot: _ = try XCTUnwrap(
      EventServerSnapshot.decode(from: local.lastSyncedSnapshot))
    expect(syncedSnapshot) == serverSnapshot
  }

  internal func testResolveStoredEventConflictKeepLocalKeepsLocalValuesAndUpdatesServerMetadata()
    async throws
  {
    let store: _ = try makeStoreActor()

    _ = try await store.createEvent(
      id: "event-5",
      userId: userId,
      startDate: makeDate("2026-03-02"),
      endDate: makeDate("2026-03-02"),
      isAllDay: false,
      startTime: "09:00",
      endTime: "11:00",
      note: "Doctor"
    )

    await store.markEventClean(id: "event-5")
    try await store.save()

    _ = try await store.updateEvent(
      id: "event-5",
      startDate: nil,
      endDate: nil,
      isAllDay: nil,
      startTime: "10:30",
      endTime: "12:00",
      note: nil
    )

    let serverUpdatedAt: _ = makeDate("2026-03-04", "16:00")
    let serverSnapshot: _ = EventServerSnapshot.from(
      eventRow: EventRow(
        id: "event-5",
        user_id: userId,
        start_date: "2026-03-02",
        end_date: "2026-03-02",
        is_all_day: false,
        start_time: "08:00",
        end_time: "10:00",
        note: "Server note",
        notification_minutes_array: [30],
        notification_anchor_time: nil
      ),
      updatedAt: serverUpdatedAt,
      revision: 9,
      deletedAt: nil
    )

    await store.markEventConflict(id: "event-5", serverSnapshot: serverSnapshot)
    try await store.save()

    try await store.resolveStoredEventConflictKeepLocal(id: "event-5")

    let localRecord: _ = try await store.getEvent(id: "event-5")

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.startTime) == "10:30"
    expect(local.endTime) == "12:00"
    expect(local.serverRevision) == 9
    expect(local.serverUpdatedAt) == serverUpdatedAt
    expect(local.conflictServerSnapshot) == nil
  }

  internal func testFetchEventsReturnsTimedAndCoveredAllDayEvents() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createEvent(
      id: "event-6",
      userId: userId,
      startDate: makeDate("2026-03-10"),
      endDate: makeDate("2026-03-10"),
      isAllDay: false,
      startTime: "12:00",
      endTime: "13:00",
      note: "Lunch"
    )

    _ = try await store.createEvent(
      id: "event-7",
      userId: userId,
      startDate: makeDate("2026-03-08"),
      endDate: makeDate("2026-03-12"),
      isAllDay: true,
      startTime: nil,
      endTime: nil,
      note: "Vacation"
    )

    let events: _ = await store.fetchEvents(
      userId: userId,
      startDate: makeDate("2026-03-10"),
      endDate: makeDate("2026-03-10", "23:59")
    )

    expect(events.map(\.id)) == ["event-7", "event-6"]
  }

  internal func testCreateJobMarksAllFieldsDirty() async throws {
    let store: _ = try makeStoreActor()

    let created: _ = try await store.createJob(
      userId: userId,
      name: "Store",
      color: "#00AA00",
      currency: "kr",
      isDefault: true,
      sortOrder: 0,
      payrollDay: 25,
      halfTaxMonth: 12,
      monthlyGoal: 30_000
    )

    let localRecord: _ = try await store.getJob(id: created.id)

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.dirtyFieldKeys) == Set(JobField.allCases)
  }

  internal func testCreateJobDoesNotCreateBaselineSnapshot() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createJob(
      userId: userId,
      name: "Store",
      color: "#00AA00",
      currency: "kr",
      isDefault: true,
      sortOrder: 0,
      payrollDay: 25,
      halfTaxMonth: 12,
      monthlyGoal: 30_000
    )

    let snapshots: _ = try await store.getAllWageSnapshots(userId: userId)

    expect(snapshots.isEmpty) == true
  }

  internal func testUpdateJobMetadataTracksChangedFieldsAfterClean() async throws {
    let store: _ = try makeStoreActor()

    let created: _ = try await store.createJob(
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

    let localRecord: _ = try await store.getJob(id: created.id)

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.name) == "Store Updated"
    expect(local.dirtyFieldKeys) == Set([.name])
  }

  internal func testUpdateJobMetadataTracksCurrencyChangesAfterClean() async throws {
    let store: _ = try makeStoreActor()

    let created: _ = try await store.createJob(
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

    let localRecord: _ = try await store.getJob(id: created.id)

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.currency) == "$"
    expect(local.dirtyFieldKeys) == Set([.currency])
  }

  internal func testMarkJobPendingDeleteMarksDeletedAtAndPendingStatus() async throws {
    let store: _ = try makeStoreActor()

    let created: _ = try await store.createJob(
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

    let localRecord: _ = try await store.getJob(id: created.id)

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .pendingDelete
    expect(local.isDefault) == false
    expect(local.deletedAt) != nil
    expect(local.dirtyFieldKeys.contains(.deletedAt)) == true
    expect(local.dirtyFieldKeys.contains(.isDefault)) == true
  }

  internal func testResolveStoredJobConflictKeepServerOverwritesLocal() async throws {
    let store: _ = try makeStoreActor()

    let created: _ = try await store.createJob(
      userId: userId,
      name: "Local Job",
      color: "#111111",
      currency: "kr",
      isDefault: false,
      sortOrder: 0,
      payrollDay: 25,
      halfTaxMonth: nil,
      monthlyGoal: 25_000
    )

    let serverUpdatedAt: _ = makeDate("2026-03-06", "12:00")
    let serverSnapshot: _ = JobServerSnapshot(
      name: "Server Job",
      color: "#222222",
      currency: "kr",
      isDefault: true,
      sortOrder: 2,
      payrollDay: 20,
      halfTaxMonth: 11,
      monthlyGoal: 35_000,
      archivedAt: nil,
      deletedAt: nil,
      updatedAt: serverUpdatedAt,
      revision: 5
    )

    await store.markJobConflict(id: created.id, serverSnapshot: serverSnapshot)
    try await store.save()

    try await store.resolveStoredJobConflictKeepServer(id: created.id)

    let localRecord: _ = try await store.getJob(id: created.id)

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .clean
    expect(local.name) == "Server Job"
    expect(local.color) == "#222222"
    expect(local.isDefault) == true
    expect(local.sortOrder) == 2
    expect(local.payrollDay) == 20
    expect(local.halfTaxMonth) == 11
    expect(local.monthlyGoal) == 35_000
    expect(local.serverRevision) == 5
    expect(local.serverUpdatedAt) == serverUpdatedAt
    expect(local.conflictServerSnapshot) == nil
    expect(local.dirtyFieldKeys.isEmpty) == true

    let syncedSnapshot: _ = try XCTUnwrap(JobServerSnapshot.decode(from: local.lastSyncedSnapshot))
    expect(syncedSnapshot) == serverSnapshot
  }

  internal func testResolveStoredJobConflictKeepLocalKeepsLocalValuesAndUpdatesServerMetadata()
    async throws
  {
    let store: _ = try makeStoreActor()

    let created: _ = try await store.createJob(
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

    let serverUpdatedAt: _ = makeDate("2026-03-06", "17:00")
    let serverSnapshot: _ = JobServerSnapshot(
      name: "Server Job",
      color: "#222222",
      currency: "kr",
      isDefault: true,
      sortOrder: 4,
      payrollDay: 20,
      halfTaxMonth: 11,
      monthlyGoal: 40_000,
      archivedAt: nil,
      deletedAt: nil,
      updatedAt: serverUpdatedAt,
      revision: 8
    )

    await store.markJobConflict(id: created.id, serverSnapshot: serverSnapshot)
    try await store.save()

    try await store.resolveStoredJobConflictKeepLocal(id: created.id)

    let localRecord: _ = try await store.getJob(id: created.id)

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.name) == "Local Edited Job"
    expect(local.serverRevision) == 8
    expect(local.serverUpdatedAt) == serverUpdatedAt
    expect(local.conflictServerSnapshot) == nil
  }

  internal func testCreateWageSnapshotMarksAllFieldsDirty() async throws {
    let store: _ = try makeStoreActor()

    let created: _ = try await store.createWageSnapshot(
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

    let localRecord: _ = try await store.getWageSnapshot(id: created.id)

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.dirtyFieldKeys) == Set(WageSnapshotField.allCases)
  }

  internal func testUpdateWageSnapshotTracksChangedFieldsAfterClean() async throws {
    let store: _ = try makeStoreActor()

    let created: _ = try await store.createWageSnapshot(
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
      tariffTypeId: nil,
      supplements: nil,
      taxEnabled: nil,
      taxPercentage: nil,
      breakEnabled: nil,
      breakMethod: nil,
      breakThresholdHours: nil,
      breakDeductionMinutes: nil
    )

    let localRecord: _ = try await store.getWageSnapshot(id: created.id)

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.hourlyWage) == 230
    expect(local.dirtyFieldKeys) == Set([.hourlyWage])
  }

  internal func testMarkWageSnapshotPendingDeleteSetsPendingDeleteStatus() async throws {
    let store: _ = try makeStoreActor()

    let created: _ = try await store.createWageSnapshot(
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

    let localRecord: _ = try await store.getWageSnapshot(id: created.id)

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .pendingDelete
  }

  internal func testResolveStoredWageSnapshotConflictKeepServerOverwritesLocal() async throws {
    let store: _ = try makeStoreActor()

    let created: _ = try await store.createWageSnapshot(
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

    let serverUpdatedAt: _ = makeDate("2026-03-09", "10:00")
    let serverSnapshot: _ = WageSnapshotServerSnapshot(
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

    let localRecord: _ = try await store.getWageSnapshot(id: created.id)

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .clean
    expect(local.jobId) == "job-server"
    expect(local.fromDateString) == "2026-03-15"
    expect(local.hourlyWage) == 260
    expect(local.wageLevel) == 4
    expect(local.tariffTypeId) == "hk_retail"
    expect(local.taxEnabled) == false
    expect(local.taxPercentage) == 0
    expect(local.breakEnabled) == false
    expect(local.breakMethod) == "none"
    expect(local.breakThresholdHours) == 6.0
    expect(local.breakDeductionMinutes) == 0
    expect(local.serverRevision) == 11
    expect(local.serverUpdatedAt) == serverUpdatedAt
    expect(local.conflictServerSnapshot) == nil
    expect(local.dirtyFieldKeys.isEmpty) == true

    let syncedSnapshot: _ = try XCTUnwrap(
      WageSnapshotServerSnapshot.decode(from: local.lastSyncedSnapshot)
    )
    expect(syncedSnapshot) == serverSnapshot
  }

  internal func testCreateUserSettingsMarksExpectedInitialDirtyFields() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createUserSettings(
      userId: userId,
      payrollDay: 25,
      currency: "NOK",
      theme: "dark",
      calendarContentColorStyle: "monochrome",
      showDashboardClockButtons: false,
      monthlyGoal: 30_000,
      monthlyGoalsByMonth: ["2026-03": 32_000],
      defaultShiftsView: "list",
      halfTaxMonth: 12,
      defaultStartupTab: "stats"
    )

    let localRecord: _ = try await store.getUserSettings(userId: userId)

    let local: _ = try XCTUnwrap(localRecord)

    let expected: Set<UserSettingsField> = [
      .theme,
      .calendarContentColorStyle,
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

    expect(local.syncStatus) == .dirty
    expect(local.dirtyFieldKeys) == expected
  }

  internal func testUpdateUserSettingsMarksThemeDirtyEvenWhenValueIsUnchanged() async throws {
    let store: _ = try makeStoreActor()

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
      calendarContentColorStyle: nil,
      showDashboardClockButtons: nil,
      halfTaxMonth: nil,
      currency: nil,
      defaultStartupTab: nil
    )

    let localRecord: _ = try await store.getUserSettings(userId: userId)

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.theme) == "dark"
    expect(local.dirtyFieldKeys) == Set([.theme])
  }

  internal func testUpdateUserSettingsMarksCalendarContentColorStyleDirty() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createUserSettings(
      userId: userId,
      payrollDay: nil,
      currency: nil,
      calendarContentColorStyle: "workplace"
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
      theme: nil,
      calendarContentColorStyle: "monochrome",
      showDashboardClockButtons: nil,
      halfTaxMonth: nil,
      currency: nil,
      defaultStartupTab: nil
    )

    let localRecord: _ = try await store.getUserSettings(userId: userId)

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.calendarContentColorStyle) == "monochrome"
    expect(local.dirtyFieldKeys) == Set([.calendarContentColorStyle])
  }

  internal func testResolveStoredUserSettingsConflictKeepServerOverwritesLocal() async throws {
    let store: _ = try makeStoreActor()

    _ = try await store.createUserSettings(
      userId: userId,
      payrollDay: 25,
      currency: "NOK",
      theme: "dark",
      calendarContentColorStyle: "monochrome",
      showDashboardClockButtons: false,
      monthlyGoal: 30_000,
      monthlyGoalsByMonth: ["2026-03": 32_000],
      defaultShiftsView: "list",
      halfTaxMonth: 12,
      defaultStartupTab: "stats"
    )

    let serverUpdatedAt: _ = makeDate("2026-03-08", "11:00")
    let serverSnapshot: _ = UserSettingsServerSnapshot(
      monthlyGoal: 42_000,
      monthlyGoalsByMonth: ["2026-03": 43_000],
      defaultShiftsView: "calendar",
      profilePictureUrl: "https://tidex.no/avatar.png",
      payrollDay: 20,
      theme: "light",
      calendarContentColorStyle: "workplace",
      showDashboardClockButtons: true,
      aiDataSharingEnabled: false,
      halfTaxMonth: nil,
      currency: "SEK",
      defaultStartupTab: "home",
      wageyShowcaseSeen: false,
      lastActive: serverUpdatedAt,
      updatedAt: serverUpdatedAt,
      revision: 12
    )

    await store.markUserSettingsConflict(userId: userId, serverSnapshot: serverSnapshot)
    try await store.save()

    try await store.resolveStoredUserSettingsConflictKeepServer(userId: userId)

    let localRecord: _ = try await store.getUserSettings(userId: userId)

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .clean
    expect(local.monthlyGoal) == 42_000
    expect(local.monthlyGoalsByMonth) == ["2026-03": 43_000]
    expect(local.defaultShiftsView) == "calendar"
    expect(local.profilePictureUrl) == "https://tidex.no/avatar.png"
    expect(local.payrollDay) == 20
    expect(local.theme) == "light"
    expect(local.calendarContentColorStyle) == "workplace"
    expect(local.showDashboardClockButtons) == true
    expect(local.halfTaxMonth) == nil
    expect(local.currency) == "SEK"
    expect(local.defaultStartupTab) == "home"
    expect(local.lastActive) == serverUpdatedAt
    expect(local.serverRevision) == 12
    expect(local.serverUpdatedAt) == serverUpdatedAt
    expect(local.conflictServerSnapshot) == nil
    expect(local.dirtyFieldKeys.isEmpty) == true

    let syncedSnapshot: _ = try XCTUnwrap(
      UserSettingsServerSnapshot.decode(from: local.lastSyncedSnapshot)
    )
    expect(syncedSnapshot) == serverSnapshot
  }

  internal func
    testResolveStoredUserSettingsConflictKeepLocalKeepsLocalValuesAndUpdatesServerMetadata()
    async throws
  {
    let store: _ = try makeStoreActor()

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
      calendarContentColorStyle: nil,
      showDashboardClockButtons: nil,
      halfTaxMonth: nil,
      currency: "NOK",
      defaultStartupTab: nil
    )

    let serverUpdatedAt: _ = makeDate("2026-03-08", "18:00")
    let serverSnapshot: _ = UserSettingsServerSnapshot(
      monthlyGoal: 45_000,
      monthlyGoalsByMonth: [:],
      defaultShiftsView: "calendar",
      profilePictureUrl: nil,
      payrollDay: 20,
      theme: "light",
      calendarContentColorStyle: "workplace",
      showDashboardClockButtons: true,
      aiDataSharingEnabled: false,
      halfTaxMonth: nil,
      currency: "SEK",
      defaultStartupTab: "home",
      wageyShowcaseSeen: false,
      lastActive: serverUpdatedAt,
      updatedAt: serverUpdatedAt,
      revision: 14
    )

    await store.markUserSettingsConflict(userId: userId, serverSnapshot: serverSnapshot)
    try await store.save()

    try await store.resolveStoredUserSettingsConflictKeepLocal(userId: userId)

    let localRecord: _ = try await store.getUserSettings(userId: userId)

    let local: _ = try XCTUnwrap(localRecord)
    expect(local.syncStatus) == .dirty
    expect(local.theme) == "dark"
    expect(local.currency) == "NOK"
    expect(local.serverRevision) == 14
    expect(local.serverUpdatedAt) == serverUpdatedAt
    expect(local.conflictServerSnapshot) == nil
  }
  deinit {
    // Required explicitly by the repository.s lifecycle lint policy.
  }
}
