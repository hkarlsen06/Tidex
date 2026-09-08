import SwiftData
import XCTest

@testable import Tidex

@MainActor
internal final class LocalStoreDirtyTrackingTests: XCTestCase {
  private let userId: String = "user-1"

  private func makeStoreActor() throws -> LocalStoreActor {
    let schema = Schema([
      LocalJob.self,
      LocalUserShift.self,
      LocalEvent.self,
      LocalRecurringShift.self,
      LocalWageSnapshot.self,
      LocalPayrollAdjustment.self,
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

  internal func testCreateUserShiftMarksAllFieldsDirty() async throws {
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

  internal func testUpdateUserShiftTracksOnlyChangedFieldsAfterClean() async throws {
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

  internal func testUpdateUserShiftCustomPauseWindowsMarksOnlyPauseFieldDirty() async throws {
    let store = try makeStoreActor()

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

    let localRecord = try await store.getUserShift(id: "shift-pause-1")
    let local = try XCTUnwrap(localRecord)

    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.dirtyFieldKeys, Set([.customPauseWindows]))
    XCTAssertEqual(
      local.decodedCustomPauseWindows,
      CustomPauseWindows(
        windows: [PauseWindow(start: "12:00", end: "12:30")]
      )
    )
  }

  internal func testMarkShiftPendingDeleteSetsPendingDeleteStatus() async throws {
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

  internal func testResolveStoredShiftConflictKeepServerOverwritesLocal() async throws {
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

    let localRecord = try await store.getUserShift(id: "shift-4")

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .clean)
    XCTAssertEqual(local.jobId, "job-server")
    XCTAssertEqual(local.shiftDateString, "2026-03-10")
    XCTAssertEqual(local.startTime, "12:00")
    XCTAssertEqual(local.endTime, "20:00")
    XCTAssertEqual(local.note, "Server note")
    XCTAssertEqual(local.serverRevision, 7)
    XCTAssertEqual(local.serverUpdatedAt, serverUpdatedAt)
    XCTAssertNil(local.conflictServerSnapshot)
    XCTAssertEqual(local.dirtyFieldKeys.isEmpty, true)

    let syncedSnapshot = try XCTUnwrap(
      UserShiftServerSnapshot.decode(from: local.lastSyncedSnapshot)
    )
    XCTAssertEqual(syncedSnapshot, serverSnapshot)
  }

  internal func testResolveStoredShiftConflictKeepLocalKeepsLocalValuesAndUpdatesServerMetadata()
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

    let localRecord = try await store.getUserShift(id: "shift-5")

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.startTime, "09:30")
    XCTAssertNil(local.note)
    XCTAssertEqual(local.serverRevision, 9)
    XCTAssertEqual(local.serverUpdatedAt, serverUpdatedAt)
    XCTAssertNil(local.conflictServerSnapshot)
  }

  internal func testUpdateUserShiftNoteMarksOnlyNoteDirty() async throws {
    let store = try makeStoreActor()

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

    let localRecord = try await store.getUserShift(id: "shift-note-1")
    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.note, "Dentist")
    XCTAssertEqual(local.dirtyFieldKeys, Set([.note]))
  }

  internal func testUpdateUserShiftNoteCanBeClearedExplicitly() async throws {
    let store = try makeStoreActor()

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

    let localRecord = try await store.getUserShift(id: "shift-note-2")
    let local = try XCTUnwrap(localRecord)
    XCTAssertNil(local.note)
    XCTAssertEqual(local.dirtyFieldKeys, Set([.note]))
  }

  internal func testAddRecurringShiftExclusionsAddsMultipleDatesInSingleMutation() async throws {
    let store = try makeStoreActor()

    let created = try await store.createRecurringShift(
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

    let addedCount = try await store.addRecurringShiftExclusions(
      id: created.id,
      dates: ["2026-03-16", "2026-03-23", "2026-03-16"]
    )

    let localRecord = try await store.getRecurringShift(id: created.id)
    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(addedCount, 2)
    XCTAssertEqual(local.decodedExclusions, ["2026-03-09", "2026-03-16", "2026-03-23"])
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.dirtyFieldKeys, Set([.exclusions]))
  }

  internal func testUpdateRecurringShiftEndConditionPreservesOverrides() async throws {
    let store = try makeStoreActor()
    let supplements = [
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
    let notes = ["2026-03-16": "Late shift"]

    let created = try await store.createRecurringShift(
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

    let localRecord = try await store.getRecurringShift(id: created.id)
    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.decodedEndCondition, .endDate(date: "2026-03-16"))
    XCTAssertEqual(local.decodedExclusions, ["2026-03-09"])
    XCTAssertEqual(local.decodedDateSpecificSupplements, supplements)
    XCTAssertEqual(local.decodedDateSpecificNotes, notes)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.dirtyFieldKeys, Set([.endCondition]))
    XCTAssertNil(local.serverDeletedAt)
  }

  internal func testUpdateRecurringShiftDateSpecificNotesMarksOnlyNoteFieldDirty() async throws {
    let store = try makeStoreActor()

    let created = try await store.createRecurringShift(
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

    let localRecord = try await store.getRecurringShift(id: created.id)
    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.decodedDateSpecificNotes, ["2026-03-09": "Swap shift"])
    XCTAssertEqual(local.dirtyFieldKeys, Set([.dateSpecificNotes]))
  }

  internal func testUpdateRecurringShiftDateSpecificNotesCanRemoveOnlyTargetedDate() async throws {
    let store = try makeStoreActor()

    let created = try await store.createRecurringShift(
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

    let localRecord = try await store.getRecurringShift(id: created.id)
    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.decodedDateSpecificNotes, ["2026-03-16": "Leave early"])
    XCTAssertEqual(local.dirtyFieldKeys, Set([.dateSpecificNotes]))
  }

  internal func testCreateEventMarksAllFieldsDirty() async throws {
    let store = try makeStoreActor()

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

    let localRecord = try await store.getEvent(id: "event-1")

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.dirtyFieldKeys, Set(EventField.allCases))
    XCTAssertEqual(local.notificationMinutesArray, [300, 60])
    XCTAssertNil(local.notificationAnchorTime)
  }

  internal func testUpdateEventTracksOnlyChangedFieldsAfterClean() async throws {
    let store = try makeStoreActor()

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

    let localRecord = try await store.getEvent(id: "event-2")

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.startTime, "10:00")
    XCTAssertEqual(local.endTime, "12:00")
    XCTAssertEqual(local.note, "Dentist")
    XCTAssertEqual(local.dirtyFieldKeys, Set([.startTime, .endTime, .note]))
  }

  internal func testUpdateEventTracksReminderFieldsAfterClean() async throws {
    let store = try makeStoreActor()

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

    let localRecord = try await store.getEvent(id: "event-2b")
    let local = try XCTUnwrap(localRecord)

    XCTAssertEqual(local.notificationMinutesArray, [120, 15])
    XCTAssertEqual(local.notificationAnchorTime, "09:30")
    XCTAssertEqual(
      local.dirtyFieldKeys,
      Set([
        .notificationMinutesArray,
        .notificationAnchorTime,
      ])
    )
  }

  internal func testMarkEventPendingDeleteSetsPendingDeleteStatus() async throws {
    let store = try makeStoreActor()

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

    let localRecord = try await store.getEvent(id: "event-3")

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .pendingDelete)
  }

  internal func testResolveStoredEventConflictKeepServerOverwritesLocal() async throws {
    let store = try makeStoreActor()

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

    let serverUpdatedAt = makeDate("2026-03-04", "14:00")
    let serverSnapshot = EventServerSnapshot.from(
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

    let localRecord = try await store.getEvent(id: "event-4")

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .clean)
    XCTAssertEqual(local.startDateString, "2026-03-05")
    XCTAssertEqual(local.endDateString, "2026-03-07")
    XCTAssertEqual(local.isAllDay, true)
    XCTAssertNil(local.startTime)
    XCTAssertNil(local.endTime)
    XCTAssertEqual(local.note, "Conference")
    XCTAssertEqual(local.notificationMinutesArray, [120])
    XCTAssertEqual(local.notificationAnchorTime, "08:30")
    XCTAssertEqual(local.serverRevision, 7)
    XCTAssertEqual(local.serverUpdatedAt, serverUpdatedAt)
    XCTAssertNil(local.conflictServerSnapshot)
    XCTAssertEqual(local.dirtyFieldKeys.isEmpty, true)

    let syncedSnapshot = try XCTUnwrap(
      EventServerSnapshot.decode(from: local.lastSyncedSnapshot))
    XCTAssertEqual(syncedSnapshot, serverSnapshot)
  }

  internal func testResolveStoredEventConflictKeepLocalKeepsLocalValuesAndUpdatesServerMetadata()
    async throws
  {
    let store = try makeStoreActor()

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

    let serverUpdatedAt = makeDate("2026-03-04", "16:00")
    let serverSnapshot = EventServerSnapshot.from(
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

    let localRecord = try await store.getEvent(id: "event-5")

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.startTime, "10:30")
    XCTAssertEqual(local.endTime, "12:00")
    XCTAssertEqual(local.serverRevision, 9)
    XCTAssertEqual(local.serverUpdatedAt, serverUpdatedAt)
    XCTAssertNil(local.conflictServerSnapshot)
  }

  internal func testFetchEventsReturnsTimedAndCoveredAllDayEvents() async throws {
    let store = try makeStoreActor()

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

    let events = await store.fetchEvents(
      userId: userId,
      startDate: makeDate("2026-03-10"),
      endDate: makeDate("2026-03-10", "23:59")
    )

    XCTAssertEqual(events.map(\.id), ["event-7", "event-6"])
  }

  internal func testCreateJobMarksAllFieldsDirty() async throws {
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
      monthlyGoal: 30_000
    )

    let localRecord = try await store.getJob(id: created.id)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.dirtyFieldKeys, Set(JobField.allCases))
  }

  internal func testCreateJobDoesNotCreateBaselineSnapshot() async throws {
    let store = try makeStoreActor()

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

    let snapshots = try await store.getAllWageSnapshots(userId: userId)

    XCTAssertEqual(snapshots.isEmpty, true)
  }

  internal func testUpdateJobMetadataTracksChangedFieldsAfterClean() async throws {
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

  internal func testUpdateJobMetadataTracksCurrencyChangesAfterClean() async throws {
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

  internal func testDeletingActiveOrRestoredJobRequiresArchivingWithoutMutatingJob() async throws {
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

    for restored in [false, true] {
      if restored {
        _ = try await store.archiveJob(id: created.id)
        _ = try await store.restoreJob(id: created.id, sortOrder: 0)
      }
      await store.markJobClean(id: created.id)
      try await store.save()

      do {
        try await store.validateArchivedJobDeletion(userId: userId, jobId: created.id)
        XCTFail("Deleting an active job must require archiving first")
      } catch JobsRepositoryError.cannotDeleteUnarchivedJob {
        // Expected for both new and restored active jobs.
      }

      let localRecord = try await store.getJob(id: created.id)
      let local = try XCTUnwrap(localRecord)
      XCTAssertNil(local.archivedAt)
      XCTAssertNil(local.deletedAt)
      XCTAssertEqual(local.syncStatus, .clean)
      XCTAssertTrue(local.dirtyFieldKeys.isEmpty)
    }
  }

  private func makeArchivedJobWithHistory(store: LocalStoreActor, ownerId: String) async throws
    -> String
  {
    let job = try await store.createJob(
      userId: ownerId, name: "Store", color: nil, currency: "kr", isDefault: false,
      sortOrder: 0, payrollDay: 25, halfTaxMonth: nil, monthlyGoal: nil
    )
    _ = try await store.createUserShift(
      id: job.id, userId: ownerId, jobId: job.id,
      shiftDate: makeDate("2026-01-12"), startTime: "09:00", endTime: "17:00",
      customSupplements: nil
    )
    let recurring = try await store.createRecurringShift(
      userId: ownerId, jobId: job.id, startTime: "09:00", endTime: "17:00",
      repeatIntervalWeeks: 1, selectedDays: ["1": "2026-01-12"], endCondition: nil,
      exclusions: nil, dateSpecificSupplements: nil
    )
    let adjustment = try await store.createPayrollAdjustment(
      userId: ownerId, jobId: job.id, amount: 100, currency: "kr", category: .bonus,
      taxTreatment: .grossTaxable, description: "Bonus", note: nil, earnedFromDate: nil,
      earnedToDate: nil, payoutDate: makeDate("2026-01-31")
    )
    let snapshot = try await store.createWageSnapshot(
      userId: ownerId, jobId: job.id, fromDate: nil, hourlyWage: 200, wageLevel: nil,
      tariffTypeId: nil, supplements: SupplementRulesSnapshot(rules: []), taxEnabled: nil,
      taxPercentage: nil, breakEnabled: nil, breakMethod: nil, breakThresholdHours: nil,
      breakDeductionMinutes: nil
    )
    _ = try await store.archiveJob(id: job.id)
    await store.markJobClean(id: job.id)
    await store.markShiftClean(id: job.id)
    await store.markRecurringShiftClean(id: recurring.id)
    await store.markPayrollAdjustmentClean(id: adjustment.id)
    await store.markWageSnapshotClean(id: snapshot.id)
    try await store.save()
    return job.id
  }

  private func deletionReceipt(jobId: String, ownerId: String, deletedAt: Date?)
    -> JobDeletionPreview
  {
    JobDeletionPreview(
      jobId: jobId, userId: ownerId, jobName: "Store", jobRevision: 5,
      confirmationToken: "reviewed",
      userShifts: 1, recurringShifts: 1, payrollAdjustments: 1, wageSnapshots: 1,
      deletedAtEpoch: deletedAt?.timeIntervalSince1970
    )
  }

  internal func testConfirmedJobDeletionRemovesCachedHistoryAndPreservesOtherJobsAndUsers()
    async throws
  {
    let store = try makeStoreActor()
    let jobId = try await makeArchivedJobWithHistory(store: store, ownerId: userId)
    let otherJobId = try await makeArchivedJobWithHistory(store: store, ownerId: userId)
    let otherUserJobId = try await makeArchivedJobWithHistory(store: store, ownerId: "other-user")
    try await store.validateArchivedJobDeletion(userId: userId, jobId: jobId)
    let deletedAt = makeDate("2026-09-08")
    try await store.applyConfirmedJobDeletion(
      userId: userId, receipt: deletionReceipt(jobId: jobId, ownerId: userId, deletedAt: deletedAt)
    )

    let jobs = try await store.getAllJobs(userId: userId)
    XCTAssertEqual(jobs.first { $0.id == jobId }?.deletedAt, deletedAt)
    XCTAssertEqual(jobs.first { $0.id == jobId }?.serverRevision, 5)
    XCTAssertEqual(jobs.first { $0.id == jobId }?.syncStatus, .clean)
    XCTAssertNil(jobs.first { $0.id == otherJobId }?.deletedAt)
    let shifts = try await store.getAllUserShifts(userId: userId)
    XCTAssertEqual(shifts.first { $0.jobId == jobId }?.serverDeletedAt, deletedAt)
    XCTAssertEqual(shifts.first { $0.jobId == jobId }?.syncStatus, .clean)
    XCTAssertNil(shifts.first { $0.jobId == otherJobId }?.serverDeletedAt)
    let recurring = try await store.getAllRecurringShifts(userId: userId)
    XCTAssertEqual(recurring.first { $0.jobId == jobId }?.serverDeletedAt, deletedAt)
    XCTAssertNil(recurring.first { $0.jobId == otherJobId }?.serverDeletedAt)
    let adjustments = try await store.getAllPayrollAdjustments(userId: userId)
    XCTAssertEqual(adjustments.first { $0.jobId == jobId }?.serverDeletedAt, deletedAt)
    XCTAssertNil(adjustments.first { $0.jobId == otherJobId }?.serverDeletedAt)
    let snapshots = try await store.getAllWageSnapshots(userId: userId)
    XCTAssertEqual(snapshots.first { $0.jobId == jobId }?.serverDeletedAt, deletedAt)
    XCTAssertNil(snapshots.first { $0.jobId == otherJobId }?.serverDeletedAt)
    try await store.validateArchivedJobDeletion(userId: "other-user", jobId: otherUserJobId)
  }

  internal func testJobDeletionRequiresSyncedHistoryAndConfirmedServerReceipt() async throws {
    let store = try makeStoreActor()
    let jobId = try await makeArchivedJobWithHistory(store: store, ownerId: userId)
    _ = try await store.markShiftPendingDelete(id: jobId)
    do {
      try await store.validateArchivedJobDeletion(userId: userId, jobId: jobId)
      XCTFail("Pending history must be synced before confirming deletion")
    } catch JobsRepositoryError.deletionSyncRequired {}

    do {
      try await store.applyConfirmedJobDeletion(
        userId: userId, receipt: deletionReceipt(jobId: jobId, ownerId: userId, deletedAt: nil)
      )
      XCTFail("A preview must not delete local history")
    } catch JobsRepositoryError.deletionRefreshFailed {}
    let job = try await store.getJob(id: jobId)
    XCTAssertNil(job?.deletedAt)
  }

  internal func testConfirmedJobDeletionRejectsAnotherOwner() async throws {
    let store = try makeStoreActor()
    let jobId = try await makeArchivedJobWithHistory(store: store, ownerId: userId)
    do {
      try await store.applyConfirmedJobDeletion(
        userId: "other-user",
        receipt: deletionReceipt(jobId: jobId, ownerId: "other-user", deletedAt: Date())
      )
      XCTFail("A receipt cannot delete another account's cached job")
    } catch JobsRepositoryError.jobNotFound {}
    try await store.validateArchivedJobDeletion(userId: userId, jobId: jobId)
  }

  internal func testResolveStoredJobConflictKeepServerOverwritesLocal() async throws {
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
      monthlyGoal: 25_000
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
      monthlyGoal: 35_000,
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
    XCTAssertEqual(local.isDefault, true)
    XCTAssertEqual(local.sortOrder, 2)
    XCTAssertEqual(local.payrollDay, 20)
    XCTAssertEqual(local.halfTaxMonth, 11)
    XCTAssertEqual(local.monthlyGoal, 35_000)
    XCTAssertEqual(local.serverRevision, 5)
    XCTAssertEqual(local.serverUpdatedAt, serverUpdatedAt)
    XCTAssertNil(local.conflictServerSnapshot)
    XCTAssertEqual(local.dirtyFieldKeys.isEmpty, true)

    let syncedSnapshot = try XCTUnwrap(JobServerSnapshot.decode(from: local.lastSyncedSnapshot))
    XCTAssertEqual(syncedSnapshot, serverSnapshot)
  }

  internal func testResolveStoredJobConflictKeepLocalKeepsLocalValuesAndUpdatesServerMetadata()
    async throws
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
      monthlyGoal: 40_000,
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

  internal func testCreateWageSnapshotMarksAllFieldsDirty() async throws {
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

  internal func testUpdateWageSnapshotTracksChangedFieldsAfterClean() async throws {
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
      tariffTypeId: nil,
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

  internal func testMarkWageSnapshotPendingDeleteSetsPendingDeleteStatus() async throws {
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

  internal func testResolveStoredWageSnapshotConflictKeepServerOverwritesLocal() async throws {
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
      supplements: try kCanonicalJSONEncoder.encode(
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
    XCTAssertEqual(local.dirtyFieldKeys.isEmpty, true)

    let syncedSnapshot = try XCTUnwrap(
      WageSnapshotServerSnapshot.decode(from: local.lastSyncedSnapshot)
    )
    XCTAssertEqual(syncedSnapshot, serverSnapshot)
  }

  internal func testCreateUserSettingsMarksExpectedInitialDirtyFields() async throws {
    let store = try makeStoreActor()

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

    let localRecord = try await store.getUserSettings(userId: userId)

    let local = try XCTUnwrap(localRecord)

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

    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.dirtyFieldKeys, expected)
  }

  internal func testUpdateUserSettingsMarksThemeDirtyEvenWhenValueIsUnchanged() async throws {
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
      calendarContentColorStyle: nil,
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

  internal func testUpdateUserSettingsMarksCalendarContentColorStyleDirty() async throws {
    let store = try makeStoreActor()

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

    let localRecord = try await store.getUserSettings(userId: userId)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.calendarContentColorStyle, "monochrome")
    XCTAssertEqual(local.dirtyFieldKeys, Set([.calendarContentColorStyle]))
  }

  internal func testUpdateUserSettingsCanResetWageyShowcaseState() async throws {
    let store = try makeStoreActor()

    _ = try await store.createUserSettings(
      userId: userId,
      wageyShowcaseSeen: true
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
      calendarContentColorStyle: nil,
      showDashboardClockButtons: nil,
      wageyShowcaseSeen: false,
      halfTaxMonth: nil,
      currency: nil,
      defaultStartupTab: nil
    )

    let localRecord = try await store.getUserSettings(userId: userId)
    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.wageyShowcaseSeen, false)
    XCTAssertEqual(local.dirtyFieldKeys, Set([.wageyShowcaseSeen]))
  }

  internal func testResolveStoredUserSettingsConflictKeepServerOverwritesLocal() async throws {
    let store = try makeStoreActor()

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

    let serverUpdatedAt = makeDate("2026-03-08", "11:00")
    let serverSnapshot = UserSettingsServerSnapshot(
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

    let localRecord = try await store.getUserSettings(userId: userId)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .clean)
    XCTAssertEqual(local.monthlyGoal, 42_000)
    XCTAssertEqual(local.monthlyGoalsByMonth, ["2026-03": 43_000])
    XCTAssertEqual(local.defaultShiftsView, "calendar")
    XCTAssertEqual(local.profilePictureUrl, "https://tidex.no/avatar.png")
    XCTAssertEqual(local.payrollDay, 20)
    XCTAssertEqual(local.theme, "light")
    XCTAssertEqual(local.calendarContentColorStyle, "workplace")
    XCTAssertEqual(local.showDashboardClockButtons, true)
    XCTAssertNil(local.halfTaxMonth)
    XCTAssertEqual(local.currency, "SEK")
    XCTAssertEqual(local.defaultStartupTab, "home")
    XCTAssertEqual(local.lastActive, serverUpdatedAt)
    XCTAssertEqual(local.serverRevision, 12)
    XCTAssertEqual(local.serverUpdatedAt, serverUpdatedAt)
    XCTAssertNil(local.conflictServerSnapshot)
    XCTAssertEqual(local.dirtyFieldKeys.isEmpty, true)

    let syncedSnapshot = try XCTUnwrap(
      UserSettingsServerSnapshot.decode(from: local.lastSyncedSnapshot)
    )
    XCTAssertEqual(syncedSnapshot, serverSnapshot)
  }

  internal func
    testResolveStoredUserSettingsConflictKeepLocalKeepsLocalValuesAndUpdatesServerMetadata()
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
      calendarContentColorStyle: nil,
      showDashboardClockButtons: nil,
      halfTaxMonth: nil,
      currency: "NOK",
      defaultStartupTab: nil
    )

    let serverUpdatedAt = makeDate("2026-03-08", "18:00")
    let serverSnapshot = UserSettingsServerSnapshot(
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

    let localRecord = try await store.getUserSettings(userId: userId)

    let local = try XCTUnwrap(localRecord)
    XCTAssertEqual(local.syncStatus, .dirty)
    XCTAssertEqual(local.theme, "dark")
    XCTAssertEqual(local.currency, "NOK")
    XCTAssertEqual(local.serverRevision, 14)
    XCTAssertEqual(local.serverUpdatedAt, serverUpdatedAt)
    XCTAssertNil(local.conflictServerSnapshot)
  }
  deinit {
    // Required explicitly by the repository.s lifecycle lint policy.
  }
}
