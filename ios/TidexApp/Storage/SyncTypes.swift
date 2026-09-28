import Foundation
import os.log

// MARK: - Sync Status

/// Status of a local record's synchronization state
internal enum SyncStatus: String, Codable {
  /// Record is synchronized with server (no local changes)
  case clean
  /// Record has conflicting changes between local and server
  case conflict
  /// Record has local changes not yet pushed to server
  case dirty
  /// Record is marked for deletion locally, pending server push
  case pendingDelete
}

// MARK: - Field Keys

/// Field keys for tracking dirty fields on LocalUserShift
internal enum UserShiftField: String, Codable, CaseIterable {
  case customPauseWindows = "custom_pause_windows"
  case customSupplements = "custom_supplements"
  case endTime = "end_time"
  case jobId = "job_id"
  case note = "note"
  case shiftDate = "shift_date"
  case startTime = "start_time"
}

/// Field keys for tracking dirty fields on LocalEvent
internal enum EventField: String, Codable, CaseIterable {
  case endDate = "end_date"
  case endTime = "end_time"
  case isAllDay = "is_all_day"
  case note = "note"
  case notificationAnchorTime = "notification_anchor_time"
  case notificationMinutesArray = "notification_minutes_array"
  case startDate = "start_date"
  case startTime = "start_time"
}

/// Field keys for tracking dirty fields on LocalRecurringShift
internal enum RecurringShiftField: String, Codable, CaseIterable {
  case dateSpecificNotes = "date_specific_notes"
  case dateSpecificPauseWindows = "date_specific_pause_windows"
  case dateSpecificSupplements = "date_specific_supplements"
  case endCondition = "end_condition"
  case endTime = "end_time"
  case exclusions = "exclusions"
  case jobId = "job_id"
  case repeatIntervalWeeks = "repeat_interval_weeks"
  case selectedDays = "selected_days"
  case startTime = "start_time"
}

/// Field keys for tracking dirty fields on LocalWageSnapshot
internal enum WageSnapshotField: String, Codable, CaseIterable {
  case breakDeductionMinutes = "break_deduction_minutes"
  case breakEnabled = "break_enabled"
  case breakMethod = "break_method"
  case breakThresholdHours = "break_threshold_hours"
  case fromDate = "from_date"
  case hourlyWage = "hourly_wage"
  case jobId = "job_id"
  case overtime = "overtime"
  case supplements = "supplements"
  case tariffTypeId = "tariff_type_id"
  case taxEnabled = "tax_enabled"
  case taxPercentage = "tax_percentage"
  case wageLevel = "wage_level"
}

/// Field keys for tracking dirty fields on LocalPayrollAdjustment
internal enum PayrollAdjustmentField: String, Codable, CaseIterable {
  case amount = "amount"
  case category = "category"
  case curatedDescription = "curated_description"
  case curatedLink = "curated_link"
  case curatedLinkTitle = "curated_link_title"
  case curatedNote = "curated_note"
  case currency = "currency"
  case description = "description"
  case earnedFromDate = "earned_from_date"
  case earnedToDate = "earned_to_date"
  case jobId = "job_id"
  case note = "note"
  case payoutDate = "payout_date"
  case taxTreatment = "tax_treatment"
}

/// Field keys for tracking dirty fields on LocalJob
internal enum JobField: String, Codable, CaseIterable {
  case archivedAt = "archived_at"
  case color = "color"
  case currency = "currency"
  case deletedAt = "deleted_at"
  case halfTaxMonth = "half_tax_month"
  case isDefault = "is_default"
  case monthlyGoal = "monthly_goal"
  case name = "name"
  case payPeriod = "pay_period"
  case payrollDay = "payroll_day"
  case sortOrder = "sort_order"
}

/// Field keys for tracking dirty fields on LocalUserSettings
internal enum UserSettingsField: String, Codable, CaseIterable {
  case aiDataSharingEnabled = "ai_data_sharing_enabled"
  case calendarContentColorStyle = "calendar_content_color_style"
  case currency = "currency"
  case defaultShiftsView = "default_shifts_view"
  case defaultStartupTab = "default_startup_tab"
  case halfTaxMonth = "half_tax_month"
  case lastActive = "last_active"
  case monthlyGoal = "monthly_goal"
  case monthlyGoalsByMonth = "monthly_goals_by_month"
  case payrollDay = "payroll_day"
  case profilePictureUrl = "profile_picture_url"
  case showDashboardClockButtons = "show_dashboard_clock_buttons"
  case theme = "theme"
  case wageyShowcaseSeen = "wagey_showcase_seen"
}

/// Field keys for tracking dirty fields on LocalNotificationPreferences
internal enum NotificationPreferencesField: String, Codable, CaseIterable {
  case sharedShiftsEnabled = "shared_shifts_enabled"
  case shiftReminderMinutesArray = "shift_reminder_minutes_array"
  case shiftRemindersEnabled = "shift_reminders_enabled"
}

// MARK: - JSON Coding Helpers

/// Canonical JSON encoder for stable encoding (sorted keys, no extra whitespace)
internal let kCanonicalJSONEncoder: JSONEncoder = { () -> JSONEncoder in
  let encoder: JSONEncoder = .init()
  encoder.outputFormatting = [.sortedKeys]
  encoder.dateEncodingStrategy = .iso8601
  return encoder
}()

/// JSON decoder for sync data
internal let kSyncJSONDecoder: JSONDecoder = { () -> JSONDecoder in
  let decoder: JSONDecoder = .init()
  decoder.dateDecodingStrategy = .iso8601
  return decoder
}()

// MARK: - Encoding Error

/// Error for encoding failures in critical sync paths
internal enum SyncEncodingError: LocalizedError {
  case emptyUpdatePayload(type: String)
  case payloadDecodingFailed(type: String, underlyingError: Error)
  case snapshotEncodingFailed(type: String, underlyingError: Error)

  /// Technical description for logging
  internal var errorDescription: String? {
    switch self {
    case .emptyUpdatePayload(let type):
      return "Empty update payload for \(type)"

    case .payloadDecodingFailed(let type, let error):
      return "Failed to decode \(type): \(error.localizedDescription)"

    case .snapshotEncodingFailed(let type, let error):
      return "Failed to encode \(type): \(error.localizedDescription)"
    }
  }

  /// User-friendly message for UI display
  internal var userFriendlyMessage: String {
    switch self {
    case .payloadDecodingFailed, .emptyUpdatePayload:
      return "Sync failed: Unable to prepare local changes. Please try again."

    case .snapshotEncodingFailed:
      return "Sync failed: Unable to save local changes. Please try again."
    }
  }
}

/// Safely encode a value, logging and throwing on failure
/// Use this for critical paths where empty Data would corrupt sync state
internal func requireEncode<T: Encodable>(_ value: T, typeName: String) throws -> Data {
  do {
    return try kCanonicalJSONEncoder.encode(value)
  } catch {
    let logger: SyncLoggerImpl = SyncLogger.shared
    logger.log("Encoding failed for \(typeName): \(error.localizedDescription)", level: .error)
    throw SyncEncodingError.snapshotEncodingFailed(type: typeName, underlyingError: error)
  }
}

/// SyncLogger for encoding errors (minimal implementation)
internal enum SyncLogger {
  internal static let shared: SyncLoggerImpl = { () -> SyncLoggerImpl in
    SyncLoggerImpl()
  }()
}

internal struct SyncLoggerImpl {
  private let logger: Logger = { () -> Logger in
    Logger(subsystem: "no.tidex.app", category: "Sync")
  }()

  internal func log(_ message: String, level: SyncLogLevel) {
    switch level {
    case .debug:
      logger.debug("\(message)")

    case .info:
      logger.info("\(message)")

    case .warning:
      logger.warning("\(message)")

    case .error:
      logger.error("\(message)")
    }
  }
}

internal enum SyncLogLevel: String {
  case debug = "DEBUG"
  case error = "ERROR"
  case info = "INFO"
  case warning = "WARN"
}
