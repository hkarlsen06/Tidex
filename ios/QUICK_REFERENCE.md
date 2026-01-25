# iOS Quick Reference

## Directory Structure

```
Native/
├── Core/                          # App-wide coordination
│   ├── AppCoordinator.swift       # Auth state & navigation
│   └── RootView.swift             # Root navigation
├── Features/                      # Feature screens & view models
│   ├── Auth/                      # Login, signup, MFA
│   ├── Dashboard/                 # Main dashboard
│   ├── AddShift/                  # Shift creation
│   ├── Shifts/                    # Shift list
│   ├── Stats/                     # Statistics
│   └── Onboarding/                # Onboarding flow
├── Services/                      # Business logic
│   ├── Auth/AuthService.swift     # Auth operations
│   ├── Data/ShiftsService.swift   # Supabase fetching
│   ├── Data/SnapshotsService.swift
│   ├── Network/SupabaseClient.swift
│   └── Payroll/PayrollCalculator.swift
├── Storage/                       # Local persistence
│   ├── LocalStore.swift           # SwiftData container
│   ├── Models/                    # SwiftData models
│   ├── Repositories/              # Local-first access
│   │   ├── ShiftsRepository.swift
│   │   ├── SettingsRepository.swift
│   │   ├── SnapshotsRepository.swift
│   │   └── RecurringShiftsRepository.swift
│   └── Sync/SyncCoordinator.swift # Bidirectional sync
├── Models/                        # Data models (Codable)
├── Localization/                  # i18n
└── Shared/                        # Reusable components
```

## Key Classes

| Class | Purpose | Pattern |
|-------|---------|---------|
| `AppCoordinator` | Auth state & navigation | Singleton, @MainActor |
| `DashboardViewModel` | Dashboard UI state | @MainActor, ObservableObject |
| `ShiftsRepository` | Local shift access | Singleton, @MainActor |
| `SyncCoordinator` | Bidirectional sync | Singleton, @MainActor |
| `PayrollCalculator` | Single shift computation | Pure function |
| `PayrollEngine` | Monthly aggregation | Pure function |
| `SnapshotsService` | Snapshot resolution | Singleton, @MainActor |
| `LocalStore` | SwiftData container | Singleton, @MainActor |

## Common Patterns

### View Model Template
```swift
@MainActor
final class MyViewModel: ObservableObject {
    private let repository: MyRepository
    @Published var data: [Item] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    init(repository: MyRepository? = nil) {
        self.repository = repository ?? MyRepository.shared
    }
    
    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            data = try await repository.fetchData()
        } catch {
            self.error = error
        }
    }
}
```

### Repository Template
```swift
@MainActor
final class MyRepository: ObservableObject {
    static let shared = MyRepository()
    private let localStore: LocalStore
    
    private init(localStore: LocalStore? = nil) {
        self.localStore = localStore ?? LocalStore.shared
    }
    
    func getItems(for userId: String) -> [Item] {
        let context = localStore.mainContext
        let descriptor = FetchDescriptor<LocalItem>(
            predicate: #Predicate { $0.userId == userId }
        )
        return (try? context.fetch(descriptor)) ?? []
    }
    
    func createItem(_ item: Item) async throws {
        try await localStore.storeActor.createItem(item)
    }
}
```

## Data Flow

```
View
  ↓ @Published
ViewModel
  ↓ Read/Write
Repository
  ↓ Fetch/Update
LocalStore (SwiftData)
  ↓ Sync
SyncCoordinator
  ↓ Network
Supabase
```

## Sync Flow

```
Pull Phase:
  For each table:
    1. Query server (updated_at > cursor)
    2. Detect conflicts (field-level merge)
    3. Insert/update local records
    4. Update cursor

Push Phase:
  For each table:
    1. Find dirty records
    2. Send PATCH/INSERT/DELETE
    3. Mark as clean
    4. Handle conflicts
```

## Payroll Computation

```
PayrollCalculator.computeShift(shift, snapshot)
  1. Resolve base rate
  2. Resolve supplement rules
  3. Build wage periods
  4. Apply break deduction
  5. Calculate paid hours
  6. Calculate pay (round to 2 decimals)
  → ShiftComputed

PayrollEngine.computeShiftsForMonth(...)
  1. Generate virtual shifts from recurring
  2. For each shift:
     - Find wage snapshot (shift date)
     - Find tax snapshot (payout date)
     - Compute via PayrollCalculator
     - Apply tax
  → [ShiftWithComputations]
```

## Sync Triggers

| Trigger | Interval Guard | Reason |
|---------|---|---|
| Manual refresh | None | User-initiated |
| App foreground | 30 seconds | Automatic |
| Post-auth | None | Initial sync |
| Shift changes | None | Notification-based |

## Dirty Tracking

| Status | Meaning | Action |
|--------|---------|--------|
| `clean` | Synced, no changes | Skip in push |
| `dirty` | Local changes | Send PATCH |
| `pendingDelete` | Marked for deletion | Send soft delete |
| `conflict` | Both sides changed | Require resolution |

## Snapshot Resolution

```
SnapshotsService.snapshotForDate(date, snapshots)
  1. Find baseline (from_date == nil)
  2. Binary search dated snapshots
  3. Return latest where from_date <= date
  4. Fallback to baseline
  → WageSnapshot?
```

## Testing Checklist

- [ ] Mock repositories in view model tests
- [ ] Test sync with mock Supabase client
- [ ] Test payroll with known inputs/outputs
- [ ] Test conflict resolution scenarios
- [ ] Test offline behavior (no network)
- [ ] Test month navigation caching
- [ ] Test dirty tracking on updates

## Performance Tips

1. **Cache**: monthCache (5-minute TTL)
2. **Prefetch**: Load neighboring months
3. **Lazy Load**: Load on-demand
4. **Batch Save**: SyncCoordinator saves in batches
5. **Binary Search**: O(log n) snapshot lookup

## Debugging Commands

```swift
// Check sync state
print(SyncCoordinator.shared.isSyncing)
print(SyncCoordinator.shared.lastError)

// Check dirty records
let pending = ShiftsRepository.shared.getPendingShifts(for: userId)
print("Pending shifts: \(pending.count)")

// Check conflicts
print("Conflicts: \(SyncCoordinator.shared.conflictCount)")

// Manual sync
await SyncCoordinator.shared.sync(reason: .manualRefresh, userId: userId)

// Reset local data
await LocalStore.shared.resetAllData()
```

## Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Stale data | Cache TTL | Wait 5 min or refresh |
| Sync not working | Network | Check connectivity |
| Conflicts | Both sides changed | Use resolveConflict* |
| Wrong payroll | Wrong snapshot | Check from_date |
| Slow month nav | No cache | Prefetch neighbors |

## Related Files

- [ARCHITECTURE.md](ARCHITECTURE.md) - Full architecture
- [PATTERNS.md](PATTERNS.md) - Code patterns
- [DATA_FLOW.md](DATA_FLOW.md) - Data flow details
- [PAYROLL_SYSTEM.md](PAYROLL_SYSTEM.md) - Payroll details
- [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md) - Why decisions

