# iOS Patterns & Best Practices

## Service Pattern

### Data Services (Supabase Fetching)

Services fetch from Supabase and publish state via @Published properties.

```swift
@MainActor
final class ShiftsService: ObservableObject {
    static let shared = ShiftsService()
    
    @Published private(set) var shifts: [ShiftRow] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    private init() {}
    
    func fetchShifts(for userId: String, startDate: String, endDate: String) async throws -> [ShiftRow] {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let response: [ShiftRow] = try await supabase
                .from("user_shifts")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value
            
            shifts = response
            return response
        } catch {
            self.error = error
            throw error
        }
    }
}
```

**Key Points**:
- Singleton pattern: `static let shared`
- @MainActor for thread safety
- @Published for reactive updates
- Error handling with defer for cleanup
- Async/await for network calls

### Repository Pattern (Local-First)

Repositories provide local-first data access with dirty tracking.

```swift
@MainActor
final class ShiftsRepository: ObservableObject {
    static let shared = ShiftsRepository()
    private let localStore: LocalStore
    
    private init(localStore: LocalStore? = nil) {
        self.localStore = localStore ?? LocalStore.shared
    }
    
    // Read operations (local only)
    func getShifts(for userId: String) -> [ShiftRow] {
        let context = localStore.mainContext
        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { $0.userId == userId && $0.serverDeletedAt == nil }
        )
        return try? context.fetch(descriptor).map { $0.toShiftRow() } ?? []
    }
    
    // Write operations (local with dirty tracking)
    func createShift(userId: String, shiftDate: Date, startTime: String, endTime: String) async throws -> ShiftRow {
        let created = try await localStore.storeActor.createUserShift(
            userId: userId,
            shiftDate: shiftDate,
            startTime: startTime,
            endTime: endTime
        )
        return created.toShiftRow()
    }
}
```

**Key Points**:
- Dependency injection: `localStore` parameter for testing
- Read operations: Synchronous, from SwiftData
- Write operations: Async, mark records as dirty
- No network calls (handled by SyncCoordinator)

## View Model Pattern

### Basic View Model Structure

```swift
@MainActor
final class MyFeatureViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let repository: MyRepository
    private let syncCoordinator: SyncCoordinator
    
    // MARK: - Published State
    @Published var data: [Item] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    // MARK: - Private State
    private var loadTask: Task<Void, Never>?
    
    // MARK: - Initialization
    init(
        repository: MyRepository? = nil,
        syncCoordinator: SyncCoordinator? = nil
    ) {
        self.repository = repository ?? MyRepository.shared
        self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
    }
    
    deinit {
        loadTask?.cancel()
    }
    
    // MARK: - Public Methods
    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            data = try await repository.fetchData()
            error = nil
        } catch {
            self.error = error
        }
    }
    
    // MARK: - User Actions
    func deleteItem(_ id: String) async {
        do {
            try await repository.deleteItem(id)
            data.removeAll { $0.id == id }
        } catch {
            self.error = error
        }
    }
}
```

**Key Points**:
- @MainActor for UI thread safety
- Dependency injection in init for testability
- Task cancellation in deinit
- Defer for cleanup (isLoading = false)
- Error handling with @Published error property

### Month Navigation Pattern (DashboardViewModel)

```swift
@MainActor
final class DashboardViewModel: ObservableObject, MonthNavigable {
    
    @Published private(set) var displayYear: Int
    @Published private(set) var displayMonth: Int
    @Published private(set) var navigationDirection: MonthNavigationDirection?
    
    private var monthCache: [String: MonthCacheEntry] = [:]
    private var prefetchTasks: [String: Task<Void, Never>] = [:]
    
    func navigateToMonth(_ year: Int, _ month: Int) async {
        let direction: MonthNavigationDirection = month > displayMonth ? .forward : .backward
        displayYear = year
        displayMonth = month
        navigationDirection = direction
        
        await loadDashboardForDisplayedMonth(showLoadingState: true)
        prefetchNeighboringMonths()
    }
    
    private func loadDashboardForDisplayedMonth(showLoadingState: Bool) async {
        let cacheKey = "\(displayYear)-\(displayMonth)"
        
        // Check cache
        if let cached = monthCache[cacheKey], cached.isValid {
            dashboardData = computeDashboardData(from: cached.shifts)
            return
        }
        
        // Load from repositories
        if showLoadingState { isLoading = true }
        defer { isLoading = false }
        
        let shifts = shiftsRepository.getShifts(for: userId)
        let computed = PayrollEngine.computeShiftsForMonth(
            year: displayYear,
            month: displayMonth,
            shifts: shifts,
            recurring: recurringShiftsRepository.getRecurringShifts(for: userId),
            snapshots: snapshotsRepository.getSnapshots(for: userId),
            settings: settingsRepository.getSettings(for: userId)
        )
        
        // Cache and display
        monthCache[cacheKey] = MonthCacheEntry(year: displayYear, month: displayMonth, shifts: computed, timestamp: Date())
        dashboardData = computeDashboardData(from: computed)
    }
    
    private func prefetchNeighboringMonths() {
        let nextMonth = (displayMonth % 12) + 1
        let nextYear = displayMonth == 12 ? displayYear + 1 : displayYear
        
        prefetchTasks["\(nextYear)-\(nextMonth)"] = Task {
            await loadDashboardForDisplayedMonth(showLoadingState: false)
        }
    }
}
```

**Key Points**:
- Cache with TTL (5 minutes)
- Background prefetching of neighbors
- Task cancellation on navigation
- Stale task detection (check displayYear/Month)

## Sync Coordination Pattern

### Triggering Sync

```swift
// Manual refresh
await syncCoordinator.sync(reason: .manualRefresh, userId: userId)

// Automatic on foreground
.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
    Task {
        await syncCoordinator.sync(reason: .appForeground, userId: userId)
    }
}

// After authentication
await syncCoordinator.sync(reason: .postAuth, userId: userId)
```

### Listening to Sync State

```swift
@ObservedObject private var syncCoordinator = SyncCoordinator.shared

var body: some View {
    VStack {
        if syncCoordinator.isSyncing {
            ProgressView()
        }
        
        if let error = syncCoordinator.lastError {
            Text("Sync failed: \(error)")
        }
    }
}
```

## Error Handling Pattern

```swift
enum MyError: Error, LocalizedError {
    case notFound
    case networkError(underlying: Error)
    case validationFailed(field: String)
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Item not found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .validationFailed(let field):
            return "Validation failed for \(field)"
        }
    }
}
```

## Testing Pattern

```swift
func testLoadData() async {
    let mockRepository = MockRepository()
    let viewModel = MyFeatureViewModel(repository: mockRepository)
    
    await viewModel.loadData()
    
    XCTAssertEqual(viewModel.data.count, 1)
    XCTAssertNil(viewModel.error)
}
```

