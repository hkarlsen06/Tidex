// swiftlint:disable cyclomatic_complexity explicit_acl explicit_type_interface function_body_length
// swiftlint:disable:previous blanket_disable_command
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

  /// Sparse month-specific goal overrides keyed by YYYY-MM.
  /// Stored as encoded JSON object for SwiftData compatibility.
  var monthlyGoalsByMonthData: Data?

  /// Default view for shifts (calendar, list, etc.)
  var defaultShiftsView: String?

  /// Profile picture URL
  var profilePictureUrl: String?

  /// Day of month for payroll (1-31)
  var payrollDay: Int?

  /// Theme preference (NOT NULL in DB, defaults to "system")
  var theme: String

  /// Calendar content color style preference (defaults to "workplace")
  /// Optional to support migration from older versions without this field
  var calendarContentColorStyle: String?

  /// Whether dashboard clock in/out buttons are visible
  /// Optional to support migration from older versions without this field
  var showDashboardClockButtons: Bool?

  /// Whether the user has consented to Wagey AI data sharing
  /// Optional to support migration from older versions without this field
  var aiDataSharingEnabled: Bool?

  /// Month number (11=November, 12=December) for half tax deduction
  var halfTaxMonth: Int?

  /// Currency code
  var currency: String?

  /// Default tab to open when launching the app
  var defaultStartupTab: String?

  /// Whether the user has dismissed the Wagey showcase
  var wageyShowcaseSeen: Bool?

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
        let keys = try kSyncJSONDecoder.decode([String].self, from: dirtyFields)
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
      let keys = newValue.map(\.rawValue)
      dirtyFields = (try? kCanonicalJSONEncoder.encode(keys)) ?? Data()
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

  /// Effective calendar content color style
  var effectiveCalendarContentColorStyle: String {
    guard let style = calendarContentColorStyle else { return "workplace" }
    switch style {
    case "workplace", "monochrome":
      return style

    default:
      return "workplace"
    }
  }

  /// Effective dashboard clock button visibility
  var effectiveShowDashboardClockButtons: Bool {
    showDashboardClockButtons ?? true
  }

  /// Effective startup tab (defaults to home)
  var effectiveDefaultStartupTab: String {
    guard let tab = defaultStartupTab else { return "home" }
    switch tab {
    case "home", "shifts", "stats", "sharing":
      return tab

    default:
      return "home"
    }
  }

  var monthlyGoalsByMonth: [String: Int] {
    get {
      guard let monthlyGoalsByMonthData, !monthlyGoalsByMonthData.isEmpty else {
        return [:]
      }

      do {
        return try kSyncJSONDecoder.decode([String: Int].self, from: monthlyGoalsByMonthData)
      } catch {
        SyncLogger.shared.log(
          "Corrupted monthlyGoalsByMonthData for user settings \(userId): \(error.localizedDescription)",
          level: .error
        )
        return [:]
      }
    }
    set {
      monthlyGoalsByMonthData =
        (try? kCanonicalJSONEncoder.encode(
          newValue.sorted { $0.key < $1.key }.reduce(into: [String: Int]()) {
            $0[$1.key] = $1.value
          })) ?? Data()
    }
  }

  // MARK: - Initialization

  init(
    userId: String,
    monthlyGoal: Int? = nil,
    monthlyGoalsByMonthData: Data? = nil,
    defaultShiftsView: String? = nil,
    profilePictureUrl: String? = nil,
    payrollDay: Int? = nil,
    theme: String = "system",
    calendarContentColorStyle: String? = "workplace",
    showDashboardClockButtons: Bool? = true,
    aiDataSharingEnabled: Bool? = nil,
    halfTaxMonth: Int? = nil,
    currency: String? = nil,
    defaultStartupTab: String? = nil,
    wageyShowcaseSeen: Bool? = nil,
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
    self.monthlyGoalsByMonthData = monthlyGoalsByMonthData
    self.defaultShiftsView = defaultShiftsView
    self.profilePictureUrl = profilePictureUrl
    self.payrollDay = payrollDay
    self.theme = theme
    self.calendarContentColorStyle = calendarContentColorStyle
    self.showDashboardClockButtons = showDashboardClockButtons
    self.aiDataSharingEnabled = aiDataSharingEnabled
    self.halfTaxMonth = halfTaxMonth
    self.currency = currency
    self.defaultStartupTab = defaultStartupTab
    self.wageyShowcaseSeen = wageyShowcaseSeen
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
    (try? kCanonicalJSONEncoder.encode([String]())) ?? Data()
  }
}

// MARK: - Server Snapshot

/// Snapshot of server data for user settings
struct UserSettingsServerSnapshot: Codable, Equatable {
  let monthlyGoal: Int?
  let monthlyGoalsByMonth: [String: Int]
  let defaultShiftsView: String?
  let profilePictureUrl: String?
  let payrollDay: Int?
  let theme: String
  let calendarContentColorStyle: String
  let showDashboardClockButtons: Bool
  let aiDataSharingEnabled: Bool
  let halfTaxMonth: Int?
  let currency: String?
  let defaultStartupTab: String?
  let wageyShowcaseSeen: Bool
  let lastActive: Date?
  let updatedAt: Date
  let revision: Int64

  private enum CodingKeys: String, CodingKey {
    case monthlyGoal
    case monthlyGoalsByMonth
    case defaultShiftsView
    case profilePictureUrl
    case payrollDay
    case theme
    case calendarContentColorStyle
    case showDashboardClockButtons
    case aiDataSharingEnabled
    case halfTaxMonth
    case currency
    case defaultStartupTab
    case wageyShowcaseSeen
    case lastActive
    case updatedAt
    case revision
  }

  /// Create snapshot from a UserSettings server response
  static func from(
    row: UserSettings,
    updatedAt: Date,
    revision: Int64
  ) -> Self {
    let dateFormatter = FormatterCache.iso8601Formatter()

    return Self(
      monthlyGoal: row.monthly_goal,
      monthlyGoalsByMonth: row.monthly_goals_by_month ?? [:],
      defaultShiftsView: row.default_shifts_view,
      profilePictureUrl: row.profile_picture_url,
      payrollDay: row.payroll_day,
      theme: row.theme,
      calendarContentColorStyle: row.effectiveCalendarContentColorStyle,
      showDashboardClockButtons: row.effectiveShowDashboardClockButtons,
      aiDataSharingEnabled: row.effectiveAIDataSharingEnabled,
      halfTaxMonth: row.half_tax_month,
      currency: row.currency,
      defaultStartupTab: row.default_startup_tab,
      wageyShowcaseSeen: row.wagey_showcase_seen ?? false,
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
    (try? kCanonicalJSONEncoder.encode(self)) ?? Data()
  }

  /// Decode from Data
  static func decode(from data: Data) -> Self? {
    try? kSyncJSONDecoder.decode(Self.self, from: data)
  }

  /// Compute changed fields compared to another snapshot
  func changedFields(from other: Self) -> Set<UserSettingsField> {
    var changed: Set<UserSettingsField> = []

    if monthlyGoal != other.monthlyGoal {
      changed.insert(.monthlyGoal)
    }
    if monthlyGoalsByMonth != other.monthlyGoalsByMonth {
      changed.insert(.monthlyGoalsByMonth)
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
    if calendarContentColorStyle != other.calendarContentColorStyle {
      changed.insert(.calendarContentColorStyle)
    }
    if showDashboardClockButtons != other.showDashboardClockButtons {
      changed.insert(.showDashboardClockButtons)
    }
    if aiDataSharingEnabled != other.aiDataSharingEnabled {
      changed.insert(.aiDataSharingEnabled)
    }
    if halfTaxMonth != other.halfTaxMonth {
      changed.insert(.halfTaxMonth)
    }
    if currency != other.currency {
      changed.insert(.currency)
    }
    if defaultStartupTab != other.defaultStartupTab {
      changed.insert(.defaultStartupTab)
    }
    if wageyShowcaseSeen != other.wageyShowcaseSeen {
      changed.insert(.wageyShowcaseSeen)
    }
    if lastActive != other.lastActive {
      changed.insert(.lastActive)
    }

    return changed
  }
}

extension UserSettingsServerSnapshot {
  /// Backward-compatible decoding for persisted snapshots written before
  /// monthlyGoalsByMonth was introduced.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    monthlyGoal = try container.decodeIfPresent(Int.self, forKey: .monthlyGoal)
    monthlyGoalsByMonth =
      try container.decodeIfPresent([String: Int].self, forKey: .monthlyGoalsByMonth) ?? [:]
    defaultShiftsView = try container.decodeIfPresent(String.self, forKey: .defaultShiftsView)
    profilePictureUrl = try container.decodeIfPresent(String.self, forKey: .profilePictureUrl)
    payrollDay = try container.decodeIfPresent(Int.self, forKey: .payrollDay)
    theme = try container.decode(String.self, forKey: .theme)
    calendarContentColorStyle =
      try container.decodeIfPresent(String.self, forKey: .calendarContentColorStyle) ?? "workplace"
    showDashboardClockButtons =
      try container.decodeIfPresent(Bool.self, forKey: .showDashboardClockButtons) ?? true
    aiDataSharingEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .aiDataSharingEnabled) ?? false
    halfTaxMonth = try container.decodeIfPresent(Int.self, forKey: .halfTaxMonth)
    currency = try container.decodeIfPresent(String.self, forKey: .currency)
    defaultStartupTab = try container.decodeIfPresent(String.self, forKey: .defaultStartupTab)
    wageyShowcaseSeen =
      try container.decodeIfPresent(Bool.self, forKey: .wageyShowcaseSeen) ?? false
    lastActive = try container.decodeIfPresent(Date.self, forKey: .lastActive)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    revision = try container.decode(Int64.self, forKey: .revision)
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
      monthly_goals_by_month: monthlyGoalsByMonth.isEmpty ? nil : monthlyGoalsByMonth,
      default_shifts_view: defaultShiftsView,
      profile_picture_url: profilePictureUrl,
      payroll_day: payrollDay,
      theme: theme,
      calendar_content_color_style: effectiveCalendarContentColorStyle,
      show_dashboard_clock_buttons: effectiveShowDashboardClockButtons,
      ai_data_sharing_enabled: aiDataSharingEnabled,
      half_tax_month: halfTaxMonth,
      currency: currency,
      default_startup_tab: defaultStartupTab,
      wagey_showcase_seen: wageyShowcaseSeen
    )
  }

  /// Create from a server response row
  static func from(
    serverRow: UserSettings,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    context _: ModelContext
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
      monthlyGoalsByMonthData: (try? kCanonicalJSONEncoder.encode(
        serverRow.monthly_goals_by_month ?? [:]))
        ?? Data(),
      defaultShiftsView: serverRow.default_shifts_view,
      profilePictureUrl: serverRow.profile_picture_url,
      payrollDay: serverRow.payroll_day,
      theme: serverRow.theme,
      calendarContentColorStyle: serverRow.effectiveCalendarContentColorStyle,
      showDashboardClockButtons: serverRow.show_dashboard_clock_buttons ?? true,
      aiDataSharingEnabled: serverRow.ai_data_sharing_enabled ?? false,
      halfTaxMonth: serverRow.half_tax_month,
      currency: serverRow.currency,
      defaultStartupTab: serverRow.default_startup_tab,
      wageyShowcaseSeen: serverRow.wagey_showcase_seen ?? false,
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
