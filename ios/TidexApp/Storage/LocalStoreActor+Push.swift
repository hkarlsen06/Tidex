import Foundation
import SwiftData
import os.log

extension LocalStoreActor {

  // MARK: - Push Operations for User Shifts

  // MARK: - Push Operations for Jobs

  // swiftlint:disable:next function_parameter_count
  internal func markJobPushed(
    id: String,
    serverRow: SyncJobRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    archivedAt: Date?,
    deletedAt: Date?,
    snapshot: JobServerSnapshot,
    baseline: SyncPushBaseline
  ) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    if keepChangesMadeDuringPush(
      existing,
      baseline: baseline,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      snapshot: snapshot
    ) {
      return
    }

    existing.name = serverRow.name
    existing.color = serverRow.color
    existing.currency = serverRow.currency
    existing.isDefault = serverRow.is_default
    existing.sortOrder = serverRow.sort_order
    existing.payrollDay = serverRow.payroll_day
    existing.halfTaxMonth = serverRow.half_tax_month
    existing.payPeriodJSON = serverRow.pay_period?.storageJSON
    existing.monthlyGoal = serverRow.monthly_goal
    existing.archivedAt = archivedAt
    existing.deletedAt = deletedAt
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func markJobClean(id: String) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  internal func markJobDeleted(
    id: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    deletedAt: Date?
  ) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.deletedAt = deletedAt
    existing.isDefault = false
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  // swiftlint:disable:next function_parameter_count
  internal func rebaseJob(
    id: String,
    serverRow: SyncJobRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    archivedAt: Date?,
    deletedAt: Date?,
    newSnapshot: JobServerSnapshot
  ) {
    autoMergeJob(
      id: id,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      archivedAt: archivedAt,
      deletedAt: deletedAt,
      newSnapshot: newSnapshot
    )
  }

  internal func resolveJobConflictKeepServer(id: String, serverSnapshot: JobServerSnapshot) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.name = serverSnapshot.name
    existing.color = serverSnapshot.color
    existing.currency = serverSnapshot.currency
    existing.isDefault = serverSnapshot.isDefault
    existing.sortOrder = serverSnapshot.sortOrder
    existing.payrollDay = serverSnapshot.payrollDay
    existing.halfTaxMonth = serverSnapshot.halfTaxMonth
    existing.payPeriodJSON = serverSnapshot.payPeriod.storageJSON
    existing.monthlyGoal = serverSnapshot.monthlyGoal
    existing.archivedAt = serverSnapshot.archivedAt
    existing.deletedAt = serverSnapshot.deletedAt
    existing.serverUpdatedAt = serverSnapshot.updatedAt
    existing.serverRevision = serverSnapshot.revision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = serverSnapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func resolveJobConflictKeepLocal(id: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
  }

  /// Mark a shift as successfully pushed (clean)
  internal func markShiftPushed(  // swiftlint:disable:this function_parameter_count
    id: String,
    serverRow: SyncShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: UserShiftServerSnapshot,
    baseline: SyncPushBaseline
  ) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    if keepChangesMadeDuringPush(
      existing,
      baseline: baseline,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      snapshot: snapshot
    ) {
      return
    }

    let dateFormatter = isoDateFormatter

    // Update with canonical server values
    existing.jobId = serverRow.job_id
    existing.shiftDate = dateFormatter.date(from: serverRow.shift_date) ?? existing.shiftDate
    existing.startTime = serverRow.start_time
    existing.endTime = serverRow.end_time
    existing.note = ShiftNoteSupport.normalize(serverRow.note)
    existing.customPauseWindows = PauseWindowSupport.normalize(serverRow.custom_pause_windows)
      .flatMap { pauseWindows in
        try? kCanonicalJSONEncoder.encode(pauseWindows)
      }
    existing.customSupplements = serverRow.custom_supplements.flatMap { supplements in
      try? kCanonicalJSONEncoder.encode(supplements)
    }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  /// Mark a shift as clean (no dirty fields)
  internal func markShiftClean(id: String) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  /// Mark a shift as successfully deleted
  internal func markShiftDeleted(
    id: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?
  ) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  /// Rebase a shift (update server metadata, keep local dirty fields)
  internal func rebaseShift(  // swiftlint:disable:this function_parameter_count
    id: String,
    serverRow: SyncShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: UserShiftServerSnapshot
  ) {
    // Same as autoMergeShift - apply server changes for non-dirty fields
    autoMergeShift(
      id: id,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      newSnapshot: newSnapshot
    )
  }

  /// Resolve shift conflict by keeping server version
  internal func resolveShiftConflictKeepServer(id: String, serverSnapshot: UserShiftServerSnapshot)
  {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    // Overwrite local with server snapshot
    existing.jobId = serverSnapshot.jobId
    existing.shiftDate = dateFormatter.date(from: serverSnapshot.shiftDate) ?? existing.shiftDate
    existing.startTime = serverSnapshot.startTime
    existing.endTime = serverSnapshot.endTime
    existing.note = serverSnapshot.note
    existing.customPauseWindows = serverSnapshot.customPauseWindows
    existing.customSupplements = serverSnapshot.customSupplements
    existing.serverUpdatedAt = serverSnapshot.updatedAt
    existing.serverRevision = serverSnapshot.revision
    existing.serverDeletedAt = serverSnapshot.deletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = serverSnapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  /// Resolve shift conflict by keeping local version (prepare for push)
  internal func resolveShiftConflictKeepLocal(id: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    // Update server revision so next push uses correct revision
    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
    // Keep dirtyFieldKeys - they contain the fields we want to push
  }

  // MARK: - Push Operations for Events

  // swiftlint:disable:next function_parameter_count
  internal func markEventPushed(
    id: String,
    serverRow: SyncEventRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: EventServerSnapshot,
    baseline: SyncPushBaseline
  ) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    if keepChangesMadeDuringPush(
      existing,
      baseline: baseline,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      snapshot: snapshot
    ) {
      return
    }

    let dateFormatter = isoDateFormatter

    existing.startDate = dateFormatter.date(from: serverRow.start_date) ?? existing.startDate
    existing.endDate = dateFormatter.date(from: serverRow.end_date) ?? existing.endDate
    existing.isAllDay = serverRow.is_all_day
    existing.startTime = serverRow.start_time
    existing.endTime = serverRow.end_time
    existing.note = serverRow.note
    existing.notificationMinutesArray =
      LocalEvent.normalizedReminderMinutes(serverRow.notification_minutes_array)
    existing.notificationAnchorTime =
      LocalEvent.normalizedAnchorTime(serverRow.notification_anchor_time)
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func markEventClean(id: String) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  internal func markEventDeleted(
    id: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?
  ) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  // swiftlint:disable:next function_parameter_count
  internal func rebaseEvent(
    id: String,
    serverRow: SyncEventRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: EventServerSnapshot
  ) {
    autoMergeEvent(
      id: id,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      newSnapshot: newSnapshot
    )
  }

  internal func resolveEventConflictKeepServer(id: String, serverSnapshot: EventServerSnapshot) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    existing.startDate = dateFormatter.date(from: serverSnapshot.startDate) ?? existing.startDate
    existing.endDate = dateFormatter.date(from: serverSnapshot.endDate) ?? existing.endDate
    existing.isAllDay = serverSnapshot.isAllDay
    existing.startTime = serverSnapshot.startTime
    existing.endTime = serverSnapshot.endTime
    existing.note = serverSnapshot.note
    existing.notificationMinutesArray =
      LocalEvent.normalizedReminderMinutes(serverSnapshot.notificationMinutesArray)
    existing.notificationAnchorTime =
      LocalEvent.normalizedAnchorTime(serverSnapshot.notificationAnchorTime)
    existing.serverUpdatedAt = serverSnapshot.updatedAt
    existing.serverRevision = serverSnapshot.revision
    existing.serverDeletedAt = serverSnapshot.deletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = serverSnapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func resolveEventConflictKeepLocal(id: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
  }

  // MARK: - Push Operations for Recurring Shifts

  // swiftlint:disable:next function_parameter_count function_body_length
  internal func markRecurringShiftPushed(
    id: String,
    serverRow: SyncRecurringShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: RecurringShiftServerSnapshot,
    baseline: SyncPushBaseline
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    if keepChangesMadeDuringPush(
      existing,
      baseline: baseline,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      snapshot: snapshot
    ) {
      return
    }

    existing.jobId = serverRow.job_id
    existing.startTime = serverRow.cleanStartTime
    existing.endTime = serverRow.cleanEndTime
    existing.repeatIntervalWeeks = serverRow.repeat_interval_weeks
    existing.selectedDays = (try? kCanonicalJSONEncoder.encode(serverRow.selected_days)) ?? Data()
    existing.endCondition = serverRow.end_condition.flatMap { endCondition in
      try? kCanonicalJSONEncoder.encode(endCondition)
    }
    existing.exclusions = serverRow.exclusions.flatMap { exclusions in
      try? kCanonicalJSONEncoder.encode(exclusions)
    }
    existing.dateSpecificPauseWindows =
      PauseWindowSupport.normalize(serverRow.date_specific_pause_windows)
      .flatMap { pauseWindows in
        try? kCanonicalJSONEncoder.encode(pauseWindows)
      }
    existing.dateSpecificSupplements = serverRow.date_specific_supplements.flatMap {
      supplements in
      try? kCanonicalJSONEncoder.encode(supplements)
    }
    existing.dateSpecificNotes = ShiftNoteSupport.normalizeDateSpecificNotes(
      serverRow.date_specific_notes
    )
    .flatMap { notes in
      try? kCanonicalJSONEncoder.encode(notes)
    }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func markRecurringShiftClean(id: String) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  internal func markRecurringShiftDeleted(
    id: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  // swiftlint:disable:next function_parameter_count
  internal func rebaseRecurringShift(
    id: String,
    serverRow: SyncRecurringShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: RecurringShiftServerSnapshot
  ) {
    autoMergeRecurringShift(
      id: id,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      newSnapshot: newSnapshot
    )
  }

  internal func resolveRecurringShiftConflictKeepServer(
    id: String, serverSnapshot: RecurringShiftServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.jobId = serverSnapshot.jobId
    existing.startTime = serverSnapshot.startTime
    existing.endTime = serverSnapshot.endTime
    existing.repeatIntervalWeeks = serverSnapshot.repeatIntervalWeeks
    existing.selectedDays = serverSnapshot.selectedDays
    existing.endCondition = serverSnapshot.endCondition
    existing.exclusions = serverSnapshot.exclusions
    existing.dateSpecificPauseWindows = serverSnapshot.dateSpecificPauseWindows
    existing.dateSpecificSupplements = serverSnapshot.dateSpecificSupplements
    existing.dateSpecificNotes = serverSnapshot.dateSpecificNotes
    existing.serverUpdatedAt = serverSnapshot.updatedAt
    existing.serverRevision = serverSnapshot.revision
    existing.serverDeletedAt = serverSnapshot.deletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = serverSnapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func resolveRecurringShiftConflictKeepLocal(id: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
  }

  // MARK: - Push Operations for Wage Snapshots

  // swiftlint:disable:next function_parameter_count
  internal func markWageSnapshotPushed(
    id: String,
    serverRow: SyncWageSnapshotRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: WageSnapshotServerSnapshot,
    baseline: SyncPushBaseline
  ) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    if keepChangesMadeDuringPush(
      existing,
      baseline: baseline,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      snapshot: snapshot
    ) {
      return
    }

    let dateFormatter = isoDateFormatter

    existing.jobId = serverRow.job_id
    existing.fromDate = serverRow.from_date.flatMap { dateFormatter.date(from: $0) }
    existing.hourlyWage = serverRow.hourly_wage
    existing.wageLevel = serverRow.wage_level
    existing.tariffTypeId = serverRow.tariff_type_id
    existing.supplements = (try? kCanonicalJSONEncoder.encode(serverRow.supplements)) ?? Data()
    existing.overtime =
      (try? kCanonicalJSONEncoder.encode(serverRow.overtime ?? .disabled)) ?? Data()
    existing.taxEnabled = serverRow.tax_enabled
    existing.taxPercentage = serverRow.tax_percentage
    existing.breakEnabled = serverRow.break_enabled
    existing.breakMethod = serverRow.break_method
    existing.breakThresholdHours = serverRow.break_threshold_hours
    existing.breakDeductionMinutes = serverRow.break_deduction_minutes
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func markWageSnapshotClean(id: String) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  internal func markWageSnapshotDeleted(
    id: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?
  ) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  // swiftlint:disable:next function_parameter_count
  internal func rebaseWageSnapshot(
    id: String,
    serverRow: SyncWageSnapshotRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: WageSnapshotServerSnapshot
  ) {
    autoMergeWageSnapshot(
      id: id,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      newSnapshot: newSnapshot
    )
  }

  internal func resolveWageSnapshotConflictKeepServer(
    id: String, serverSnapshot: WageSnapshotServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    existing.jobId = serverSnapshot.jobId
    existing.fromDate = serverSnapshot.fromDate.flatMap { dateFormatter.date(from: $0) }
    existing.hourlyWage = serverSnapshot.hourlyWage
    existing.wageLevel = serverSnapshot.wageLevel
    existing.tariffTypeId = serverSnapshot.tariffTypeId
    existing.supplements = serverSnapshot.supplements
    existing.overtime = serverSnapshot.overtime
    existing.taxEnabled = serverSnapshot.taxEnabled
    existing.taxPercentage = serverSnapshot.taxPercentage
    existing.breakEnabled = serverSnapshot.breakEnabled
    existing.breakMethod = serverSnapshot.breakMethod
    existing.breakThresholdHours = serverSnapshot.breakThresholdHours
    existing.breakDeductionMinutes = serverSnapshot.breakDeductionMinutes
    existing.serverUpdatedAt = serverSnapshot.updatedAt
    existing.serverRevision = serverSnapshot.revision
    existing.serverDeletedAt = serverSnapshot.deletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = serverSnapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func resolveWageSnapshotConflictKeepLocal(id: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
  }

  // MARK: - Push Operations for User Settings

  // swiftlint:disable:next function_parameter_count
  internal func markUserSettingsPushed(
    userId: String,
    serverRow: SyncUserSettingsRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: UserSettingsServerSnapshot,
    baseline: SyncPushBaseline
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    if keepChangesMadeDuringPush(
      existing,
      baseline: baseline,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      snapshot: snapshot
    ) {
      return
    }

    let dateFormatter = FormatterCache.iso8601Formatter()

    existing.monthlyGoal = serverRow.monthly_goal
    existing.monthlyGoalsByMonth = serverRow.monthly_goals_by_month ?? [:]
    existing.defaultShiftsView = serverRow.default_shifts_view
    existing.profilePictureUrl = serverRow.profile_picture_url
    existing.payrollDay = serverRow.payroll_day
    existing.theme = serverRow.theme
    existing.calendarContentColorStyle = serverRow.calendar_content_color_style ?? "workplace"
    existing.showDashboardClockButtons = serverRow.show_dashboard_clock_buttons ?? true
    existing.halfTaxMonth = serverRow.half_tax_month
    existing.currency = serverRow.currency
    existing.defaultStartupTab = serverRow.default_startup_tab
    existing.lastActive = serverRow.last_active.flatMap { dateFormatter.date(from: $0) }
    existing.createdAt = serverRow.created_at.flatMap { dateFormatter.date(from: $0) }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func markUserSettingsClean(userId: String) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  internal func rebaseUserSettings(
    userId: String,
    serverRow: SyncUserSettingsRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    newSnapshot: UserSettingsServerSnapshot
  ) {
    autoMergeUserSettings(
      userId: userId,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      newSnapshot: newSnapshot
    )
  }

  internal func resolveUserSettingsConflictKeepServer(
    userId: String, serverSnapshot: UserSettingsServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.monthlyGoal = serverSnapshot.monthlyGoal
    existing.monthlyGoalsByMonth = serverSnapshot.monthlyGoalsByMonth
    existing.defaultShiftsView = serverSnapshot.defaultShiftsView
    existing.profilePictureUrl = serverSnapshot.profilePictureUrl
    existing.payrollDay = serverSnapshot.payrollDay
    existing.theme = serverSnapshot.theme
    existing.calendarContentColorStyle = serverSnapshot.calendarContentColorStyle
    existing.showDashboardClockButtons = serverSnapshot.showDashboardClockButtons
    existing.halfTaxMonth = serverSnapshot.halfTaxMonth
    existing.currency = serverSnapshot.currency
    existing.defaultStartupTab = serverSnapshot.defaultStartupTab
    existing.lastActive = serverSnapshot.lastActive
    existing.serverUpdatedAt = serverSnapshot.updatedAt
    existing.serverRevision = serverSnapshot.revision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = serverSnapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func resolveUserSettingsConflictKeepLocal(userId: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
  }
}
