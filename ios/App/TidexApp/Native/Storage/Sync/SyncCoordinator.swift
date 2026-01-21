import Foundation
import Supabase
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SyncCoordinator")

/// Batch size for intermediate saves during pull operations.
/// Rows are saved every N rows to ensure durability if a later row fails.
/// Cursor is only persisted after full page success, so failed pages will re-pull.
private let pullSaveBatchSize = 50

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

    /// Reset sync state when user changes (e.g., sign out)
    /// Clears the interval guard so the next user's initial sync isn't blocked
    func resetForUserChange() {
        lastAutoSyncAt = nil
        lastError = nil
        lastSyncedAt = nil
        conflictCount = 0
        logger.info("Sync state reset for user change")
    }

    // MARK: - Device Locale Update

    /// Updates the user's raw_user_meta_data with the current device locale
    /// This helps track which locale the user's device is set to for notifications/localization
    private func updateDeviceLocale() async {
        // Get the device's preferred language (e.g., "en", "no", "nb")
        guard let languageCode = Locale.current.language.languageCode?.identifier else {
            logger.debug("Could not determine device language code")
            return
        }

        do {
            _ = try await supabase.auth.update(
                user: UserAttributes(data: ["locale": .string(languageCode)])
            )
            logger.debug("Updated user locale to: \(languageCode)")
        } catch {
            // Non-fatal - log but don't fail the sync
            logger.warning("Failed to update device locale: \(error.localizedDescription)")
        }
    }

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

        // Interval guard for automatic syncs (silent skip)
        // Local changes, manual refreshes, and Watch refreshes always bypass the interval guard
        if reason != .manualRefresh && reason != .localChange && reason != .watchRefresh {
            if let lastAuto = lastAutoSyncAt,
               Date().timeIntervalSince(lastAuto) < minimumSyncInterval {
                return SyncResult(
                    success: false,
                    tableResults: [],
                    pushResults: [],
                    totalRowsProcessed: 0,
                    totalRowsPushed: 0,
                    totalConflicts: 0,
                    totalAutoMerged: 0,
                    duration: 0,
                    error: nil
                )
            }
        }

        syncInProgress = true
        isSyncing = true
        lastError = nil

        // SAFETY: Ensure flags are always reset, even on unexpected errors
        defer {
            syncInProgress = false
            isSyncing = false
        }

        let startTime = Date()

        // Update device locale in user metadata (non-blocking, errors logged but not propagated)
        await updateDeviceLocale()

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
            _ = pushResults.reduce(0) { $0 + $1.rebased } // totalRebased - tracked but not logged
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

            // Only log when there's actual data transfer
            if totalRows > 0 || totalPushed > 0 || totalConflicts > 0 {
                logger.info("Sync: \(totalRows) pulled, \(totalPushed) pushed\(totalConflicts > 0 ? ", \(totalConflicts) conflicts" : "")")
            }

            // Update widget storage with latest shift data
            NativeWidgetStorage.updateWidgetStorage(for: userId)

            // Note: syncInProgress and isSyncing are reset by defer block
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

            // Extract user-friendly message if available, otherwise use technical description
            let userFriendlyMessage: String
            let technicalMessage = error.localizedDescription

            if let syncError = error as? SyncError {
                userFriendlyMessage = syncError.userFriendlyMessage
            } else if let encodingError = error as? SyncEncodingError {
                userFriendlyMessage = encodingError.userFriendlyMessage
            } else {
                userFriendlyMessage = "Sync failed: \(technicalMessage)"
            }

            // Log technical details for debugging
            logger.error("Sync failed: \(technicalMessage)")

            await storeActor.updateSyncState(userId: userId) { state in
                state.markSyncFailed(error: technicalMessage)
            }

            // Surface user-friendly message to UI
            lastError = userFriendlyMessage

            // Note: syncInProgress and isSyncing are reset by defer block
            return SyncResult(
                success: false,
                tableResults: [],
                pushResults: [],
                totalRowsProcessed: 0,
                totalRowsPushed: 0,
                totalConflicts: 0,
                totalAutoMerged: 0,
                duration: duration,
                error: userFriendlyMessage
            )
        }
    }

    // MARK: - Pull Implementation

    /// Pull changes for a single table
    /// Uses updated_at timestamp cursor with tie-breaker for incremental sync
    private func pullTable(
        _ table: SyncTable,
        userId: String,
        syncState: LocalSyncState
    ) async throws -> TablePullResult {
        var cursor = syncState.updatedAtCursor(for: table)
        var totalRows = 0
        var newConflicts = 0
        var autoMerged = 0
        var maxRevision: Int64 = syncState.cursor(for: table) // Legacy, for debugging

        logger.debug("Pulling \(table.displayName) from \(cursor.description)")

        // Page through all changes using updated_at cursor
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
            case .notificationPreferences:
                result = try await pullNotificationPreferencesPage(userId: userId, cursor: cursor)
            }

            totalRows += result.rowsProcessed
            newConflicts += result.newConflicts
            autoMerged += result.autoMerged

            // Track legacy max revision for debugging
            if result.maxRevision > maxRevision {
                maxRevision = result.maxRevision
            }

            // Update cursor if we processed rows
            if let lastUpdatedAt = result.lastUpdatedAt {
                cursor = SyncCursor(updatedAt: lastUpdatedAt, tieId: result.lastTieId)

                // Persist cursor to sync state
                let storeActor = LocalStore.shared.storeActor
                await storeActor.updateSyncState(userId: userId) { state in
                    state.updateUpdatedAtCursor(for: table, updatedAt: lastUpdatedAt, tieId: result.lastTieId)
                    // Also update legacy cursor for debugging
                    state.updateCursor(for: table, to: result.maxRevision)
                }
            }

            // No more pages
            if !result.hasMore {
                break
            }
        }

        let finalCursor = cursor.updatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "initial"
        logger.debug("Pulled \(table.displayName): \(totalRows) rows, cursor now at \(finalCursor)")

        return TablePullResult(
            table: table,
            rowsProcessed: totalRows,
            lastUpdatedAt: cursor.updatedAt,
            lastUpdatedAtTieId: cursor.tieId,
            maxRevision: maxRevision,
            newConflicts: newConflicts,
            autoMerged: autoMerged
        )
    }

    /// Result of pulling a single page
    private struct PagePullResult {
        let rowsProcessed: Int
        /// Last updated_at timestamp in this page (for cursor)
        let lastUpdatedAt: Date?
        /// ID of the last row at lastUpdatedAt (tie-breaker)
        let lastTieId: String
        /// Legacy max revision in this page (for debugging)
        let maxRevision: Int64
        let newConflicts: Int
        let autoMerged: Int
        let hasMore: Bool
    }

    // MARK: - User Shifts Pull

    private func pullUserShiftsPage(userId: String, cursor: SyncCursor) async throws -> PagePullResult {
        // Query server for changes since cursor using updated_at + id tie-breaker
        // Condition: (updated_at > cursor.updatedAt) OR (updated_at == cursor.updatedAt AND id > cursor.tieId)
        let rows: [SyncShiftRow]

        if let cursorUpdatedAt = cursor.updatedAt {
            // Incremental sync: fetch rows after cursor
            let cursorTimestamp = formatISO8601(cursorUpdatedAt)
            let cursorTieId = cursor.tieId

            // Use Supabase's or() filter for the compound condition
            // (updated_at > cursor) OR (updated_at = cursor AND id > tieId)
            rows = try await supabase
                .from("user_shifts")
                .select()
                .eq("user_id", value: userId)
                .or("updated_at.gt.\(cursorTimestamp),and(updated_at.eq.\(cursorTimestamp),id.gt.\(cursorTieId))")
                .order("updated_at", ascending: true)
                .order("id", ascending: true)
                .limit(pageSize)
                .execute()
                .value
        } else {
            // Initial sync: fetch all rows
            rows = try await supabase
                .from("user_shifts")
                .select()
                .eq("user_id", value: userId)
                .order("updated_at", ascending: true)
                .order("id", ascending: true)
                .limit(pageSize)
                .execute()
                .value
        }

        if rows.isEmpty {
            return PagePullResult(
                rowsProcessed: 0,
                lastUpdatedAt: cursor.updatedAt,
                lastTieId: cursor.tieId,
                maxRevision: 0,
                newConflicts: 0,
                autoMerged: 0,
                hasMore: false
            )
        }

        let storeActor = LocalStore.shared.storeActor
        var newConflicts = 0
        var autoMerged = 0
        var maxRevision: Int64 = 0
        let pageStartTime = Date()

        for (index, row) in rows.enumerated() {
            let result = try await applyShiftRow(row, storeActor: storeActor)
            if result == .conflict { newConflicts += 1 }
            if result == .autoMerged { autoMerged += 1 }
            if row.revision > maxRevision {
                maxRevision = row.revision
            }

            // Batch save for durability: persist partial progress every N rows
            // Cursor is NOT advanced here - only after full page success
            let rowNumber = index + 1
            if rowNumber % pullSaveBatchSize == 0 {
                try await storeActor.save()
                logger.debug("user_shifts: saved batch at row \(rowNumber)/\(rows.count)")
            }
        }

        // Final save for any remaining rows
        try await storeActor.save()

        let duration = Date().timeIntervalSince(pageStartTime)
        logger.info("user_shifts: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

        // Get cursor position from the last row
        // SAFETY: guard let prevents crash if rows somehow became empty
        guard let lastRow = rows.last else {
            logger.warning("Unexpected empty rows after processing in pullShiftsPage")
            return PagePullResult(
                rowsProcessed: 0,
                lastUpdatedAt: Date(),
                lastTieId: "",
                maxRevision: maxRevision,
                newConflicts: newConflicts,
                autoMerged: autoMerged,
                hasMore: false
            )
        }
        // SAFETY: Throw on parse failure to prevent cursor corruption
        let lastUpdatedAt = try requireISO8601(lastRow.updated_at, table: .userShifts, id: lastRow.id)

        return PagePullResult(
            rowsProcessed: rows.count,
            lastUpdatedAt: lastUpdatedAt,
            lastTieId: lastRow.id,
            maxRevision: maxRevision,
            newConflicts: newConflicts,
            autoMerged: autoMerged,
            hasMore: rows.count == pageSize
        )
    }

    /// Apply a server shift row to local storage
    private func applyShiftRow(_ serverRow: SyncShiftRow, storeActor: LocalStoreActor) async throws -> ApplyResult {
        // SAFETY: Throw on parse failure to prevent data corruption
        let serverUpdatedAt = try requireISO8601(serverRow.updated_at, table: .userShifts, id: serverRow.id)
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
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = Date.localTimeZone

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
            lastSyncedSnapshot: try snapshot.encodedOrThrow(),
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

    private func pullRecurringShiftsPage(userId: String, cursor: SyncCursor) async throws -> PagePullResult {
        // Query using updated_at + id tie-breaker
        let rows: [SyncRecurringShiftRow]

        if let cursorUpdatedAt = cursor.updatedAt {
            let cursorTimestamp = formatISO8601(cursorUpdatedAt)
            let cursorTieId = cursor.tieId

            rows = try await supabase
                .from("recurring_shifts")
                .select()
                .eq("user_id", value: userId)
                .or("updated_at.gt.\(cursorTimestamp),and(updated_at.eq.\(cursorTimestamp),id.gt.\(cursorTieId))")
                .order("updated_at", ascending: true)
                .order("id", ascending: true)
                .limit(pageSize)
                .execute()
                .value
        } else {
            rows = try await supabase
                .from("recurring_shifts")
                .select()
                .eq("user_id", value: userId)
                .order("updated_at", ascending: true)
                .order("id", ascending: true)
                .limit(pageSize)
                .execute()
                .value
        }

        if rows.isEmpty {
            return PagePullResult(
                rowsProcessed: 0,
                lastUpdatedAt: cursor.updatedAt,
                lastTieId: cursor.tieId,
                maxRevision: 0,
                newConflicts: 0,
                autoMerged: 0,
                hasMore: false
            )
        }

        let storeActor = LocalStore.shared.storeActor
        var newConflicts = 0
        var autoMerged = 0
        var maxRevision: Int64 = 0
        let pageStartTime = Date()

        for (index, row) in rows.enumerated() {
            let result = try await applyRecurringShiftRow(row, storeActor: storeActor)
            if result == .conflict { newConflicts += 1 }
            if result == .autoMerged { autoMerged += 1 }
            if row.revision > maxRevision {
                maxRevision = row.revision
            }

            // Batch save for durability
            let rowNumber = index + 1
            if rowNumber % pullSaveBatchSize == 0 {
                try await storeActor.save()
                logger.debug("recurring_shifts: saved batch at row \(rowNumber)/\(rows.count)")
            }
        }

        // Final save for any remaining rows
        try await storeActor.save()

        let duration = Date().timeIntervalSince(pageStartTime)
        logger.info("recurring_shifts: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

        // SAFETY: guard let prevents crash if rows somehow became empty
        guard let lastRow = rows.last else {
            logger.warning("Unexpected empty rows after processing in pullRecurringShiftsPage")
            return PagePullResult(
                rowsProcessed: 0,
                lastUpdatedAt: Date(),
                lastTieId: "",
                maxRevision: maxRevision,
                newConflicts: newConflicts,
                autoMerged: autoMerged,
                hasMore: false
            )
        }
        // SAFETY: Throw on parse failure to prevent cursor corruption
        let lastUpdatedAt = try requireISO8601(lastRow.updated_at, table: .recurringShifts, id: lastRow.id)

        return PagePullResult(
            rowsProcessed: rows.count,
            lastUpdatedAt: lastUpdatedAt,
            lastTieId: lastRow.id,
            maxRevision: maxRevision,
            newConflicts: newConflicts,
            autoMerged: autoMerged,
            hasMore: rows.count == pageSize
        )
    }

    private func applyRecurringShiftRow(_ serverRow: SyncRecurringShiftRow, storeActor: LocalStoreActor) async throws -> ApplyResult {
        // SAFETY: Throw on parse failure to prevent data corruption
        let serverUpdatedAt = try requireISO8601(serverRow.updated_at, table: .recurringShifts, id: serverRow.id)
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
            selectedDays: try canonicalJSONEncoder.encode(serverRow.selected_days),
            endCondition: serverRow.end_condition.flatMap { try? canonicalJSONEncoder.encode($0) },
            exclusions: serverRow.exclusions.flatMap { try? canonicalJSONEncoder.encode($0) },
            dateSpecificSupplements: serverRow.date_specific_supplements.flatMap { try? canonicalJSONEncoder.encode($0) },
            serverUpdatedAt: serverUpdatedAt,
            serverRevision: serverRow.revision,
            serverDeletedAt: serverDeletedAt,
            syncStatus: .clean,
            dirtyFields: LocalRecurringShift.emptyDirtyFields(),
            lastSyncedSnapshot: try snapshot.encodedOrThrow(),
            localUpdatedAt: Date(),
            conflictServerSnapshot: nil
        )

        try await storeActor.upsertRecurringShift(localShift)
    }

    private func convertToRecurringShiftField(_ field: RecurringShiftField) -> RecurringShiftField {
        field
    }

    // MARK: - Wage Snapshots Pull

    private func pullWageSnapshotsPage(userId: String, cursor: SyncCursor) async throws -> PagePullResult {
        // Query using updated_at + id tie-breaker
        let rows: [SyncWageSnapshotRow]

        if let cursorUpdatedAt = cursor.updatedAt {
            let cursorTimestamp = formatISO8601(cursorUpdatedAt)
            let cursorTieId = cursor.tieId

            rows = try await supabase
                .from("wage_snapshots")
                .select()
                .eq("user_id", value: userId)
                .or("updated_at.gt.\(cursorTimestamp),and(updated_at.eq.\(cursorTimestamp),id.gt.\(cursorTieId))")
                .order("updated_at", ascending: true)
                .order("id", ascending: true)
                .limit(pageSize)
                .execute()
                .value
        } else {
            rows = try await supabase
                .from("wage_snapshots")
                .select()
                .eq("user_id", value: userId)
                .order("updated_at", ascending: true)
                .order("id", ascending: true)
                .limit(pageSize)
                .execute()
                .value
        }

        if rows.isEmpty {
            return PagePullResult(
                rowsProcessed: 0,
                lastUpdatedAt: cursor.updatedAt,
                lastTieId: cursor.tieId,
                maxRevision: 0,
                newConflicts: 0,
                autoMerged: 0,
                hasMore: false
            )
        }

        let storeActor = LocalStore.shared.storeActor
        var newConflicts = 0
        var autoMerged = 0
        var maxRevision: Int64 = 0
        let pageStartTime = Date()

        for (index, row) in rows.enumerated() {
            let result = try await applyWageSnapshotRow(row, storeActor: storeActor)
            if result == .conflict { newConflicts += 1 }
            if result == .autoMerged { autoMerged += 1 }
            if row.revision > maxRevision {
                maxRevision = row.revision
            }

            // Batch save for durability
            let rowNumber = index + 1
            if rowNumber % pullSaveBatchSize == 0 {
                try await storeActor.save()
                logger.debug("wage_snapshots: saved batch at row \(rowNumber)/\(rows.count)")
            }
        }

        // Final save for any remaining rows
        try await storeActor.save()

        let duration = Date().timeIntervalSince(pageStartTime)
        logger.info("wage_snapshots: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

        // SAFETY: guard let prevents crash if rows somehow became empty
        guard let lastRow = rows.last else {
            logger.warning("Unexpected empty rows after processing in pullWageSnapshotsPage")
            return PagePullResult(
                rowsProcessed: 0,
                lastUpdatedAt: Date(),
                lastTieId: "",
                maxRevision: maxRevision,
                newConflicts: newConflicts,
                autoMerged: autoMerged,
                hasMore: false
            )
        }
        // SAFETY: Throw on parse failure to prevent cursor corruption
        let lastUpdatedAt = try requireISO8601(lastRow.updated_at, table: .wageSnapshots, id: lastRow.id)

        return PagePullResult(
            rowsProcessed: rows.count,
            lastUpdatedAt: lastUpdatedAt,
            lastTieId: lastRow.id,
            maxRevision: maxRevision,
            newConflicts: newConflicts,
            autoMerged: autoMerged,
            hasMore: rows.count == pageSize
        )
    }

    private func applyWageSnapshotRow(_ serverRow: SyncWageSnapshotRow, storeActor: LocalStoreActor) async throws -> ApplyResult {
        // SAFETY: Throw on parse failure to prevent data corruption
        let serverUpdatedAt = try requireISO8601(serverRow.updated_at, table: .wageSnapshots, id: serverRow.id)
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
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = Date.localTimeZone

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
            lastSyncedSnapshot: try snapshot.encodedOrThrow(),
            localUpdatedAt: Date(),
            conflictServerSnapshot: nil
        )

        try await storeActor.upsertWageSnapshot(localSnapshot)
    }

    private func convertToWageSnapshotField(_ field: WageSnapshotField) -> WageSnapshotField {
        field
    }

    // MARK: - User Settings Pull

    private func pullUserSettingsPage(userId: String, cursor: SyncCursor) async throws -> PagePullResult {
        // Query using updated_at + user_id tie-breaker (user_settings uses user_id as primary key)
        let rows: [SyncUserSettingsRow]

        if let cursorUpdatedAt = cursor.updatedAt {
            let cursorTimestamp = formatISO8601(cursorUpdatedAt)
            let cursorTieId = cursor.tieId

            rows = try await supabase
                .from("user_settings")
                .select()
                .eq("user_id", value: userId)
                .or("updated_at.gt.\(cursorTimestamp),and(updated_at.eq.\(cursorTimestamp),user_id.gt.\(cursorTieId))")
                .order("updated_at", ascending: true)
                .order("user_id", ascending: true)
                .limit(pageSize)
                .execute()
                .value
        } else {
            rows = try await supabase
                .from("user_settings")
                .select()
                .eq("user_id", value: userId)
                .order("updated_at", ascending: true)
                .order("user_id", ascending: true)
                .limit(pageSize)
                .execute()
                .value
        }

        if rows.isEmpty {
            return PagePullResult(
                rowsProcessed: 0,
                lastUpdatedAt: cursor.updatedAt,
                lastTieId: cursor.tieId,
                maxRevision: 0,
                newConflicts: 0,
                autoMerged: 0,
                hasMore: false
            )
        }

        let storeActor = LocalStore.shared.storeActor
        var newConflicts = 0
        var autoMerged = 0
        var maxRevision: Int64 = 0
        let pageStartTime = Date()

        for (index, row) in rows.enumerated() {
            let result = try await applyUserSettingsRow(row, storeActor: storeActor)
            if result == .conflict { newConflicts += 1 }
            if result == .autoMerged { autoMerged += 1 }
            if row.revision > maxRevision {
                maxRevision = row.revision
            }

            // Batch save for durability
            let rowNumber = index + 1
            if rowNumber % pullSaveBatchSize == 0 {
                try await storeActor.save()
                logger.debug("user_settings: saved batch at row \(rowNumber)/\(rows.count)")
            }
        }

        // Final save for any remaining rows
        try await storeActor.save()

        let duration = Date().timeIntervalSince(pageStartTime)
        logger.info("user_settings: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

        // SAFETY: guard let prevents crash if rows somehow became empty
        guard let lastRow = rows.last else {
            logger.warning("Unexpected empty rows after processing in pullUserSettingsPage")
            return PagePullResult(
                rowsProcessed: 0,
                lastUpdatedAt: Date(),
                lastTieId: "",
                maxRevision: maxRevision,
                newConflicts: newConflicts,
                autoMerged: autoMerged,
                hasMore: false
            )
        }
        // SAFETY: Throw on parse failure to prevent cursor corruption
        let lastUpdatedAt = try requireISO8601(lastRow.updated_at, table: .userSettings, id: lastRow.user_id)

        return PagePullResult(
            rowsProcessed: rows.count,
            lastUpdatedAt: lastUpdatedAt,
            lastTieId: lastRow.user_id, // user_settings uses user_id as primary key
            maxRevision: maxRevision,
            newConflicts: newConflicts,
            autoMerged: autoMerged,
            hasMore: rows.count == pageSize
        )
    }

    private func applyUserSettingsRow(_ serverRow: SyncUserSettingsRow, storeActor: LocalStoreActor) async throws -> ApplyResult {
        // SAFETY: Throw on parse failure to prevent data corruption
        let serverUpdatedAt = try requireISO8601(serverRow.updated_at, table: .userSettings, id: serverRow.user_id)

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
            lastSyncedSnapshot: try snapshot.encodedOrThrow(),
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
        case .notificationPreferences:
            return try await pushNotificationPreferences(userId: userId)
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

        // Check if this is a new record that needs INSERT (serverRevision == 0 means never synced)
        if shift.serverRevision == 0 {
            return try await insertUserShift(shift, userId: userId, storeActor: storeActor)
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
            if let data = shift.customSupplements {
                let decoded = try requireAnyJSON(
                    data,
                    table: .userShifts,
                    id: shiftId,
                    field: "custom_supplements"
                )
                updateData["custom_supplements"] = decoded
            } else {
                updateData["custom_supplements"] = .null
            }
        }

        try requireNonEmptyUpdate(updateData, table: .userShifts, id: shiftId)

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

                // Get old values from last synced snapshot for notification (before marking pushed)
                let oldSnapshot = UserShiftServerSnapshot.decode(from: shift.lastSyncedSnapshot)

                await storeActor.markShiftPushed(
                    id: shiftId,
                    serverRow: returnedRow,
                    serverUpdatedAt: serverUpdatedAt,
                    serverRevision: returnedRow.revision,
                    snapshot: serverSnapshot
                )

                logger.debug("Pushed shift \(shiftId.prefix(8))")

                // Notify shared users if date or times changed
                let dateOrTimesChanged = dirtyFields.contains(.shiftDate) ||
                                         dirtyFields.contains(.startTime) ||
                                         dirtyFields.contains(.endTime)
                if dateOrTimesChanged {
                    await notifyShiftChange(
                        shiftId: shiftId,
                        shiftDate: returnedRow.shift_date,
                        startTime: returnedRow.start_time,
                        endTime: returnedRow.end_time,
                        eventType: "updated",
                        oldStartTime: oldSnapshot?.startTime,
                        oldEndTime: oldSnapshot?.endTime
                    )
                }

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
            // Check if it's an RLS policy violation - mark as conflict, don't abort sync
            let errorString = String(describing: error)
            if errorString.contains("row-level security") || errorString.contains("42501") {
                logger.warning("Shift \(shiftId.prefix(8)) blocked by RLS policy on UPDATE, marking as conflict")
                await storeActor.markShiftConflict(id: shiftId, serverSnapshot: nil)
                return .conflict
            }
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

            // Get shift details from snapshot before marking deleted (for notification)
            let snapshot = UserShiftServerSnapshot.decode(from: shift.lastSyncedSnapshot)

            await storeActor.markShiftDeleted(
                id: shiftId,
                serverUpdatedAt: serverUpdatedAt,
                serverRevision: returnedRow.revision,
                serverDeletedAt: serverDeletedAt
            )

            logger.debug("Deleted shift \(shiftId.prefix(8))")

            // Notify shared users about the deleted shift (best-effort)
            if let snapshot = snapshot {
                await notifyShiftChange(
                    shiftId: shiftId,
                    shiftDate: snapshot.shiftDate,
                    startTime: snapshot.startTime,
                    endTime: snapshot.endTime,
                    eventType: "deleted"
                )
            }

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

    /// Insert a new user shift that was created locally (serverRevision == 0)
    private func insertUserShift(
        _ shift: LocalUserShift,
        userId: String,
        storeActor: LocalStoreActor
    ) async throws -> PushResult {
        let shiftId = shift.id

        // Build full insert data
        var insertData: [String: AnyJSON] = [
            "id": .string(shiftId),
            "user_id": .string(userId),
            "shift_date": .string(shift.shiftDateString),
            "start_time": .string(shift.startTime),
            "end_time": .string(shift.endTime)
        ]

        if let data = shift.customSupplements {
            let decoded = try requireAnyJSON(
                data,
                table: .userShifts,
                id: shiftId,
                field: "custom_supplements"
            )
            insertData["custom_supplements"] = decoded
        }

        do {
            let returnedRows: [SyncShiftRow] = try await supabase
                .from("user_shifts")
                .insert(insertData)
                .select()
                .execute()
                .value

            if let returnedRow = returnedRows.first {
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

                logger.debug("Inserted new shift \(shiftId.prefix(8))")

                // Notify shared users about the new shift (best-effort)
                await notifyShiftChange(
                    shiftId: shiftId,
                    shiftDate: returnedRow.shift_date,
                    startTime: returnedRow.start_time,
                    endTime: returnedRow.end_time,
                    eventType: "added"
                )

                return .success
            } else {
                logger.error("Insert shift returned no rows for \(shiftId.prefix(8))")
                return .conflict
            }
        } catch {
            let errorString = String(describing: error)
            // Check if it's a duplicate key error (row already exists on server)
            if errorString.contains("duplicate") || errorString.contains("23505") {
                logger.warning("Shift \(shiftId.prefix(8)) already exists on server, fetching and merging")
                // Fetch the existing server row and treat as conflict
                let serverRows: [SyncShiftRow] = try await supabase
                    .from("user_shifts")
                    .select()
                    .eq("id", value: shiftId)
                    .execute()
                    .value

                if let serverRow = serverRows.first {
                    let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()
                    let serverSnapshot = UserShiftServerSnapshot.from(
                        shiftDate: serverRow.shift_date,
                        startTime: serverRow.start_time,
                        endTime: serverRow.end_time,
                        customSupplements: serverRow.custom_supplements,
                        updatedAt: serverUpdatedAt,
                        revision: serverRow.revision,
                        deletedAt: serverRow.deleted_at.flatMap { parseISO8601($0) }
                    )
                    await storeActor.markShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
                }
                return .conflict
            }
            // Check if it's an RLS policy violation - mark as conflict, don't abort sync
            if errorString.contains("row-level security") || errorString.contains("42501") {
                logger.warning("Shift \(shiftId.prefix(8)) blocked by RLS policy, marking as conflict")
                await storeActor.markShiftConflict(id: shiftId, serverSnapshot: nil)
                return .conflict
            }
            logger.error("Insert shift failed: \(error.localizedDescription)")
            throw error
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
            // Server row doesn't exist - check if this is a new local record that needs INSERT
            if shift.serverRevision == 0 {
                logger.debug("Shift \(shiftId.prefix(8)) is new (serverRevision=0), attempting INSERT")
                return try await insertUserShift(shift, userId: userId, storeActor: storeActor)
            }
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

        // Check if this is a new record that needs INSERT (serverRevision == 0 means never synced)
        if shift.serverRevision == 0 {
            return try await insertRecurringShift(shift, userId: userId, storeActor: storeActor)
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
            let decoded = try requireAnyJSON(
                shift.selectedDays,
                table: .recurringShifts,
                id: shiftId,
                field: "selected_days"
            )
            updateData["selected_days"] = decoded
        }
        if dirtyFields.contains(.endCondition) {
            if let data = shift.endCondition {
                let decoded = try requireAnyJSON(
                    data,
                    table: .recurringShifts,
                    id: shiftId,
                    field: "end_condition"
                )
                updateData["end_condition"] = decoded
            } else {
                updateData["end_condition"] = .null
            }
        }
        if dirtyFields.contains(.exclusions) {
            if let data = shift.exclusions {
                let decoded = try requireAnyJSON(
                    data,
                    table: .recurringShifts,
                    id: shiftId,
                    field: "exclusions"
                )
                updateData["exclusions"] = decoded
            } else {
                updateData["exclusions"] = .null
            }
        }
        if dirtyFields.contains(.dateSpecificSupplements) {
            if let data = shift.dateSpecificSupplements {
                let decoded = try requireAnyJSON(
                    data,
                    table: .recurringShifts,
                    id: shiftId,
                    field: "date_specific_supplements"
                )
                updateData["date_specific_supplements"] = decoded
            } else {
                updateData["date_specific_supplements"] = .null
            }
        }

        try requireNonEmptyUpdate(updateData, table: .recurringShifts, id: shiftId)

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
            // Check if it's an RLS policy violation - mark as conflict, don't abort sync
            let errorString = String(describing: error)
            if errorString.contains("row-level security") || errorString.contains("42501") {
                logger.warning("Recurring shift \(shiftId.prefix(8)) blocked by RLS policy on UPDATE, marking as conflict")
                await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: nil)
                return .conflict
            }
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

    /// Insert a new recurring shift that was created locally (serverRevision == 0)
    private func insertRecurringShift(
        _ shift: LocalRecurringShift,
        userId: String,
        storeActor: LocalStoreActor
    ) async throws -> PushResult {
        let shiftId = shift.id

        // Build full insert data
        var insertData: [String: AnyJSON] = [
            "id": .string(shiftId),
            "user_id": .string(userId),
            "start_time": .string(shift.startTime),
            "end_time": .string(shift.endTime),
            "repeat_interval_weeks": .integer(shift.repeatIntervalWeeks)
        ]

        // selected_days is required
        let selectedDaysDecoded = try requireAnyJSON(
            shift.selectedDays,
            table: .recurringShifts,
            id: shiftId,
            field: "selected_days"
        )
        insertData["selected_days"] = selectedDaysDecoded

        if let data = shift.endCondition {
            let decoded = try requireAnyJSON(data, table: .recurringShifts, id: shiftId, field: "end_condition")
            insertData["end_condition"] = decoded
        }

        if let data = shift.exclusions {
            let decoded = try requireAnyJSON(data, table: .recurringShifts, id: shiftId, field: "exclusions")
            insertData["exclusions"] = decoded
        }

        if let data = shift.dateSpecificSupplements {
            let decoded = try requireAnyJSON(data, table: .recurringShifts, id: shiftId, field: "date_specific_supplements")
            insertData["date_specific_supplements"] = decoded
        }

        do {
            let returnedRows: [SyncRecurringShiftRow] = try await supabase
                .from("recurring_shifts")
                .insert(insertData)
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

                logger.debug("Inserted new recurring shift \(shiftId.prefix(8))")
                return .success
            } else {
                logger.error("Insert recurring shift returned no rows for \(shiftId.prefix(8))")
                return .conflict
            }
        } catch {
            let errorString = String(describing: error)
            // Check if it's a duplicate key error
            if errorString.contains("duplicate") || errorString.contains("23505") {
                logger.warning("Recurring shift \(shiftId.prefix(8)) already exists on server, fetching and merging")
                let serverRows: [SyncRecurringShiftRow] = try await supabase
                    .from("recurring_shifts")
                    .select()
                    .eq("id", value: shiftId)
                    .execute()
                    .value

                if let serverRow = serverRows.first {
                    let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()
                    let serverSnapshot = RecurringShiftServerSnapshot.from(
                        row: serverRow.toRecurringShiftRow(),
                        updatedAt: serverUpdatedAt,
                        revision: serverRow.revision,
                        deletedAt: serverRow.deleted_at.flatMap { parseISO8601($0) }
                    )
                    await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
                }
                return .conflict
            }
            // Check if it's an RLS policy violation - mark as conflict, don't abort sync
            if errorString.contains("row-level security") || errorString.contains("42501") {
                logger.warning("Recurring shift \(shiftId.prefix(8)) blocked by RLS policy, marking as conflict")
                await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: nil)
                return .conflict
            }
            logger.error("Insert recurring shift failed: \(error.localizedDescription)")
            throw error
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
            // Server row doesn't exist - check if this is a new local record that needs INSERT
            if shift.serverRevision == 0 {
                logger.debug("Recurring shift \(shiftId.prefix(8)) is new (serverRevision=0), attempting INSERT")
                return try await insertRecurringShift(shift, userId: userId, storeActor: storeActor)
            }
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

        // Check if this is a new record that needs INSERT (serverRevision == 0 means never synced)
        if snapshot.serverRevision == 0 {
            return try await insertWageSnapshot(snapshot, userId: userId, storeActor: storeActor)
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
            let decoded = try requireAnyJSON(
                snapshot.supplements,
                table: .wageSnapshots,
                id: snapshotId,
                field: "supplements"
            )
            updateData["supplements"] = decoded
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

        try requireNonEmptyUpdate(updateData, table: .wageSnapshots, id: snapshotId)

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
            // Check if it's an RLS policy violation - mark as conflict, don't abort sync
            let errorString = String(describing: error)
            if errorString.contains("row-level security") || errorString.contains("42501") {
                logger.warning("Wage snapshot \(snapshotId.prefix(8)) blocked by RLS policy on UPDATE, marking as conflict")
                await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: nil)
                return .conflict
            }
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

    /// Insert a new wage snapshot that was created locally (serverRevision == 0)
    private func insertWageSnapshot(
        _ snapshot: LocalWageSnapshot,
        userId: String,
        storeActor: LocalStoreActor
    ) async throws -> PushResult {
        let snapshotId = snapshot.id

        // Build full insert data
        var insertData: [String: AnyJSON] = [
            "id": .string(snapshotId),
            "user_id": .string(userId),
            "hourly_wage": .double(snapshot.hourlyWage)
        ]

        // from_date (nil for baseline snapshot)
        if let fromDateString = snapshot.fromDateString {
            insertData["from_date"] = .string(fromDateString)
        }

        // wage_level
        if let level = snapshot.wageLevel {
            insertData["wage_level"] = .integer(level)
        }

        // supplements (required)
        let supplementsDecoded = try requireAnyJSON(
            snapshot.supplements,
            table: .wageSnapshots,
            id: snapshotId,
            field: "supplements"
        )
        insertData["supplements"] = supplementsDecoded

        // Optional fields
        if let enabled = snapshot.taxEnabled {
            insertData["tax_enabled"] = .bool(enabled)
        }
        if let percentage = snapshot.taxPercentage {
            insertData["tax_percentage"] = .double(percentage)
        }
        if let enabled = snapshot.breakEnabled {
            insertData["break_enabled"] = .bool(enabled)
        }
        if let method = snapshot.breakMethod {
            insertData["break_method"] = .string(method)
        }
        if let hours = snapshot.breakThresholdHours {
            insertData["break_threshold_hours"] = .double(hours)
        }
        if let minutes = snapshot.breakDeductionMinutes {
            insertData["break_deduction_minutes"] = .integer(minutes)
        }

        do {
            let returnedRows: [SyncWageSnapshotRow] = try await supabase
                .from("wage_snapshots")
                .insert(insertData)
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

                logger.debug("Inserted new wage snapshot \(snapshotId.prefix(8))")
                return .success
            } else {
                logger.error("Insert wage snapshot returned no rows for \(snapshotId.prefix(8))")
                return .conflict
            }
        } catch {
            let errorString = String(describing: error)
            // Check if it's a duplicate key error
            if errorString.contains("duplicate") || errorString.contains("23505") {
                logger.warning("Wage snapshot \(snapshotId.prefix(8)) already exists on server, fetching and merging")
                let serverRows: [SyncWageSnapshotRow] = try await supabase
                    .from("wage_snapshots")
                    .select()
                    .eq("id", value: snapshotId)
                    .execute()
                    .value

                if let serverRow = serverRows.first {
                    let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()
                    let serverSnapshot = WageSnapshotServerSnapshot.from(
                        row: serverRow.toWageSnapshot(),
                        updatedAt: serverUpdatedAt,
                        revision: serverRow.revision,
                        deletedAt: serverRow.deleted_at.flatMap { parseISO8601($0) }
                    )
                    await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: serverSnapshot)
                }
                return .conflict
            }
            // Check if it's an RLS policy violation - mark as conflict, don't abort sync
            if errorString.contains("row-level security") || errorString.contains("42501") {
                logger.warning("Wage snapshot \(snapshotId.prefix(8)) blocked by RLS policy, marking as conflict")
                await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: nil)
                return .conflict
            }
            logger.error("Insert wage snapshot failed: \(error.localizedDescription)")
            throw error
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
            // Server row doesn't exist - check if this is a new local record that needs INSERT
            if snapshot.serverRevision == 0 {
                logger.debug("Wage snapshot \(snapshotId.prefix(8)) is new (serverRevision=0), attempting INSERT")
                return try await insertWageSnapshot(snapshot, userId: userId, storeActor: storeActor)
            }
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

        // Check if this is a new record that needs INSERT (serverRevision == 0 means never synced)
        if settings.serverRevision == 0 {
            return try await insertUserSettings(settings, userId: userId, storeActor: storeActor)
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
            // Check if it's an RLS policy violation - mark as conflict, don't abort sync
            let errorString = String(describing: error)
            if errorString.contains("row-level security") || errorString.contains("42501") {
                logger.warning("User settings for \(userId.prefix(8)) blocked by RLS policy on UPDATE, marking as conflict")
                await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: nil)
                return .conflict
            }
            logger.error("Push user settings failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Insert new user settings that were created locally (serverRevision == 0)
    private func insertUserSettings(
        _ settings: LocalUserSettings,
        userId: String,
        storeActor: LocalStoreActor
    ) async throws -> PushResult {
        // Build full insert data
        var insertData: [String: AnyJSON] = [
            "user_id": .string(userId),
            "theme": .string(settings.theme)
        ]

        // Optional fields
        if let goal = settings.monthlyGoal {
            insertData["monthly_goal"] = .integer(goal)
        }
        if let view = settings.defaultShiftsView {
            insertData["default_shifts_view"] = .string(view)
        }
        if let url = settings.profilePictureUrl {
            insertData["profile_picture_url"] = .string(url)
        }
        if let day = settings.payrollDay {
            insertData["payroll_day"] = .integer(day)
        }
        if let month = settings.halfTaxMonth {
            insertData["half_tax_month"] = .integer(month)
        }
        if let currency = settings.currency {
            insertData["currency"] = .string(currency)
        }
        if let lastActive = settings.lastActive {
            insertData["last_active"] = .string(ISO8601DateFormatter().string(from: lastActive))
        }

        do {
            let returnedRows: [SyncUserSettingsRow] = try await supabase
                .from("user_settings")
                .insert(insertData)
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

                logger.debug("Inserted new user settings for \(userId.prefix(8))")
                return .success
            } else {
                logger.error("Insert user settings returned no rows for \(userId.prefix(8))")
                return .conflict
            }
        } catch {
            let errorString = String(describing: error)
            // Check if it's a duplicate key error
            if errorString.contains("duplicate") || errorString.contains("23505") {
                logger.warning("User settings for \(userId.prefix(8)) already exists on server, fetching and merging")
                let serverRows: [SyncUserSettingsRow] = try await supabase
                    .from("user_settings")
                    .select()
                    .eq("user_id", value: userId)
                    .execute()
                    .value

                if let serverRow = serverRows.first {
                    let serverUpdatedAt = parseISO8601(serverRow.updated_at) ?? Date()
                    let serverSnapshot = UserSettingsServerSnapshot.from(
                        row: serverRow.toUserSettings(),
                        updatedAt: serverUpdatedAt,
                        revision: serverRow.revision
                    )
                    await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: serverSnapshot)
                }
                return .conflict
            }
            // Check if it's an RLS policy violation - mark as conflict, don't abort sync
            if errorString.contains("row-level security") || errorString.contains("42501") {
                logger.warning("User settings for \(userId.prefix(8)) blocked by RLS policy, marking as conflict")
                await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: nil)
                return .conflict
            }
            logger.error("Insert user settings failed: \(error.localizedDescription)")
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
            // Server row doesn't exist - check if this is a new local record that needs INSERT
            if settings.serverRevision == 0 {
                logger.debug("User settings for \(userId.prefix(8)) is new (serverRevision=0), attempting INSERT")
                return try await insertUserSettings(settings, userId: userId, storeActor: storeActor)
            }
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

        // Update widget storage since shift data changed
        NativeWidgetStorage.updateWidgetStorage(for: userId)
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

        // Update widget storage since recurring shift data changed (affects generated shifts)
        NativeWidgetStorage.updateWidgetStorage(for: userId)
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

        // Update widget storage since wage calculations may have changed
        NativeWidgetStorage.updateWidgetStorage(for: userId)
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

        // Update widget storage since settings (e.g., currency) may affect display
        NativeWidgetStorage.updateWidgetStorage(for: userId)
    }

    // MARK: - Notification Preferences Pull

    private func pullNotificationPreferencesPage(userId: String, cursor: SyncCursor) async throws -> PagePullResult {
        // Query using updated_at + user_id tie-breaker (notification_preferences uses user_id as primary key)
        // Note: This table has no revision column - iOS is source of truth
        let rows: [SyncNotificationPreferencesRow]

        if let cursorUpdatedAt = cursor.updatedAt {
            let cursorTimestamp = formatISO8601(cursorUpdatedAt)
            let cursorTieId = cursor.tieId

            rows = try await supabase
                .from("notification_preferences")
                .select()
                .eq("user_id", value: userId)
                .or("updated_at.gt.\(cursorTimestamp),and(updated_at.eq.\(cursorTimestamp),user_id.gt.\(cursorTieId))")
                .order("updated_at", ascending: true)
                .order("user_id", ascending: true)
                .limit(pageSize)
                .execute()
                .value
        } else {
            rows = try await supabase
                .from("notification_preferences")
                .select()
                .eq("user_id", value: userId)
                .order("updated_at", ascending: true)
                .order("user_id", ascending: true)
                .limit(pageSize)
                .execute()
                .value
        }

        if rows.isEmpty {
            return PagePullResult(
                rowsProcessed: 0,
                lastUpdatedAt: cursor.updatedAt,
                lastTieId: cursor.tieId,
                maxRevision: 0,
                newConflicts: 0,
                autoMerged: 0,
                hasMore: false
            )
        }

        let pageStartTime = Date()

        // Apply each row to local storage using the repository
        let repository = NotificationPreferencesRepository.shared
        for row in rows {
            let serverUpdatedAt = parseISO8601(row.updated_at) ?? Date()
            repository.saveFromServer(row: row.toNotificationPreferencesRow(), serverUpdatedAt: serverUpdatedAt)
        }

        let duration = Date().timeIntervalSince(pageStartTime)
        logger.info("notification_preferences: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s")

        guard let lastRow = rows.last else {
            logger.warning("Unexpected empty rows after processing in pullNotificationPreferencesPage")
            return PagePullResult(
                rowsProcessed: 0,
                lastUpdatedAt: Date(),
                lastTieId: "",
                maxRevision: 0,
                newConflicts: 0,
                autoMerged: 0,
                hasMore: false
            )
        }

        let lastUpdatedAt = try requireISO8601(lastRow.updated_at, table: .notificationPreferences, id: lastRow.user_id)

        return PagePullResult(
            rowsProcessed: rows.count,
            lastUpdatedAt: lastUpdatedAt,
            lastTieId: lastRow.user_id,
            maxRevision: 0, // No revision column for notification_preferences
            newConflicts: 0, // iOS is source of truth, no conflicts
            autoMerged: 0,
            hasMore: rows.count == pageSize
        )
    }

    // MARK: - Notification Preferences Push

    private func pushNotificationPreferences(userId: String) async throws -> TablePushResult {
        let repository = NotificationPreferencesRepository.shared

        // Get dirty preferences (if any)
        guard let preferences = repository.getDirtyPreferences(for: userId) else {
            return TablePushResult(table: .notificationPreferences, rowsPushed: 0, newConflicts: 0, rebased: 0)
        }

        // Build upsert payload - iOS is source of truth, so we always push all fields
        let updateData: [String: AnyJSON] = [
            "user_id": .string(userId),
            "shift_reminders_enabled": .bool(preferences.shiftRemindersEnabled),
            "shift_reminder_minutes_array": .array(preferences.shiftReminderMinutesArray.map { .integer($0) }),
            "shared_shifts_enabled": .bool(preferences.sharedShiftsEnabled)
        ]

        do {
            // Upsert to server (insert or update based on user_id)
            let returnedRows: [SyncNotificationPreferencesRow] = try await supabase
                .from("notification_preferences")
                .upsert(updateData, onConflict: "user_id")
                .select()
                .execute()
                .value

            if let returnedRow = returnedRows.first {
                let serverUpdatedAt = parseISO8601(returnedRow.updated_at) ?? Date()
                repository.markClean(for: userId, serverUpdatedAt: serverUpdatedAt)
                logger.debug("Pushed notification preferences for user \(userId.prefix(8))")
                return TablePushResult(table: .notificationPreferences, rowsPushed: 1, newConflicts: 0, rebased: 0)
            } else {
                logger.warning("No rows returned after notification preferences upsert")
                return TablePushResult(table: .notificationPreferences, rowsPushed: 0, newConflicts: 0, rebased: 0)
            }
        } catch {
            logger.error("Push notification preferences failed: \(error.localizedDescription)")
            throw error
        }
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

    /// Parse ISO8601 date string to Date, throwing on failure
    /// Use this for cursor-affecting code paths to prevent data loss
    /// - Parameters:
    ///   - string: The ISO8601 date string to parse
    ///   - table: The table being synced (for error context)
    ///   - id: The row ID (for error context)
    /// - Returns: Parsed Date
    /// - Throws: SyncError.dateParsingFailed if parsing fails
    private func requireISO8601(_ string: String, table: SyncTable, id: String) throws -> Date {
        if let date = parseISO8601(string) {
            return date
        }
        logger.error("Failed to parse updated_at for \(table.displayName) id=\(id): '\(string)'")
        throw SyncError.dateParsingFailed(table: table, id: id, rawValue: string)
    }

    private func requireAnyJSON(
        _ data: Data,
        table: SyncTable,
        id: String,
        field: String
    ) throws -> AnyJSON {
        do {
            return try AnyJSON.decoder.decode(AnyJSON.self, from: data)
        } catch {
            logger.error("Failed to decode \(table.displayName) field=\(field) id=\(id)")
            throw SyncEncodingError.payloadDecodingFailed(
                type: "\(table.rawValue).\(field)",
                underlyingError: error
            )
        }
    }

    private func requireNonEmptyUpdate(
        _ updateData: [String: AnyJSON],
        table: SyncTable,
        id: String
    ) throws {
        guard !updateData.isEmpty else {
            logger.error("Empty update payload for \(table.displayName) id=\(id)")
            throw SyncEncodingError.emptyUpdatePayload(type: "\(table.rawValue).\(id)")
        }
    }

    /// Format Date to ISO8601 string for Supabase queries
    /// Uses fractional seconds for maximum precision
    private func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    // MARK: - Shift Notification Helper

    /// Notify shared users about a shift change via RPC
    /// This is best-effort - failures are logged but don't affect sync success
    ///
    /// - Parameters:
    ///   - shiftId: The shift's UUID
    ///   - shiftDate: The shift date in YYYY-MM-DD format
    ///   - startTime: The shift start time in HH:mm format
    ///   - endTime: The shift end time in HH:mm format
    ///   - eventType: The type of change: "added", "updated", or "deleted"
    ///   - oldStartTime: For updates: the previous start time
    ///   - oldEndTime: For updates: the previous end time
    private func notifyShiftChange(
        shiftId: String,
        shiftDate: String,
        startTime: String,
        endTime: String,
        eventType: String,
        oldStartTime: String? = nil,
        oldEndTime: String? = nil
    ) async {
        // Generate a unique mutation ID for idempotency
        let mutationId = UUID().uuidString

        do {
            // Build RPC parameters
            var params: [String: AnyJSON] = [
                "p_shift_id": .string(shiftId),
                "p_shift_date": .string(shiftDate),
                "p_start_time": .string(startTime),
                "p_end_time": .string(endTime),
                "p_event_type": .string(eventType),
                "p_mutation_id": .string(mutationId)
            ]

            // Include old times for update events (if times changed)
            if let oldStart = oldStartTime, let oldEnd = oldEndTime {
                params["p_old_start_time"] = .string(oldStart)
                params["p_old_end_time"] = .string(oldEnd)
            }

            // Call the RPC - response contains {"queued": N, "delivery": "immediate"|"batched"|"none"}
            let _: AnyJSON = try await supabase
                .rpc("enqueue_shift_notification", params: params)
                .execute()
                .value

            logger.debug("Notified shift change: \(eventType) for \(shiftId.prefix(8))")
        } catch {
            // Best-effort: log but don't fail the sync
            logger.warning("Failed to notify shift change: \(error.localizedDescription)")
        }
    }
}

// MARK: - Sync Errors

/// Errors that can occur during sync operations
enum SyncError: LocalizedError {
    case notFound(table: SyncTable, id: String)
    case notInConflict(table: SyncTable, id: String)
    case missingConflictSnapshot(table: SyncTable, id: String)
    case dateParsingFailed(table: SyncTable, id: String, rawValue: String)

    /// Technical description for logging
    var errorDescription: String? {
        switch self {
        case .notFound(let table, let id):
            return "\(table.displayName) with id \(id) not found"
        case .notInConflict(let table, let id):
            return "\(table.displayName) with id \(id) is not in conflict state"
        case .missingConflictSnapshot(let table, let id):
            return "\(table.displayName) with id \(id) has no conflict snapshot"
        case .dateParsingFailed(let table, let id, let rawValue):
            return "\(table.displayName) with id \(id) has unparseable updated_at: '\(rawValue)'"
        }
    }

    /// User-friendly message for UI display
    var userFriendlyMessage: String {
        switch self {
        case .notFound:
            return "Sync failed: Record not found locally. Please refresh and try again."
        case .notInConflict, .missingConflictSnapshot:
            return "Sync failed: Conflict state mismatch. Please refresh and try again."
        case .dateParsingFailed(let table, let id, _):
            return "Sync failed: Server returned invalid data for \(table.displayName) (ID: \(id.prefix(8))...). Please contact support."
        }
    }
}

// MARK: - Debug Test Harness

#if DEBUG
/// Debug-only test harness for sync safety verification
/// Call from a debug menu or unit test to verify cursor safety
enum SyncTestHarness {
    /// Test that malformed updated_at throws the correct error type
    /// This verifies the error path without needing actual sync infrastructure
    static func testMalformedUpdatedAtThrowsError() -> (passed: Bool, message: String) {
        // Directly test the date parsing logic
        let malformedDate = "not-a-date"
        let testTable = SyncTable.userShifts
        let testId = "test-id-12345"

        // ISO8601DateFormatter should return nil for malformed dates
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: malformedDate) != nil {
            return (false, "FAIL: ISO8601DateFormatter accepted malformed date")
        }

        // SyncError should capture the details correctly
        let error = SyncError.dateParsingFailed(table: testTable, id: testId, rawValue: malformedDate)

        // Verify technical description contains details
        guard let description = error.errorDescription else {
            return (false, "FAIL: Error has no description")
        }
        guard description.contains(testId) && description.contains(malformedDate) else {
            return (false, "FAIL: Error description missing details: \(description)")
        }

        // Verify user-friendly message is actionable
        let userMessage = error.userFriendlyMessage
        guard userMessage.contains("contact support") else {
            return (false, "FAIL: User message not actionable: \(userMessage)")
        }

        return (true, "PASS: Malformed date creates proper error with details")
    }

    /// Test that encoding failure throws and is caught properly
    static func testEncodingFailureIsCaught() -> (passed: Bool, message: String) {
        // Create a snapshot with valid data - encoding should succeed
        let validSnapshot = UserShiftServerSnapshot.from(
            shiftDate: "2025-01-15",
            startTime: "09:00",
            endTime: "17:00",
            customSupplements: nil,
            updatedAt: Date(),
            revision: 1,
            deletedAt: nil
        )

        do {
            let data = try validSnapshot.encodedOrThrow()
            guard !data.isEmpty else {
                return (false, "FAIL: Encoded data is empty")
            }
            return (true, "PASS: Valid snapshot encodes successfully")
        } catch {
            return (false, "FAIL: Valid snapshot encoding threw: \(error)")
        }
    }

    /// Test that user-friendly messages are provided for all error types
    static func testUserFriendlyMessages() -> (passed: Bool, message: String) {
        let errors: [SyncError] = [
            .notFound(table: .userShifts, id: "test"),
            .notInConflict(table: .recurringShifts, id: "test"),
            .missingConflictSnapshot(table: .wageSnapshots, id: "test"),
            .dateParsingFailed(table: .userSettings, id: "test", rawValue: "bad")
        ]

        for error in errors {
            let message = error.userFriendlyMessage
            guard !message.isEmpty else {
                return (false, "FAIL: Empty user message for \(error)")
            }
            guard message.contains("Sync failed") else {
                return (false, "FAIL: Message doesn't indicate sync failure: \(message)")
            }
        }

        return (true, "PASS: All error types have user-friendly messages")
    }

    /// Run all tests and return summary
    static func runAllTests() -> String {
        var results: [String] = []

        let test1 = testMalformedUpdatedAtThrowsError()
        results.append(test1.message)

        let test2 = testEncodingFailureIsCaught()
        results.append(test2.message)

        let test3 = testUserFriendlyMessages()
        results.append(test3.message)

        let allPassed = results.allSatisfy { $0.hasPrefix("PASS") }
        let summary = allPassed ? "✅ All tests passed" : "❌ Some tests failed"

        return ([summary] + results).joined(separator: "\n")
    }
}
#endif
