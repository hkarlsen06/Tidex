# iOS App Documentation

## Quick Start

The iOS app is a native SwiftUI application for tracking work shifts and calculating wages. It uses a **local-first, sync-based architecture** with Supabase as the backend.

**Key Technologies**:
- SwiftUI for UI
- SwiftData for local storage
- Supabase for backend & sync
- Combine for reactive updates

## Documentation Files

### [ARCHITECTURE.md](docs/ARCHITECTURE.md)
High-level overview of the app structure, directory layout, and core patterns:
- AppCoordinator (auth state & navigation)
- View Models (UI state management)
- Repositories (local-first data access)
- SyncCoordinator (bidirectional sync)
- Payroll calculation system

**Read this first** to understand how the app is organized.

### [DATA_FLOW.md](docs/DATA_FLOW.md)
Complete data flow from UI to Supabase and back:
- Overall data architecture diagram
- Sync flow (pull → conflict detection → push)
- Sync triggers (manual, foreground, post-auth)
- Data consistency guarantees
- Payroll computation flow
- Snapshot resolution
- Dirty tracking
- Testing sync

**Reference this** when debugging data issues or understanding sync behavior.

### [PAYROLL_SYSTEM.md](docs/PAYROLL_SYSTEM.md)
Detailed payroll computation system:
- PayrollCalculator (single shift)
- PayrollEngine (monthly aggregation)
- SnapshotsService (snapshot resolution)
- WageSnapshot & SupplementRule models
- Wage period breakdown
- Break deduction (fixed vs proportional)
- Conflict exclusion
- Testing payroll

**Use this** when working on wage calculations or snapshot logic.

## Architecture at a Glance

```
Views (SwiftUI)
    ↓ Observed properties
View Models (@MainActor, @Observable)
    ↓ Read/Write operations
Repositories (Local-First)
    ↓ Fetch/Update
LocalStore (SwiftData)
    ↓ Bidirectional sync
SyncCoordinator (Singleton)
    ↓ Network calls
Supabase (Server)
```

## Key Concepts

### Local-First
- All reads from SwiftData (fast, offline)
- All writes mark records as dirty
- SyncCoordinator pushes dirty records to server
- Enables offline support

### Singleton Services
- AppCoordinator: Auth state & navigation
- SyncCoordinator: Bidirectional sync
- Repositories: Data access
- Services: Supabase fetching

### @MainActor
- All UI-related code runs on main thread
- Thread-safe reactive updates
- Prevents race conditions

### Dirty Tracking
- Records marked dirty/clean for incremental sync
- Only dirty fields sent in PATCH requests
- Reduces bandwidth and conflict surface

### Conflict Resolution
- Field-level merge (not row-level)
- Auto-merge when possible
- User resolution when needed
- Snapshots for merge detection

### Snapshot-Based Configuration
- Wage settings versioned by date
- Tax settings versioned by date
- Binary search for applicable snapshot
- Fallback to baseline snapshot

## Common Tasks

### Adding a New Feature

1. Create feature directory: `Features/MyFeature/`
2. Create view model: `MyFeatureViewModel.swift`
3. Create repository (if needed): `Storage/Repositories/MyRepository.swift`
4. Create view: `MyFeatureView.swift`
5. Follow existing patterns in the codebase

### Debugging Sync Issues

1. Check SyncCoordinator state: `syncCoordinator.isSyncing`, `lastError`
2. Review sync flow in [DATA_FLOW.md](DATA_FLOW.md)
3. Check dirty tracking: `getPendingShifts()`, `syncStatus`
4. Look for conflicts: `conflictCount`, `resolveConflict*()`

### Modifying Payroll Logic

1. Review [PAYROLL_SYSTEM.md](PAYROLL_SYSTEM.md)
2. Update PayrollCalculator or PayrollEngine
3. Ensure consistency with the shared backend payroll implementation in `supabase/functions/_shared/payroll`
4. Test with property-based tests

### Adding a New Repository

1. Create file: `Storage/Repositories/MyRepository.swift`
2. Implement read operations (sync, from SwiftData)
3. Implement write operations (async, mark dirty)
4. Accept optional LocalStore for testing

## Testing

### Unit Tests
```swift
func testLoadData() async {
    let mockRepository = MockRepository()
    let viewModel = MyFeatureViewModel(repository: mockRepository)
    
    await viewModel.loadData()
    
    XCTAssertEqual(viewModel.data.count, 1)
}
```

### Sync Tests
```swift
let result = await syncCoordinator.sync(reason: .manualRefresh, userId: userId)
XCTAssertTrue(result.success)
XCTAssertEqual(result.totalRowsProcessed, 10)
```

### Payroll Tests
```swift
let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)
XCTAssertEqual(computed.gross, expectedGross)
```

## Performance Tips

1. **Caching**: View models cache computed data (5-minute TTL)
2. **Prefetching**: Dashboard prefetches neighboring months
3. **Lazy Loading**: Load data on-demand, not upfront
4. **Batch Saves**: SyncCoordinator saves in batches during pull
5. **Binary Search**: SnapshotsService uses binary search for O(log n) lookup

## Troubleshooting

### Sync not working
- Check network connectivity
- Verify Supabase credentials in APIConfiguration
- Check SyncCoordinator.lastError
- Review sync flow in [DATA_FLOW.md](DATA_FLOW.md)

### Stale data
- Check monthCache TTL (5 minutes)
- Verify repositories are reading from localStore.mainContext
- Check if sync completed successfully

### Payroll calculations wrong
- Verify snapshot is correct (check from_date)
- Check break deduction settings
- Compare with the shared backend payroll calculation
- Review [PAYROLL_SYSTEM.md](PAYROLL_SYSTEM.md)

### Conflicts not resolving
- Check conflict detection logic
- Verify lastSyncedSnapshot is set
- Try manual resolution: `resolveConflictKeepLocal()`
- Review conflict resolution in [DATA_FLOW.md](DATA_FLOW.md)

## Documentation Index

| Document | Purpose | Audience |
|----------|---------|----------|
| [README.md](README.md) | Overview & quick start | Everyone |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design & structure | Architects, senior devs |
| [docs/DATA_FLOW.md](docs/DATA_FLOW.md) | Data flow & sync system | Backend devs, debuggers |
| [docs/PAYROLL_SYSTEM.md](docs/PAYROLL_SYSTEM.md) | Wage calculation system | Payroll feature devs |
| [docs/LOCALIZATION.md](docs/LOCALIZATION.md) | Localization & adding languages | All developers |

## Related Documentation

- [../AGENTS.md](../AGENTS.md) - Project instructions for coding agents
- [../docs/](../docs/) - Shared documentation (payroll spec, notifications, DB schema)
- [../marketing/](../marketing/) - Public/legal website code
