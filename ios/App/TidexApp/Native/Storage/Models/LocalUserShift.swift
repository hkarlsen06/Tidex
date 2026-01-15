import Foundation
import SwiftData

// MARK: - Local User Shift

/// SwiftData model for locally persisted user shifts
/// Maps to the `user_shifts` table in Supabase
@Model
final class LocalUserShift {
    // MARK: - Primary Key & Foreign Key

    /// Unique identifier (UUID string from server)
    @Attribute(.unique)
    var id: String

    /// User who owns this shift
    var userId: String

    // MARK: - Shift Data

    /// Date of the shift (stored as Date, derived from YYYY-MM-DD)
    var shiftDate: Date

    /// Start time in HH:mm format
    var startTime: String

    /// End time in HH:mm format (can be less than startTime for cross-midnight)
    var endTime: String

    /// Custom supplements JSON blob (nullable)
    /// Stored as canonical JSON Data for reliable diffing
    var customSupplements: Data?

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
    /// Contains JSON-encoded UserShiftServerSnapshot
    var lastSyncedSnapshot: Data

    /// When the user last modified this record locally
    var localUpdatedAt: Date

    /// Server version on conflict (for resolution UI)
    /// Contains JSON-encoded UserShiftServerSnapshot
    var conflictServerSnapshot: Data?

    // MARK: - Computed Properties

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .clean }
        set { syncStatusRaw = newValue.rawValue }
    }

    /// Decoded dirty fields
    var dirtyFieldKeys: Set<UserShiftField> {
        get {
            guard let keys = try? syncJSONDecoder.decode([String].self, from: dirtyFields) else {
                return []
            }
            return Set(keys.compactMap { UserShiftField(rawValue: $0) })
        }
        set {
            let keys = newValue.map { $0.rawValue }
            dirtyFields = (try? canonicalJSONEncoder.encode(keys)) ?? Data()
        }
    }

    /// Decoded custom supplements
    var decodedCustomSupplements: CustomSupplementsData? {
        get {
            guard let data = customSupplements else { return nil }
            return try? syncJSONDecoder.decode(CustomSupplementsData.self, from: data)
        }
        set {
            customSupplements = newValue.flatMap { try? canonicalJSONEncoder.encode($0) }
        }
    }

    /// Shift date as ISO string (YYYY-MM-DD)
    var shiftDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: shiftDate)
    }

    /// Whether this shift is soft-deleted
    var isDeleted: Bool {
        serverDeletedAt != nil
    }

    // MARK: - Initialization

    init(
        id: String,
        userId: String,
        shiftDate: Date,
        startTime: String,
        endTime: String,
        customSupplements: Data? = nil,
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
        self.shiftDate = shiftDate
        self.startTime = startTime
        self.endTime = endTime
        self.customSupplements = customSupplements
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

/// Snapshot of server data for a user shift
/// Used for conflict detection and field-level diffing
struct UserShiftServerSnapshot: Codable, Equatable {
    let shiftDate: String
    let startTime: String
    let endTime: String
    let customSupplements: Data?
    let updatedAt: Date
    let revision: Int64
    let deletedAt: Date?

    /// Create snapshot from a ShiftRow server response
    static func from(
        shiftDate: String,
        startTime: String,
        endTime: String,
        customSupplements: CustomSupplementsData?,
        updatedAt: Date,
        revision: Int64,
        deletedAt: Date?
    ) -> UserShiftServerSnapshot {
        let supplementsData = customSupplements.flatMap { try? canonicalJSONEncoder.encode($0) }
        return UserShiftServerSnapshot(
            shiftDate: shiftDate,
            startTime: startTime,
            endTime: endTime,
            customSupplements: supplementsData,
            updatedAt: updatedAt,
            revision: revision,
            deletedAt: deletedAt
        )
    }

    /// Encode to Data (throws on failure for critical paths)
    /// Use this in insert/update paths where empty Data would corrupt sync state
    func encodedOrThrow() throws -> Data {
        try requireEncode(self, typeName: "UserShiftServerSnapshot")
    }

    /// Encode to Data (returns empty Data on failure - use only for non-critical paths)
    /// DEPRECATED: Prefer encodedOrThrow() for new code
    func encoded() -> Data {
        (try? canonicalJSONEncoder.encode(self)) ?? Data()
    }

    /// Decode from Data
    static func decode(from data: Data) -> UserShiftServerSnapshot? {
        try? syncJSONDecoder.decode(UserShiftServerSnapshot.self, from: data)
    }

    /// Compute changed fields compared to another snapshot
    func changedFields(from other: UserShiftServerSnapshot) -> Set<UserShiftField> {
        var changed: Set<UserShiftField> = []

        if shiftDate != other.shiftDate {
            changed.insert(.shiftDate)
        }
        if startTime != other.startTime {
            changed.insert(.startTime)
        }
        if endTime != other.endTime {
            changed.insert(.endTime)
        }
        if customSupplements != other.customSupplements {
            changed.insert(.customSupplements)
        }

        return changed
    }
}

// MARK: - Conversion Extensions

extension LocalUserShift {
    /// Convert to ShiftRow for use with existing payroll calculators
    func toShiftRow() -> ShiftRow {
        ShiftRow(
            id: id,
            user_id: userId,
            shift_date: shiftDateString,
            start_time: startTime,
            end_time: endTime,
            custom_supplements: decodedCustomSupplements,
            created_at: nil,
            recurring_id: nil,
            recurring_anchor_weekday: nil
        )
    }

    /// Create from a server response row
    static func from(
        serverRow: ShiftRow,
        userId: String,
        serverUpdatedAt: Date,
        serverRevision: Int64,
        serverDeletedAt: Date?,
        context: ModelContext
    ) -> LocalUserShift {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        let shiftDate = dateFormatter.date(from: serverRow.shift_date) ?? Date()
        let supplementsData = serverRow.custom_supplements.flatMap { try? canonicalJSONEncoder.encode($0) }

        let snapshot = UserShiftServerSnapshot.from(
            shiftDate: serverRow.shift_date,
            startTime: serverRow.start_time,
            endTime: serverRow.end_time,
            customSupplements: serverRow.custom_supplements,
            updatedAt: serverUpdatedAt,
            revision: serverRevision,
            deletedAt: serverDeletedAt
        )

        return LocalUserShift(
            id: serverRow.id,
            userId: userId,
            shiftDate: shiftDate,
            startTime: serverRow.start_time,
            endTime: serverRow.end_time,
            customSupplements: supplementsData,
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
