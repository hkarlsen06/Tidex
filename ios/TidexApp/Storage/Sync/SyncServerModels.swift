import Foundation

// MARK: - Server Row Types for Sync

internal struct SyncRowId: Codable {
  internal let id: String
}

/// Extended shift row with sync metadata fields
/// Used when fetching from server for sync (includes updated_at, revision, deleted_at)
internal struct SyncShiftRow: Codable {
  internal let id: String
  internal let user_id: String
  internal let job_id: String?
  internal let shift_date: String
  internal let start_time: String
  internal let end_time: String
  internal let note: String?
  internal let custom_pause_windows: CustomPauseWindows?
  internal let custom_supplements: CustomSupplementsData?
  internal let created_at: String?
  internal let updated_at: String
  internal let revision: Int64
  internal let deleted_at: String?

  /// Convert to regular ShiftRow (for compatibility)
  internal func toShiftRow() -> ShiftRow {
    ShiftRow(
      id: id,
      user_id: user_id,
      job_id: job_id,
      shift_date: shift_date,
      start_time: start_time,
      end_time: end_time,
      note: note,
      custom_pause_windows: custom_pause_windows,
      custom_supplements: custom_supplements,
      created_at: created_at
    )
  }
}

/// Extended event row with sync metadata fields.
internal struct SyncEventRow: Codable {
  internal let id: String
  internal let user_id: String
  internal let start_date: String
  internal let end_date: String
  internal let is_all_day: Bool
  internal let start_time: String?
  internal let end_time: String?
  internal let note: String
  internal let notification_minutes_array: [Int]?
  internal let notification_anchor_time: String?
  internal let created_at: String?
  internal let updated_at: String
  internal let revision: Int64
  internal let deleted_at: String?

  internal func toEventRow() -> EventRow {
    EventRow(
      id: id,
      user_id: user_id,
      start_date: start_date,
      end_date: end_date,
      is_all_day: is_all_day,
      start_time: start_time,
      end_time: end_time,
      note: note,
      notification_minutes_array: notification_minutes_array,
      notification_anchor_time: notification_anchor_time,
      created_at: created_at
    )
  }
}

/// Extended recurring shift row with sync metadata fields
internal struct SyncRecurringShiftRow: Codable {
  private static let timeZoneOffsetSeparatorMinimumIndex: Int = 2
  private static let timePrefixLength: Int = 5

  internal let id: String
  internal let user_id: String
  internal let job_id: String?
  internal let start_time: String
  internal let end_time: String
  internal let repeat_interval_weeks: Int
  internal let selected_days: SelectedDays
  internal let end_condition: EndCondition?
  internal let exclusions: [String]?
  internal let date_specific_pause_windows: DateSpecificPauseWindows?
  internal let date_specific_supplements: [String: CustomSupplementsData]?
  internal let date_specific_notes: [String: String]?
  internal let updated_at: String
  internal let revision: Int64
  internal let deleted_at: String?

  /// Clean start time (removes timezone suffix from timetz)
  internal var cleanStartTime: String {
    cleanTime(start_time)
  }

  /// Clean end time (removes timezone suffix from timetz)
  internal var cleanEndTime: String {
    cleanTime(end_time)
  }

  private func cleanTime(_ time: String) -> String {
    var cleaned: String = time

    if let plusIndex = cleaned.firstIndex(of: "+") {
      cleaned = String(cleaned[..<plusIndex])
    }

    if let minusIndex = cleaned.lastIndex(of: "-"),
      cleaned.distance(from: cleaned.startIndex, to: minusIndex)
        > Self.timeZoneOffsetSeparatorMinimumIndex
    {
      cleaned = String(cleaned[..<minusIndex])
    }

    return String(cleaned.prefix(Self.timePrefixLength))
  }

  /// Convert to regular RecurringShiftRow
  internal func toRecurringShiftRow() -> RecurringShiftRow {
    RecurringShiftRow(
      id: id,
      user_id: user_id,
      job_id: job_id,
      start_time: start_time,
      end_time: end_time,
      repeat_interval_weeks: repeat_interval_weeks,
      selected_days: selected_days,
      end_condition: end_condition,
      exclusions: exclusions,
      date_specific_pause_windows: date_specific_pause_windows,
      date_specific_supplements: date_specific_supplements,
      date_specific_notes: date_specific_notes
    )
  }
}

/// Extended wage snapshot row with sync metadata fields
internal struct SyncWageSnapshotRow: Codable {
  internal let id: String
  internal let user_id: String
  internal let job_id: String?
  internal let from_date: String?
  internal let hourly_wage: Double
  internal let wage_level: Int?
  internal let tariff_type_id: String?
  internal let supplements: SupplementRulesSnapshot
  internal let overtime: OvertimeConfig?
  internal let tax_enabled: Bool?
  internal let tax_percentage: Double?
  internal let break_enabled: Bool?
  internal let break_method: String?
  internal let break_threshold_hours: Double?
  internal let break_deduction_minutes: Int?
  internal let created_at: String?
  internal let updated_at: String
  internal let revision: Int64
  internal let deleted_at: String?

  /// Convert to regular WageSnapshot
  internal func toWageSnapshot() -> WageSnapshot {
    WageSnapshot(
      id: id,
      user_id: user_id,
      job_id: job_id,
      from_date: from_date,
      hourly_wage: hourly_wage,
      wage_level: wage_level,
      tariff_type_id: tariff_type_id,
      supplements: supplements,
      overtime: overtime ?? .disabled,
      tax_enabled: tax_enabled,
      tax_percentage: tax_percentage,
      break_enabled: break_enabled,
      break_method: break_method,
      break_threshold_hours: break_threshold_hours,
      break_deduction_minutes: break_deduction_minutes,
      created_at: created_at
    )
  }
}

/// Extended payroll adjustment row with sync metadata fields
internal struct SyncPayrollAdjustmentRow: Codable {
  internal let id: String
  internal let user_id: String
  internal let job_id: String?
  internal let amount: Double
  internal let currency: String
  internal let category: PayrollAdjustmentCategory
  internal let tax_treatment: PayrollAdjustmentTaxTreatment
  internal let description: String
  internal let note: String?
  internal let curated_note: String?
  internal let curated_description: String?
  internal let curated_link: String?
  internal let curated_link_title: String?
  internal let earned_from_date: String?
  internal let earned_to_date: String?
  internal let payout_date: String
  internal let created_at: String?
  internal let updated_at: String
  internal let revision: Int64
  internal let deleted_at: String?

  internal func toPayrollAdjustment() -> PayrollAdjustment {
    PayrollAdjustment(
      id: id,
      user_id: user_id,
      job_id: job_id,
      amount: amount,
      currency: currency,
      category: category,
      tax_treatment: tax_treatment,
      description: description,
      note: note,
      curated_note: curated_note,
      curated_description: curated_description,
      curated_link: curated_link,
      curated_link_title: curated_link_title,
      earned_from_date: earned_from_date,
      earned_to_date: earned_to_date,
      payout_date: payout_date,
      created_at: created_at,
      updated_at: updated_at,
      revision: revision,
      deleted_at: deleted_at
    )
  }
}

/// Extended jobs row with sync metadata fields
internal struct SyncJobRow: Codable {
  internal let id: String
  internal let user_id: String
  internal let name: String
  internal let color: String?
  internal let currency: String
  internal let is_default: Bool
  internal let sort_order: Int
  internal let payroll_day: Int?
  internal let half_tax_month: Int?
  internal let monthly_goal: Int?
  internal let archived_at: String?
  internal let deleted_at: String?
  internal let created_at: String?
  internal let updated_at: String
  internal let revision: Int64

  private enum CodingKeys: String, CodingKey {
    case id
    case user_id
    case name
    case color
    case currency
    case is_default
    case sort_order
    case payroll_day
    case half_tax_month
    case monthly_goal
    case archived_at
    case deleted_at
    case created_at
    case updated_at
    case revision
  }

  internal init(from decoder: Decoder) throws {
    let container: KeyedDecodingContainer<CodingKeys> =
      try decoder.container(keyedBy: CodingKeys.self)

    id = try container.decode(String.self, forKey: .id)
    user_id = try container.decode(String.self, forKey: .user_id)
    name = try container.decode(String.self, forKey: .name)
    color = try container.decodeIfPresent(String.self, forKey: .color)
    currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "kr"
    is_default = try container.decode(Bool.self, forKey: .is_default)
    sort_order = try container.decode(Int.self, forKey: .sort_order)
    payroll_day = try container.decodeIfPresent(Int.self, forKey: .payroll_day)
    half_tax_month = try container.decodeIfPresent(Int.self, forKey: .half_tax_month)
    monthly_goal = try container.decodeIfPresent(Int.self, forKey: .monthly_goal)
    archived_at = try container.decodeIfPresent(String.self, forKey: .archived_at)
    deleted_at = try container.decodeIfPresent(String.self, forKey: .deleted_at)
    created_at = try container.decodeIfPresent(String.self, forKey: .created_at)
    updated_at = try container.decode(String.self, forKey: .updated_at)
    revision = try container.decode(Int64.self, forKey: .revision)
  }
}

/// Extended user settings row with sync metadata fields
internal struct SyncUserSettingsRow: Codable {
  internal let user_id: String
  internal let created_at: String?
  internal let updated_at: String
  internal let last_active: String?
  internal let monthly_goal: Int?
  internal let monthly_goals_by_month: [String: Int]?
  internal let default_shifts_view: String?
  internal let profile_picture_url: String?
  internal let payroll_day: Int?
  internal let theme: String
  internal let calendar_content_color_style: String?
  internal let show_dashboard_clock_buttons: Bool?
  internal let ai_data_sharing_enabled: Bool?
  internal let half_tax_month: Int?
  internal let currency: String?
  internal let default_startup_tab: String?
  internal let wagey_showcase_seen: Bool?  // swiftlint:disable:this identifier_name
  internal let revision: Int64

  /// Convert to regular UserSettings
  internal func toUserSettings() -> UserSettings {
    UserSettings(
      user_id: user_id,
      created_at: created_at,
      updated_at: updated_at,
      last_active: last_active,
      monthly_goal: monthly_goal,
      monthly_goals_by_month: monthly_goals_by_month,
      default_shifts_view: default_shifts_view,
      profile_picture_url: profile_picture_url,
      payroll_day: payroll_day,
      theme: theme,
      calendar_content_color_style: calendar_content_color_style ?? "workplace",
      show_dashboard_clock_buttons: show_dashboard_clock_buttons,
      ai_data_sharing_enabled: ai_data_sharing_enabled,
      half_tax_month: half_tax_month,
      currency: currency,
      default_startup_tab: default_startup_tab,
      wagey_showcase_seen: wagey_showcase_seen
    )
  }
}

/// Notification preferences row for sync
/// Note: This table has no revision column - iOS is the source of truth
internal struct SyncNotificationPreferencesRow: Codable {
  internal let user_id: String
  internal let shift_reminders_enabled: Bool
  internal let shift_reminder_minutes_array: [Int]?
  internal let shared_shifts_enabled: Bool
  internal let updated_at: String

  /// Convert to NotificationPreferencesRow
  internal func toNotificationPreferencesRow() -> NotificationPreferencesRow {
    NotificationPreferencesRow(
      user_id: user_id,
      shared_shifts_enabled: shared_shifts_enabled,
      shift_reminders_enabled: shift_reminders_enabled,
      shift_reminder_minutes_array: shift_reminder_minutes_array,
      updated_at: updated_at
    )
  }
}

// MARK: - Sync Result Types

/// Result of pulling a single table
internal struct TablePullResult {
  internal let table: SyncTable
  internal let rowsProcessed: Int
  /// Last updated_at timestamp processed (for cursor)
  internal let lastUpdatedAt: Date?
  /// ID of the last row at the lastUpdatedAt timestamp (tie-breaker)
  internal let lastUpdatedAtTieId: String?
  /// Legacy max revision (kept for debugging only)
  internal let maxRevision: Int64
  internal let newConflicts: Int, autoMerged: Int
  internal let affectedMonths: Set<ShiftChangeAffectedMonth>
}

/// Overall sync result
internal struct SyncResult {
  internal let success: Bool
  internal let tableResults: [TablePullResult]
  internal let pushResults: [TablePushResult]
  internal let totalRowsProcessed: Int
  internal let totalRowsPushed: Int
  internal let totalConflicts: Int
  internal let totalAutoMerged: Int
  internal let duration: TimeInterval
  internal let error: String?

  internal var hasConflicts: Bool {
    totalConflicts > 0
  }
}

// MARK: - Push Result Types

/// Result of pushing a single table
internal struct TablePushResult {
  internal let table: SyncTable
  internal let rowsPushed: Int, newConflicts: Int, rebased: Int
  internal let affectedMonths: Set<ShiftChangeAffectedMonth> = []
}

// MARK: - Sync Completion Summary

internal struct SyncTableChange: Equatable {
  internal let table: SyncTable
  internal let pulledRows: Int, pushedRows: Int, newConflicts: Int, autoMerged: Int, rebased: Int
  internal let affectedMonths: Set<ShiftChangeAffectedMonth>

  internal var changesLocalReadModels: Bool {
    pulledRows > 0 || newConflicts > 0 || autoMerged > 0 || rebased > 0
  }
}

internal struct SyncCompletionSummary: Equatable {
  internal let reason: SyncReason
  internal let userId: String
  internal let completedAt: Date
  internal let tableChanges: [SyncTableChange]

  internal init(
    reason: SyncReason,
    userId: String,
    tableResults: [TablePullResult],
    pushResults: [TablePushResult],
    completedAt: Date = Date()
  ) {
    self.reason = reason
    self.userId = userId
    self.completedAt = completedAt

    let pullResultsByTable: [SyncTable: TablePullResult] =
      Dictionary(uniqueKeysWithValues: tableResults.map { ($0.table, $0) })
    let pushResultsByTable: [SyncTable: TablePushResult] =
      Dictionary(uniqueKeysWithValues: pushResults.map { ($0.table, $0) })
    let tables: Set<SyncTable> = Set(pullResultsByTable.keys).union(pushResultsByTable.keys)

    self.tableChanges = tables.sorted { $0.rawValue < $1.rawValue }.map { table in
      let pullResult: TablePullResult? = pullResultsByTable[table]
      let pushResult: TablePushResult? = pushResultsByTable[table]
      return SyncTableChange(
        table: table,
        pulledRows: pullResult?.rowsProcessed ?? 0,
        pushedRows: pushResult?.rowsPushed ?? 0,
        newConflicts: (pullResult?.newConflicts ?? 0) + (pushResult?.newConflicts ?? 0),
        autoMerged: pullResult?.autoMerged ?? 0,
        rebased: pushResult?.rebased ?? 0,
        affectedMonths: (pullResult?.affectedMonths ?? []).union(pushResult?.affectedMonths ?? [])
      )
    }
  }

  internal var localReadModelChanges: [SyncTableChange] {
    tableChanges.filter(\.changesLocalReadModels)
  }

  internal var hasLocalReadModelChanges: Bool {
    !localReadModelChanges.isEmpty
  }
}

/// Result of pushing a single record
internal enum PushResult {
  case conflict
  case deleted
  case noChange
  case rebased
  case success
}

// MARK: - Conflict Resolution

/// Resolution choice for a conflict
internal enum ConflictResolution {
  /// Keep the local (iPhone) version and push to server
  case keepLocal
  /// Keep the server (Web) version and discard local changes
  case keepServer
}
