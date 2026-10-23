import Foundation
import SwiftData

// SwiftData models belong to the ModelContext that fetched them, and only
// `LocalStoreActor` may touch its context. Code outside the actor, such as
// `SyncCoordinator`, gets unmanaged copies instead. A copy has the same values
// as the stored row but isn't attached to any context, so changes to it are
// never saved. Write through the actor's update methods instead.

protocol UnmanagedCopyable {
  func unmanagedCopy() -> sending Self
}

extension LocalStoreActor {
  func jobCopy(id: String) throws -> sending LocalJob? {
    try getJob(id: id)?.unmanagedCopy()
  }

  func dirtyJobCopies(userId: String) throws -> sending [LocalJob] {
    copies(of: try getDirtyJobs(userId: userId))
  }

  func userShiftCopy(id: String) throws -> sending LocalUserShift? {
    try getUserShift(id: id)?.unmanagedCopy()
  }

  func dirtyUserShiftCopies(userId: String) throws -> sending [LocalUserShift] {
    copies(of: try getDirtyUserShifts(userId: userId))
  }

  func eventCopy(id: String) throws -> sending LocalEvent? {
    try getEvent(id: id)?.unmanagedCopy()
  }

  func dirtyEventCopies(userId: String) throws -> sending [LocalEvent] {
    copies(of: try getDirtyEvents(userId: userId))
  }

  func recurringShiftCopy(id: String) throws -> sending LocalRecurringShift? {
    try getRecurringShift(id: id)?.unmanagedCopy()
  }

  func dirtyRecurringShiftCopies(userId: String) throws -> sending [LocalRecurringShift] {
    copies(of: try getDirtyRecurringShifts(userId: userId))
  }

  func wageSnapshotCopy(id: String) throws -> sending LocalWageSnapshot? {
    try getWageSnapshot(id: id)?.unmanagedCopy()
  }

  func dirtyWageSnapshotCopies(userId: String) throws -> sending [LocalWageSnapshot] {
    copies(of: try getDirtyWageSnapshots(userId: userId))
  }

  func payrollAdjustmentCopy(id: String) throws -> sending LocalPayrollAdjustment? {
    try getPayrollAdjustment(id: id)?.unmanagedCopy()
  }

  func dirtyPayrollAdjustmentCopies(userId: String) throws -> sending [LocalPayrollAdjustment] {
    copies(of: try getDirtyPayrollAdjustments(userId: userId))
  }

  func userSettingsCopy(userId: String) throws -> sending LocalUserSettings? {
    try getUserSettings(userId: userId)?.unmanagedCopy()
  }

  func dirtyUserSettingsCopy(userId: String) throws -> sending LocalUserSettings? {
    try getDirtyUserSettings(userId: userId)?.unmanagedCopy()
  }

  func syncStateCopy(userId: String) throws -> sending LocalSyncState? {
    try getSyncState(userId: userId)?.unmanagedCopy()
  }

  func syncStateCopyCreatingIfNeeded(userId: String) throws -> sending LocalSyncState {
    try getOrCreateSyncState(userId: userId).unmanagedCopy()
  }

  func copies<Model: UnmanagedCopyable>(of models: [Model]) -> sending [Model] {
    var copies: [Model] = []
    for model in models {
      copies.append(model.unmanagedCopy())
    }
    return copies
  }
}

extension LocalJob: UnmanagedCopyable {
  func unmanagedCopy() -> sending LocalJob {
    let copy = LocalJob(
      id: id,
      userId: userId,
      name: name,
      color: color,
      currency: currency,
      isDefault: isDefault,
      sortOrder: sortOrder,
      payrollDay: payrollDay,
      halfTaxMonth: halfTaxMonth,
      payPeriodJSON: payPeriodJSON,
      monthlyGoal: monthlyGoal,
      archivedAt: archivedAt,
      deletedAt: deletedAt,
      createdAt: createdAt,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      syncStatus: syncStatus,
      dirtyFields: dirtyFields,
      lastSyncedSnapshot: lastSyncedSnapshot,
      localUpdatedAt: localUpdatedAt,
      conflictServerSnapshot: conflictServerSnapshot
    )
    copy.syncStatusRaw = syncStatusRaw
    return copy
  }
}

extension LocalUserShift: UnmanagedCopyable {
  func unmanagedCopy() -> sending LocalUserShift {
    let copy = LocalUserShift(
      id: id,
      userId: userId,
      jobId: jobId,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      note: note,
      customPauseWindows: customPauseWindows,
      customSupplements: customSupplements,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      syncStatus: syncStatus,
      dirtyFields: dirtyFields,
      lastSyncedSnapshot: lastSyncedSnapshot,
      localUpdatedAt: localUpdatedAt,
      conflictServerSnapshot: conflictServerSnapshot
    )
    copy.syncStatusRaw = syncStatusRaw
    copy.note = note
    return copy
  }
}

extension LocalEvent: UnmanagedCopyable {
  func unmanagedCopy() -> sending LocalEvent {
    let copy = LocalEvent(
      id: id,
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      isAllDay: isAllDay,
      startTime: startTime,
      endTime: endTime,
      note: note,
      notificationMinutesArray: notificationMinutesArray,
      notificationAnchorTime: notificationAnchorTime,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      syncStatus: syncStatus,
      dirtyFields: dirtyFields,
      lastSyncedSnapshot: lastSyncedSnapshot,
      localUpdatedAt: localUpdatedAt,
      conflictServerSnapshot: conflictServerSnapshot
    )
    copy.syncStatusRaw = syncStatusRaw
    copy.notificationMinutesArray = notificationMinutesArray
    copy.notificationAnchorTime = notificationAnchorTime
    return copy
  }
}

extension LocalRecurringShift: UnmanagedCopyable {
  func unmanagedCopy() -> sending LocalRecurringShift {
    let copy = LocalRecurringShift(
      id: id,
      userId: userId,
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
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      syncStatus: syncStatus,
      dirtyFields: dirtyFields,
      lastSyncedSnapshot: lastSyncedSnapshot,
      localUpdatedAt: localUpdatedAt,
      conflictServerSnapshot: conflictServerSnapshot
    )
    copy.syncStatusRaw = syncStatusRaw
    return copy
  }
}

extension LocalWageSnapshot: UnmanagedCopyable {
  func unmanagedCopy() -> sending LocalWageSnapshot {
    let copy = LocalWageSnapshot(
      id: id,
      userId: userId,
      jobId: jobId,
      fromDate: fromDate,
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
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      syncStatus: syncStatus,
      dirtyFields: dirtyFields,
      lastSyncedSnapshot: lastSyncedSnapshot,
      localUpdatedAt: localUpdatedAt,
      conflictServerSnapshot: conflictServerSnapshot
    )
    copy.syncStatusRaw = syncStatusRaw
    return copy
  }
}

extension LocalPayrollAdjustment: UnmanagedCopyable {
  func unmanagedCopy() -> sending LocalPayrollAdjustment {
    let copy = LocalPayrollAdjustment(
      id: id,
      userId: userId,
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
      earnedFromDate: earnedFromDate,
      earnedToDate: earnedToDate,
      payoutDate: payoutDate,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      syncStatus: syncStatus,
      dirtyFields: dirtyFields,
      lastSyncedSnapshot: lastSyncedSnapshot,
      localUpdatedAt: localUpdatedAt,
      conflictServerSnapshot: conflictServerSnapshot
    )
    copy.categoryRaw = categoryRaw
    copy.taxTreatmentRaw = taxTreatmentRaw
    copy.syncStatusRaw = syncStatusRaw
    return copy
  }
}

extension LocalUserSettings: UnmanagedCopyable {
  func unmanagedCopy() -> sending LocalUserSettings {
    let copy = LocalUserSettings(
      userId: userId,
      monthlyGoal: monthlyGoal,
      monthlyGoalsByMonthData: monthlyGoalsByMonthData,
      defaultShiftsView: defaultShiftsView,
      profilePictureUrl: profilePictureUrl,
      payrollDay: payrollDay,
      theme: theme,
      calendarContentColorStyle: calendarContentColorStyle,
      showDashboardClockButtons: showDashboardClockButtons,
      halfTaxMonth: halfTaxMonth,
      currency: currency,
      defaultStartupTab: defaultStartupTab,
      lastActive: lastActive,
      createdAt: createdAt,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      syncStatus: syncStatus,
      dirtyFields: dirtyFields,
      lastSyncedSnapshot: lastSyncedSnapshot,
      localUpdatedAt: localUpdatedAt,
      conflictServerSnapshot: conflictServerSnapshot
    )
    copy.syncStatusRaw = syncStatusRaw
    return copy
  }
}

extension LocalSyncState: UnmanagedCopyable {
  func unmanagedCopy() -> sending LocalSyncState {
    let copy = LocalSyncState(
      userId: userId,
      lastRevisionUserShifts: lastRevisionUserShifts,
      lastRevisionRecurringShifts: lastRevisionRecurringShifts,
      lastRevisionWageSnapshots: lastRevisionWageSnapshots,
      lastRevisionUserSettings: lastRevisionUserSettings,
      lastRevisionJobs: lastRevisionJobs,
      lastRevisionEvents: lastRevisionEvents,
      lastRevisionPayrollAdjustments: lastRevisionPayrollAdjustments,
      lastRevisionNotificationPreferences: lastRevisionNotificationPreferences,
      convexCursorsResetAt: convexCursorsResetAt,
      lastSuccessfulSyncAt: lastSuccessfulSyncAt,
      lastSyncAttemptAt: lastSyncAttemptAt,
      lastSyncError: lastSyncError,
      lastJobsUpdatedAt: lastJobsUpdatedAt,
      lastJobsUpdatedAtTieId: lastJobsUpdatedAtTieId,
      lastUserShiftsUpdatedAt: lastUserShiftsUpdatedAt,
      lastUserShiftsUpdatedAtTieId: lastUserShiftsUpdatedAtTieId,
      lastEventsUpdatedAt: lastEventsUpdatedAt,
      lastEventsUpdatedAtTieId: lastEventsUpdatedAtTieId,
      lastRecurringShiftsUpdatedAt: lastRecurringShiftsUpdatedAt,
      lastRecurringShiftsUpdatedAtTieId: lastRecurringShiftsUpdatedAtTieId,
      lastWageSnapshotsUpdatedAt: lastWageSnapshotsUpdatedAt,
      lastWageSnapshotsUpdatedAtTieId: lastWageSnapshotsUpdatedAtTieId,
      lastPayrollAdjustmentsUpdatedAt: lastPayrollAdjustmentsUpdatedAt,
      lastPayrollAdjustmentsUpdatedAtTieId: lastPayrollAdjustmentsUpdatedAtTieId,
      lastUserSettingsUpdatedAt: lastUserSettingsUpdatedAt,
      lastUserSettingsUpdatedAtTieId: lastUserSettingsUpdatedAtTieId,
      lastNotificationPreferencesUpdatedAt: lastNotificationPreferencesUpdatedAt,
      lastNotificationPreferencesUpdatedAtTieId: lastNotificationPreferencesUpdatedAtTieId
    )
    return copy
  }
}
