import Foundation
import SwiftData

// MARK: - Local User Settings

/// SwiftData model for locally persisted user settings
/// Maps to the `user_settings` table in Supabase
/// Note: This is a single-row-per-user table, so userId is the unique key
@Model
final class LocalUserSettings {
  // MARK: - Primary Key

  /// User ID (primary key - one settings row per user)
  @Attribute(.unique)
  var userId: String

  // MARK: - User Settings Data

  /// Monthly earnings goal
  var monthlyGoal: Int?

  /// Default view for shifts (calendar, list, etc.)
  var defaultShiftsView: String?

  /// Profile picture URL
  var profilePictureUrl: String?

  /// Day of month for payroll (1-31)
  var payrollDay: Int?

  /// Theme preference (NOT NULL in DB, defaults to "system")
  var theme: String

  /// Calendar animation style preference (defaults to "horizontal")
  /// Optional to support migration from older versions without this field
  var calendarAnimationStyle: String?

  /// Month number (11=November, 12=December) for half tax deduction
  var halfTaxMonth: Int?

  /// Currency code
  var currency: String?

  /// When the user was last active
  var lastActive: Date?

  /// When the settings were created
  var createdAt: Date?

  // MARK: - Server Metadata

  /// Server's updated_at timestamp
  var serverUpdatedAt: Date

  /// Server's revision number for optimistic concurrency
  var serverRevision: Int64

  // MARK: - Sync Metadata

  /// Current sync status
  var syncStatusRaw: String

  /// Fields modified locally since last sync (JSON array of field keys)
  var dirtyFields: Data

  /// Snapshot of server data at last sync (for conflict detection)
  var lastSyncedSnapshot: Data

  /// When the user last modified this record locally
  var localUpdatedAt: Date

  /// Server version on conflict (for resolution UI)
  var conflictServerSnapshot: Data?

  // MARK: - Computed Properties

  var syncStatus: SyncStatus {
    get { SyncStatus(rawValue: syncStatusRaw) ?? .clean }
    set { syncStatusRaw = newValue.rawValue }
  }

  /// Decoded dirty fields
  /// When decoding fails (corrupted data), treats record as fully dirty to prevent silent data loss
  var dirtyFieldKeys: Set<UserSettingsField> {
    get {
      // Empty data means no dirty fields (common case for clean records)
      guard !dirtyFields.isEmpty else {
        return []
      }

      do {
        let keys = try syncJSONDecoder.decode([String].self, from: dirtyFields)
        return Set(keys.compactMap { UserSettingsField(rawValue: $0) })
      } catch {
        // If decode fails, treat as fully dirty to ensure data is pushed to server
        // This prevents silent data loss when dirty fields data is corrupted
        SyncLogger.shared.log(
          "Corrupted dirtyFields for user settings \(userId), treating as fully dirty: \(error.localizedDescription)",
          level: .error
        )
        return Set(UserSettingsField.allCases)
      }
    }
    set {
      let keys = newValue.map { $0.rawValue }
      dirtyFields = (try? canonicalJSONEncoder.encode(keys)) ?? Data()
    }
  }

  /// Effective payroll day (defaults to 1 if not set)
  var effectivePayrollDay: Int {
    payrollDay ?? 1
  }

  /// Effective default view
  var effectiveDefaultView: String {
    defaultShiftsView ?? "calendar"
  }

  /// Effective calendar animation style
  var effectiveCalendarAnimationStyle: String {
    calendarAnimationStyle ?? "horizontal"
  }

  // MARK: - Initialization

  init(
    userId: String,
    monthlyGoal: Int? = nil,
    defaultShiftsView: String? = nil,
    profilePictureUrl: String? = nil,
    payrollDay: Int? = nil,
    theme: String = "system",
    calendarAnimationStyle: String? = "horizontal",
    halfTaxMonth: Int? = nil,
    currency: String? = nil,
    lastActive: Date? = nil,
    createdAt: Date? = nil,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    syncStatus: SyncStatus = .clean,
    dirtyFields: Data = Data(),
    lastSyncedSnapshot: Data,
    localUpdatedAt: Date,
    conflictServerSnapshot: Data? = nil
  ) {
    self.userId = userId
    self.monthlyGoal = monthlyGoal
    self.defaultShiftsView = defaultShiftsView
    self.profilePictureUrl = profilePictureUrl
    self.payrollDay = payrollDay
    self.theme = theme
    self.calendarAnimationStyle = calendarAnimationStyle
    self.halfTaxMonth = halfTaxMonth
    self.currency = currency
    self.lastActive = lastActive
    self.createdAt = createdAt
    self.serverUpdatedAt = serverUpdatedAt
    self.serverRevision = serverRevision
    self.syncStatusRaw = syncStatus.rawValue
    self.dirtyFields = dirtyFields
    self.lastSyncedSnapshot = lastSyncedSnapshot
    self.localUpdatedAt = localUpdatedAt
    self.conflictServerSnapshot = conflictServerSnapshot
  }

  /// Initialize empty dirty fields array
  static func emptyDirtyFields() -> Data {
    (try? canonicalJSONEncoder.encode([String]())) ?? Data()
  }
}

// MARK: - Server Snapshot

/// Snapshot of server data for user settings
struct UserSettingsServerSnapshot: Codable, Equatable {
  let monthlyGoal: Int?
  let defaultShiftsView: String?
  let profilePictureUrl: String?
  let payrollDay: Int?
  let theme: String
  let calendarAnimationStyle: String
  let halfTaxMonth: Int?
  let currency: String?
  let lastActive: Date?
  let updatedAt: Date
  let revision: Int64

  /// Create snapshot from a UserSettings server response
  static func from(
    row: UserSettings,
    updatedAt: Date,
    revision: Int64
  ) -> UserSettingsServerSnapshot {
    let dateFormatter = ISO8601DateFormatter()

    return UserSettingsServerSnapshot(
      monthlyGoal: row.monthly_goal,
      defaultShiftsView: row.default_shifts_view,
      profilePictureUrl: row.profile_picture_url,
      payrollDay: row.payroll_day,
      theme: row.theme,
      calendarAnimationStyle: row.calendar_animation_style,
      halfTaxMonth: row.half_tax_month,
      currency: row.currency,
      lastActive: row.last_active.flatMap { dateFormatter.date(from: $0) },
      updatedAt: updatedAt,
      revision: revision
    )
  }

  /// Encode to Data (throws on failure for critical paths)
  /// Use this in insert/update paths where empty Data would corrupt sync state
  func encodedOrThrow() throws -> Data {
    try requireEncode(self, typeName: "UserSettingsServerSnapshot")
  }

  /// Encode to Data (returns empty Data on failure - use only for non-critical paths)
  /// DEPRECATED: Prefer encodedOrThrow() for new code
  func encoded() -> Data {
    (try? canonicalJSONEncoder.encode(self)) ?? Data()
  }

  /// Decode from Data
  static func decode(from data: Data) -> UserSettingsServerSnapshot? {
    try? syncJSONDecoder.decode(UserSettingsServerSnapshot.self, from: data)
  }

  /// Compute changed fields compared to another snapshot
  func changedFields(from other: UserSettingsServerSnapshot) -> Set<UserSettingsField> {
    var changed: Set<UserSettingsField> = []

    if monthlyGoal != other.monthlyGoal {
      changed.insert(.monthlyGoal)
    }
    if defaultShiftsView != other.defaultShiftsView {
      changed.insert(.defaultShiftsView)
    }
    if profilePictureUrl != other.profilePictureUrl {
      changed.insert(.profilePictureUrl)
    }
    if payrollDay != other.payrollDay {
      changed.insert(.payrollDay)
    }
    if theme != other.theme {
      changed.insert(.theme)
    }
    if calendarAnimationStyle != other.calendarAnimationStyle {
      changed.insert(.calendarAnimationStyle)
    }
    if halfTaxMonth != other.halfTaxMonth {
      changed.insert(.halfTaxMonth)
    }
    if currency != other.currency {
      changed.insert(.currency)
    }
    if lastActive != other.lastActive {
      changed.insert(.lastActive)
    }

    return changed
  }
}

// MARK: - Conversion Extensions

extension LocalUserSettings {
  /// Convert to UserSettings for use with existing code
  func toUserSettings() -> UserSettings {
    let dateFormatter = FormatterCache.iso8601Formatter()

    return UserSettings(
      user_id: userId,
      created_at: createdAt.map { dateFormatter.string(from: $0) },
      updated_at: dateFormatter.string(from: serverUpdatedAt),
      last_active: lastActive.map { dateFormatter.string(from: $0) },
      monthly_goal: monthlyGoal,
      default_shifts_view: defaultShiftsView,
      profile_picture_url: profilePictureUrl,
      payroll_day: payrollDay,
      theme: theme,
      calendar_animation_style: effectiveCalendarAnimationStyle,
      half_tax_month: halfTaxMonth,
      currency: currency
    )
  }

  /// Create from a server response row
  static func from(
    serverRow: UserSettings,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    context: ModelContext
  ) -> LocalUserSettings {
    let dateFormatter = FormatterCache.iso8601Formatter()

    let lastActive = serverRow.last_active.flatMap { dateFormatter.date(from: $0) }
    let createdAt = serverRow.created_at.flatMap { dateFormatter.date(from: $0) }

    let snapshot = UserSettingsServerSnapshot.from(
      row: serverRow,
      updatedAt: serverUpdatedAt,
      revision: serverRevision
    )

    return LocalUserSettings(
      userId: serverRow.user_id,
      monthlyGoal: serverRow.monthly_goal,
      defaultShiftsView: serverRow.default_shifts_view,
      profilePictureUrl: serverRow.profile_picture_url,
      payrollDay: serverRow.payroll_day,
      theme: serverRow.theme,
      calendarAnimationStyle: serverRow.calendar_animation_style,
      halfTaxMonth: serverRow.half_tax_month,
      currency: serverRow.currency,
      lastActive: lastActive,
      createdAt: createdAt,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      syncStatus: .clean,
      dirtyFields: emptyDirtyFields(),
      lastSyncedSnapshot: snapshot.encoded(),
      localUpdatedAt: Date(),
      conflictServerSnapshot: nil
    )
  }
}
