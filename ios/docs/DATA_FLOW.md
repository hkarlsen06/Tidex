# iOS Data Flow & Synchronization

## Overall Data Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        SwiftUI Views                         │
│                   (DashboardView, ShiftListView)             │
└────────────────────────┬────────────────────────────────────┘
                         │ @Published properties
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    View Models (@MainActor)                  │
│         (DashboardViewModel, ShiftsListViewModel)            │
│  - Manage UI state (@Published)                              │
│  - Handle user interactions                                  │
│  - Cache computed data                                       │
└────────────────────────┬────────────────────────────────────┘
                         │ Read/Write operations
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Repositories (Local-First)                      │
│    (ShiftsRepository, SettingsRepository, etc.)              │
│  - All reads from SwiftData (synchronous)                    │
│  - All writes mark records as dirty                          │
│  - No network calls                                          │
└────────────────────────┬────────────────────────────────────┘
                         │ Fetch/Update
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              LocalStore (SwiftData)                          │
│  - Persistent local storage                                  │
│  - Models: LocalUserShift, LocalRecurringShift, etc.         │
│  - Dirty tracking: syncStatus (clean/dirty/pendingDelete)    │
│  - Conflict tracking: lastSyncedSnapshot, serverRevision     │
└────────────────────────┬────────────────────────────────────┘
                         │ Bidirectional sync
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              SyncCoordinator (Singleton)                     │
│  - Pulls latest server state                                 │
│  - Detects conflicts (field-level merge)                     │
│  - Pushes dirty records                                      │
│  - Manages sync state & errors                               │
└────────────────────────┬────────────────────────────────────┘
                         │ Network calls
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Supabase (Server)                         │
│  - user_shifts, recurring_shifts, wage_snapshots, etc.       │
│  - Revision tracking for conflict detection                  │
│  - Soft deletes (deleted_at column)                          │
└─────────────────────────────────────────────────────────────┘
```

## Sync Flow (Detailed)

### Phase 1: Pull (Get Latest Server State)

```
For each table (user_shifts, recurring_shifts, wage_snapshots, user_settings):
  1. Get cursor from LocalSyncState (last updated_at)
  2. Query server: SELECT * WHERE updated_at > cursor
  3. For each row:
     a. Check if exists locally
     b. If exists & clean: Overwrite with server data
     c. If exists & dirty: Detect conflict
        - If server unchanged: Keep local edits
        - If server changed: Field-level merge
        - If merge fails: Mark as conflict
     d. If not exists: Insert as new clean row
  4. Update cursor in LocalSyncState
```

### Phase 2: Push (Send Dirty Records)

```
For each table:
  1. Query local: SELECT * WHERE syncStatus IN (dirty, pendingDelete)
  2. For each dirty record:
     a. If pendingDelete: Soft delete (UPDATE deleted_at = now())
     b. If new (serverRevision == 0): INSERT
     c. If updated: PATCH with only dirty fields
  3. Server returns updated record with new serverRevision
  4. Mark record as clean in local storage
  5. If conflict: Mark as conflict, don't mark clean
```

### Conflict Resolution

**Field-Level Merge**:
- Compare server row with lastSyncedSnapshot
- Identify which fields changed on server
- Keep local edits for fields not changed on server
- Conflict only if both local and server changed same field

**Auto-Merge**:
- If merge succeeds: Rebase local record and retry push
- If merge fails: Mark as conflict, require user resolution

**User Resolution**:
- `resolveConflictKeepLocal()`: Mark dirty, retry push
- `resolveConflictKeepServer()`: Overwrite with server data

## Sync Triggers

### Manual Refresh
```swift
await syncCoordinator.sync(reason: .manualRefresh, userId: userId)
```
- User pulls to refresh
- No interval guard (always executes)

### App Foreground
```swift
.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
    Task {
        await syncCoordinator.sync(reason: .appForeground, userId: userId)
    }
}
```
- Minimum interval: 30 seconds
- Skipped if last sync was recent

### Post-Authentication
```swift
// In AppCoordinator after successful login
await syncCoordinator.sync(reason: .postAuth, userId: userId)
```
- Initial sync after login
- No interval guard

### Shift Changes
```swift
// In ShiftsRepository after creating/updating shift
NotificationCenter.default.post(name: Notification.Name.shiftsDidChange, object: nil)

// In view model
.onReceive(NotificationCenter.default.publisher(for: Notification.Name.shiftsDidChange)) { _ in
    Task { await loadDashboard() }
}
```
- Notification-based, not automatic sync
- View models refresh from local repositories

## Data Consistency Guarantees

### Optimistic Updates
- Write to local storage immediately
- Mark as dirty
- Push to server asynchronously
- If push fails: Conflict resolution

### Offline Support
- All reads work offline (from SwiftData)
- All writes work offline (marked dirty)
- Sync happens when network available

### Conflict Detection
- Server revision tracking
- Field-level snapshots
- Automatic merge when possible
- User resolution when needed

## Payroll Computation Flow

```
View Model requests dashboard data
  ↓
Load from repositories:
  - shifts: ShiftsRepository.getShifts()
  - recurring: RecurringShiftsRepository.getRecurringShifts()
  - snapshots: SnapshotsRepository.getSnapshots()
  - settings: SettingsRepository.getSettings()
  ↓
PayrollEngine.computeShiftsForMonth():
  1. Generate virtual shifts from recurring patterns
  2. Combine with regular shifts
  3. For each shift:
     a. Find wage snapshot (shift date)
     b. Find tax snapshot (payout date)
     c. PayrollCalculator.computeShift()
     d. Apply tax settings
  4. Calculate monthly totals
  5. Return [ShiftWithComputations]
  ↓
Cache in monthCache (5-minute TTL)
  ↓
Display in view
```

## Snapshot Resolution

**Binary Search** for applicable snapshot:
```swift
// Find latest snapshot where from_date <= target_date
let applicable = SnapshotsService.snapshotForDate(date, from: snapshots)
```

**Fallback Chain**:
1. Dated snapshot (from_date <= target_date)
2. Baseline snapshot (from_date == nil)
3. Hardcoded defaults

## Dirty Tracking

**Sync Status Values**:
- `clean`: Synced with server, no local changes
- `dirty`: Local changes, needs push
- `pendingDelete`: Marked for deletion, needs soft delete
- `conflict`: Server and local both changed same field

**Dirty Field Tracking**:
- Each model tracks which fields are dirty
- Only dirty fields sent in PATCH request
- Reduces bandwidth and conflict surface

## Testing Sync

```swift
// Mock repository for testing
let mockRepository = MockShiftsRepository()
mockRepository.shifts = [testShift]

let viewModel = DashboardViewModel(shiftsRepository: mockRepository)
await viewModel.loadDashboard()

XCTAssertEqual(viewModel.dashboardData?.currentMonthShiftCount, 1)
```

