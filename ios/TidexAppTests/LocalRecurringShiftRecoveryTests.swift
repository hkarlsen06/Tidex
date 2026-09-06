import XCTest

@testable import Tidex

final class LocalRecurringShiftRecoveryTests: XCTestCase {
  func testDecodedSelectedDaysFallsBackToLastSyncedSnapshotWhenLocalBlobIsCorrupt() throws {
    let selectedDays = ["1": "2026-03-02", "3": "2026-02-25"] as SelectedDays
    let selectedDaysData = try kCanonicalJSONEncoder.encode(selectedDays)
    let timestamp = Date.fromDateAndTime("2026-03-02", time: "10:00") ?? Date()

    let snapshot = RecurringShiftServerSnapshot(
      jobId: "job-1",
      startTime: "17:00",
      endTime: "23:15",
      repeatIntervalWeeks: 1,
      selectedDays: selectedDaysData,
      endCondition: nil,
      exclusions: nil,
      dateSpecificPauseWindows: nil,
      dateSpecificSupplements: nil,
      dateSpecificNotes: nil,
      updatedAt: timestamp,
      revision: 7,
      deletedAt: nil
    )

    let localShift = LocalRecurringShift(
      id: "recurring-1",
      userId: "user-1",
      jobId: "job-1",
      startTime: "17:00",
      endTime: "23:15",
      repeatIntervalWeeks: 1,
      selectedDays: Data("not-json".utf8),
      endCondition: nil,
      exclusions: nil,
      dateSpecificPauseWindows: nil,
      dateSpecificSupplements: nil,
      serverUpdatedAt: timestamp,
      serverRevision: 7,
      serverDeletedAt: nil,
      syncStatus: .clean,
      dirtyFields: LocalRecurringShift.emptyDirtyFields(),
      lastSyncedSnapshot: try snapshot.encodedOrThrow(),
      localUpdatedAt: timestamp,
      conflictServerSnapshot: nil
    )

    XCTAssertEqual(localShift.decodedSelectedDays, selectedDays)
    XCTAssertEqual(localShift.toRecurringShiftRow().selected_days, selectedDays)
  }

  func testDecodedExclusionsFallsBackToLastSyncedSnapshotWhenLocalBlobIsCorrupt() throws {
    let exclusions = ["2026-03-16", "2026-03-30"]
    let exclusionsData = try kCanonicalJSONEncoder.encode(exclusions)
    let timestamp = Date.fromDateAndTime("2026-03-02", time: "10:00") ?? Date()

    let snapshot = RecurringShiftServerSnapshot(
      jobId: "job-1",
      startTime: "17:00",
      endTime: "23:15",
      repeatIntervalWeeks: 1,
      selectedDays: try kCanonicalJSONEncoder.encode(["1": "2026-03-02"] as SelectedDays),
      endCondition: nil,
      exclusions: exclusionsData,
      dateSpecificPauseWindows: nil,
      dateSpecificSupplements: nil,
      dateSpecificNotes: nil,
      updatedAt: timestamp,
      revision: 7,
      deletedAt: nil
    )

    let localShift = LocalRecurringShift(
      id: "recurring-2",
      userId: "user-1",
      jobId: "job-1",
      startTime: "17:00",
      endTime: "23:15",
      repeatIntervalWeeks: 1,
      selectedDays: try kCanonicalJSONEncoder.encode(["1": "2026-03-02"] as SelectedDays),
      endCondition: nil,
      exclusions: Data("not-json".utf8),
      dateSpecificPauseWindows: nil,
      dateSpecificSupplements: nil,
      serverUpdatedAt: timestamp,
      serverRevision: 7,
      serverDeletedAt: nil,
      syncStatus: .clean,
      dirtyFields: LocalRecurringShift.emptyDirtyFields(),
      lastSyncedSnapshot: try snapshot.encodedOrThrow(),
      localUpdatedAt: timestamp,
      conflictServerSnapshot: nil
    )

    XCTAssertEqual(localShift.decodedExclusions, exclusions)
    XCTAssertEqual(localShift.toRecurringShiftRow().exclusions, exclusions)
  }
}
