import Foundation
import SwiftData

// MARK: - Local Recurring Shift

/// SwiftData model for locally persisted recurring shifts
/// Maps to the `recurring_shifts` table in Supabase
@Model
final class LocalRecurringShift {
  // MARK: - Primary Key & Foreign Key

  /// Unique identifier (UUID string from server)
  @Attribute(.unique)
  var id: String

  /// User who owns this recurring shift
  var userId: String

  // MARK: - Recurring Shift Data

  /// Job that owns this recurring pattern (nullable during rollout compatibility)
  var jobId: String?

  /// Start time in HH:mm format
  var startTime: String

  /// End time in HH:mm format
  var endTime: String

  /// Repetition interval: 0 = every week, 1 = every 2 weeks, etc.
  var repeatIntervalWeeks: Int

  /// Selected days with anchor dates (JSON)
  /// Key is weekday (0-6 where 0=Sunday), value is ISO date string
  var selectedDays: Data

  /// End condition (JSON, nullable)
  var endCondition: Data?

  /// Excluded dates (JSON array of ISO date strings)
  var exclusions: Data?

  /// Date-specific supplements (JSON)
  var dateSpecificSupplements: Data?

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
  var dirtyFieldKeys: Set<RecurringShiftField> {
    get {
      // Empty data means no dirty fields (common case for clean records)
      guard !dirtyFields.isEmpty else {
        return []
      }

      do {
        let keys = try syncJSONDecoder.decode([String].self, from: dirtyFields)
        return Set(keys.compactMap { RecurringShiftField(rawValue: $0) })
      } catch {
        // If decode fails, treat as fully dirty to ensure data is pushed to server
        // This prevents silent data loss when dirty fields data is corrupted
        SyncLogger.shared.log(
          "Corrupted dirtyFields for recurring shift \(id), treating as fully dirty: \(error.localizedDescription)",
          level: .error
        )
        return Set(RecurringShiftField.allCases)
      }
    }
    set {
      let keys = newValue.map { $0.rawValue }
      dirtyFields = (try? canonicalJSONEncoder.encode(keys)) ?? Data()
    }
  }

  /// Decoded selected days
  var decodedSelectedDays: SelectedDays {
    get {
      if let decoded = try? syncJSONDecoder.decode(SelectedDays.self, from: selectedDays),
        !decoded.isEmpty
      {
        return decoded
      }

      if let snapshot = RecurringShiftServerSnapshot.decode(from: lastSyncedSnapshot),
        let fallback = try? syncJSONDecoder.decode(SelectedDays.self, from: snapshot.selectedDays),
        !fallback.isEmpty
      {
        SyncLogger.shared.log(
          "Recovered corrupt selectedDays for recurring shift \(id) from last synced snapshot",
          level: .warning
        )
        return fallback
      }

      return [:]
    }
    set {
      selectedDays = (try? canonicalJSONEncoder.encode(newValue)) ?? Data()
    }
  }

  /// Decoded end condition
  var decodedEndCondition: EndCondition? {
    get {
      guard let data = endCondition else { return nil }
      if let decoded = try? syncJSONDecoder.decode(EndCondition.self, from: data) {
        return decoded
      }

      if let snapshot = RecurringShiftServerSnapshot.decode(from: lastSyncedSnapshot),
        let fallback = snapshot.endCondition.flatMap({
          try? syncJSONDecoder.decode(EndCondition.self, from: $0)
        })
      {
        SyncLogger.shared.log(
          "Recovered corrupt endCondition for recurring shift \(id) from last synced snapshot",
          level: .warning
        )
        return fallback
      }

      return nil
    }
    set {
      endCondition = newValue.flatMap { try? canonicalJSONEncoder.encode($0) }
    }
  }

  /// Decoded exclusions
  var decodedExclusions: [String] {
    get {
      guard let data = exclusions else { return [] }
      if let decoded = try? syncJSONDecoder.decode([String].self, from: data) {
        return decoded
      }

      if let snapshot = RecurringShiftServerSnapshot.decode(from: lastSyncedSnapshot),
        let fallback = snapshot.exclusions.flatMap({
          try? syncJSONDecoder.decode([String].self, from: $0)
        })
      {
        SyncLogger.shared.log(
          "Recovered corrupt exclusions for recurring shift \(id) from last synced snapshot",
          level: .warning
        )
        return fallback
      }

      return []
    }
    set {
      exclusions = newValue.isEmpty ? nil : (try? canonicalJSONEncoder.encode(newValue))
    }
  }

  /// Decoded date-specific supplements
  var decodedDateSpecificSupplements: [String: CustomSupplementsData] {
    get {
      guard let data = dateSpecificSupplements else { return [:] }
      if let decoded = try? syncJSONDecoder.decode([String: CustomSupplementsData].self, from: data)
      {
        return decoded
      }

      if let snapshot = RecurringShiftServerSnapshot.decode(from: lastSyncedSnapshot),
        let fallback = snapshot.dateSpecificSupplements.flatMap({
          try? syncJSONDecoder.decode([String: CustomSupplementsData].self, from: $0)
        })
      {
        SyncLogger.shared.log(
          """
          Recovered corrupt dateSpecificSupplements for recurring shift \(id) from last synced snapshot
          """,
          level: .warning
        )
        return fallback
      }

      return [:]
    }
    set {
      dateSpecificSupplements =
        newValue.isEmpty ? nil : (try? canonicalJSONEncoder.encode(newValue))
    }
  }

  /// Whether this recurring shift is soft-deleted
  var isDeleted: Bool {
    serverDeletedAt != nil
  }

  // MARK: - Initialization

  init(
    id: String,
    userId: String,
    jobId: String? = nil,
    startTime: String,
    endTime: String,
    repeatIntervalWeeks: Int,
    selectedDays: Data,
    endCondition: Data? = nil,
    exclusions: Data? = nil,
    dateSpecificSupplements: Data? = nil,
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
    self.startTime = startTime
    self.endTime = endTime
    self.repeatIntervalWeeks = repeatIntervalWeeks
    self.selectedDays = selectedDays
    self.endCondition = endCondition
    self.exclusions = exclusions
    self.dateSpecificSupplements = dateSpecificSupplements
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
    (try? canonicalJSONEncoder.encode([String]())) ?? Data()
  }
}

// MARK: - Server Snapshot

/// Snapshot of server data for a recurring shift
struct RecurringShiftServerSnapshot: Codable, Equatable {
  let jobId: String?
  let startTime: String
  let endTime: String
  let repeatIntervalWeeks: Int
  let selectedDays: Data
  let endCondition: Data?
  let exclusions: Data?
  let dateSpecificSupplements: Data?
  let updatedAt: Date
  let revision: Int64
  let deletedAt: Date?

  /// Create snapshot from a RecurringShiftRow server response
  static func from(
    row: RecurringShiftRow,
    updatedAt: Date,
    revision: Int64,
    deletedAt: Date?
  ) -> RecurringShiftServerSnapshot {
    RecurringShiftServerSnapshot(
      jobId: row.job_id,
      startTime: row.cleanStartTime,
      endTime: row.cleanEndTime,
      repeatIntervalWeeks: row.repeat_interval_weeks,
      selectedDays: (try? canonicalJSONEncoder.encode(row.selected_days)) ?? Data(),
      endCondition: row.end_condition.flatMap { try? canonicalJSONEncoder.encode($0) },
      exclusions: row.exclusions.flatMap { try? canonicalJSONEncoder.encode($0) },
      dateSpecificSupplements: row.date_specific_supplements.flatMap {
        try? canonicalJSONEncoder.encode($0)
      },
      updatedAt: updatedAt,
      revision: revision,
      deletedAt: deletedAt
    )
  }

  /// Encode to Data (throws on failure for critical paths)
  /// Use this in insert/update paths where empty Data would corrupt sync state
  func encodedOrThrow() throws -> Data {
    try requireEncode(self, typeName: "RecurringShiftServerSnapshot")
  }

  /// Encode to Data (returns empty Data on failure - use only for non-critical paths)
  /// DEPRECATED: Prefer encodedOrThrow() for new code
  func encoded() -> Data {
    (try? canonicalJSONEncoder.encode(self)) ?? Data()
  }

  /// Decode from Data
  static func decode(from data: Data) -> RecurringShiftServerSnapshot? {
    try? syncJSONDecoder.decode(RecurringShiftServerSnapshot.self, from: data)
  }

  /// Compute changed fields compared to another snapshot
  func changedFields(from other: RecurringShiftServerSnapshot) -> Set<RecurringShiftField> {
    var changed: Set<RecurringShiftField> = []

    if jobId != other.jobId {
      changed.insert(.jobId)
    }
    if startTime != other.startTime {
      changed.insert(.startTime)
    }
    if endTime != other.endTime {
      changed.insert(.endTime)
    }
    if repeatIntervalWeeks != other.repeatIntervalWeeks {
      changed.insert(.repeatIntervalWeeks)
    }
    if selectedDays != other.selectedDays {
      changed.insert(.selectedDays)
    }
    if endCondition != other.endCondition {
      changed.insert(.endCondition)
    }
    if exclusions != other.exclusions {
      changed.insert(.exclusions)
    }
    if dateSpecificSupplements != other.dateSpecificSupplements {
      changed.insert(.dateSpecificSupplements)
    }

    return changed
  }
}

// MARK: - Conversion Extensions

extension LocalRecurringShift {
  /// Convert to RecurringShiftRow for use with existing generators
  func toRecurringShiftRow() -> RecurringShiftRow {
    RecurringShiftRow(
      id: id,
      user_id: userId,
      job_id: jobId,
      start_time: startTime,
      end_time: endTime,
      repeat_interval_weeks: repeatIntervalWeeks,
      selected_days: decodedSelectedDays,
      end_condition: decodedEndCondition,
      exclusions: decodedExclusions.isEmpty ? nil : decodedExclusions,
      date_specific_supplements: decodedDateSpecificSupplements.isEmpty
        ? nil : decodedDateSpecificSupplements
    )
  }

  /// Create from a server response row
  static func from(
    serverRow: RecurringShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    context: ModelContext
  ) -> LocalRecurringShift {
    let snapshot = RecurringShiftServerSnapshot.from(
      row: serverRow,
      updatedAt: serverUpdatedAt,
      revision: serverRevision,
      deletedAt: serverDeletedAt
    )

    return LocalRecurringShift(
      id: serverRow.id,
      userId: serverRow.user_id,
      jobId: serverRow.job_id,
      startTime: serverRow.cleanStartTime,
      endTime: serverRow.cleanEndTime,
      repeatIntervalWeeks: serverRow.repeat_interval_weeks,
      selectedDays: (try? canonicalJSONEncoder.encode(serverRow.selected_days)) ?? Data(),
      endCondition: serverRow.end_condition.flatMap { try? canonicalJSONEncoder.encode($0) },
      exclusions: serverRow.exclusions.flatMap { try? canonicalJSONEncoder.encode($0) },
      dateSpecificSupplements: serverRow.date_specific_supplements.flatMap {
        try? canonicalJSONEncoder.encode($0)
      },
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
