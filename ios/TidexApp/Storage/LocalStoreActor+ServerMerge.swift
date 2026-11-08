import Foundation
import SwiftData
import os.log

extension LocalStoreActor {

  // MARK: - Sync Update Operations for Jobs

  @discardableResult
  // swiftlint:disable:next function_parameter_count
  internal func updateJobFromServer(
    id: String,
    serverRow: SyncJobRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    archivedAt: Date?,
    deletedAt: Date?,
    snapshot: JobServerSnapshot
  ) -> Bool {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {
      return false
    }

    // The coordinator read the sync status outside this actor. Check it again here so a local
    // edit made since then is not overwritten.
    guard existing.syncStatus == .clean else {
      return false
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
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()

    return true
  }

  internal func markJobConflict(id: String, serverSnapshot: JobServerSnapshot?) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  internal func updateJobConflictSnapshot(id: String, serverSnapshot: JobServerSnapshot) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  // swiftlint:disable:next function_parameter_count
  internal func autoMergeJob(
    id: String,
    serverRow: SyncJobRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    archivedAt: Date?,
    deletedAt: Date?,
    newSnapshot: JobServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    // Read the dirty fields here, in the same actor turn as the merge, so a local edit saved
    // after the coordinator read the row is kept.
    let localDirtyFields = SyncMerge.fieldsToKeepLocally(existing, server: newSnapshot)

    func mergeUnlessDirty(_ field: JobField, _ apply: () -> Void) {
      if !localDirtyFields.contains(field) { apply() }
    }

    mergeUnlessDirty(.name) { existing.name = serverRow.name }
    mergeUnlessDirty(.color) { existing.color = serverRow.color }
    mergeUnlessDirty(.currency) { existing.currency = serverRow.currency }
    mergeUnlessDirty(.isDefault) { existing.isDefault = serverRow.is_default }
    mergeUnlessDirty(.sortOrder) { existing.sortOrder = serverRow.sort_order }
    mergeUnlessDirty(.payrollDay) { existing.payrollDay = serverRow.payroll_day }
    mergeUnlessDirty(.halfTaxMonth) { existing.halfTaxMonth = serverRow.half_tax_month }
    mergeUnlessDirty(.payPeriod) { existing.payPeriodJSON = serverRow.pay_period?.storageJSON }
    mergeUnlessDirty(.monthlyGoal) { existing.monthlyGoal = serverRow.monthly_goal }
    mergeUnlessDirty(.archivedAt) { existing.archivedAt = archivedAt }
    mergeUnlessDirty(.deletedAt) { existing.deletedAt = deletedAt }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.lastSyncedSnapshot = newSnapshot.encoded()
    settleMergedDirtyFields(existing, keepingLocal: localDirtyFields)
  }

  // MARK: - Sync Update Operations for User Shifts

  /// Update a shift from server data (for clean rows)
  @discardableResult
  internal func updateShiftFromServer(
    id: String,
    serverRow: SyncShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    snapshot: UserShiftServerSnapshot
  ) -> Bool {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {
      return false
    }

    // The coordinator read the sync status outside this actor. Check it again here so a local
    // edit made since then is not overwritten.
    guard existing.syncStatus == .clean else {
      return false
    }

    let dateFormatter = isoDateFormatter

    existing.jobId = serverRow.job_id
    existing.shiftDate = dateFormatter.date(from: serverRow.shift_date) ?? existing.shiftDate
    existing.startTime = serverRow.start_time
    existing.endTime = serverRow.end_time
    existing.note = ShiftNoteSupport.normalize(serverRow.note)
    existing.customPauseWindows = PauseWindowSupport.normalize(serverRow.custom_pause_windows)
      .flatMap { value in
        try? kCanonicalJSONEncoder.encode(value)
      }
    existing.customSupplements = serverRow.custom_supplements.flatMap { value in
      try? kCanonicalJSONEncoder.encode(value)
    }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()

    return true
  }

  /// Mark a shift as having a conflict
  internal func markShiftConflict(id: String, serverSnapshot: UserShiftServerSnapshot?) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  /// Update conflict snapshot for a shift already in conflict
  internal func updateShiftConflictSnapshot(id: String, serverSnapshot: UserShiftServerSnapshot) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  /// Auto-merge a shift (apply server changes for non-dirty fields)
  internal func autoMergeShift(  // swiftlint:disable:this function_parameter_count
    id: String,
    serverRow: SyncShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: UserShiftServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    // Read the dirty fields here, in the same actor turn as the merge, so a local edit saved
    // after the coordinator read the row is kept.
    let localDirtyFields = SyncMerge.fieldsToKeepLocally(existing, server: newSnapshot)

    let dateFormatter = isoDateFormatter

    // Apply server changes only for non-dirty fields
    if !localDirtyFields.contains(.jobId) {
      existing.jobId = serverRow.job_id
    }
    if !localDirtyFields.contains(.shiftDate) {
      existing.shiftDate = dateFormatter.date(from: serverRow.shift_date) ?? existing.shiftDate
    }
    if !localDirtyFields.contains(.startTime) {
      existing.startTime = serverRow.start_time
    }
    if !localDirtyFields.contains(.endTime) {
      existing.endTime = serverRow.end_time
    }
    if !localDirtyFields.contains(.note) {
      existing.note = ShiftNoteSupport.normalize(serverRow.note)
    }
    if !localDirtyFields.contains(.customPauseWindows) {
      existing.customPauseWindows = PauseWindowSupport.normalize(serverRow.custom_pause_windows)
        .flatMap { try? kCanonicalJSONEncoder.encode($0) }
    }
    if !localDirtyFields.contains(.customSupplements) {
      existing.customSupplements = serverRow.custom_supplements.flatMap { value in
        try? kCanonicalJSONEncoder.encode(value)
      }
    }

    // Update server metadata
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = newSnapshot.encoded()
    settleMergedDirtyFields(existing, keepingLocal: localDirtyFields)
  }

  // MARK: - Sync Update Operations for Events

  @discardableResult
  internal func updateEventFromServer(
    id: String,
    serverRow: SyncEventRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    snapshot: EventServerSnapshot
  ) -> Bool {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {
      return false
    }

    // The coordinator read the sync status outside this actor. Check it again here so a local
    // edit made since then is not overwritten.
    guard existing.syncStatus == .clean else {
      return false
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
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()

    return true
  }

  internal func markEventConflict(id: String, serverSnapshot: EventServerSnapshot?) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  internal func updateEventConflictSnapshot(id: String, serverSnapshot: EventServerSnapshot) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  // swiftlint:disable:next function_parameter_count
  internal func autoMergeEvent(
    id: String,
    serverRow: SyncEventRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: EventServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    // Read the dirty fields here, in the same actor turn as the merge, so a local edit saved
    // after the coordinator read the row is kept.
    let localDirtyFields = SyncMerge.fieldsToKeepLocally(existing, server: newSnapshot)

    let dateFormatter = isoDateFormatter

    if !localDirtyFields.contains(.startDate) {
      existing.startDate = dateFormatter.date(from: serverRow.start_date) ?? existing.startDate
    }
    if !localDirtyFields.contains(.endDate) {
      existing.endDate = dateFormatter.date(from: serverRow.end_date) ?? existing.endDate
    }
    if !localDirtyFields.contains(.isAllDay) {
      existing.isAllDay = serverRow.is_all_day
    }
    if !localDirtyFields.contains(.startTime) {
      existing.startTime = serverRow.start_time
    }
    if !localDirtyFields.contains(.endTime) {
      existing.endTime = serverRow.end_time
    }
    if !localDirtyFields.contains(.note) {
      existing.note = serverRow.note
    }
    if !localDirtyFields.contains(.notificationMinutesArray) {
      existing.notificationMinutesArray =
        LocalEvent.normalizedReminderMinutes(serverRow.notification_minutes_array)
    }
    if !localDirtyFields.contains(.notificationAnchorTime) {
      existing.notificationAnchorTime =
        LocalEvent.normalizedAnchorTime(serverRow.notification_anchor_time)
    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = newSnapshot.encoded()
    settleMergedDirtyFields(existing, keepingLocal: localDirtyFields)
  }

  // MARK: - Sync Update Operations for Recurring Shifts

  @discardableResult
  // swiftlint:disable:next function_body_length
  internal func updateRecurringShiftFromServer(
    id: String,
    serverRow: SyncRecurringShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    snapshot: RecurringShiftServerSnapshot
  ) -> Bool {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {
      return false
    }

    // The coordinator read the sync status outside this actor. Check it again here so a local
    // edit made since then is not overwritten.
    guard existing.syncStatus == .clean else {
      return false
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
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()

    return true
  }

  internal func markRecurringShiftConflict(
    id: String, serverSnapshot: RecurringShiftServerSnapshot?
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  internal func updateRecurringShiftConflictSnapshot(
    id: String, serverSnapshot: RecurringShiftServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  // swiftlint:disable:next function_parameter_count function_body_length
  internal func autoMergeRecurringShift(
    id: String,
    serverRow: SyncRecurringShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: RecurringShiftServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    // Read the dirty fields here, in the same actor turn as the merge, so a local edit saved
    // after the coordinator read the row is kept.
    let localDirtyFields = SyncMerge.fieldsToKeepLocally(existing, server: newSnapshot)

    if !localDirtyFields.contains(.jobId) {
      existing.jobId = serverRow.job_id
    }
    if !localDirtyFields.contains(.startTime) {
      existing.startTime = serverRow.cleanStartTime
    }
    if !localDirtyFields.contains(.endTime) {
      existing.endTime = serverRow.cleanEndTime
    }
    if !localDirtyFields.contains(.repeatIntervalWeeks) {
      existing.repeatIntervalWeeks = serverRow.repeat_interval_weeks
    }
    if !localDirtyFields.contains(.selectedDays) {
      existing.selectedDays = (try? kCanonicalJSONEncoder.encode(serverRow.selected_days)) ?? Data()
    }
    if !localDirtyFields.contains(.endCondition) {
      existing.endCondition = serverRow.end_condition.flatMap { value in
        try? kCanonicalJSONEncoder.encode(value)
      }
    }
    if !localDirtyFields.contains(.exclusions) {
      existing.exclusions = serverRow.exclusions.flatMap { try? kCanonicalJSONEncoder.encode($0) }
    }
    if !localDirtyFields.contains(.dateSpecificPauseWindows) {
      existing.dateSpecificPauseWindows =
        PauseWindowSupport.normalize(serverRow.date_specific_pause_windows)
        .flatMap { try? kCanonicalJSONEncoder.encode($0) }
    }
    if !localDirtyFields.contains(.dateSpecificSupplements) {
      existing.dateSpecificSupplements = serverRow.date_specific_supplements.flatMap { value in
        try? kCanonicalJSONEncoder.encode(value)
      }
    }
    if !localDirtyFields.contains(.dateSpecificNotes) {
      existing.dateSpecificNotes =
        ShiftNoteSupport.normalizeDateSpecificNotes(serverRow.date_specific_notes)
        .flatMap { try? kCanonicalJSONEncoder.encode($0) }
    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = newSnapshot.encoded()
    settleMergedDirtyFields(existing, keepingLocal: localDirtyFields)
  }

  // MARK: - Sync Update Operations for Wage Snapshots

  @discardableResult
  internal func updateWageSnapshotFromServer(
    id: String,
    serverRow: SyncWageSnapshotRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    snapshot: WageSnapshotServerSnapshot
  ) -> Bool {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {
      return false
    }

    // The coordinator read the sync status outside this actor. Check it again here so a local
    // edit made since then is not overwritten.
    guard existing.syncStatus == .clean else {
      return false
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
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()

    return true
  }

  internal func markWageSnapshotConflict(id: String, serverSnapshot: WageSnapshotServerSnapshot?) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  internal func updateWageSnapshotConflictSnapshot(
    id: String, serverSnapshot: WageSnapshotServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  // swiftlint:disable:next function_parameter_count
  internal func autoMergeWageSnapshot(
    id: String,
    serverRow: SyncWageSnapshotRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: WageSnapshotServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    // Read the dirty fields here, in the same actor turn as the merge, so a local edit saved
    // after the coordinator read the row is kept.
    let localDirtyFields = SyncMerge.fieldsToKeepLocally(existing, server: newSnapshot)

    let dateFormatter = isoDateFormatter

    func mergeUnlessDirty(_ field: WageSnapshotField, _ apply: () -> Void) {
      if !localDirtyFields.contains(field) { apply() }
    }

    mergeUnlessDirty(.jobId) { existing.jobId = serverRow.job_id }
    mergeUnlessDirty(.fromDate) {
      existing.fromDate = serverRow.from_date.flatMap { dateFormatter.date(from: $0) }
    }
    mergeUnlessDirty(.hourlyWage) { existing.hourlyWage = serverRow.hourly_wage }
    mergeUnlessDirty(.wageLevel) { existing.wageLevel = serverRow.wage_level }
    mergeUnlessDirty(.tariffTypeId) { existing.tariffTypeId = serverRow.tariff_type_id }
    mergeUnlessDirty(.supplements) {
      existing.supplements = (try? kCanonicalJSONEncoder.encode(serverRow.supplements)) ?? Data()
    }
    mergeUnlessDirty(.overtime) {
      existing.overtime =
        (try? kCanonicalJSONEncoder.encode(serverRow.overtime ?? .disabled)) ?? Data()
    }
    mergeUnlessDirty(.taxEnabled) { existing.taxEnabled = serverRow.tax_enabled }
    mergeUnlessDirty(.taxPercentage) { existing.taxPercentage = serverRow.tax_percentage }
    mergeUnlessDirty(.breakEnabled) { existing.breakEnabled = serverRow.break_enabled }
    mergeUnlessDirty(.breakMethod) { existing.breakMethod = serverRow.break_method }
    mergeUnlessDirty(.breakThresholdHours) {
      existing.breakThresholdHours = serverRow.break_threshold_hours
    }
    mergeUnlessDirty(.breakDeductionMinutes) {
      existing.breakDeductionMinutes = serverRow.break_deduction_minutes
    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = newSnapshot.encoded()
    settleMergedDirtyFields(existing, keepingLocal: localDirtyFields)
  }

  // MARK: - Sync Update Operations for User Settings

  @discardableResult
  internal func updateUserSettingsFromServer(
    userId: String,
    serverRow: SyncUserSettingsRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: UserSettingsServerSnapshot
  ) -> Bool {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {
      return false
    }

    // The coordinator read the sync status outside this actor. Check it again here so a local
    // edit made since then is not overwritten.
    guard existing.syncStatus == .clean else {
      return false
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
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()

    return true
  }

  internal func markUserSettingsConflict(
    userId: String, serverSnapshot: UserSettingsServerSnapshot?
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  internal func updateUserSettingsConflictSnapshot(
    userId: String, serverSnapshot: UserSettingsServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  private func mergeServerFields(
    into existing: LocalUserSettings,
    from serverRow: SyncUserSettingsRow,
    keepingLocal localDirtyFields: Set<UserSettingsField>
  ) {
    let dateFormatter = FormatterCache.iso8601Formatter()

    func mergeUnlessDirty(_ field: UserSettingsField, _ apply: () -> Void) {
      if !localDirtyFields.contains(field) { apply() }
    }

    mergeUnlessDirty(.monthlyGoal) { existing.monthlyGoal = serverRow.monthly_goal }
    mergeUnlessDirty(.monthlyGoalsByMonth) {
      existing.monthlyGoalsByMonth = serverRow.monthly_goals_by_month ?? [:]
    }
    mergeUnlessDirty(.defaultShiftsView) {
      existing.defaultShiftsView = serverRow.default_shifts_view
    }
    mergeUnlessDirty(.profilePictureUrl) {
      existing.profilePictureUrl = serverRow.profile_picture_url
    }
    mergeUnlessDirty(.payrollDay) { existing.payrollDay = serverRow.payroll_day }
    mergeUnlessDirty(.theme) { existing.theme = serverRow.theme }
    mergeUnlessDirty(.calendarContentColorStyle) {
      existing.calendarContentColorStyle = serverRow.calendar_content_color_style ?? "workplace"
    }
    mergeUnlessDirty(.showDashboardClockButtons) {
      existing.showDashboardClockButtons = serverRow.show_dashboard_clock_buttons ?? true
    }
    mergeUnlessDirty(.halfTaxMonth) { existing.halfTaxMonth = serverRow.half_tax_month }
    mergeUnlessDirty(.currency) { existing.currency = serverRow.currency }
    mergeUnlessDirty(.defaultStartupTab) {
      existing.defaultStartupTab = serverRow.default_startup_tab
    }
    mergeUnlessDirty(.lastActive) {
      existing.lastActive = serverRow.last_active.flatMap { dateFormatter.date(from: $0) }
    }
  }

  internal func autoMergeUserSettings(
    userId: String,
    serverRow: SyncUserSettingsRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    newSnapshot: UserSettingsServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    // Read the dirty fields here, in the same actor turn as the merge, so a local edit saved
    // after the coordinator read the row is kept.
    let localDirtyFields = SyncMerge.fieldsToKeepLocally(existing, server: newSnapshot)

    mergeServerFields(into: existing, from: serverRow, keepingLocal: localDirtyFields)

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.lastSyncedSnapshot = newSnapshot.encoded()
    settleMergedDirtyFields(existing, keepingLocal: localDirtyFields)
  }
}
