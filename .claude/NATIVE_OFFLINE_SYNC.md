# Native Offline Sync Implementation Plan

> **Workflow**: This document is divided into phases. Complete one phase at a time, then mark it as done and add implementation notes before resetting context. Do NOT continue to the next phase after completing one.

---

## Overview

**Branch**: `iOS/native-screens`

**Objective**: Make the iOS app fully offline-first:
- All UI reads from local persistent storage only
- Network is used only by a sync layer that writes into the local store
- Sync runs on app open, foreground, and pull-to-refresh
- Changes can be made offline, queued locally, and pushed later
- Conflicts are handled deterministically with field-level merge

**Hard Constraints**:
- iOS 18+ target
- Keep Supabase auth session handling in Keychain as-is
- No new server infrastructure (direct Supabase queries with RLS)
- Only backwards-compatible DB changes (no drops, renames, type changes)
- Production-safe migrations (additive only)

---

## Phase Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Database Migrations | ✅ Complete |
| 2 | iOS SwiftData Models | ✅ Complete |
| 3 | LocalStore & Repositories | ✅ Complete |
| 4 | SyncCoordinator (Pull) | ⬜ Not Started |
| 5 | SyncCoordinator (Push & Conflicts) | ⬜ Not Started |
| 6 | UI/ViewModel Refactor | ⬜ Not Started |
| 7 | Widget Integration | ⬜ Not Started |
| 8 | Testing & Validation | ⬜ Not Started |

---

## Phase 1: Database Migrations

**Status**: ✅ Complete

### Scope

Add `revision` and `updated_at` columns to support optimistic concurrency and incremental sync.

### Tables in Scope
- `public.user_shifts`
- `public.recurring_shifts`
- `public.wage_snapshots`
- `public.user_settings`

### Background
- `deleted_at` already exists on user_shifts, recurring_shifts, wage_snapshots (soft delete implemented)
- `user_settings` already has `updated_at` with a moddatetime trigger

### Tasks

#### 1.1 Add columns for optimistic concurrency

Add `revision` and `updated_at` with clear meaning:
- `updated_at`: server-managed "row last changed timestamp"
- `revision`: server-managed monotonically increasing integer per row, increments on each update

Apply these changes:
- `user_shifts`: add `updated_at timestamptz not null default now()`; add `revision bigint not null default 1`
- `recurring_shifts`: add `updated_at timestamptz not null default now()`; add `revision bigint not null default 1`
- `wage_snapshots`: add `updated_at timestamptz not null default now()`; add `revision bigint not null default 1`
- `user_settings`: add `revision bigint not null default 1` (keep existing `updated_at` semantics)

#### 1.2 Add triggers to bump revision and updated_at

- Create a single trigger function that sets:
  - `new.updated_at = now()`
  - `new.revision = old.revision + 1`
- Attach BEFORE UPDATE triggers to: `user_shifts`, `recurring_shifts`, `wage_snapshots`
- For `user_settings`: Replace the existing moddatetime(updated_at) trigger with a unified trigger that updates both `updated_at` and `revision` together

#### 1.3 Add indexes for sync

Create indexes for "changes since cursor" queries:
- `user_shifts`: index on `(user_id, revision)`
- `recurring_shifts`: index on `(user_id, revision)`
- `wage_snapshots`: index on `(user_id, revision)`
- `user_settings`: index on `(user_id, revision)`

Keep existing indexes. Do not remove anything.

#### 1.4 Confirm RLS compatibility

- Do not weaken RLS
- UPDATE is allowed for setting updated_at and revision via triggers (same UPDATE statement)
- Soft-deleted rows remain readable for sync queries (iOS sync will include deleted rows)

### Notes

**Completed: 2026-01-15**

**Migration Applied**: `20260115000450_add_revision_and_updated_at_for_sync`

**Changes Made**:

1. **Columns Added**:
   - `user_shifts`: `updated_at timestamptz NOT NULL DEFAULT now()`, `revision bigint NOT NULL DEFAULT 1`
   - `recurring_shifts`: `updated_at timestamptz NOT NULL DEFAULT now()`, `revision bigint NOT NULL DEFAULT 1`
   - `wage_snapshots`: `updated_at timestamptz NOT NULL DEFAULT now()`, `revision bigint NOT NULL DEFAULT 1`
   - `user_settings`: `revision bigint NOT NULL DEFAULT 1` (already had `updated_at`)

2. **Trigger Function Created**:
   - `public.set_updated_at_and_revision()` - Sets `updated_at = now()` and `revision = old.revision + 1` on every UPDATE

3. **Triggers Attached**:
   - `set_updated_at_revision` BEFORE UPDATE trigger on all four tables
   - For `user_settings`, replaced the old `handle_updated_at` moddatetime trigger

4. **Indexes Created**:
   - `idx_user_shifts_user_revision` on `(user_id, revision)`
   - `idx_recurring_shifts_user_revision` on `(user_id, revision)`
   - `idx_wage_snapshots_user_revision` on `(user_id, revision)`
   - `idx_user_settings_user_revision` on `(user_id, revision)`

5. **RLS Verification**:
   - All existing RLS policies remain intact
   - UPDATE policies allow trigger to modify `updated_at` and `revision`
   - SELECT policies don't filter `deleted_at`, allowing sync to fetch soft-deleted rows

**Tested**: Verified trigger increments revision correctly (1 → 2 on update)

**iOS Sync Query Pattern** (for Phase 4):
```sql
SELECT * FROM user_shifts
WHERE user_id = :userId AND revision > :cursor
ORDER BY revision ASC
LIMIT 500;
```

---

## Phase 2: iOS SwiftData Models

**Status**: ✅ Complete

### Scope

Create SwiftData models for local persistence in a `Storage` module/folder.

### Models to Implement

#### LocalUserShift
- `id`: UUID
- `userId`: UUID
- `shiftDate`: Date (store as Date, derived from YYYY-MM-DD)
- `startTime`: String (match current DB type)
- `endTime`: String
- `customSupplements`: Data (persist JSONB safely)
- `serverUpdatedAt`: Date
- `serverRevision`: Int64
- `serverDeletedAt`: Date? (maps to deleted_at)
- `syncStatus`: String or enum rawValue
- `dirtyFields`: Data (JSON array of strings)
- `lastSyncedSnapshot`: Data (JSON blob for diffing)
- `localUpdatedAt`: Date (when user changed locally)
- `conflictServerSnapshot`: Data? (server version on conflict)

#### LocalRecurringShift
- `id`, `userId`
- `startTime`, `endTime`, `repeatIntervalWeeks`
- `selectedDays` JSON
- `endCondition` JSON
- `exclusions` JSON
- `dateSpecificSupplements` JSON
- `serverUpdatedAt`, `serverRevision`, `serverDeletedAt`
- `syncStatus`, `dirtyFields`, `lastSyncedSnapshot`, `localUpdatedAt`, `conflictServerSnapshot`

#### LocalWageSnapshot
- `id`, `userId`
- `fromDate`: Date? (nullable for baseline)
- `hourlyWage`, `wageLevel`
- `supplements` JSON
- `taxEnabled`, `taxPercentage`
- `breakEnabled`, `breakMethod`, `breakThresholdHours`, `breakDeductionMinutes`
- `serverUpdatedAt`, `serverRevision`, `serverDeletedAt`
- `syncStatus`, `dirtyFields`, `lastSyncedSnapshot`, `localUpdatedAt`, `conflictServerSnapshot`

#### LocalUserSettings
- `userId`
- `monthlyGoal`, `defaultShiftsView`, `profilePictureUrl`, `payrollDay`, `theme`, `halfTaxMonth`, `currency`, `lastActive`
- `createdAt` (optional)
- `serverUpdatedAt`, `serverRevision`
- `syncStatus`, `dirtyFields`, `lastSyncedSnapshot`, `localUpdatedAt`, `conflictServerSnapshot`

#### LocalSyncState
- `userId`
- `lastRevisionUserShifts`: Int64
- `lastRevisionRecurringShifts`: Int64
- `lastRevisionWageSnapshots`: Int64
- `lastRevisionUserSettings`: Int64
- `lastSuccessfulSyncAt`: Date?
- `lastSyncAttemptAt`: Date?
- `lastSyncError`: String?

### Implementation Notes
- Store JSONB fields as Data containing canonical JSON with stable encoding for reliable diffs
- Define a "ServerRowSnapshot" codable per table for `lastSyncedSnapshot` and `conflictServerSnapshot`
- Define explicit field keys per model (e.g., for user_shifts: `shift_date`, `start_time`, `end_time`, `custom_supplements`)
- For JSON blobs, treat the entire blob as one field initially (whole-field diffing)

### Notes

**Completed: 2026-01-15**

**Files Created**:

1. **`Native/Storage/SyncTypes.swift`** - Common sync types and helpers:
   - `SyncStatus` enum: `clean`, `dirty`, `pendingDelete`, `conflict`
   - Field key enums for each model (`UserShiftField`, `RecurringShiftField`, etc.)
   - Canonical JSON encoder/decoder for stable encoding

2. **`Native/Storage/Models/LocalUserShift.swift`** - SwiftData model for user shifts:
   - All shift data fields plus sync metadata
   - `UserShiftServerSnapshot` codable for conflict detection
   - `changedFields(from:)` for field-level diffing
   - Conversion methods `toShiftRow()` and `from(serverRow:)`

3. **`Native/Storage/Models/LocalRecurringShift.swift`** - SwiftData model for recurring shifts:
   - JSON-encoded complex fields (selectedDays, endCondition, exclusions, dateSpecificSupplements)
   - `RecurringShiftServerSnapshot` with field-level diff support
   - Time cleaning (removes timezone suffix from timetz)

4. **`Native/Storage/Models/LocalWageSnapshot.swift`** - SwiftData model for wage snapshots:
   - All wage/tax/break settings
   - `WageSnapshotServerSnapshot` with field-level diff support
   - Baseline snapshot support (nullable fromDate)

5. **`Native/Storage/Models/LocalUserSettings.swift`** - SwiftData model for user settings:
   - Single-row-per-user (userId is unique key)
   - `UserSettingsServerSnapshot` with field-level diff support

6. **`Native/Storage/Models/LocalSyncState.swift`** - Sync state tracking:
   - Per-table revision cursors
   - Sync timestamps and error tracking
   - `SyncTable` enum for table iteration
   - `SyncReason` enum for trigger classification

**Architecture Decisions**:

1. **@Model classes with @Attribute(.unique)** - SwiftData handles uniqueness constraints
2. **Raw string storage for enums** - `syncStatusRaw` with computed `syncStatus` property for type safety
3. **Data for JSON fields** - All JSONB fields stored as `Data` with computed property accessors
4. **Canonical JSON encoding** - `sortedKeys` formatting for deterministic diffs
5. **ServerSnapshot per model** - Each model has its own snapshot type for type-safe field comparison
6. **Conversion extensions** - `toXxxRow()` methods for compatibility with existing payroll calculators

**Field-Level Diff Design**:

Each `ServerSnapshot` type implements `changedFields(from:)` that returns a `Set` of field keys:
```swift
func changedFields(from other: UserShiftServerSnapshot) -> Set<UserShiftField>
```

This enables the sync logic in Phase 4/5 to:
1. Compare `lastSyncedSnapshot` vs new server row → `serverChangedFields`
2. Check if `dirtyFields ∩ serverChangedFields = ∅` → auto-merge possible
3. If overlap → mark conflict

**Next Steps for Phase 3**:
- Create `LocalStore.swift` with ModelContainer setup
- Create repository classes that query SwiftData
- Refactor existing services to use repositories

---

## Phase 3: LocalStore & Repositories

**Status**: ✅ Complete

### Scope

Set up LocalStore container and create repositories that replace network-first services.

### Tasks

#### 3.1 Implement LocalStore container

- Create `LocalStore.swift` that sets up the ModelContainer
- Ensure container is created once and injected through app environment, not recreated per view
- Add a `LocalStoreActor` or similar serialization mechanism so writes from sync do not collide

#### 3.2 Create local-first Repositories

Existing services to refactor:
- `ShiftsService.swift`
- `SettingsService.swift`
- `SnapshotsService.swift`

Existing pattern: services fetch from Supabase, set @Published arrays.

Refactor target:
- Create repositories that query SwiftData and return local data
- Services can remain as facades but must read from SwiftData only, no Supabase calls from UI-facing services
- All Supabase calls move into SyncEngine only

### Notes

**Completed: 2026-01-15**

**Files Created**:

1. **`Native/Storage/LocalStore.swift`** - Central SwiftData container:
   - `LocalStore` singleton with shared `ModelContainer`
   - `LocalStoreActor` (`@ModelActor`) for serialized writes from sync
   - Schema includes all 5 local models
   - CRUD operations for all model types
   - Conflict and pending change detection helpers
   - `resetAllData()` for logout/debugging

2. **`Native/Storage/Repositories/ShiftsRepository.swift`** - Local-first shift access:
   - Read operations: `getShifts(for:startDate:endDate:)`, `getAllShifts(for:)`, `getShift(id:)`
   - Write operations: `createShift(...)`, `updateShift(...)`, `deleteShift(id:)`
   - Dirty field tracking for field-level sync
   - Conflict resolution: `resolveConflictKeepLocal(id:)`, `resolveConflictKeepServer(id:)`
   - Pending/conflict status queries

3. **`Native/Storage/Repositories/SettingsRepository.swift`** - Local-first settings access:
   - Read operations: `getSettings(for:)`, `getLocalSettings(for:)`
   - Write operations: `updateSettings(for:...)`, `updateLastActive(for:)`
   - Dirty field tracking per field
   - Conflict resolution methods

4. **`Native/Storage/Repositories/SnapshotsRepository.swift`** - Local-first wage snapshot access:
   - Read operations: `getSnapshots(for:)`, `getSnapshot(id:)`, `getBaselineSnapshot(for:)`
   - Date resolution: `snapshotForDate(_:userId:)`, `snapshotsForDates(_:userId:)` using binary search
   - Write operations: `createSnapshot(...)`, `updateSnapshot(...)`, `deleteSnapshot(id:)`
   - Conflict resolution methods

5. **`Native/Storage/Repositories/RecurringShiftsRepository.swift`** - Local-first recurring shift access:
   - Read operations: `getRecurringShifts(for:)`, `getRecurringShift(id:)`
   - Write operations: `createRecurringShift(...)`, `updateRecurringShift(...)`, `deleteRecurringShift(id:)`
   - Exclusion management: `addExclusion(id:date:)`
   - Conflict resolution methods

**Architecture Decisions**:

1. **Singleton Repositories** - Shared instances matching existing service pattern for easy migration
2. **@MainActor for UI reads** - Repositories are MainActor-isolated for safe SwiftUI integration
3. **Actor for writes** - `LocalStoreActor` ensures thread-safe writes during sync operations
4. **Dirty field tracking** - All write operations automatically track which fields changed
5. **Conversion methods** - Repositories return existing `*Row` types for compatibility with PayrollEngine
6. **Conflict resolution** - Both "keep local" and "keep server" resolution strategies implemented

**Data Flow Design**:

```
UI Layer (Views/ViewModels)
    ↓ reads
Repository (SwiftData queries)
    ↓ writes
LocalStoreActor (serialized)
    ↓ syncs
SyncCoordinator (Phase 4/5)
    ↓ network
Supabase
```

**Existing Services vs New Repositories**:

| Existing Service | New Repository | Migration Path |
|------------------|----------------|----------------|
| `ShiftsService` | `ShiftsRepository` | ViewModels will switch to repository for reads |
| `SettingsService` | `SettingsRepository` | ViewModels will switch to repository for reads |
| `SnapshotsService` | `SnapshotsRepository` | ViewModels will switch to repository for reads |

The existing services will continue to exist but will be deprecated once:
1. SyncCoordinator populates local store (Phase 4)
2. ViewModels switch to repositories (Phase 6)

**Next Steps for Phase 4**:
- Create `SyncCoordinator` with single-flight sync
- Implement pull logic using revision cursors
- Apply incoming rows with field-level merge logic

---

## Phase 4: SyncCoordinator (Pull)

**Status**: ⬜ Not Started

### Scope

Implement the pull phase of sync: incremental fetch by revision with paging.

### Tasks

#### 4.1 Create SyncCoordinator

Create SyncCoordinator that exposes:
- `sync(reason: SyncReason) async`
- Status publisher or observable properties for UI (syncing, last error)

Trigger points:
- On authenticated session established in AppCoordinator
- On app enters foreground (scenePhase)
- Manual refresh action from dashboard (pull-to-refresh)

Guardrails:
- Prevent concurrent sync runs (single flight)
- Add minimum interval (e.g., 60 seconds unless user triggers)

#### 4.2 Implement Pull Phase

For each table:
1. Read cursor from LocalSyncState (`lastRevisionX`)
2. Query Supabase:
   - filter `user_id = current user`
   - filter `revision > cursor`
   - order by `revision` ascending
   - limit page size (500)
   - include deleted rows (do not filter `deleted_at`)
3. Apply page results into SwiftData
4. Update cursor to max revision seen
5. Repeat until no more rows

#### 4.3 Apply Rules for Incoming Rows

- **Row does not exist locally**: Insert as clean, set `serverRevision`/`serverUpdatedAt`/`serverDeletedAt`, set `lastSyncedSnapshot` to server row
- **Row exists and is clean**: Overwrite local fields with server row, update server metadata, update `lastSyncedSnapshot`
- **Row exists and is dirty**:
  - If `serverRevision` equals local `serverRevision`: server unchanged, keep local edits
  - If `serverRevision` > local: conflict candidate, use field-level diff logic

#### 4.4 Implement Field-Level Merge

When pulling newer server version while local is dirty:
1. Compute `serverChangedFields` by diffing `lastSyncedSnapshot` vs new server row
2. If `dirtyFields` and `serverChangedFields` do not overlap → auto-merge:
   - Start from new server row as base
   - Apply local changes only for `dirtyFields`
   - Keep `syncStatus = dirty` (still needs push)
   - Update `serverRevision`/`serverUpdatedAt` to new server values
   - Update `lastSyncedSnapshot` to new server row
3. If overlap exists → mark conflict:
   - Save `conflictServerSnapshot` as new server row
   - Keep local values unchanged
   - Set `syncStatus = conflict`

### Notes
<!-- Implementation notes will be added here when phase is complete -->

---

## Phase 5: SyncCoordinator (Push & Conflicts)

**Status**: ⬜ Not Started

### Scope

Implement push phase with optimistic concurrency and conflict resolution UI.

### Tasks

#### 5.1 Implement Push Phase

Push only local objects with `syncStatus = dirty` or `syncStatus = deleted`.

**For deleted objects**:
- Perform UPDATE setting `deleted_at = now()`
- Filters: `id`, `user_id`, `revision = serverRevision`, `deleted_at is null`
- Request returning row
- If empty: fetch server row, mark conflict, store server snapshot

**For dirty objects**:
- Build update patch using `dirtyFields` only
- Perform UPDATE with filters: `id`, `user_id`, `revision = serverRevision`, `deleted_at is null`
- Request returning row
- If success:
  - Update local from returned canonical row
  - Clear `dirtyFields`
  - Set `syncStatus = clean`
  - Update `lastSyncedSnapshot`
- If empty:
  - Fetch server row by id
  - Run field-level merge logic
  - If can auto-merge: rebase and retry push once
  - If not: mark conflict

**Important**: Only one automatic retry after rebase to avoid loops.

#### 5.2 Implement Conflict UI

For objects in conflict, present two versions:
- Local version (iPhone)
- Server version (Web)

Actions:
- **Use Web version**:
  - Overwrite local with `conflictServerSnapshot`
  - Clear `dirtyFields`
  - Set `syncStatus = clean`
  - Set `lastSyncedSnapshot = conflictServerSnapshot`
  - Clear `conflictServerSnapshot`
- **Use iPhone version**:
  - Overwrite `serverRevision`/`serverUpdatedAt` to server version values
  - Keep local values and `dirtyFields`
  - Set `syncStatus = dirty`
  - Attempt push once

**No "keep both" option**.

### Notes
<!-- Implementation notes will be added here when phase is complete -->

---

## Phase 6: UI/ViewModel Refactor

**Status**: ⬜ Not Started

### Scope

Refactor UI and ViewModels to read only from local storage.

### Tasks

#### 6.1 Refactor DashboardViewModel and DashboardView

Current behavior:
- `loadDashboard` triggers network fetches via services and caches month results

Target behavior:
- `loadDashboard` reads from local repositories only
- Manual refresh triggers `SyncCoordinator.sync()`, then reloads local computed data
- Remove or reduce in-memory month cache initially (reintroduce later if needed with invalidation on local store changes)

#### 6.2 Add AppCoordinator Triggers

- After authentication, trigger sync immediately in background
- On foreground, trigger sync with interval guard

#### 6.3 Remove Direct Supabase Usage

- Ensure no view model calls `ShiftsService.fetchShifts` (network) anymore
- Networking remains only inside SyncEngine

### Notes
<!-- Implementation notes will be added here when phase is complete -->

---

## Phase 7: Widget Integration

**Status**: ⬜ Not Started

### Scope

Update widget data source to be fed from native local store.

### Current State
- `OfflineShiftStorage.swift` writes `StoredShift` array to App Group UserDefaults
- Currently written by WebView, not native

### Tasks

#### 7.1 Add Native Widget Writer

When `LocalUserShift` changes materially:
1. Query relevant upcoming shifts from SwiftData
2. Write simplified `StoredShift` payload into App Group UserDefaults
3. Trigger `WidgetCenter.shared.reloadAllTimelines()`

#### 7.2 Gradual Migration

- Do not remove `OfflineShiftStorage` immediately if other code depends on it
- Add new writer path from native
- Gradually retire WebView writer later

### Notes
<!-- Implementation notes will be added here when phase is complete -->

---

## Phase 8: Testing & Validation

**Status**: ⬜ Not Started

### Scope

Execute test plan to validate offline-first functionality.

### Test Cases

#### 8.1 Local-only UI Validation
- Launch app with airplane mode after at least one successful sync
- Confirm dashboard shows shifts and wage data from local store

#### 8.2 Offline Edits Then Sync
- Edit a shift locally offline
- Confirm it is marked pending/dirty
- Reconnect, trigger sync
- Confirm server updates and local becomes clean

#### 8.3 Conflict Scenario with Field-Level Merge
- Baseline: sync clean
- Change shift on web (change `end_time`)
- Offline on iOS, change `custom_supplements` only
- Sync iOS: Should auto-merge (no overlap) and push without conflict UI

#### 8.4 Conflict Scenario with Overlapping Fields
- Change shift on web (change `end_time`)
- Offline on iOS, also change `end_time`
- Sync iOS: Should mark conflict
- Verify "Use Web" and "Use iPhone" paths behave correctly

#### 8.5 Soft Delete Sync
- Delete shift on web (`deleted_at` set)
- Sync iOS:
  - Shift should disappear from normal UI reads
  - Local should store deleted state, not resurrect it

#### 8.6 Wage Snapshot Edits and Conflicts
- Repeat conflict tests with `wage_snapshots` (since they are mutable)

### Final Reporting Requirements

When complete, document:
1. All DB migrations applied and their filenames
2. All new iOS files created and key files modified
3. Final data flow in one short sequence:
   - UI read path (local only)
   - Sync pull path
   - Sync push path
   - Conflict resolution path
4. 5-10 log line examples showing sync progress and conflict detection (no sensitive data)

### Notes
<!-- Implementation notes will be added here when phase is complete -->

---

## Implementation Recommendations

- Use SwiftData (iOS 18+)
- Store JSONB fields as Data containing canonical JSON with stable encoding for reliable diffs
- Define a single "ServerRowSnapshot" codable per table for `lastSyncedSnapshot` and `conflictServerSnapshot`
- Page size for pull: 500 (conservative, loop per table to avoid memory spikes)
- Always keep sync single-flight and serialized

## No Server Infrastructure Required

Direct Supabase queries work because:
- Pull uses revision cursors and simple filters
- Push uses optimistic concurrency by filtering revision and checking returned row
- Conflict handling fetches server row by id when needed

**Optional future improvement**: Add Supabase RPCs for bulk sync performance (not required for first implementation)
