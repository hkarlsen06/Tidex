// swiftlint:disable cyclomatic_complexity explicit_acl explicit_type_interface
// swiftlint:disable:previous blanket_disable_command
import Foundation
import SwiftData

// MARK: - Local Wage Snapshot

/// SwiftData model for locally persisted wage snapshots
/// Maps to the `wage_snapshots` table in Supabase
@Model
final class LocalWageSnapshot {
  // MARK: - Primary Key & Foreign Key

  /// Unique identifier (UUID string from server)
  @Attribute(.unique)
  var id: String

  /// User who owns this snapshot
  var userId: String

  // MARK: - Wage Snapshot Data

  /// Job that owns this snapshot (nullable during rollout compatibility)
  var jobId: String?

  /// Effective date (nullable for baseline snapshot)
  var fromDate: Date?

  /// Hourly wage in NOK
  var hourlyWage: Double

  /// Wage level (nil = custom, 1-9 = tariff level)
  var wageLevel: Int?

  /// Tariff type ID (e.g., "hk_retail") or nil for custom wage
  var tariffTypeId: String?

  /// Supplement rules (JSON)
  var supplements: Data

  /// Overtime config (JSON)
  var overtime: Data = (try? kCanonicalJSONEncoder.encode(OvertimeConfig.disabled)) ?? Data()

  /// Whether tax is enabled
  var taxEnabled: Bool?

  /// Tax percentage
  var taxPercentage: Double?

  /// Whether break deduction is enabled
  var breakEnabled: Bool?

  /// Break deduction method
  var breakMethod: String?

  /// Break threshold in hours
  var breakThresholdHours: Double?

  /// Break deduction in minutes
  var breakDeductionMinutes: Int?

  // MARK: - Server Metadata

  /// Server's updated_at timestamp
  var serverUpdatedAt: Date

  /// Server's revision number for optimistic concurrency
  var serverRevision: Int64

  /// Server's deleted_at timestamp (soft delete)
  var serverDeletedAt: Date?

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
  var dirtyFieldKeys: Set<WageSnapshotField> {
    get {
      // Empty data means no dirty fields (common case for clean records)
      guard !dirtyFields.isEmpty else {
        return []
      }

      do {
        let keys = try kSyncJSONDecoder.decode([String].self, from: dirtyFields)
        return Set(keys.compactMap { WageSnapshotField(rawValue: $0) })
      } catch {
        // If decode fails, treat as fully dirty to ensure data is pushed to server
        // This prevents silent data loss when dirty fields data is corrupted
        SyncLogger.shared.log(
          "Corrupted dirtyFields for wage snapshot \(id), treating as fully dirty: \(error.localizedDescription)",
          level: .error
        )
        return Set(WageSnapshotField.allCases)
      }
    }
    set {
      let keys = newValue.map(\.rawValue)
      dirtyFields = (try? kCanonicalJSONEncoder.encode(keys)) ?? Data()
    }
  }

  /// Decoded supplement rules
  var decodedSupplements: SupplementRulesSnapshot {
    get {
      (try? kSyncJSONDecoder.decode(SupplementRulesSnapshot.self, from: supplements))
        ?? SupplementRulesSnapshot(rules: [])
    }
    set {
      supplements = (try? kCanonicalJSONEncoder.encode(newValue)) ?? Data()
    }
  }

  /// Decoded overtime config
  var decodedOvertime: OvertimeConfig {
    get {
      (try? kSyncJSONDecoder.decode(OvertimeConfig.self, from: overtime)) ?? .disabled
    }
    set {
      overtime = (try? kCanonicalJSONEncoder.encode(newValue)) ?? Data()
    }
  }

  /// from_date as ISO string (YYYY-MM-DD) or nil for baseline
  var fromDateString: String? {
    guard let date = fromDate else { return nil }
    return FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone).string(from: date)
  }

  /// Whether this is a baseline (undated) snapshot
  var isBaseline: Bool {
    fromDate == nil
  }

  /// Whether this snapshot is soft-deleted
  var isDeleted: Bool {
    serverDeletedAt != nil
  }

  /// Whether this snapshot has been deleted locally and is waiting to sync
  var isPendingDelete: Bool {
    syncStatusRaw == "pendingDelete"
  }

  /// Whether this snapshot should appear in regular user-facing reads
  var isVisible: Bool {
    serverDeletedAt == nil && !isPendingDelete
  }

  /// Effective tax enabled (defaults to false if nil)
  var effectiveTaxEnabled: Bool {
    taxEnabled ?? false
  }

  /// Effective tax percentage (defaults to 0 if nil)
  var effectiveTaxPercentage: Double {
    taxPercentage ?? 0
  }

  /// Effective break enabled (defaults to true if nil)
  var effectiveBreakEnabled: Bool {
    breakEnabled ?? true
  }

  /// Effective break threshold hours (defaults to 5.5 if nil)
  var effectiveBreakThresholdHours: Double {
    breakThresholdHours ?? 5.5
  }

  /// Effective break deduction minutes (defaults to 30 if nil)
  var effectiveBreakDeductionMinutes: Int {
    breakDeductionMinutes ?? 30
  }

  /// Parsed break method enum
  var effectiveBreakMethod: BreakMethod {
    guard let method = breakMethod else { return .proportional }
    return BreakMethod(rawValue: method) ?? .proportional
  }

  // MARK: - Initialization

  init(
    id: String,
    userId: String,
    jobId: String? = nil,
    fromDate: Date? = nil,
    hourlyWage: Double,
    wageLevel: Int? = nil,
    tariffTypeId: String? = nil,
    supplements: Data,
    overtime: Data = (try? kCanonicalJSONEncoder.encode(OvertimeConfig.disabled)) ?? Data(),
    taxEnabled: Bool? = nil,
    taxPercentage: Double? = nil,
    breakEnabled: Bool? = nil,
    breakMethod: String? = nil,
    breakThresholdHours: Double? = nil,
    breakDeductionMinutes: Int? = nil,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date? = nil,
    syncStatus: SyncStatus = .clean,
    dirtyFields: Data = Data(),
    lastSyncedSnapshot: Data,
    localUpdatedAt: Date,
    conflictServerSnapshot: Data? = nil
  ) {
    self.id = id
    self.userId = userId
    self.jobId = jobId
    self.fromDate = fromDate
    self.hourlyWage = hourlyWage
    self.wageLevel = wageLevel
    self.tariffTypeId = tariffTypeId
    self.supplements = supplements
    self.overtime = overtime
    self.taxEnabled = taxEnabled
    self.taxPercentage = taxPercentage
    self.breakEnabled = breakEnabled
    self.breakMethod = breakMethod
    self.breakThresholdHours = breakThresholdHours
    self.breakDeductionMinutes = breakDeductionMinutes
    self.serverUpdatedAt = serverUpdatedAt
    self.serverRevision = serverRevision
    self.serverDeletedAt = serverDeletedAt
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

/// Snapshot of server data for a wage snapshot
struct WageSnapshotServerSnapshot: Codable, Equatable {
  let jobId: String?
  let fromDate: String?
  let hourlyWage: Double
  let wageLevel: Int?
  let tariffTypeId: String?
  let supplements: Data
  let overtime: Data
  let taxEnabled: Bool?
  let taxPercentage: Double?
  let breakEnabled: Bool?
  let breakMethod: String?
  let breakThresholdHours: Double?
  let breakDeductionMinutes: Int?
  let updatedAt: Date
  let revision: Int64
  let deletedAt: Date?

  init(
    jobId: String?,
    fromDate: String?,
    hourlyWage: Double,
    wageLevel: Int?,
    tariffTypeId: String?,
    supplements: Data,
    overtime: Data = (try? kCanonicalJSONEncoder.encode(OvertimeConfig.disabled)) ?? Data(),
    taxEnabled: Bool?,
    taxPercentage: Double?,
    breakEnabled: Bool?,
    breakMethod: String?,
    breakThresholdHours: Double?,
    breakDeductionMinutes: Int?,
    updatedAt: Date,
    revision: Int64,
    deletedAt: Date?
  ) {
    self.jobId = jobId
    self.fromDate = fromDate
    self.hourlyWage = hourlyWage
    self.wageLevel = wageLevel
    self.tariffTypeId = tariffTypeId
    self.supplements = supplements
    self.overtime = overtime
    self.taxEnabled = taxEnabled
    self.taxPercentage = taxPercentage
    self.breakEnabled = breakEnabled
    self.breakMethod = breakMethod
    self.breakThresholdHours = breakThresholdHours
    self.breakDeductionMinutes = breakDeductionMinutes
    self.updatedAt = updatedAt
    self.revision = revision
    self.deletedAt = deletedAt
  }

  private enum CodingKeys: String, CodingKey {
    case jobId
    case fromDate
    case hourlyWage
    case wageLevel
    case tariffTypeId
    case supplements
    case overtime
    case taxEnabled
    case taxPercentage
    case breakEnabled
    case breakMethod
    case breakThresholdHours
    case breakDeductionMinutes
    case updatedAt
    case revision
    case deletedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    jobId = try container.decodeIfPresent(String.self, forKey: .jobId)
    fromDate = try container.decodeIfPresent(String.self, forKey: .fromDate)
    hourlyWage = try container.decode(Double.self, forKey: .hourlyWage)
    wageLevel = try container.decodeIfPresent(Int.self, forKey: .wageLevel)
    tariffTypeId = try container.decodeIfPresent(String.self, forKey: .tariffTypeId)
    supplements = try container.decode(Data.self, forKey: .supplements)
    overtime =
      (try? container.decodeIfPresent(Data.self, forKey: .overtime))
      ?? ((try? kCanonicalJSONEncoder.encode(OvertimeConfig.disabled)) ?? Data())
    taxEnabled = try container.decodeIfPresent(Bool.self, forKey: .taxEnabled)
    taxPercentage = try container.decodeIfPresent(Double.self, forKey: .taxPercentage)
    breakEnabled = try container.decodeIfPresent(Bool.self, forKey: .breakEnabled)
    breakMethod = try container.decodeIfPresent(String.self, forKey: .breakMethod)
    breakThresholdHours = try container.decodeIfPresent(Double.self, forKey: .breakThresholdHours)
    breakDeductionMinutes = try container.decodeIfPresent(Int.self, forKey: .breakDeductionMinutes)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    revision = try container.decode(Int64.self, forKey: .revision)
    deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
  }

  /// Create snapshot from a WageSnapshot server response
  static func from(
    row: WageSnapshot,
    updatedAt: Date,
    revision: Int64,
    deletedAt: Date?
  ) -> Self {
    Self(
      jobId: row.job_id,
      fromDate: row.from_date,
      hourlyWage: row.hourly_wage,
      wageLevel: row.wage_level,
      tariffTypeId: row.tariff_type_id,
      supplements: (try? kCanonicalJSONEncoder.encode(row.supplements)) ?? Data(),
      overtime: (try? kCanonicalJSONEncoder.encode(row.overtime)) ?? Data(),
      taxEnabled: row.tax_enabled,
      taxPercentage: row.tax_percentage,
      breakEnabled: row.break_enabled,
      breakMethod: row.break_method,
      breakThresholdHours: row.break_threshold_hours,
      breakDeductionMinutes: row.break_deduction_minutes,
      updatedAt: updatedAt,
      revision: revision,
      deletedAt: deletedAt
    )
  }

  /// Encode to Data (throws on failure for critical paths)
  /// Use this in insert/update paths where empty Data would corrupt sync state
  func encodedOrThrow() throws -> Data {
    try requireEncode(self, typeName: "WageSnapshotServerSnapshot")
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
  func changedFields(from other: Self) -> Set<WageSnapshotField> {
    var changed: Set<WageSnapshotField> = []

    if jobId != other.jobId {
      changed.insert(.jobId)
    }
    if fromDate != other.fromDate {
      changed.insert(.fromDate)
    }
    if hourlyWage != other.hourlyWage {
      changed.insert(.hourlyWage)
    }
    if wageLevel != other.wageLevel {
      changed.insert(.wageLevel)
    }
    if tariffTypeId != other.tariffTypeId {
      changed.insert(.tariffTypeId)
    }
    if supplements != other.supplements {
      changed.insert(.supplements)
    }
    if overtime != other.overtime {
      changed.insert(.overtime)
    }
    if taxEnabled != other.taxEnabled {
      changed.insert(.taxEnabled)
    }
    if taxPercentage != other.taxPercentage {
      changed.insert(.taxPercentage)
    }
    if breakEnabled != other.breakEnabled {
      changed.insert(.breakEnabled)
    }
    if breakMethod != other.breakMethod {
      changed.insert(.breakMethod)
    }
    if breakThresholdHours != other.breakThresholdHours {
      changed.insert(.breakThresholdHours)
    }
    if breakDeductionMinutes != other.breakDeductionMinutes {
      changed.insert(.breakDeductionMinutes)
    }

    return changed
  }
}

// MARK: - Conversion Extensions

extension LocalWageSnapshot {
  /// Convert to WageSnapshot for use with existing payroll calculators
  func toWageSnapshot() -> WageSnapshot {
    WageSnapshot(
      id: id,
      user_id: userId,
      job_id: jobId,
      from_date: fromDateString,
      hourly_wage: hourlyWage,
      wage_level: wageLevel,
      tariff_type_id: tariffTypeId,
      supplements: decodedSupplements,
      overtime: decodedOvertime,
      tax_enabled: taxEnabled,
      tax_percentage: taxPercentage,
      break_enabled: breakEnabled,
      break_method: breakMethod,
      break_threshold_hours: breakThresholdHours,
      break_deduction_minutes: breakDeductionMinutes,
      created_at: nil
    )
  }

  /// Create from a server response row
  static func from(
    serverRow: WageSnapshot,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    context _: ModelContext
  ) -> LocalWageSnapshot {
    let dateFormatter = FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone)

    let fromDate = serverRow.from_date.flatMap { dateFormatter.date(from: $0) }

    let snapshot = WageSnapshotServerSnapshot.from(
      row: serverRow,
      updatedAt: serverUpdatedAt,
      revision: serverRevision,
      deletedAt: serverDeletedAt
    )

    return LocalWageSnapshot(
      id: serverRow.id,
      userId: serverRow.user_id,
      jobId: serverRow.job_id,
      fromDate: fromDate,
      hourlyWage: serverRow.hourly_wage,
      wageLevel: serverRow.wage_level,
      tariffTypeId: serverRow.tariff_type_id,
      supplements: (try? kCanonicalJSONEncoder.encode(serverRow.supplements)) ?? Data(),
      overtime: (try? kCanonicalJSONEncoder.encode(serverRow.overtime)) ?? Data(),
      taxEnabled: serverRow.tax_enabled,
      taxPercentage: serverRow.tax_percentage,
      breakEnabled: serverRow.break_enabled,
      breakMethod: serverRow.break_method,
      breakThresholdHours: serverRow.break_threshold_hours,
      breakDeductionMinutes: serverRow.break_deduction_minutes,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      syncStatus: .clean,
      dirtyFields: emptyDirtyFields(),
      lastSyncedSnapshot: snapshot.encoded(),
      localUpdatedAt: Date(),
      conflictServerSnapshot: nil
    )
  }
}
