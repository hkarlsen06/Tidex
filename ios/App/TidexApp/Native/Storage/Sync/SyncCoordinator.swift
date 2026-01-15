import Foundation
import Supabase
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SyncCoordinator")

// MARK: - Sync Coordinator

/// Coordinates bidirectional sync between local SwiftData storage and Supabase
/// Implements incremental sync via revision cursors with field-level conflict detection
@MainActor
final class SyncCoordinator: ObservableObject {
    /// Shared instance
    static let shared = SyncCoordinator()

    // MARK: - Published State

    /// Whether a sync is currently in progress
    @Published private(set) var isSyncing = false

    /// Last sync error (nil if last sync succeeded)
    @Published private(set) var lastError: String?

    /// Number of unresolved conflicts
    @Published private(set) var conflictCount = 0

    /// When the last successful sync completed
    @Published private(set) var lastSyncedAt: Date?

    // MARK: - Configuration

    /// Page size for incremental sync queries
    private let pageSize = 500

    /// Minimum interval between automatic syncs (in seconds)
    private let minimumSyncInterval: TimeInterval = 60

    // MARK: - Private State

    /// Lock to prevent concurrent syncs
    private var syncInProgress = false

    /// Last automatic sync attempt time
    private var lastAutoSyncAt: Date?

    private init() {}

    // MARK: - Public API

    /// Trigger a sync operation
    /// - Parameters:
    ///   - reason: Why the sync was triggered (for logging)
    ///   - userId: User ID to sync for
    /// - Returns: Sync result
    @discardableResult
    func sync(reason: SyncReason, userId: String) async -> SyncResult {
        // Single-flight protection
        guard !syncInProgress else {
            logger.info("Sync already in progress, skipping \(reason.rawValue)")
            return SyncResult(
                success: false,
                tableResults: [],
                totalRowsProcessed: 0,
                totalConflicts: 0,
                totalAutoMerged: 0,
                duration: 0,
                error: "Sync already in progress"
            )
        }

        // Interval guard for automatic syncs
        if reason != .manualRefresh {
            if let lastAuto = lastAutoSyncAt,
               Date().timeIntervalSince(lastAuto) < minimumSyncInterval {
                logger.info("Skipping auto sync, last sync was \(Int(Date().timeIntervalSince(lastAuto)))s ago")
                return SyncResult(
                    success: false,
                    tableResults: [],
                    totalRowsProcessed: 0,
                    totalConflicts: 0,
                    totalAutoMerged: 0,
                    duration: 0,
                    error: "Minimum sync interval not reached"
                )
            }
        }

        syncInProgress = true
        isSyncing = true
        lastError = nil

        let startTime = Date()
        logger.info("Starting sync: \(reason.rawValue) for user \(userId.prefix(8))...")

        // Get or create sync state
        let storeActor = LocalStore.shared.storeActor
        do {
            let syncState = try await storeActor.getOrCreateSyncState(userId: userId)
            await storeActor.updateSyncState(userId: userId) { state in
                state.markSyncStarted()
            }

            // Pull all tables
            var tableResults: [TablePullResult] = []

            for table in SyncTable.allCases {
                let result = try await pullTable(table, userId: userId, syncState: syncState)
                tableResults.append(result)
            }

            // Calculate totals
            let totalRows = tableResults.reduce(0) { $0 + $1.rowsProcessed }
            let totalConflicts = tableResults.reduce(0) { $0 + $1.newConflicts }
            let totalAutoMerged = tableResults.reduce(0) { $0 + $1.autoMerged }
            let duration = Date().timeIntervalSince(startTime)

            // Update sync state
            await storeActor.updateSyncState(userId: userId) { state in
                state.markSyncSucceeded()
            }

            // Update published state
            lastSyncedAt = Date()
            conflictCount = try await storeActor.countConflicts(userId: userId)

            if reason != .manualRefresh {
                lastAutoSyncAt = Date()
            }

            logger.info("Sync completed: \(totalRows) rows, \(totalConflicts) conflicts, \(totalAutoMerged) auto-merged in \(String(format: "%.2f", duration))s")

            syncInProgress = false
            isSyncing = false

            return SyncResult(
                success: true,
                tableResults: tableResults,
                totalRowsProcessed: totalRows,
                totalConflicts: totalConflicts,
                totalAutoMerged: totalAutoMerged,
                duration: duration,
                error: nil
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            let errorMessage = error.localizedDescription

            logger.error("Sync failed: \(errorMessage)")

            await storeActor.updateSyncState(userId: userId) { state in
                state.markSyncFailed(error: errorMessage)
            }

            lastError = errorMessage
            syncInProgress = false
            isSyncing = false

            return SyncResult(
                success: false,
                tableResults: [],
                totalRowsProcessed: 0,
                totalConflicts: 0,
                totalAutoMerged: 0,
                duration: duration,
                error: errorMessage
            )
        }
    }

    // MARK: - Pull Implementation

    /// Pull changes for a single table
    private func pullTable(
        _ table: SyncTable,
        userId: String,
        syncState: LocalSyncState
    ) async throws -> TablePullResult {
        var cursor = syncState.cursor(for: table)
        var totalRows = 0
        var newConflicts = 0
        var autoMerged = 0

        logger.debug("Pulling \(table.displayName) from revision \(cursor)")

        // Page through all changes
        while true {
            let result: PagePullResult

            switch table {
            case .userShifts:
                result = try await pullUserShiftsPage(userId: userId, cursor: cursor)
            case .recurringShifts:
                result = try await pullRecurringShiftsPage(userId: userId, cursor: cursor)
            case .wageSnapshots:
                result = try await pullWageSnapshotsPage(userId: userId, cursor: cursor)
            case .userSettings:
                result = try await pullUserSettingsPage(userId: userId, cursor: cursor)
            }

            totalRows += result.rowsProcessed
            newConflicts += result.newConflicts
            autoMerged += result.autoMerged

            if result.maxRevision > cursor {
                cursor = result.maxRevision
                // Update cursor in sync state
                let storeActor = LocalStore.shared.storeActor
                await storeActor.updateSyncState(userId: userId) { state in
                    state.updateCursor(for: table, to: cursor)
                }
            }

            // No more pages
            if !result.hasMore {
                break
            }
        }

        logger.debug("Pulled \(table.displayName): \(totalRows) rows, max revision \(cursor)")

        return TablePullResult(
            table: table,
            rowsProcessed: totalRows,
            maxRevision: cursor,
            newConflicts: newConflicts,
            autoMerged: autoMerged
        )
    }

    /// Result of pulling a single page
    private struct PagePullResult {
        let rowsProcessed: Int
        let maxRevision: Int64
        let newConflicts: Int
        let autoMerged: Int
        let hasMore: Bool
    }

    // MARK: - User Shifts Pull

    private func pullUserShiftsPage(userId: String, cursor: Int64) async throws -> PagePullResult {
        // Query server for changes since cursor
        let rows: [SyncShiftRow] = try await supabase
            .from("user_shifts")
            .select()
            .eq("user_id", value: userId)
            .gt("revision", value: cursor)
            .order("revision", ascending: true)
            .limit(pageSize)
            .execute()
            .value

        if rows.isEmpty {
            return PagePullResult(rowsProcessed: 0, maxRevision: cursor, newConflicts: 0, autoMerged: 0, hasMore: false)
        }

        let storeActor = LocalStore.shared.storeActor
        var newConflicts = 0
        var autoMerged = 0
        var maxRevision = cursor

        for row in rows {
            let result = try await applyShiftRow(row, storeActor: storeActor)
            if result == .conflict { newConflicts += 1 }
            if result == .autoMerged { autoMerged += 1 }
            if row.revision > maxRevision {
                maxRevision = row.revision
            }
        }

        try await storeActor.save()

        return PagePullResult(
            rowsProcessed: rows.count,
            maxRevision: maxRevision,
            newConflicts: newConflicts,
            autoMerged: autoMerged,
            hasMore: rows.count == pageSize
        )
    }

    /// Apply a server shift row to local storage
    private func applyShiftRow(_ serverRow: SyncShiftRow, storeActor: LocalStoreActor) async throws -> ApplyResult {
        let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()
        let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

        // Check if exists locally
        if let existing = try await storeActor.getUserShift(id: serverRow.id) {
            return try await applyShiftToExisting(
                existing: existing,
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                serverDeletedAt: serverDeletedAt,
                storeActor: storeActor
            )
        } else {
            // Insert as new clean row
            try await insertNewShift(
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                serverDeletedAt: serverDeletedAt,
                storeActor: storeActor
            )
            return .inserted
        }
    }

    private func applyShiftToExisting(
        existing: LocalUserShift,
        serverRow: SyncShiftRow,
        serverUpdatedAt: Date,
        serverDeletedAt: Date?,
        storeActor: LocalStoreActor
    ) async throws -> ApplyResult {
        let serverSnapshot = UserShiftServerSnapshot.from(
            shiftDate: serverRow.shift_date,
            startTime: serverRow.start_time,
            endTime: serverRow.end_time,
            customSupplements: serverRow.custom_supplements,
            updatedAt: serverUpdatedAt,
            revision: serverRow.revision,
            deletedAt: serverDeletedAt
        )

        switch existing.syncStatus {
        case .clean:
            // Overwrite with server data
            await storeActor.updateShiftFromServer(
                id: serverRow.id,
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                serverRevision: serverRow.revision,
                serverDeletedAt: serverDeletedAt,
                snapshot: serverSnapshot
            )
            return .updated

        case .dirty, .pendingDelete:
            // Check for conflict
            if serverRow.revision == existing.serverRevision {
                // Server unchanged, keep local edits
                return .noChange
            }

            // Server changed - check for field-level merge
            guard let lastSnapshot = UserShiftServerSnapshot.decode(from: existing.lastSyncedSnapshot) else {
                // Cannot decode snapshot, mark conflict
                await storeActor.markShiftConflict(id: serverRow.id, serverSnapshot: serverSnapshot)
                return .conflict
            }

            let serverChangedFields = serverSnapshot.changedFields(from: lastSnapshot)
            let localDirtyFields = existing.dirtyFieldKeys

            // Check for overlap
            let conflictingFields = serverChangedFields.intersection(Set(localDirtyFields.map { convertToUserShiftField($0) }))

            if conflictingFields.isEmpty {
                // Auto-merge: apply server changes for non-dirty fields, keep local for dirty
                await storeActor.autoMergeShift(
                    id: serverRow.id,
                    serverRow: serverRow,
                    serverUpdatedAt: serverUpdatedAt,
                    serverRevision: serverRow.revision,
                    serverDeletedAt: serverDeletedAt,
                    newSnapshot: serverSnapshot,
                    localDirtyFields: localDirtyFields
                )
                return .autoMerged
            } else {
                // Conflict - overlapping fields
                await storeActor.markShiftConflict(id: serverRow.id, serverSnapshot: serverSnapshot)
                return .conflict
            }

        case .conflict:
            // Already in conflict, update conflict snapshot
            await storeActor.updateShiftConflictSnapshot(id: serverRow.id, serverSnapshot: serverSnapshot)
            return .noChange
        }
    }

    private func insertNewShift(
        serverRow: SyncShiftRow,
        serverUpdatedAt: Date,
        serverDeletedAt: Date?,
        storeActor: LocalStoreActor
    ) async throws {
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
            revision: serverRow.revision,
            deletedAt: serverDeletedAt
        )

        let localShift = LocalUserShift(
            id: serverRow.id,
            userId: serverRow.user_id,
            shiftDate: shiftDate,
            startTime: serverRow.start_time,
            endTime: serverRow.end_time,
            customSupplements: supplementsData,
            serverUpdatedAt: serverUpdatedAt,
            serverRevision: serverRow.revision,
            serverDeletedAt: serverDeletedAt,
            syncStatus: .clean,
            dirtyFields: LocalUserShift.emptyDirtyFields(),
            lastSyncedSnapshot: snapshot.encoded(),
            localUpdatedAt: Date(),
            conflictServerSnapshot: nil
        )

        try await storeActor.upsertUserShift(localShift)
    }

    // Helper to convert UserShiftField to itself (for type safety in intersection)
    private func convertToUserShiftField(_ field: UserShiftField) -> UserShiftField {
        field
    }

    // MARK: - Recurring Shifts Pull

    private func pullRecurringShiftsPage(userId: String, cursor: Int64) async throws -> PagePullResult {
        let rows: [SyncRecurringShiftRow] = try await supabase
            .from("recurring_shifts")
            .select()
            .eq("user_id", value: userId)
            .gt("revision", value: cursor)
            .order("revision", ascending: true)
            .limit(pageSize)
            .execute()
            .value

        if rows.isEmpty {
            return PagePullResult(rowsProcessed: 0, maxRevision: cursor, newConflicts: 0, autoMerged: 0, hasMore: false)
        }

        let storeActor = LocalStore.shared.storeActor
        var newConflicts = 0
        var autoMerged = 0
        var maxRevision = cursor

        for row in rows {
            let result = try await applyRecurringShiftRow(row, storeActor: storeActor)
            if result == .conflict { newConflicts += 1 }
            if result == .autoMerged { autoMerged += 1 }
            if row.revision > maxRevision {
                maxRevision = row.revision
            }
        }

        try await storeActor.save()

        return PagePullResult(
            rowsProcessed: rows.count,
            maxRevision: maxRevision,
            newConflicts: newConflicts,
            autoMerged: autoMerged,
            hasMore: rows.count == pageSize
        )
    }

    private func applyRecurringShiftRow(_ serverRow: SyncRecurringShiftRow, storeActor: LocalStoreActor) async throws -> ApplyResult {
        let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()
        let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

        if let existing = try await storeActor.getRecurringShift(id: serverRow.id) {
            return try await applyRecurringShiftToExisting(
                existing: existing,
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                serverDeletedAt: serverDeletedAt,
                storeActor: storeActor
            )
        } else {
            try await insertNewRecurringShift(
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                serverDeletedAt: serverDeletedAt,
                storeActor: storeActor
            )
            return .inserted
        }
    }

    private func applyRecurringShiftToExisting(
        existing: LocalRecurringShift,
        serverRow: SyncRecurringShiftRow,
        serverUpdatedAt: Date,
        serverDeletedAt: Date?,
        storeActor: LocalStoreActor
    ) async throws -> ApplyResult {
        let serverSnapshot = RecurringShiftServerSnapshot.from(
            row: serverRow.toRecurringShiftRow(),
            updatedAt: serverUpdatedAt,
            revision: serverRow.revision,
            deletedAt: serverDeletedAt
        )

        switch existing.syncStatus {
        case .clean:
            await storeActor.updateRecurringShiftFromServer(
                id: serverRow.id,
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                serverRevision: serverRow.revision,
                serverDeletedAt: serverDeletedAt,
                snapshot: serverSnapshot
            )
            return .updated

        case .dirty, .pendingDelete:
            if serverRow.revision == existing.serverRevision {
                return .noChange
            }

            guard let lastSnapshot = RecurringShiftServerSnapshot.decode(from: existing.lastSyncedSnapshot) else {
                await storeActor.markRecurringShiftConflict(id: serverRow.id, serverSnapshot: serverSnapshot)
                return .conflict
            }

            let serverChangedFields = serverSnapshot.changedFields(from: lastSnapshot)
            let localDirtyFields = existing.dirtyFieldKeys
            let conflictingFields = serverChangedFields.intersection(Set(localDirtyFields.map { convertToRecurringShiftField($0) }))

            if conflictingFields.isEmpty {
                await storeActor.autoMergeRecurringShift(
                    id: serverRow.id,
                    serverRow: serverRow,
                    serverUpdatedAt: serverUpdatedAt,
                    serverRevision: serverRow.revision,
                    serverDeletedAt: serverDeletedAt,
                    newSnapshot: serverSnapshot,
                    localDirtyFields: localDirtyFields
                )
                return .autoMerged
            } else {
                await storeActor.markRecurringShiftConflict(id: serverRow.id, serverSnapshot: serverSnapshot)
                return .conflict
            }

        case .conflict:
            await storeActor.updateRecurringShiftConflictSnapshot(id: serverRow.id, serverSnapshot: serverSnapshot)
            return .noChange
        }
    }

    private func insertNewRecurringShift(
        serverRow: SyncRecurringShiftRow,
        serverUpdatedAt: Date,
        serverDeletedAt: Date?,
        storeActor: LocalStoreActor
    ) async throws {
        let snapshot = RecurringShiftServerSnapshot.from(
            row: serverRow.toRecurringShiftRow(),
            updatedAt: serverUpdatedAt,
            revision: serverRow.revision,
            deletedAt: serverDeletedAt
        )

        let localShift = LocalRecurringShift(
            id: serverRow.id,
            userId: serverRow.user_id,
            startTime: serverRow.cleanStartTime,
            endTime: serverRow.cleanEndTime,
            repeatIntervalWeeks: serverRow.repeat_interval_weeks,
            selectedDays: (try? canonicalJSONEncoder.encode(serverRow.selected_days)) ?? Data(),
            endCondition: serverRow.end_condition.flatMap { try? canonicalJSONEncoder.encode($0) },
            exclusions: serverRow.exclusions.flatMap { try? canonicalJSONEncoder.encode($0) },
            dateSpecificSupplements: serverRow.date_specific_supplements.flatMap { try? canonicalJSONEncoder.encode($0) },
            serverUpdatedAt: serverUpdatedAt,
            serverRevision: serverRow.revision,
            serverDeletedAt: serverDeletedAt,
            syncStatus: .clean,
            dirtyFields: LocalRecurringShift.emptyDirtyFields(),
            lastSyncedSnapshot: snapshot.encoded(),
            localUpdatedAt: Date(),
            conflictServerSnapshot: nil
        )

        try await storeActor.upsertRecurringShift(localShift)
    }

    private func convertToRecurringShiftField(_ field: RecurringShiftField) -> RecurringShiftField {
        field
    }

    // MARK: - Wage Snapshots Pull

    private func pullWageSnapshotsPage(userId: String, cursor: Int64) async throws -> PagePullResult {
        let rows: [SyncWageSnapshotRow] = try await supabase
            .from("wage_snapshots")
            .select()
            .eq("user_id", value: userId)
            .gt("revision", value: cursor)
            .order("revision", ascending: true)
            .limit(pageSize)
            .execute()
            .value

        if rows.isEmpty {
            return PagePullResult(rowsProcessed: 0, maxRevision: cursor, newConflicts: 0, autoMerged: 0, hasMore: false)
        }

        let storeActor = LocalStore.shared.storeActor
        var newConflicts = 0
        var autoMerged = 0
        var maxRevision = cursor

        for row in rows {
            let result = try await applyWageSnapshotRow(row, storeActor: storeActor)
            if result == .conflict { newConflicts += 1 }
            if result == .autoMerged { autoMerged += 1 }
            if row.revision > maxRevision {
                maxRevision = row.revision
            }
        }

        try await storeActor.save()

        return PagePullResult(
            rowsProcessed: rows.count,
            maxRevision: maxRevision,
            newConflicts: newConflicts,
            autoMerged: autoMerged,
            hasMore: rows.count == pageSize
        )
    }

    private func applyWageSnapshotRow(_ serverRow: SyncWageSnapshotRow, storeActor: LocalStoreActor) async throws -> ApplyResult {
        let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()
        let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

        if let existing = try await storeActor.getWageSnapshot(id: serverRow.id) {
            return try await applyWageSnapshotToExisting(
                existing: existing,
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                serverDeletedAt: serverDeletedAt,
                storeActor: storeActor
            )
        } else {
            try await insertNewWageSnapshot(
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                serverDeletedAt: serverDeletedAt,
                storeActor: storeActor
            )
            return .inserted
        }
    }

    private func applyWageSnapshotToExisting(
        existing: LocalWageSnapshot,
        serverRow: SyncWageSnapshotRow,
        serverUpdatedAt: Date,
        serverDeletedAt: Date?,
        storeActor: LocalStoreActor
    ) async throws -> ApplyResult {
        let serverSnapshot = WageSnapshotServerSnapshot.from(
            row: serverRow.toWageSnapshot(),
            updatedAt: serverUpdatedAt,
            revision: serverRow.revision,
            deletedAt: serverDeletedAt
        )

        switch existing.syncStatus {
        case .clean:
            await storeActor.updateWageSnapshotFromServer(
                id: serverRow.id,
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                serverRevision: serverRow.revision,
                serverDeletedAt: serverDeletedAt,
                snapshot: serverSnapshot
            )
            return .updated

        case .dirty, .pendingDelete:
            if serverRow.revision == existing.serverRevision {
                return .noChange
            }

            guard let lastSnapshot = WageSnapshotServerSnapshot.decode(from: existing.lastSyncedSnapshot) else {
                await storeActor.markWageSnapshotConflict(id: serverRow.id, serverSnapshot: serverSnapshot)
                return .conflict
            }

            let serverChangedFields = serverSnapshot.changedFields(from: lastSnapshot)
            let localDirtyFields = existing.dirtyFieldKeys
            let conflictingFields = serverChangedFields.intersection(Set(localDirtyFields.map { convertToWageSnapshotField($0) }))

            if conflictingFields.isEmpty {
                await storeActor.autoMergeWageSnapshot(
                    id: serverRow.id,
                    serverRow: serverRow,
                    serverUpdatedAt: serverUpdatedAt,
                    serverRevision: serverRow.revision,
                    serverDeletedAt: serverDeletedAt,
                    newSnapshot: serverSnapshot,
                    localDirtyFields: localDirtyFields
                )
                return .autoMerged
            } else {
                await storeActor.markWageSnapshotConflict(id: serverRow.id, serverSnapshot: serverSnapshot)
                return .conflict
            }

        case .conflict:
            await storeActor.updateWageSnapshotConflictSnapshot(id: serverRow.id, serverSnapshot: serverSnapshot)
            return .noChange
        }
    }

    private func insertNewWageSnapshot(
        serverRow: SyncWageSnapshotRow,
        serverUpdatedAt: Date,
        serverDeletedAt: Date?,
        storeActor: LocalStoreActor
    ) async throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        let fromDate = serverRow.from_date.flatMap { dateFormatter.date(from: $0) }

        let snapshot = WageSnapshotServerSnapshot.from(
            row: serverRow.toWageSnapshot(),
            updatedAt: serverUpdatedAt,
            revision: serverRow.revision,
            deletedAt: serverDeletedAt
        )

        let localSnapshot = LocalWageSnapshot(
            id: serverRow.id,
            userId: serverRow.user_id,
            fromDate: fromDate,
            hourlyWage: serverRow.hourly_wage,
            wageLevel: serverRow.wage_level,
            supplements: (try? canonicalJSONEncoder.encode(serverRow.supplements)) ?? Data(),
            taxEnabled: serverRow.tax_enabled,
            taxPercentage: serverRow.tax_percentage,
            breakEnabled: serverRow.break_enabled,
            breakMethod: serverRow.break_method,
            breakThresholdHours: serverRow.break_threshold_hours,
            breakDeductionMinutes: serverRow.break_deduction_minutes,
            serverUpdatedAt: serverUpdatedAt,
            serverRevision: serverRow.revision,
            serverDeletedAt: serverDeletedAt,
            syncStatus: .clean,
            dirtyFields: LocalWageSnapshot.emptyDirtyFields(),
            lastSyncedSnapshot: snapshot.encoded(),
            localUpdatedAt: Date(),
            conflictServerSnapshot: nil
        )

        try await storeActor.upsertWageSnapshot(localSnapshot)
    }

    private func convertToWageSnapshotField(_ field: WageSnapshotField) -> WageSnapshotField {
        field
    }

    // MARK: - User Settings Pull

    private func pullUserSettingsPage(userId: String, cursor: Int64) async throws -> PagePullResult {
        let rows: [SyncUserSettingsRow] = try await supabase
            .from("user_settings")
            .select()
            .eq("user_id", value: userId)
            .gt("revision", value: cursor)
            .order("revision", ascending: true)
            .limit(pageSize)
            .execute()
            .value

        if rows.isEmpty {
            return PagePullResult(rowsProcessed: 0, maxRevision: cursor, newConflicts: 0, autoMerged: 0, hasMore: false)
        }

        let storeActor = LocalStore.shared.storeActor
        var newConflicts = 0
        var autoMerged = 0
        var maxRevision = cursor

        for row in rows {
            let result = try await applyUserSettingsRow(row, storeActor: storeActor)
            if result == .conflict { newConflicts += 1 }
            if result == .autoMerged { autoMerged += 1 }
            if row.revision > maxRevision {
                maxRevision = row.revision
            }
        }

        try await storeActor.save()

        return PagePullResult(
            rowsProcessed: rows.count,
            maxRevision: maxRevision,
            newConflicts: newConflicts,
            autoMerged: autoMerged,
            hasMore: rows.count == pageSize
        )
    }

    private func applyUserSettingsRow(_ serverRow: SyncUserSettingsRow, storeActor: LocalStoreActor) async throws -> ApplyResult {
        let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()

        if let existing = try await storeActor.getUserSettings(userId: serverRow.user_id) {
            return try await applyUserSettingsToExisting(
                existing: existing,
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                storeActor: storeActor
            )
        } else {
            try await insertNewUserSettings(
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                storeActor: storeActor
            )
            return .inserted
        }
    }

    private func applyUserSettingsToExisting(
        existing: LocalUserSettings,
        serverRow: SyncUserSettingsRow,
        serverUpdatedAt: Date,
        storeActor: LocalStoreActor
    ) async throws -> ApplyResult {
        let serverSnapshot = UserSettingsServerSnapshot.from(
            row: serverRow.toUserSettings(),
            updatedAt: serverUpdatedAt,
            revision: serverRow.revision
        )

        switch existing.syncStatus {
        case .clean:
            await storeActor.updateUserSettingsFromServer(
                userId: serverRow.user_id,
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                serverRevision: serverRow.revision,
                snapshot: serverSnapshot
            )
            return .updated

        case .dirty:
            if serverRow.revision == existing.serverRevision {
                return .noChange
            }

            guard let lastSnapshot = UserSettingsServerSnapshot.decode(from: existing.lastSyncedSnapshot) else {
                await storeActor.markUserSettingsConflict(userId: serverRow.user_id, serverSnapshot: serverSnapshot)
                return .conflict
            }

            let serverChangedFields = serverSnapshot.changedFields(from: lastSnapshot)
            let localDirtyFields = existing.dirtyFieldKeys
            let conflictingFields = serverChangedFields.intersection(Set(localDirtyFields.map { convertToUserSettingsField($0) }))

            if conflictingFields.isEmpty {
                await storeActor.autoMergeUserSettings(
                    userId: serverRow.user_id,
                    serverRow: serverRow,
                    serverUpdatedAt: serverUpdatedAt,
                    serverRevision: serverRow.revision,
                    newSnapshot: serverSnapshot,
                    localDirtyFields: localDirtyFields
                )
                return .autoMerged
            } else {
                await storeActor.markUserSettingsConflict(userId: serverRow.user_id, serverSnapshot: serverSnapshot)
                return .conflict
            }

        case .pendingDelete, .conflict:
            // Settings don't have pendingDelete, treat as conflict
            await storeActor.updateUserSettingsConflictSnapshot(userId: serverRow.user_id, serverSnapshot: serverSnapshot)
            return .noChange
        }
    }

    private func insertNewUserSettings(
        serverRow: SyncUserSettingsRow,
        serverUpdatedAt: Date,
        storeActor: LocalStoreActor
    ) async throws {
        let dateFormatter = ISO8601DateFormatter()

        let lastActive = serverRow.last_active.flatMap { dateFormatter.date(from: $0) }
        let createdAt = serverRow.created_at.flatMap { dateFormatter.date(from: $0) }

        let snapshot = UserSettingsServerSnapshot.from(
            row: serverRow.toUserSettings(),
            updatedAt: serverUpdatedAt,
            revision: serverRow.revision
        )

        let localSettings = LocalUserSettings(
            userId: serverRow.user_id,
            monthlyGoal: serverRow.monthly_goal,
            defaultShiftsView: serverRow.default_shifts_view,
            profilePictureUrl: serverRow.profile_picture_url,
            payrollDay: serverRow.payroll_day,
            theme: serverRow.theme,
            halfTaxMonth: serverRow.half_tax_month,
            currency: serverRow.currency,
            lastActive: lastActive,
            createdAt: createdAt,
            serverUpdatedAt: serverUpdatedAt,
            serverRevision: serverRow.revision,
            syncStatus: .clean,
            dirtyFields: LocalUserSettings.emptyDirtyFields(),
            lastSyncedSnapshot: snapshot.encoded(),
            localUpdatedAt: Date(),
            conflictServerSnapshot: nil
        )

        try await storeActor.upsertUserSettings(localSettings)
    }

    private func convertToUserSettingsField(_ field: UserSettingsField) -> UserSettingsField {
        field
    }

    // MARK: - Helpers

    private enum ApplyResult {
        case inserted
        case updated
        case noChange
        case autoMerged
        case conflict
    }

    /// Parse ISO8601 date string to Date
    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: string) {
            return date
        }

        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
