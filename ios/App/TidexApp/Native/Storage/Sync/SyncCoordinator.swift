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
                pushResults: [],
                totalRowsProcessed: 0,
                totalRowsPushed: 0,
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
                    pushResults: [],
                    totalRowsProcessed: 0,
                    totalRowsPushed: 0,
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

            // Phase 1: Pull all tables (get latest server state)
            var tableResults: [TablePullResult] = []

            for table in SyncTable.allCases {
                let result = try await pullTable(table, userId: userId, syncState: syncState)
                tableResults.append(result)
            }

            // Phase 2: Push dirty records to server
            var pushResults: [TablePushResult] = []

            for table in SyncTable.allCases {
                let result = try await pushTable(table, userId: userId)
                pushResults.append(result)
            }

            // Calculate totals
            let totalRows = tableResults.reduce(0) { $0 + $1.rowsProcessed }
            let totalPushed = pushResults.reduce(0) { $0 + $1.rowsPushed }
            let pullConflicts = tableResults.reduce(0) { $0 + $1.newConflicts }
            let pushConflicts = pushResults.reduce(0) { $0 + $1.newConflicts }
            let totalConflicts = pullConflicts + pushConflicts
            let totalAutoMerged = tableResults.reduce(0) { $0 + $1.autoMerged }
            let totalRebased = pushResults.reduce(0) { $0 + $1.rebased }
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

            logger.info("Sync completed: pulled \(totalRows), pushed \(totalPushed), \(totalConflicts) conflicts, \(totalAutoMerged) auto-merged, \(totalRebased) rebased in \(String(format: "%.2f", duration))s")

            // Update widget storage with latest shift data
            NativeWidgetStorage.updateWidgetStorage(for: userId)

            syncInProgress = false
            isSyncing = false

            return SyncResult(
                success: true,
                tableResults: tableResults,
                pushResults: pushResults,
                totalRowsProcessed: totalRows,
                totalRowsPushed: totalPushed,
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
                pushResults: [],
                totalRowsProcessed: 0,
                totalRowsPushed: 0,
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
        // Note: Convert Int64 to Int for PostgrestFilterValue conformance
        let rows: [SyncShiftRow] = try await supabase
            .from("user_shifts")
            .select()
            .eq("user_id", value: userId)
            .gt("revision", value: Int(cursor))
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
        // Note: Convert Int64 to Int for PostgrestFilterValue conformance
        let rows: [SyncRecurringShiftRow] = try await supabase
            .from("recurring_shifts")
            .select()
            .eq("user_id", value: userId)
            .gt("revision", value: Int(cursor))
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
        // Note: Convert Int64 to Int for PostgrestFilterValue conformance
        let rows: [SyncWageSnapshotRow] = try await supabase
            .from("wage_snapshots")
            .select()
            .eq("user_id", value: userId)
            .gt("revision", value: Int(cursor))
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
        // Note: Convert Int64 to Int for PostgrestFilterValue conformance
        let rows: [SyncUserSettingsRow] = try await supabase
            .from("user_settings")
            .select()
            .eq("user_id", value: userId)
            .gt("revision", value: Int(cursor))
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

    // MARK: - Push Implementation

    /// Push dirty records for a single table
    private func pushTable(_ table: SyncTable, userId: String) async throws -> TablePushResult {
        logger.debug("Pushing \(table.displayName)")

        switch table {
        case .userShifts:
            return try await pushUserShifts(userId: userId)
        case .recurringShifts:
            return try await pushRecurringShifts(userId: userId)
        case .wageSnapshots:
            return try await pushWageSnapshots(userId: userId)
        case .userSettings:
            return try await pushUserSettings(userId: userId)
        }
    }

    // MARK: - User Shifts Push

    private func pushUserShifts(userId: String) async throws -> TablePushResult {
        let storeActor = LocalStore.shared.storeActor
        let dirtyShifts = try await storeActor.getDirtyUserShifts(userId: userId)

        if dirtyShifts.isEmpty {
            return TablePushResult(table: .userShifts, rowsPushed: 0, newConflicts: 0, rebased: 0)
        }

        var rowsPushed = 0
        var newConflicts = 0
        var rebased = 0

        for shift in dirtyShifts {
            let result = try await pushUserShift(shift, userId: userId, storeActor: storeActor, isRetry: false)
            switch result {
            case .success, .deleted:
                rowsPushed += 1
            case .conflict:
                newConflicts += 1
            case .rebased:
                rebased += 1
                rowsPushed += 1
            case .noChange:
                break
            }
        }

        try await storeActor.save()
        return TablePushResult(table: .userShifts, rowsPushed: rowsPushed, newConflicts: newConflicts, rebased: rebased)
    }

    private func pushUserShift(
        _ shift: LocalUserShift,
        userId: String,
        storeActor: LocalStoreActor,
        isRetry: Bool
    ) async throws -> PushResult {
        let shiftId = shift.id

        if shift.syncStatus == .pendingDelete {
            // Soft delete: UPDATE deleted_at = now()
            return try await pushUserShiftDelete(shift, userId: userId, storeActor: storeActor)
        }

        // Build update patch using only dirty fields
        let dirtyFields = shift.dirtyFieldKeys
        if dirtyFields.isEmpty {
            // No fields dirty, mark as clean
            await storeActor.markShiftClean(id: shiftId)
            return .noChange
        }

        // Build partial update
        var updateData: [String: AnyJSON] = [:]
        if dirtyFields.contains(.shiftDate) {
            updateData["shift_date"] = .string(shift.shiftDateString)
        }
        if dirtyFields.contains(.startTime) {
            updateData["start_time"] = .string(shift.startTime)
        }
        if dirtyFields.contains(.endTime) {
            updateData["end_time"] = .string(shift.endTime)
        }
        if dirtyFields.contains(.customSupplements) {
            if let supplements = shift.decodedCustomSupplements {
                if let jsonData = try? canonicalJSONEncoder.encode(supplements),
                   let decoded = try? AnyJSON.decoder.decode(AnyJSON.self, from: jsonData) {
                    updateData["custom_supplements"] = decoded
                }
            } else {
                updateData["custom_supplements"] = .null
            }
        }

        // Optimistic concurrency: filter by revision
        // Note: Convert Int64 to Int for PostgrestFilterValue conformance
        let serverRevision = Int(shift.serverRevision)

        do {
            // UPDATE with revision filter, returning the updated row
            let returnedRows: [SyncShiftRow] = try await supabase
                .from("user_shifts")
                .update(updateData)
                .eq("id", value: shiftId)
                .eq("user_id", value: userId)
                .eq("revision", value: serverRevision)
                .is("deleted_at", value: nil)
                .select()
                .execute()
                .value

            if let returnedRow = returnedRows.first {
                // Success - update local with canonical server values
                let serverUpdatedAt = parseISO8601(returnedRow.updated_at) ?? Date()
                let serverSnapshot = UserShiftServerSnapshot.from(
                    shiftDate: returnedRow.shift_date,
                    startTime: returnedRow.start_time,
                    endTime: returnedRow.end_time,
                    customSupplements: returnedRow.custom_supplements,
                    updatedAt: serverUpdatedAt,
                    revision: returnedRow.revision,
                    deletedAt: nil
                )

                await storeActor.markShiftPushed(
                    id: shiftId,
                    serverRow: returnedRow,
                    serverUpdatedAt: serverUpdatedAt,
                    serverRevision: returnedRow.revision,
                    snapshot: serverSnapshot
                )

                logger.debug("Pushed shift \(shiftId.prefix(8))")
                return .success
            } else {
                // Row wasn't updated - revision mismatch
                return try await handleShiftPushConflict(
                    shift: shift,
                    userId: userId,
                    storeActor: storeActor,
                    isRetry: isRetry
                )
            }
        } catch {
            logger.error("Push shift failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func pushUserShiftDelete(
        _ shift: LocalUserShift,
        userId: String,
        storeActor: LocalStoreActor
    ) async throws -> PushResult {
        let shiftId = shift.id
        // Note: Convert Int64 to Int for PostgrestFilterValue conformance
        let serverRevision = Int(shift.serverRevision)

        // UPDATE deleted_at = now() with revision filter
        let returnedRows: [SyncShiftRow] = try await supabase
            .from("user_shifts")
            .update(["deleted_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))])
            .eq("id", value: shiftId)
            .eq("user_id", value: userId)
            .eq("revision", value: serverRevision)
            .is("deleted_at", value: nil)
            .select()
            .execute()
            .value

        if let returnedRow = returnedRows.first {
            // Success - mark as deleted locally
            let serverUpdatedAt = parseISO8601(returnedRow.updated_at) ?? Date()
            let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }

            await storeActor.markShiftDeleted(
                id: shiftId,
                serverUpdatedAt: serverUpdatedAt,
                serverRevision: returnedRow.revision,
                serverDeletedAt: serverDeletedAt
            )

            logger.debug("Deleted shift \(shiftId.prefix(8))")
            return .deleted
        } else {
            // Conflict - fetch current server state
            let serverRows: [SyncShiftRow] = try await supabase
                .from("user_shifts")
                .select()
                .eq("id", value: shiftId)
                .execute()
                .value

            if let serverRow = serverRows.first {
                let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()
                let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

                if serverDeletedAt != nil {
                    // Already deleted on server, just clean up local
                    await storeActor.markShiftDeleted(
                        id: shiftId,
                        serverUpdatedAt: serverUpdatedAt,
                        serverRevision: serverRow.revision,
                        serverDeletedAt: serverDeletedAt
                    )
                    return .deleted
                }

                // Mark conflict
                let serverSnapshot = UserShiftServerSnapshot.from(
                    shiftDate: serverRow.shift_date,
                    startTime: serverRow.start_time,
                    endTime: serverRow.end_time,
                    customSupplements: serverRow.custom_supplements,
                    updatedAt: serverUpdatedAt,
                    revision: serverRow.revision,
                    deletedAt: serverDeletedAt
                )
                await storeActor.markShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
            }
            return .conflict
        }
    }

    private func handleShiftPushConflict(
        shift: LocalUserShift,
        userId: String,
        storeActor: LocalStoreActor,
        isRetry: Bool
    ) async throws -> PushResult {
        let shiftId = shift.id

        // Fetch current server state
        let serverRows: [SyncShiftRow] = try await supabase
            .from("user_shifts")
            .select()
            .eq("id", value: shiftId)
            .execute()
            .value

        guard let serverRow = serverRows.first else {
            // Row was deleted on server
            logger.debug("Shift \(shiftId.prefix(8)) was deleted on server")
            await storeActor.markShiftConflict(id: shiftId, serverSnapshot: nil)
            return .conflict
        }

        let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()
        let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

        if serverDeletedAt != nil {
            // Server soft-deleted this row
            let serverSnapshot = UserShiftServerSnapshot.from(
                shiftDate: serverRow.shift_date,
                startTime: serverRow.start_time,
                endTime: serverRow.end_time,
                customSupplements: serverRow.custom_supplements,
                updatedAt: serverUpdatedAt,
                revision: serverRow.revision,
                deletedAt: serverDeletedAt
            )
            await storeActor.markShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
            return .conflict
        }

        // Try field-level merge
        guard let lastSnapshot = UserShiftServerSnapshot.decode(from: shift.lastSyncedSnapshot) else {
            // Cannot decode snapshot, mark conflict
            let serverSnapshot = UserShiftServerSnapshot.from(
                shiftDate: serverRow.shift_date,
                startTime: serverRow.start_time,
                endTime: serverRow.end_time,
                customSupplements: serverRow.custom_supplements,
                updatedAt: serverUpdatedAt,
                revision: serverRow.revision,
                deletedAt: serverDeletedAt
            )
            await storeActor.markShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
            return .conflict
        }

        let newServerSnapshot = UserShiftServerSnapshot.from(
            shiftDate: serverRow.shift_date,
            startTime: serverRow.start_time,
            endTime: serverRow.end_time,
            customSupplements: serverRow.custom_supplements,
            updatedAt: serverUpdatedAt,
            revision: serverRow.revision,
            deletedAt: serverDeletedAt
        )

        let serverChangedFields = newServerSnapshot.changedFields(from: lastSnapshot)
        let localDirtyFields = shift.dirtyFieldKeys
        let conflictingFields = serverChangedFields.intersection(Set(localDirtyFields.map { convertToUserShiftField($0) }))

        if conflictingFields.isEmpty && !isRetry {
            // Auto-merge possible: rebase and retry once
            await storeActor.rebaseShift(
                id: shiftId,
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                serverRevision: serverRow.revision,
                serverDeletedAt: serverDeletedAt,
                newSnapshot: newServerSnapshot,
                localDirtyFields: localDirtyFields
            )

            // Reload and retry
            if let rebasedShift = try await storeActor.getUserShift(id: shiftId) {
                let retryResult = try await pushUserShift(rebasedShift, userId: userId, storeActor: storeActor, isRetry: true)
                if retryResult == .success {
                    return .rebased
                }
                return retryResult
            }
            return .conflict
        } else {
            // Conflict - overlapping fields or retry failed
            await storeActor.markShiftConflict(id: shiftId, serverSnapshot: newServerSnapshot)
            return .conflict
        }
    }

    // MARK: - Recurring Shifts Push

    private func pushRecurringShifts(userId: String) async throws -> TablePushResult {
        let storeActor = LocalStore.shared.storeActor
        let dirtyShifts = try await storeActor.getDirtyRecurringShifts(userId: userId)

        if dirtyShifts.isEmpty {
            return TablePushResult(table: .recurringShifts, rowsPushed: 0, newConflicts: 0, rebased: 0)
        }

        var rowsPushed = 0
        var newConflicts = 0
        var rebased = 0

        for shift in dirtyShifts {
            let result = try await pushRecurringShift(shift, userId: userId, storeActor: storeActor, isRetry: false)
            switch result {
            case .success, .deleted:
                rowsPushed += 1
            case .conflict:
                newConflicts += 1
            case .rebased:
                rebased += 1
                rowsPushed += 1
            case .noChange:
                break
            }
        }

        try await storeActor.save()
        return TablePushResult(table: .recurringShifts, rowsPushed: rowsPushed, newConflicts: newConflicts, rebased: rebased)
    }

    private func pushRecurringShift(
        _ shift: LocalRecurringShift,
        userId: String,
        storeActor: LocalStoreActor,
        isRetry: Bool
    ) async throws -> PushResult {
        let shiftId = shift.id

        if shift.syncStatus == .pendingDelete {
            return try await pushRecurringShiftDelete(shift, userId: userId, storeActor: storeActor)
        }

        let dirtyFields = shift.dirtyFieldKeys
        if dirtyFields.isEmpty {
            await storeActor.markRecurringShiftClean(id: shiftId)
            return .noChange
        }

        // Build partial update
        var updateData: [String: AnyJSON] = [:]
        if dirtyFields.contains(.startTime) {
            updateData["start_time"] = .string(shift.startTime)
        }
        if dirtyFields.contains(.endTime) {
            updateData["end_time"] = .string(shift.endTime)
        }
        if dirtyFields.contains(.repeatIntervalWeeks) {
            updateData["repeat_interval_weeks"] = .integer(shift.repeatIntervalWeeks)
        }
        if dirtyFields.contains(.selectedDays) {
            if let jsonData = shift.selectedDays.isEmpty ? nil : shift.selectedDays,
               let decoded = try? AnyJSON.decoder.decode(AnyJSON.self, from: jsonData) {
                updateData["selected_days"] = decoded
            }
        }
        if dirtyFields.contains(.endCondition) {
            if let data = shift.endCondition,
               let decoded = try? AnyJSON.decoder.decode(AnyJSON.self, from: data) {
                updateData["end_condition"] = decoded
            } else {
                updateData["end_condition"] = .null
            }
        }
        if dirtyFields.contains(.exclusions) {
            if let data = shift.exclusions,
               let decoded = try? AnyJSON.decoder.decode(AnyJSON.self, from: data) {
                updateData["exclusions"] = decoded
            } else {
                updateData["exclusions"] = .null
            }
        }
        if dirtyFields.contains(.dateSpecificSupplements) {
            if let data = shift.dateSpecificSupplements,
               let decoded = try? AnyJSON.decoder.decode(AnyJSON.self, from: data) {
                updateData["date_specific_supplements"] = decoded
            } else {
                updateData["date_specific_supplements"] = .null
            }
        }

        // Note: Convert Int64 to Int for PostgrestFilterValue conformance
        let serverRevision = Int(shift.serverRevision)

        do {
            let returnedRows: [SyncRecurringShiftRow] = try await supabase
                .from("recurring_shifts")
                .update(updateData)
                .eq("id", value: shiftId)
                .eq("user_id", value: userId)
                .eq("revision", value: serverRevision)
                .is("deleted_at", value: nil)
                .select()
                .execute()
                .value

            if let returnedRow = returnedRows.first {
                let serverUpdatedAt = parseISO8601(returnedRow.updated_at) ?? Date()
                let serverSnapshot = RecurringShiftServerSnapshot.from(
                    row: returnedRow.toRecurringShiftRow(),
                    updatedAt: serverUpdatedAt,
                    revision: returnedRow.revision,
                    deletedAt: nil
                )

                await storeActor.markRecurringShiftPushed(
                    id: shiftId,
                    serverRow: returnedRow,
                    serverUpdatedAt: serverUpdatedAt,
                    serverRevision: returnedRow.revision,
                    snapshot: serverSnapshot
                )

                logger.debug("Pushed recurring shift \(shiftId.prefix(8))")
                return .success
            } else {
                return try await handleRecurringShiftPushConflict(
                    shift: shift,
                    userId: userId,
                    storeActor: storeActor,
                    isRetry: isRetry
                )
            }
        } catch {
            logger.error("Push recurring shift failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func pushRecurringShiftDelete(
        _ shift: LocalRecurringShift,
        userId: String,
        storeActor: LocalStoreActor
    ) async throws -> PushResult {
        let shiftId = shift.id
        // Note: Convert Int64 to Int for PostgrestFilterValue conformance
        let serverRevision = Int(shift.serverRevision)

        let returnedRows: [SyncRecurringShiftRow] = try await supabase
            .from("recurring_shifts")
            .update(["deleted_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))])
            .eq("id", value: shiftId)
            .eq("user_id", value: userId)
            .eq("revision", value: serverRevision)
            .is("deleted_at", value: nil)
            .select()
            .execute()
            .value

        if let returnedRow = returnedRows.first {
            let serverUpdatedAt = parseISO8601(returnedRow.updated_at) ?? Date()
            let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }

            await storeActor.markRecurringShiftDeleted(
                id: shiftId,
                serverUpdatedAt: serverUpdatedAt,
                serverRevision: returnedRow.revision,
                serverDeletedAt: serverDeletedAt
            )

            logger.debug("Deleted recurring shift \(shiftId.prefix(8))")
            return .deleted
        } else {
            // Fetch and check server state
            let serverRows: [SyncRecurringShiftRow] = try await supabase
                .from("recurring_shifts")
                .select()
                .eq("id", value: shiftId)
                .execute()
                .value

            if let serverRow = serverRows.first {
                let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()
                let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

                if serverDeletedAt != nil {
                    await storeActor.markRecurringShiftDeleted(
                        id: shiftId,
                        serverUpdatedAt: serverUpdatedAt,
                        serverRevision: serverRow.revision,
                        serverDeletedAt: serverDeletedAt
                    )
                    return .deleted
                }

                let serverSnapshot = RecurringShiftServerSnapshot.from(
                    row: serverRow.toRecurringShiftRow(),
                    updatedAt: serverUpdatedAt,
                    revision: serverRow.revision,
                    deletedAt: serverDeletedAt
                )
                await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
            }
            return .conflict
        }
    }

    private func handleRecurringShiftPushConflict(
        shift: LocalRecurringShift,
        userId: String,
        storeActor: LocalStoreActor,
        isRetry: Bool
    ) async throws -> PushResult {
        let shiftId = shift.id

        let serverRows: [SyncRecurringShiftRow] = try await supabase
            .from("recurring_shifts")
            .select()
            .eq("id", value: shiftId)
            .execute()
            .value

        guard let serverRow = serverRows.first else {
            logger.debug("Recurring shift \(shiftId.prefix(8)) was deleted on server")
            await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: nil)
            return .conflict
        }

        let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()
        let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

        if serverDeletedAt != nil {
            let serverSnapshot = RecurringShiftServerSnapshot.from(
                row: serverRow.toRecurringShiftRow(),
                updatedAt: serverUpdatedAt,
                revision: serverRow.revision,
                deletedAt: serverDeletedAt
            )
            await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
            return .conflict
        }

        guard let lastSnapshot = RecurringShiftServerSnapshot.decode(from: shift.lastSyncedSnapshot) else {
            let serverSnapshot = RecurringShiftServerSnapshot.from(
                row: serverRow.toRecurringShiftRow(),
                updatedAt: serverUpdatedAt,
                revision: serverRow.revision,
                deletedAt: serverDeletedAt
            )
            await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
            return .conflict
        }

        let newServerSnapshot = RecurringShiftServerSnapshot.from(
            row: serverRow.toRecurringShiftRow(),
            updatedAt: serverUpdatedAt,
            revision: serverRow.revision,
            deletedAt: serverDeletedAt
        )

        let serverChangedFields = newServerSnapshot.changedFields(from: lastSnapshot)
        let localDirtyFields = shift.dirtyFieldKeys
        let conflictingFields = serverChangedFields.intersection(Set(localDirtyFields.map { convertToRecurringShiftField($0) }))

        if conflictingFields.isEmpty && !isRetry {
            await storeActor.rebaseRecurringShift(
                id: shiftId,
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                serverRevision: serverRow.revision,
                serverDeletedAt: serverDeletedAt,
                newSnapshot: newServerSnapshot,
                localDirtyFields: localDirtyFields
            )

            if let rebasedShift = try await storeActor.getRecurringShift(id: shiftId) {
                let retryResult = try await pushRecurringShift(rebasedShift, userId: userId, storeActor: storeActor, isRetry: true)
                if retryResult == .success {
                    return .rebased
                }
                return retryResult
            }
            return .conflict
        } else {
            await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: newServerSnapshot)
            return .conflict
        }
    }

    // MARK: - Wage Snapshots Push

    private func pushWageSnapshots(userId: String) async throws -> TablePushResult {
        let storeActor = LocalStore.shared.storeActor
        let dirtySnapshots = try await storeActor.getDirtyWageSnapshots(userId: userId)

        if dirtySnapshots.isEmpty {
            return TablePushResult(table: .wageSnapshots, rowsPushed: 0, newConflicts: 0, rebased: 0)
        }

        var rowsPushed = 0
        var newConflicts = 0
        var rebased = 0

        for snapshot in dirtySnapshots {
            let result = try await pushWageSnapshot(snapshot, userId: userId, storeActor: storeActor, isRetry: false)
            switch result {
            case .success, .deleted:
                rowsPushed += 1
            case .conflict:
                newConflicts += 1
            case .rebased:
                rebased += 1
                rowsPushed += 1
            case .noChange:
                break
            }
        }

        try await storeActor.save()
        return TablePushResult(table: .wageSnapshots, rowsPushed: rowsPushed, newConflicts: newConflicts, rebased: rebased)
    }

    private func pushWageSnapshot(
        _ snapshot: LocalWageSnapshot,
        userId: String,
        storeActor: LocalStoreActor,
        isRetry: Bool
    ) async throws -> PushResult {
        let snapshotId = snapshot.id

        if snapshot.syncStatus == .pendingDelete {
            return try await pushWageSnapshotDelete(snapshot, userId: userId, storeActor: storeActor)
        }

        let dirtyFields = snapshot.dirtyFieldKeys
        if dirtyFields.isEmpty {
            await storeActor.markWageSnapshotClean(id: snapshotId)
            return .noChange
        }

        // Build partial update
        var updateData: [String: AnyJSON] = [:]
        if dirtyFields.contains(.fromDate) {
            if let fromDateString = snapshot.fromDateString {
                updateData["from_date"] = .string(fromDateString)
            } else {
                updateData["from_date"] = .null
            }
        }
        if dirtyFields.contains(.hourlyWage) {
            updateData["hourly_wage"] = .double(snapshot.hourlyWage)
        }
        if dirtyFields.contains(.wageLevel) {
            if let level = snapshot.wageLevel {
                updateData["wage_level"] = .integer(level)
            } else {
                updateData["wage_level"] = .null
            }
        }
        if dirtyFields.contains(.supplements) {
            if let decoded = try? AnyJSON.decoder.decode(AnyJSON.self, from: snapshot.supplements) {
                updateData["supplements"] = decoded
            }
        }
        if dirtyFields.contains(.taxEnabled) {
            if let enabled = snapshot.taxEnabled {
                updateData["tax_enabled"] = .bool(enabled)
            } else {
                updateData["tax_enabled"] = .null
            }
        }
        if dirtyFields.contains(.taxPercentage) {
            if let percentage = snapshot.taxPercentage {
                updateData["tax_percentage"] = .double(percentage)
            } else {
                updateData["tax_percentage"] = .null
            }
        }
        if dirtyFields.contains(.breakEnabled) {
            if let enabled = snapshot.breakEnabled {
                updateData["break_enabled"] = .bool(enabled)
            } else {
                updateData["break_enabled"] = .null
            }
        }
        if dirtyFields.contains(.breakMethod) {
            if let method = snapshot.breakMethod {
                updateData["break_method"] = .string(method)
            } else {
                updateData["break_method"] = .null
            }
        }
        if dirtyFields.contains(.breakThresholdHours) {
            if let hours = snapshot.breakThresholdHours {
                updateData["break_threshold_hours"] = .double(hours)
            } else {
                updateData["break_threshold_hours"] = .null
            }
        }
        if dirtyFields.contains(.breakDeductionMinutes) {
            if let minutes = snapshot.breakDeductionMinutes {
                updateData["break_deduction_minutes"] = .integer(minutes)
            } else {
                updateData["break_deduction_minutes"] = .null
            }
        }

        // Note: Convert Int64 to Int for PostgrestFilterValue conformance
        let serverRevision = Int(snapshot.serverRevision)

        do {
            let returnedRows: [SyncWageSnapshotRow] = try await supabase
                .from("wage_snapshots")
                .update(updateData)
                .eq("id", value: snapshotId)
                .eq("user_id", value: userId)
                .eq("revision", value: serverRevision)
                .is("deleted_at", value: nil)
                .select()
                .execute()
                .value

            if let returnedRow = returnedRows.first {
                let serverUpdatedAt = parseISO8601(returnedRow.updated_at) ?? Date()
                let serverSnapshot = WageSnapshotServerSnapshot.from(
                    row: returnedRow.toWageSnapshot(),
                    updatedAt: serverUpdatedAt,
                    revision: returnedRow.revision,
                    deletedAt: nil
                )

                await storeActor.markWageSnapshotPushed(
                    id: snapshotId,
                    serverRow: returnedRow,
                    serverUpdatedAt: serverUpdatedAt,
                    serverRevision: returnedRow.revision,
                    snapshot: serverSnapshot
                )

                logger.debug("Pushed wage snapshot \(snapshotId.prefix(8))")
                return .success
            } else {
                return try await handleWageSnapshotPushConflict(
                    snapshot: snapshot,
                    userId: userId,
                    storeActor: storeActor,
                    isRetry: isRetry
                )
            }
        } catch {
            logger.error("Push wage snapshot failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func pushWageSnapshotDelete(
        _ snapshot: LocalWageSnapshot,
        userId: String,
        storeActor: LocalStoreActor
    ) async throws -> PushResult {
        let snapshotId = snapshot.id
        // Note: Convert Int64 to Int for PostgrestFilterValue conformance
        let serverRevision = Int(snapshot.serverRevision)

        let returnedRows: [SyncWageSnapshotRow] = try await supabase
            .from("wage_snapshots")
            .update(["deleted_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))])
            .eq("id", value: snapshotId)
            .eq("user_id", value: userId)
            .eq("revision", value: serverRevision)
            .is("deleted_at", value: nil)
            .select()
            .execute()
            .value

        if let returnedRow = returnedRows.first {
            let serverUpdatedAt = parseISO8601(returnedRow.updated_at) ?? Date()
            let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }

            await storeActor.markWageSnapshotDeleted(
                id: snapshotId,
                serverUpdatedAt: serverUpdatedAt,
                serverRevision: returnedRow.revision,
                serverDeletedAt: serverDeletedAt
            )

            logger.debug("Deleted wage snapshot \(snapshotId.prefix(8))")
            return .deleted
        } else {
            let serverRows: [SyncWageSnapshotRow] = try await supabase
                .from("wage_snapshots")
                .select()
                .eq("id", value: snapshotId)
                .execute()
                .value

            if let serverRow = serverRows.first {
                let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()
                let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

                if serverDeletedAt != nil {
                    await storeActor.markWageSnapshotDeleted(
                        id: snapshotId,
                        serverUpdatedAt: serverUpdatedAt,
                        serverRevision: serverRow.revision,
                        serverDeletedAt: serverDeletedAt
                    )
                    return .deleted
                }

                let serverSnapshot = WageSnapshotServerSnapshot.from(
                    row: serverRow.toWageSnapshot(),
                    updatedAt: serverUpdatedAt,
                    revision: serverRow.revision,
                    deletedAt: serverDeletedAt
                )
                await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: serverSnapshot)
            }
            return .conflict
        }
    }

    private func handleWageSnapshotPushConflict(
        snapshot: LocalWageSnapshot,
        userId: String,
        storeActor: LocalStoreActor,
        isRetry: Bool
    ) async throws -> PushResult {
        let snapshotId = snapshot.id

        let serverRows: [SyncWageSnapshotRow] = try await supabase
            .from("wage_snapshots")
            .select()
            .eq("id", value: snapshotId)
            .execute()
            .value

        guard let serverRow = serverRows.first else {
            logger.debug("Wage snapshot \(snapshotId.prefix(8)) was deleted on server")
            await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: nil)
            return .conflict
        }

        let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()
        let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

        if serverDeletedAt != nil {
            let serverSnapshot = WageSnapshotServerSnapshot.from(
                row: serverRow.toWageSnapshot(),
                updatedAt: serverUpdatedAt,
                revision: serverRow.revision,
                deletedAt: serverDeletedAt
            )
            await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: serverSnapshot)
            return .conflict
        }

        guard let lastSnapshot = WageSnapshotServerSnapshot.decode(from: snapshot.lastSyncedSnapshot) else {
            let serverSnapshot = WageSnapshotServerSnapshot.from(
                row: serverRow.toWageSnapshot(),
                updatedAt: serverUpdatedAt,
                revision: serverRow.revision,
                deletedAt: serverDeletedAt
            )
            await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: serverSnapshot)
            return .conflict
        }

        let newServerSnapshot = WageSnapshotServerSnapshot.from(
            row: serverRow.toWageSnapshot(),
            updatedAt: serverUpdatedAt,
            revision: serverRow.revision,
            deletedAt: serverDeletedAt
        )

        let serverChangedFields = newServerSnapshot.changedFields(from: lastSnapshot)
        let localDirtyFields = snapshot.dirtyFieldKeys
        let conflictingFields = serverChangedFields.intersection(Set(localDirtyFields.map { convertToWageSnapshotField($0) }))

        if conflictingFields.isEmpty && !isRetry {
            await storeActor.rebaseWageSnapshot(
                id: snapshotId,
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                serverRevision: serverRow.revision,
                serverDeletedAt: serverDeletedAt,
                newSnapshot: newServerSnapshot,
                localDirtyFields: localDirtyFields
            )

            if let rebasedSnapshot = try await storeActor.getWageSnapshot(id: snapshotId) {
                let retryResult = try await pushWageSnapshot(rebasedSnapshot, userId: userId, storeActor: storeActor, isRetry: true)
                if retryResult == .success {
                    return .rebased
                }
                return retryResult
            }
            return .conflict
        } else {
            await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: newServerSnapshot)
            return .conflict
        }
    }

    // MARK: - User Settings Push

    private func pushUserSettings(userId: String) async throws -> TablePushResult {
        let storeActor = LocalStore.shared.storeActor
        guard let settings = try await storeActor.getDirtyUserSettings(userId: userId) else {
            return TablePushResult(table: .userSettings, rowsPushed: 0, newConflicts: 0, rebased: 0)
        }

        let result = try await pushUserSettingsRow(settings, userId: userId, storeActor: storeActor, isRetry: false)

        var rowsPushed = 0
        var newConflicts = 0
        var rebased = 0

        switch result {
        case .success:
            rowsPushed = 1
        case .conflict:
            newConflicts = 1
        case .rebased:
            rebased = 1
            rowsPushed = 1
        case .noChange, .deleted:
            break
        }

        try await storeActor.save()
        return TablePushResult(table: .userSettings, rowsPushed: rowsPushed, newConflicts: newConflicts, rebased: rebased)
    }

    private func pushUserSettingsRow(
        _ settings: LocalUserSettings,
        userId: String,
        storeActor: LocalStoreActor,
        isRetry: Bool
    ) async throws -> PushResult {
        let dirtyFields = settings.dirtyFieldKeys
        if dirtyFields.isEmpty {
            await storeActor.markUserSettingsClean(userId: userId)
            return .noChange
        }

        // Build partial update
        var updateData: [String: AnyJSON] = [:]
        if dirtyFields.contains(.monthlyGoal) {
            if let goal = settings.monthlyGoal {
                updateData["monthly_goal"] = .integer(goal)
            } else {
                updateData["monthly_goal"] = .null
            }
        }
        if dirtyFields.contains(.defaultShiftsView) {
            if let view = settings.defaultShiftsView {
                updateData["default_shifts_view"] = .string(view)
            } else {
                updateData["default_shifts_view"] = .null
            }
        }
        if dirtyFields.contains(.profilePictureUrl) {
            if let url = settings.profilePictureUrl {
                updateData["profile_picture_url"] = .string(url)
            } else {
                updateData["profile_picture_url"] = .null
            }
        }
        if dirtyFields.contains(.payrollDay) {
            if let day = settings.payrollDay {
                updateData["payroll_day"] = .integer(day)
            } else {
                updateData["payroll_day"] = .null
            }
        }
        if dirtyFields.contains(.theme) {
            updateData["theme"] = .string(settings.theme)
        }
        if dirtyFields.contains(.halfTaxMonth) {
            if let month = settings.halfTaxMonth {
                updateData["half_tax_month"] = .integer(month)
            } else {
                updateData["half_tax_month"] = .null
            }
        }
        if dirtyFields.contains(.currency) {
            if let currency = settings.currency {
                updateData["currency"] = .string(currency)
            } else {
                updateData["currency"] = .null
            }
        }
        if dirtyFields.contains(.lastActive) {
            if let lastActive = settings.lastActive {
                updateData["last_active"] = .string(ISO8601DateFormatter().string(from: lastActive))
            } else {
                updateData["last_active"] = .null
            }
        }

        // Note: Convert Int64 to Int for PostgrestFilterValue conformance
        let serverRevision = Int(settings.serverRevision)

        do {
            let returnedRows: [SyncUserSettingsRow] = try await supabase
                .from("user_settings")
                .update(updateData)
                .eq("user_id", value: userId)
                .eq("revision", value: serverRevision)
                .select()
                .execute()
                .value

            if let returnedRow = returnedRows.first {
                let serverUpdatedAt = parseISO8601(returnedRow.updated_at) ?? Date()
                let serverSnapshot = UserSettingsServerSnapshot.from(
                    row: returnedRow.toUserSettings(),
                    updatedAt: serverUpdatedAt,
                    revision: returnedRow.revision
                )

                await storeActor.markUserSettingsPushed(
                    userId: userId,
                    serverRow: returnedRow,
                    serverUpdatedAt: serverUpdatedAt,
                    serverRevision: returnedRow.revision,
                    snapshot: serverSnapshot
                )

                logger.debug("Pushed user settings for \(userId.prefix(8))")
                return .success
            } else {
                return try await handleUserSettingsPushConflict(
                    settings: settings,
                    userId: userId,
                    storeActor: storeActor,
                    isRetry: isRetry
                )
            }
        } catch {
            logger.error("Push user settings failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func handleUserSettingsPushConflict(
        settings: LocalUserSettings,
        userId: String,
        storeActor: LocalStoreActor,
        isRetry: Bool
    ) async throws -> PushResult {
        let serverRows: [SyncUserSettingsRow] = try await supabase
            .from("user_settings")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

        guard let serverRow = serverRows.first else {
            logger.debug("User settings for \(userId.prefix(8)) were deleted on server")
            await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: nil)
            return .conflict
        }

        let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()

        guard let lastSnapshot = UserSettingsServerSnapshot.decode(from: settings.lastSyncedSnapshot) else {
            let serverSnapshot = UserSettingsServerSnapshot.from(
                row: serverRow.toUserSettings(),
                updatedAt: serverUpdatedAt,
                revision: serverRow.revision
            )
            await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: serverSnapshot)
            return .conflict
        }

        let newServerSnapshot = UserSettingsServerSnapshot.from(
            row: serverRow.toUserSettings(),
            updatedAt: serverUpdatedAt,
            revision: serverRow.revision
        )

        let serverChangedFields = newServerSnapshot.changedFields(from: lastSnapshot)
        let localDirtyFields = settings.dirtyFieldKeys
        let conflictingFields = serverChangedFields.intersection(Set(localDirtyFields.map { convertToUserSettingsField($0) }))

        if conflictingFields.isEmpty && !isRetry {
            await storeActor.rebaseUserSettings(
                userId: userId,
                serverRow: serverRow,
                serverUpdatedAt: serverUpdatedAt,
                serverRevision: serverRow.revision,
                newSnapshot: newServerSnapshot,
                localDirtyFields: localDirtyFields
            )

            if let rebasedSettings = try await storeActor.getUserSettings(userId: userId) {
                let retryResult = try await pushUserSettingsRow(rebasedSettings, userId: userId, storeActor: storeActor, isRetry: true)
                if retryResult == .success {
                    return .rebased
                }
                return retryResult
            }
            return .conflict
        } else {
            await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: newServerSnapshot)
            return .conflict
        }
    }

    // MARK: - Conflict Resolution API

    /// Resolve a conflict for a user shift
    func resolveShiftConflict(shiftId: String, resolution: ConflictResolution, userId: String) async throws {
        let storeActor = LocalStore.shared.storeActor

        guard let shift = try await storeActor.getUserShift(id: shiftId) else {
            throw SyncError.notFound(table: .userShifts, id: shiftId)
        }

        guard shift.syncStatus == .conflict else {
            throw SyncError.notInConflict(table: .userShifts, id: shiftId)
        }

        switch resolution {
        case .keepServer:
            // Overwrite local with server snapshot
            guard let serverSnapshotData = shift.conflictServerSnapshot,
                  let serverSnapshot = UserShiftServerSnapshot.decode(from: serverSnapshotData) else {
                throw SyncError.missingConflictSnapshot(table: .userShifts, id: shiftId)
            }

            await storeActor.resolveShiftConflictKeepServer(id: shiftId, serverSnapshot: serverSnapshot)

        case .keepLocal:
            // Update serverRevision to server's value, keep local values, set dirty, attempt push
            guard let serverSnapshotData = shift.conflictServerSnapshot,
                  let serverSnapshot = UserShiftServerSnapshot.decode(from: serverSnapshotData) else {
                throw SyncError.missingConflictSnapshot(table: .userShifts, id: shiftId)
            }

            await storeActor.resolveShiftConflictKeepLocal(id: shiftId, serverRevision: serverSnapshot.revision)

            // Attempt to push
            if let updatedShift = try await storeActor.getUserShift(id: shiftId) {
                _ = try await pushUserShift(updatedShift, userId: userId, storeActor: storeActor, isRetry: false)
                try await storeActor.save()
            }
        }

        // Update conflict count
        conflictCount = try await storeActor.countConflicts(userId: userId)
    }

    /// Resolve a conflict for a recurring shift
    func resolveRecurringShiftConflict(shiftId: String, resolution: ConflictResolution, userId: String) async throws {
        let storeActor = LocalStore.shared.storeActor

        guard let shift = try await storeActor.getRecurringShift(id: shiftId) else {
            throw SyncError.notFound(table: .recurringShifts, id: shiftId)
        }

        guard shift.syncStatus == .conflict else {
            throw SyncError.notInConflict(table: .recurringShifts, id: shiftId)
        }

        switch resolution {
        case .keepServer:
            guard let serverSnapshotData = shift.conflictServerSnapshot,
                  let serverSnapshot = RecurringShiftServerSnapshot.decode(from: serverSnapshotData) else {
                throw SyncError.missingConflictSnapshot(table: .recurringShifts, id: shiftId)
            }

            await storeActor.resolveRecurringShiftConflictKeepServer(id: shiftId, serverSnapshot: serverSnapshot)

        case .keepLocal:
            guard let serverSnapshotData = shift.conflictServerSnapshot,
                  let serverSnapshot = RecurringShiftServerSnapshot.decode(from: serverSnapshotData) else {
                throw SyncError.missingConflictSnapshot(table: .recurringShifts, id: shiftId)
            }

            await storeActor.resolveRecurringShiftConflictKeepLocal(id: shiftId, serverRevision: serverSnapshot.revision)

            if let updatedShift = try await storeActor.getRecurringShift(id: shiftId) {
                _ = try await pushRecurringShift(updatedShift, userId: userId, storeActor: storeActor, isRetry: false)
                try await storeActor.save()
            }
        }

        conflictCount = try await storeActor.countConflicts(userId: userId)
    }

    /// Resolve a conflict for a wage snapshot
    func resolveWageSnapshotConflict(snapshotId: String, resolution: ConflictResolution, userId: String) async throws {
        let storeActor = LocalStore.shared.storeActor

        guard let snapshot = try await storeActor.getWageSnapshot(id: snapshotId) else {
            throw SyncError.notFound(table: .wageSnapshots, id: snapshotId)
        }

        guard snapshot.syncStatus == .conflict else {
            throw SyncError.notInConflict(table: .wageSnapshots, id: snapshotId)
        }

        switch resolution {
        case .keepServer:
            guard let serverSnapshotData = snapshot.conflictServerSnapshot,
                  let serverSnapshot = WageSnapshotServerSnapshot.decode(from: serverSnapshotData) else {
                throw SyncError.missingConflictSnapshot(table: .wageSnapshots, id: snapshotId)
            }

            await storeActor.resolveWageSnapshotConflictKeepServer(id: snapshotId, serverSnapshot: serverSnapshot)

        case .keepLocal:
            guard let serverSnapshotData = snapshot.conflictServerSnapshot,
                  let serverSnapshot = WageSnapshotServerSnapshot.decode(from: serverSnapshotData) else {
                throw SyncError.missingConflictSnapshot(table: .wageSnapshots, id: snapshotId)
            }

            await storeActor.resolveWageSnapshotConflictKeepLocal(id: snapshotId, serverRevision: serverSnapshot.revision)

            if let updatedSnapshot = try await storeActor.getWageSnapshot(id: snapshotId) {
                _ = try await pushWageSnapshot(updatedSnapshot, userId: userId, storeActor: storeActor, isRetry: false)
                try await storeActor.save()
            }
        }

        conflictCount = try await storeActor.countConflicts(userId: userId)
    }

    /// Resolve a conflict for user settings
    func resolveUserSettingsConflict(resolution: ConflictResolution, userId: String) async throws {
        let storeActor = LocalStore.shared.storeActor

        guard let settings = try await storeActor.getUserSettings(userId: userId) else {
            throw SyncError.notFound(table: .userSettings, id: userId)
        }

        guard settings.syncStatus == .conflict else {
            throw SyncError.notInConflict(table: .userSettings, id: userId)
        }

        switch resolution {
        case .keepServer:
            guard let serverSnapshotData = settings.conflictServerSnapshot,
                  let serverSnapshot = UserSettingsServerSnapshot.decode(from: serverSnapshotData) else {
                throw SyncError.missingConflictSnapshot(table: .userSettings, id: userId)
            }

            await storeActor.resolveUserSettingsConflictKeepServer(userId: userId, serverSnapshot: serverSnapshot)

        case .keepLocal:
            guard let serverSnapshotData = settings.conflictServerSnapshot,
                  let serverSnapshot = UserSettingsServerSnapshot.decode(from: serverSnapshotData) else {
                throw SyncError.missingConflictSnapshot(table: .userSettings, id: userId)
            }

            await storeActor.resolveUserSettingsConflictKeepLocal(userId: userId, serverRevision: serverSnapshot.revision)

            if let updatedSettings = try await storeActor.getUserSettings(userId: userId) {
                _ = try await pushUserSettingsRow(updatedSettings, userId: userId, storeActor: storeActor, isRetry: false)
                try await storeActor.save()
            }
        }

        conflictCount = try await storeActor.countConflicts(userId: userId)
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

// MARK: - Sync Errors

/// Errors that can occur during sync operations
enum SyncError: LocalizedError {
    case notFound(table: SyncTable, id: String)
    case notInConflict(table: SyncTable, id: String)
    case missingConflictSnapshot(table: SyncTable, id: String)

    var errorDescription: String? {
        switch self {
        case .notFound(let table, let id):
            return "\(table.displayName) with id \(id) not found"
        case .notInConflict(let table, let id):
            return "\(table.displayName) with id \(id) is not in conflict state"
        case .missingConflictSnapshot(let table, let id):
            return "\(table.displayName) with id \(id) has no conflict snapshot"
        }
    }
}
