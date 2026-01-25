# iOS App Architecture

## Overview

The iOS app uses a **local-first, sync-based architecture** with clear separation of concerns. Data is stored locally in SwiftData, synced bidirectionally with Supabase, and computed on-demand for display.

## Directory Structure

```
Native/
├── Core/                    # App-wide coordination
│   ├── AppCoordinator       # Central auth state & navigation (singleton)
│   └── RootView             # Root navigation based on auth state
├── Features/                # Feature-specific screens & view models
│   ├── Auth/                # Login, signup, MFA, password reset
│   ├── Dashboard/           # Main dashboard with month navigation
│   ├── AddShift/            # Shift creation/editing
│   ├── Shifts/              # Shift list views
│   ├── Stats/               # Statistics & analytics
│   └── Onboarding/          # Pre & post-auth onboarding
├── Services/                # Business logic & data operations
│   ├── Auth/                # Authentication operations
│   ├── Data/                # Supabase data fetching (ShiftsService, SnapshotsService)
│   ├── Network/             # API configuration & Supabase client
│   └── Payroll/             # Wage calculations (PayrollCalculator, PayrollEngine)
├── Storage/                 # Local data persistence
│   ├── LocalStore           # SwiftData container & actor
│   ├── Models/              # SwiftData model definitions
│   ├── Repositories/        # Local-first data access (ShiftsRepository, etc.)
│   └── Sync/                # Bidirectional sync (SyncCoordinator)
├── Models/                  # Data models (Codable)
└── Shared/                  # Reusable components & utilities
```

## Core Patterns

### 1. AppCoordinator (Singleton)

**Purpose**: Central source of truth for authentication state and app-wide navigation.

**Key Responsibilities**:
- Listens to Supabase auth events
- Manages app state: loading → unauthenticated → mfaRequired → termsRequired → authenticated
- Triggers SyncCoordinator after authentication
- Provides user profile data (userId, displayName, avatarUrl)

**Usage**:
```swift
@ObservedObject private var coordinator = AppCoordinator.shared
// Access: coordinator.appState, coordinator.userId, coordinator.userDisplayName
```

### 2. View Models (@MainActor, ObservableObject)

**Pattern**: Each feature has a dedicated view model that:
- Depends on repositories (local-first data access)
- Publishes UI state via @Published properties
- Handles user interactions and async operations
- Caches computed data to avoid redundant calculations

**Example - DashboardViewModel**:
- Dependencies: ShiftsRepository, SettingsRepository, SnapshotsRepository, SyncCoordinator
- Published state: dashboardData, isLoading, error, displayYear, displayMonth
- Caching: monthCache (5-minute TTL) for computed shifts
- Prefetching: Loads neighboring months in background

### 3. Repositories (Local-First)

**Pattern**: All data reads come from SwiftData; network calls handled by SyncCoordinator.

**Available Repositories**:
- `ShiftsRepository`: User shifts with dirty tracking
- `SettingsRepository`: User settings (payroll day, currency, tax)
- `SnapshotsRepository`: Wage snapshots for payroll
- `RecurringShiftsRepository`: Recurring shift patterns

**Key Methods**:
- Read: `getShifts()`, `getSettings()`, `getSnapshots()`
- Write: `createShift()`, `updateShift()`, `deleteShift()`
- Conflict: `resolveConflictKeepLocal()`, `resolveConflictKeepServer()`

### 4. SyncCoordinator (Singleton)

**Purpose**: Bidirectional sync between local SwiftData and Supabase.

**Sync Flow**:
1. **Pull Phase**: Fetch latest server state for all tables
2. **Conflict Detection**: Field-level merge with auto-merge capability
3. **Push Phase**: Send dirty records to server
4. **Cleanup**: Mark synced records as clean

**Sync Triggers**:
- Manual refresh (user-initiated)
- App foreground (automatic)
- After authentication (initial sync)
- Minimum interval: 30 seconds between auto-syncs

### 5. Payroll Calculation

**Architecture**: Pure, deterministic computation with snapshot-based configuration.

**Key Components**:
- `PayrollCalculator.computeShift()`: Single shift computation
- `PayrollEngine.computeShiftsForMonth()`: Monthly aggregation with tax
- `SnapshotsService.snapshotForDate()`: Binary search for applicable snapshot

**Snapshot System**:
- Wage snapshot (shift date): Determines hourly rate & supplements
- Tax snapshot (payout date): Determines tax settings
- Baseline snapshot (from_date == nil): Fallback if no dated snapshot

## Data Flow

### Authentication Flow
1. User logs in via AuthService
2. AppCoordinator listens to Supabase auth events
3. On successful auth: AppCoordinator triggers SyncCoordinator
4. SyncCoordinator pulls all data from Supabase
5. Repositories read from local SwiftData
6. View models display data from repositories

### Shift Creation Flow
1. User enters shift details in AddShiftViewModel
2. ViewModel calls ShiftsRepository.createShift()
3. Repository creates LocalUserShift marked as "dirty"
4. ViewModel notifies via Notification.shiftsDidChange
5. SyncCoordinator detects dirty record and pushes to server
6. Server returns updated record with serverRevision
7. Repository marks record as "clean"

### Month Navigation
1. User navigates to different month in DashboardViewModel
2. ViewModel checks monthCache (5-minute TTL)
3. If cached: Return immediately
4. If not cached: Load from repositories, compute via PayrollEngine
5. Background: Prefetch neighboring months

## Key Design Decisions

1. **Local-First**: All reads from SwiftData, network calls only for sync
2. **Singleton Services**: AppCoordinator, SyncCoordinator, repositories are singletons
3. **@MainActor**: All UI-related code runs on main thread
4. **Dirty Tracking**: Records marked dirty/clean for incremental sync
5. **Conflict Resolution**: Field-level merge with auto-merge capability
6. **Snapshot-Based Config**: Wage/tax settings versioned by date
7. **Caching**: View models cache computed data with TTL
8. **Notifications**: Cross-feature communication via Notification.Name

## Testing Patterns

- Repositories accept optional LocalStore for dependency injection
- View models accept optional services for testing
- SyncCoordinator has testable sync result tracking
- PayrollCalculator is pure function (no side effects)

