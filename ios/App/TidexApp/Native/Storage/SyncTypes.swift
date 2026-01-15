import Foundation

// MARK: - Sync Status

/// Status of a local record's synchronization state
enum SyncStatus: String, Codable {
    /// Record is synchronized with server (no local changes)
    case clean
    /// Record has local changes not yet pushed to server
    case dirty
    /// Record is marked for deletion locally, pending server push
    case pendingDelete
    /// Record has conflicting changes between local and server
    case conflict
}

// MARK: - Field Keys

/// Field keys for tracking dirty fields on LocalUserShift
enum UserShiftField: String, Codable, CaseIterable {
    case shiftDate = "shift_date"
    case startTime = "start_time"
    case endTime = "end_time"
    case customSupplements = "custom_supplements"
}

/// Field keys for tracking dirty fields on LocalRecurringShift
enum RecurringShiftField: String, Codable, CaseIterable {
    case startTime = "start_time"
    case endTime = "end_time"
    case repeatIntervalWeeks = "repeat_interval_weeks"
    case selectedDays = "selected_days"
    case endCondition = "end_condition"
    case exclusions = "exclusions"
    case dateSpecificSupplements = "date_specific_supplements"
}

/// Field keys for tracking dirty fields on LocalWageSnapshot
enum WageSnapshotField: String, Codable, CaseIterable {
    case fromDate = "from_date"
    case hourlyWage = "hourly_wage"
    case wageLevel = "wage_level"
    case supplements = "supplements"
    case taxEnabled = "tax_enabled"
    case taxPercentage = "tax_percentage"
    case breakEnabled = "break_enabled"
    case breakMethod = "break_method"
    case breakThresholdHours = "break_threshold_hours"
    case breakDeductionMinutes = "break_deduction_minutes"
}

/// Field keys for tracking dirty fields on LocalUserSettings
enum UserSettingsField: String, Codable, CaseIterable {
    case monthlyGoal = "monthly_goal"
    case defaultShiftsView = "default_shifts_view"
    case profilePictureUrl = "profile_picture_url"
    case payrollDay = "payroll_day"
    case theme = "theme"
    case halfTaxMonth = "half_tax_month"
    case currency = "currency"
    case lastActive = "last_active"
}

// MARK: - JSON Coding Helpers

/// Canonical JSON encoder for stable encoding (sorted keys, no extra whitespace)
let canonicalJSONEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

/// JSON decoder for sync data
let syncJSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()
