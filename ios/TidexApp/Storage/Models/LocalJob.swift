// swiftlint:disable cyclomatic_complexity explicit_acl explicit_type_interface
// swiftlint:disable:previous blanket_disable_command
import Foundation
import SwiftData

// MARK: - Local Job

/// SwiftData model for locally persisted jobs
/// Maps to the `jobs` table in Supabase
@Model
final class LocalJob {
  // MARK: - Primary Key & Foreign Key

  /// Unique identifier (UUID string from server)
  @Attribute(.unique)
  var id: String

  /// User who owns this job
  var userId: String

  // MARK: - Job Data

  var name: String
  var color: String?
  /// Keep a model-level default so lightweight migration can populate legacy rows.
  var currency: String = "kr"
  var isDefault: Bool
  var sortOrder: Int
  var payrollDay: Int?
  var halfTaxMonth: Int?
  /// JSON-encoded `PayPeriod`, or nil for the calendar-month default. See `PayPeriod.storageJSON`.
  var payPeriodJSON: String?
  var monthlyGoal: Int?
  var archivedAt: Date?
  var deletedAt: Date?
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
  var dirtyFieldKeys: Set<JobField> {
    get {
      guard !dirtyFields.isEmpty else {
        return []
      }

      do {
        let keys = try kSyncJSONDecoder.decode([String].self, from: dirtyFields)
        return Set(keys.compactMap { JobField(rawValue: $0) })
      } catch {
        SyncLogger.shared.log(
          "Corrupted dirtyFields for job \(id), treating as fully dirty: \(error.localizedDescription)",
          level: .error
        )
        return Set(JobField.allCases)
      }
    }
    set {
      let keys = newValue.map(\.rawValue)
      dirtyFields = (try? kCanonicalJSONEncoder.encode(keys)) ?? Data()
    }
  }

  // MARK: - Initialization

  init(
    id: String,
    userId: String,
    name: String,
    color: String? = nil,
    currency: String = "kr",
    isDefault: Bool,
    sortOrder: Int,
    payrollDay: Int? = nil,
    halfTaxMonth: Int? = nil,
    payPeriodJSON: String? = nil,
    monthlyGoal: Int? = nil,
    archivedAt: Date? = nil,
    deletedAt: Date? = nil,
    createdAt: Date? = nil,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    syncStatus: SyncStatus = .clean,
    dirtyFields: Data = Data(),
    lastSyncedSnapshot: Data,
    localUpdatedAt: Date,
    conflictServerSnapshot: Data? = nil
  ) {
    self.id = id
    self.userId = userId
    self.name = name
    self.color = color
    self.currency = currency
    self.isDefault = isDefault
    self.sortOrder = sortOrder
    self.payrollDay = payrollDay
    self.halfTaxMonth = halfTaxMonth
    self.payPeriodJSON = payPeriodJSON
    self.monthlyGoal = monthlyGoal
    self.archivedAt = archivedAt
    self.deletedAt = deletedAt
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

/// Snapshot of server data for a job
struct JobServerSnapshot: Codable, Equatable {
  let name: String
  let color: String?
  let currency: String
  let isDefault: Bool
  let sortOrder: Int
  let payrollDay: Int?
  let halfTaxMonth: Int?
  /// Normalized to `.calendarMonth` when unset, so the two representations of "no override"
  /// (a NULL column and an explicit calendar-month JSON value) never register as a diff.
  let payPeriod: PayPeriod
  let monthlyGoal: Int?
  let archivedAt: Date?
  let deletedAt: Date?
  let updatedAt: Date
  let revision: Int64

  static func from(
    row: SyncJobRow,
    updatedAt: Date
  ) -> Self {
    Self(
      name: row.name,
      color: row.color,
      currency: row.currency,
      isDefault: row.is_default,
      sortOrder: row.sort_order,
      payrollDay: row.payroll_day,
      halfTaxMonth: row.half_tax_month,
      payPeriod: row.pay_period ?? .calendarMonth,
      monthlyGoal: row.monthly_goal,
      archivedAt: row.archived_at.flatMap { parseJobISO8601($0) },
      deletedAt: row.deleted_at.flatMap { parseJobISO8601($0) },
      updatedAt: updatedAt,
      revision: row.revision
    )
  }

  func encodedOrThrow() throws -> Data {
    try requireEncode(self, typeName: "JobServerSnapshot")
  }

  func encoded() -> Data {
    (try? kCanonicalJSONEncoder.encode(self)) ?? Data()
  }

  static func decode(from data: Data) -> Self? {
    try? kSyncJSONDecoder.decode(Self.self, from: data)
  }

  func changedFields(from other: Self) -> Set<JobField> {
    var changed: Set<JobField> = []

    if name != other.name {
      changed.insert(.name)
    }
    if color != other.color {
      changed.insert(.color)
    }
    if currency != other.currency {
      changed.insert(.currency)
    }
    if isDefault != other.isDefault {
      changed.insert(.isDefault)
    }
    if sortOrder != other.sortOrder {
      changed.insert(.sortOrder)
    }
    if payrollDay != other.payrollDay {
      changed.insert(.payrollDay)
    }
    if halfTaxMonth != other.halfTaxMonth {
      changed.insert(.halfTaxMonth)
    }
    if payPeriod != other.payPeriod {
      changed.insert(.payPeriod)
    }
    if monthlyGoal != other.monthlyGoal {
      changed.insert(.monthlyGoal)
    }
    if archivedAt != other.archivedAt {
      changed.insert(.archivedAt)
    }
    if deletedAt != other.deletedAt {
      changed.insert(.deletedAt)
    }

    return changed
  }
}

extension JobServerSnapshot {
  private enum CodingKeys: String, CodingKey {
    case name
    case color
    case currency
    case isDefault
    case sortOrder
    case payrollDay
    case halfTaxMonth
    case payPeriod
    case monthlyGoal
    case archivedAt
    case deletedAt
    case updatedAt
    case revision
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    name = try container.decode(String.self, forKey: .name)
    color = try container.decodeIfPresent(String.self, forKey: .color)
    currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "kr"
    isDefault = try container.decode(Bool.self, forKey: .isDefault)
    sortOrder = try container.decode(Int.self, forKey: .sortOrder)
    payrollDay = try container.decodeIfPresent(Int.self, forKey: .payrollDay)
    halfTaxMonth = try container.decodeIfPresent(Int.self, forKey: .halfTaxMonth)
    payPeriod = try container.decodeIfPresent(PayPeriod.self, forKey: .payPeriod) ?? .calendarMonth
    monthlyGoal = try container.decodeIfPresent(Int.self, forKey: .monthlyGoal)
    archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
    deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    revision = try container.decode(Int64.self, forKey: .revision)
  }
}

// MARK: - Conversion Extensions

extension LocalJob {
  func toJob() -> Job {
    Job(
      id: id,
      user_id: userId,
      name: name,
      color: color,
      currency: currency,
      is_default: isDefault,
      sort_order: sortOrder,
      payroll_day: payrollDay,
      half_tax_month: halfTaxMonth,
      monthly_goal: monthlyGoal,
      archived_at: archivedAt.map { formatJobISO8601($0) },
      deleted_at: deletedAt.map { formatJobISO8601($0) },
      created_at: createdAt.map { formatJobISO8601($0) },
      updated_at: formatJobISO8601(serverUpdatedAt),
      pay_period: payPeriodJSON.map { PayPeriod.fromStorageJSON($0) }
    )
  }

  static func from(
    serverRow: SyncJobRow,
    serverUpdatedAt: Date
  ) -> LocalJob {
    LocalJob(
      id: serverRow.id,
      userId: serverRow.user_id,
      name: serverRow.name,
      color: serverRow.color,
      currency: serverRow.currency,
      isDefault: serverRow.is_default,
      sortOrder: serverRow.sort_order,
      payrollDay: serverRow.payroll_day,
      halfTaxMonth: serverRow.half_tax_month,
      payPeriodJSON: serverRow.pay_period?.storageJSON,
      monthlyGoal: serverRow.monthly_goal,
      archivedAt: serverRow.archived_at.flatMap { parseJobISO8601($0) },
      deletedAt: serverRow.deleted_at.flatMap { parseJobISO8601($0) },
      createdAt: serverRow.created_at.flatMap { parseJobISO8601($0) },
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRow.revision,
      syncStatus: .clean,
      dirtyFields: emptyDirtyFields(),
      lastSyncedSnapshot: (try? JobServerSnapshot.from(row: serverRow, updatedAt: serverUpdatedAt)
        .encodedOrThrow()) ?? Data(),
      localUpdatedAt: Date(),
      conflictServerSnapshot: nil
    )
  }
}

/// Visible to tests so ISO8601TimestampTests can exercise Postgres-form parsing directly.
func parseJobISO8601(_ value: String) -> Date? {
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }

  let normalized = normalizeJobTimestamp(trimmed)
  return ISO8601Timestamp.date(from: normalized) ?? ISO8601Timestamp.date(from: trimmed)
}

private func formatJobISO8601(_ date: Date) -> String {
  ISO8601Timestamp.string(from: date)
}

private func normalizeJobTimestamp(_ value: String) -> String {
  var normalized = value

  // Some Postgres outputs use a space separator instead of "T".
  if normalized.contains(" "), !normalized.contains("T") {
    normalized = normalized.replacingOccurrences(of: " ", with: "T")
  }

  // Normalize "+00" / "-07" offset suffix to "+00:00" / "-07:00".
  if let range = normalized.range(of: #"([+-]\d{2})$"#, options: .regularExpression) {
    normalized.insert(contentsOf: ":00", at: range.upperBound)
  }

  // Normalize "+0000" / "-0700" suffix to "+00:00" / "-07:00".
  if let range = normalized.range(of: #"([+-]\d{2})(\d{2})$"#, options: .regularExpression) {
    let suffix = String(normalized[range])
    if suffix.count == 5 {
      let hours = suffix.prefix(3)
      let minutes = suffix.suffix(2)
      normalized.replaceSubrange(range, with: "\(hours):\(minutes)")
    }
  }

  return normalized
}
