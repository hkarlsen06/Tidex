import Foundation
import SwiftData
import os.log

// MARK: - Sync Merge Support

/// A server snapshot that can list the fields that differ from another snapshot.
internal protocol SyncFieldSnapshot {
  associatedtype Field: Hashable

  func changedFields(from other: Self) -> Set<Field>
  func encoded() -> Data
}

/// Sync metadata shared by the local models that the sync coordinator pushes.
internal protocol SyncPushTrackedModel: AnyObject {
  associatedtype Snapshot: SyncFieldSnapshot

  var localUpdatedAt: Date { get }
  var syncStatus: SyncStatus { get set }
  var dirtyFieldKeys: Set<Snapshot.Field> { get set }
  var serverUpdatedAt: Date { get set }
  var serverRevision: Int64 { get set }
  var lastSyncedSnapshot: Data { get set }
  var conflictServerSnapshot: Data? { get set }

  /// The row's current local values in server snapshot form.
  var localValuesSnapshot: Snapshot { get }
}

/// Local row state captured when a push request is built.
/// Every local edit or delete updates `localUpdatedAt` or `syncStatus`, so a mismatch after the
/// request returns means the row changed while the push was in flight.
internal struct SyncPushBaseline: Equatable, Sendable {
  internal let localUpdatedAt: Date
  internal let syncStatus: SyncStatus

  internal init(_ row: some SyncPushTrackedModel) {
    localUpdatedAt = row.localUpdatedAt
    syncStatus = row.syncStatus
  }
}

internal enum SyncMerge {
  /// Returns the dirty local fields to keep when a newer server row arrives for a dirty row.
  /// Matching values acknowledge a pending write. Differing dirty fields still need pushing.
  /// A server timestamp can belong to an earlier local edit whose response was lost, so it
  /// cannot establish that the server value is newer than an unacknowledged local edit.
  internal static func fieldsToKeepLocally<Row: SyncPushTrackedModel>(
    _ row: Row,
    server: Row.Snapshot
  ) -> Set<Row.Snapshot.Field> {
    row.dirtyFieldKeys.intersection(
      row.localValuesSnapshot.changedFields(from: server))
  }
}

extension LocalStoreActor {
  /// Records a server revision without touching local values or dirty fields.
  /// The next push sends the local values against this revision.
  internal func adoptServerRevision(
    _ row: some SyncPushTrackedModel,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: Data
  ) {
    row.serverUpdatedAt = serverUpdatedAt
    row.serverRevision = serverRevision
    row.lastSyncedSnapshot = snapshot
    row.conflictServerSnapshot = nil
    if row.syncStatus == .conflict {
      row.syncStatus = .dirty
    }
  }

  /// Keeps an edit or delete made while a push was in flight.
  /// Returns `true` when the row changed after `baseline` was captured. In that case only the
  /// returned server revision is recorded, and the caller must not overwrite the row.
  internal func keepChangesMadeDuringPush<Row: SyncPushTrackedModel>(
    _ row: Row,
    baseline: SyncPushBaseline,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: Row.Snapshot
  ) -> Bool {
    guard SyncPushBaseline(row) != baseline else { return false }
    // A dirty field that now matches the server row was acknowledged by this push and not
    // edited again. Left dirty, it would later overwrite a newer edit from another device.
    let stillPending = SyncMerge.fieldsToKeepLocally(row, server: snapshot)
    adoptServerRevision(
      row,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      snapshot: snapshot.encoded()
    )
    settleMergedDirtyFields(row, keepingLocal: stillPending)
    return true
  }

  /// Drops the dirty fields a server merge settled and sets the status to match.
  /// A pending delete stays pending.
  internal func settleMergedDirtyFields<Row: SyncPushTrackedModel>(
    _ row: Row,
    keepingLocal keep: Set<Row.Snapshot.Field>
  ) {
    row.dirtyFieldKeys = row.dirtyFieldKeys.intersection(keep)
    row.conflictServerSnapshot = nil
    guard row.syncStatus != .pendingDelete else { return }
    row.syncStatus = row.dirtyFieldKeys.isEmpty ? .clean : .dirty
  }
}

extension JobServerSnapshot: SyncFieldSnapshot {
  internal typealias Field = JobField
}

extension UserShiftServerSnapshot: SyncFieldSnapshot {
  internal typealias Field = UserShiftField
}

extension EventServerSnapshot: SyncFieldSnapshot {
  internal typealias Field = EventField
}

extension RecurringShiftServerSnapshot: SyncFieldSnapshot {
  internal typealias Field = RecurringShiftField
}

extension WageSnapshotServerSnapshot: SyncFieldSnapshot {
  internal typealias Field = WageSnapshotField
}

extension UserSettingsServerSnapshot: SyncFieldSnapshot {
  internal typealias Field = UserSettingsField
}

extension PayrollAdjustmentServerSnapshot: SyncFieldSnapshot {
  internal typealias Field = PayrollAdjustmentField
}

extension LocalJob: SyncPushTrackedModel {
  internal var localValuesSnapshot: JobServerSnapshot {
    JobServerSnapshot(
      name: name,
      color: color,
      currency: currency,
      isDefault: isDefault,
      sortOrder: sortOrder,
      payrollDay: payrollDay,
      halfTaxMonth: halfTaxMonth,
      payPeriod: PayPeriod.fromStorageJSON(payPeriodJSON),
      monthlyGoal: monthlyGoal,
      archivedAt: archivedAt,
      deletedAt: deletedAt,
      updatedAt: serverUpdatedAt,
      revision: serverRevision
    )
  }
}

extension LocalUserShift: SyncPushTrackedModel {
  internal var localValuesSnapshot: UserShiftServerSnapshot {
    UserShiftServerSnapshot(
      jobId: jobId,
      shiftDate: shiftDateString,
      startTime: startTime,
      endTime: endTime,
      note: note,
      customPauseWindows: customPauseWindows,
      customSupplements: customSupplements,
      updatedAt: serverUpdatedAt,
      revision: serverRevision,
      deletedAt: serverDeletedAt
    )
  }
}

extension LocalEvent: SyncPushTrackedModel {
  internal var localValuesSnapshot: EventServerSnapshot {
    EventServerSnapshot(
      startDate: startDateString,
      endDate: endDateString,
      isAllDay: isAllDay,
      startTime: startTime,
      endTime: endTime,
      note: note,
      notificationMinutesArray: LocalEvent.normalizedReminderMinutesOptional(
        notificationMinutesArray),
      notificationAnchorTime: notificationAnchorTime,
      updatedAt: serverUpdatedAt,
      revision: serverRevision,
      deletedAt: serverDeletedAt
    )
  }
}

extension LocalRecurringShift: SyncPushTrackedModel {
  internal var localValuesSnapshot: RecurringShiftServerSnapshot {
    RecurringShiftServerSnapshot(
      jobId: jobId,
      startTime: startTime,
      endTime: endTime,
      repeatIntervalWeeks: repeatIntervalWeeks,
      selectedDays: selectedDays,
      endCondition: endCondition,
      exclusions: exclusions,
      dateSpecificPauseWindows: dateSpecificPauseWindows,
      dateSpecificSupplements: dateSpecificSupplements,
      dateSpecificNotes: dateSpecificNotes,
      updatedAt: serverUpdatedAt,
      revision: serverRevision,
      deletedAt: serverDeletedAt
    )
  }
}

extension LocalWageSnapshot: SyncPushTrackedModel {
  internal var localValuesSnapshot: WageSnapshotServerSnapshot {
    WageSnapshotServerSnapshot(
      jobId: jobId,
      fromDate: fromDateString,
      hourlyWage: hourlyWage,
      wageLevel: wageLevel,
      tariffTypeId: tariffTypeId,
      supplements: supplements,
      overtime: overtime,
      taxEnabled: taxEnabled,
      taxPercentage: taxPercentage,
      breakEnabled: breakEnabled,
      breakMethod: breakMethod,
      breakThresholdHours: breakThresholdHours,
      breakDeductionMinutes: breakDeductionMinutes,
      updatedAt: serverUpdatedAt,
      revision: serverRevision,
      deletedAt: serverDeletedAt
    )
  }
}

extension LocalUserSettings: SyncPushTrackedModel {
  internal var localValuesSnapshot: UserSettingsServerSnapshot {
    UserSettingsServerSnapshot(
      monthlyGoal: monthlyGoal,
      monthlyGoalsByMonth: monthlyGoalsByMonth,
      defaultShiftsView: defaultShiftsView,
      profilePictureUrl: profilePictureUrl,
      payrollDay: payrollDay,
      theme: theme,
      calendarContentColorStyle: effectiveCalendarContentColorStyle,
      showDashboardClockButtons: effectiveShowDashboardClockButtons,
      halfTaxMonth: halfTaxMonth,
      currency: currency,
      defaultStartupTab: defaultStartupTab,
      lastActive: lastActive,
      updatedAt: serverUpdatedAt,
      revision: serverRevision
    )
  }
}

extension LocalPayrollAdjustment: SyncPushTrackedModel {
  internal var localValuesSnapshot: PayrollAdjustmentServerSnapshot {
    PayrollAdjustmentServerSnapshot(
      jobId: jobId,
      amount: amount,
      currency: currency,
      category: category,
      taxTreatment: taxTreatment,
      description: descriptionText,
      note: note,
      curatedNote: curatedNote,
      curatedDescription: curatedDescription,
      curatedLink: curatedLink,
      curatedLinkTitle: curatedLinkTitle,
      earnedFromDate: earnedFromDateString,
      earnedToDate: earnedToDateString,
      payoutDate: payoutDateString,
      updatedAt: serverUpdatedAt,
      revision: serverRevision,
      deletedAt: serverDeletedAt
    )
  }
}