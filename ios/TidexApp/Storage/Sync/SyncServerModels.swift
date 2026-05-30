import Foundation

// MARK: - Server Row Types for Sync

struct SyncRowId: Codable {
  let id: String
}

/// Extended shift row with sync metadata fields
/// Used when fetching from server for sync (includes updated_at, revision, deleted_at)
struct SyncShiftRow: Codable {
  let id: String
  let user_id: String
  let job_id: String?
  let shift_date: String
  let start_time: String
  let end_time: String
  let note: String?
  let custom_pause_windows: CustomPauseWindows?
  let custom_supplements: CustomSupplementsData?
  let created_at: String?
  let updated_at: String
  let revision: Int64
  let deleted_at: String?

  /// Convert to regular ShiftRow (for compatibility)
  func toShiftRow() -> ShiftRow {
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
struct SyncEventRow: Codable {
  let id: String
  let user_id: String
  let start_date: String
  let end_date: String
  let is_all_day: Bool
  let start_time: String?
  let end_time: String?
  let note: String
  let notification_minutes_array: [Int]?
  let notification_anchor_time: String?
  let created_at: String?
  let updated_at: String
  let revision: Int64
  let deleted_at: String?

  func toEventRow() -> EventRow {
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
struct SyncRecurringShiftRow: Codable {
  let id: String
  let user_id: String
  let job_id: String?
  let start_time: String
  let end_time: String
  let repeat_interval_weeks: Int
  let selected_days: SelectedDays
  let end_condition: EndCondition?
  let exclusions: [String]?
  let date_specific_pause_windows: DateSpecificPauseWindows?
  let date_specific_supplements: [String: CustomSupplementsData]?
  let date_specific_notes: [String: String]?
  let updated_at: String
  let revision: Int64
  let deleted_at: String?

  /// Clean start time (removes timezone suffix from timetz)
  var cleanStartTime: String {
    cleanTime(start_time)
  }

  /// Clean end time (removes timezone suffix from timetz)
  var cleanEndTime: String {
    cleanTime(end_time)
  }

  private func cleanTime(_ time: String) -> String {
    var cleaned = time

    if let plusIndex = cleaned.firstIndex(of: "+") {
      cleaned = String(cleaned[..<plusIndex])
    }

    if let minusIndex = cleaned.lastIndex(of: "-"),
      cleaned.distance(from: cleaned.startIndex, to: minusIndex) > 2
    {
      cleaned = String(cleaned[..<minusIndex])
    }

    return String(cleaned.prefix(5))
  }

  /// Convert to regular RecurringShiftRow
  func toRecurringShiftRow() -> RecurringShiftRow {
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
struct SyncWageSnapshotRow: Codable {
  let id: String
  let user_id: String
  let job_id: String?
  let from_date: String?
  let hourly_wage: Double
  let wage_level: Int?
  let tariff_type_id: String?
  let supplements: SupplementRulesSnapshot
  let tax_enabled: Bool?
  let tax_percentage: Double?
  let break_enabled: Bool?
  let break_method: String?
  let break_threshold_hours: Double?
  let break_deduction_minutes: Int?
  let created_at: String?
  let updated_at: String
  let revision: Int64
  let deleted_at: String?

  /// Convert to regular WageSnapshot
  func toWageSnapshot() -> WageSnapshot {
    WageSnapshot(
      id: id,
      user_id: user_id,
      job_id: job_id,
      from_date: from_date,
      hourly_wage: hourly_wage,
      wage_level: wage_level,
      tariff_type_id: tariff_type_id,
      supplements: supplements,
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
struct SyncPayrollAdjustmentRow: Codable {
  let id: String
  let user_id: String
  let job_id: String?
  let amount: Double
  let currency: String
  let category: PayrollAdjustmentCategory
  let tax_treatment: PayrollAdjustmentTaxTreatment
  let description: String
  let note: String?
  let curated_note: String?
  let curated_description: String?
  let curated_link: String?
  let curated_link_title: String?
  let earned_from_date: String?
  let earned_to_date: String?
  let payout_date: String
  let created_at: String?
  let updated_at: String
  let revision: Int64
  let deleted_at: String?

  func toPayrollAdjustment() -> PayrollAdjustment {
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
struct SyncJobRow: Codable {
  let id: String
  let user_id: String
  let name: String
  let color: String?
  let currency: String
  let is_default: Bool
  let sort_order: Int
  let payroll_day: Int?
  let half_tax_month: Int?
  let monthly_goal: Int?
  let archived_at: String?
  let deleted_at: String?
  let created_at: String?
  let updated_at: String
  let revision: Int64

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

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

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
struct SyncUserSettingsRow: Codable {
  let user_id: String
  let created_at: String?
  let updated_at: String
  let last_active: String?
  let monthly_goal: Int?
  let monthly_goals_by_month: [String: Int]?
  let default_shifts_view: String?
  let profile_picture_url: String?
  let payroll_day: Int?
  let theme: String
  let calendar_content_color_style: String?
  let show_dashboard_clock_buttons: Bool?
  let ai_data_sharing_enabled: Bool?
  let half_tax_month: Int?
  let currency: String?
  let default_startup_tab: String?
  let revision: Int64

  /// Convert to regular UserSettings
  func toUserSettings() -> UserSettings {
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
      default_startup_tab: default_startup_tab
    )
  }
}

/// Notification preferences row for sync
/// Note: This table has no revision column - iOS is the source of truth
struct SyncNotificationPreferencesRow: Codable {
  let user_id: String
  let shift_reminders_enabled: Bool
  let shift_reminder_minutes_array: [Int]?
  let shared_shifts_enabled: Bool
  let updated_at: String

  /// Convert to NotificationPreferencesRow
  func toNotificationPreferencesRow() -> NotificationPreferencesRow {
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
struct TablePullResult {
  let table: SyncTable
  let rowsProcessed: Int
  /// Last updated_at timestamp processed (for cursor)
  let lastUpdatedAt: Date?
  /// ID of the last row at the lastUpdatedAt timestamp (tie-breaker)
  let lastUpdatedAtTieId: String?
  /// Legacy max revision (kept for debugging only)
  let maxRevision: Int64
  let newConflicts: Int
  let autoMerged: Int
  let affectedMonths: Set<ShiftChangeAffectedMonth>
}

/// Overall sync result
struct SyncResult {
  let success: Bool
  let tableResults: [TablePullResult]
  let pushResults: [TablePushResult]
  let totalRowsProcessed: Int
  let totalRowsPushed: Int
  let totalConflicts: Int
  let totalAutoMerged: Int
  let duration: TimeInterval
  let error: String?

  var hasConflicts: Bool {
    totalConflicts > 0
  }
}

// MARK: - Push Result Types

/// Result of pushing a single table
struct TablePushResult {
  let table: SyncTable
  let rowsPushed: Int
  let newConflicts: Int
  let rebased: Int
  let affectedMonths: Set<ShiftChangeAffectedMonth> = []
}

// MARK: - Sync Completion Summary

struct SyncTableChange: Equatable {
  let table: SyncTable
  let pulledRows: Int
  let pushedRows: Int
  let newConflicts: Int
  let autoMerged: Int
  let rebased: Int
  let affectedMonths: Set<ShiftChangeAffectedMonth>

  var changesLocalReadModels: Bool {
    pulledRows > 0 || newConflicts > 0 || autoMerged > 0 || rebased > 0
  }
}

struct SyncCompletionSummary: Equatable {
  let reason: SyncReason
  let userId: String
  let completedAt: Date
  let tableChanges: [SyncTableChange]

  init(
    reason: SyncReason,
    userId: String,
    completedAt: Date = Date(),
    tableResults: [TablePullResult],
    pushResults: [TablePushResult]
  ) {
    self.reason = reason
    self.userId = userId
    self.completedAt = completedAt

    let pullResultsByTable = Dictionary(uniqueKeysWithValues: tableResults.map { ($0.table, $0) })
    let pushResultsByTable = Dictionary(uniqueKeysWithValues: pushResults.map { ($0.table, $0) })
    let tables = Set(pullResultsByTable.keys).union(pushResultsByTable.keys)

    self.tableChanges = tables.sorted { $0.rawValue < $1.rawValue }.map { table in
      let pullResult = pullResultsByTable[table]
      let pushResult = pushResultsByTable[table]
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

  var localReadModelChanges: [SyncTableChange] {
    tableChanges.filter(\.changesLocalReadModels)
  }

  var hasLocalReadModelChanges: Bool {
    !localReadModelChanges.isEmpty
  }
}

/// Result of pushing a single record
enum PushResult {
  case success
  case conflict
  case rebased
  case noChange
  case deleted
}

// MARK: - Conflict Resolution

/// Resolution choice for a conflict
enum ConflictResolution {
  /// Keep the local (iPhone) version and push to server
  case keepLocal
  /// Keep the server (Web) version and discard local changes
  case keepServer
}
