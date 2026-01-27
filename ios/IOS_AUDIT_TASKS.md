# iOS Core App Audit - Task List

This document contains all issues identified during the iOS core app audit, organized by priority in descending order. Each task is self-contained with all context needed to implement the fix.

**Instructions for Claude:** When referencing this document, find the first task with `Status: PENDING` and implement the fix. After completing the fix, update the status to `DONE` and commit the changes with a descriptive message.

---

## CRITICAL PRIORITY

---

---

### TASK-002: Implement Token Refresh Lock to Prevent Concurrent Refresh Race Condition

**Status:** DONE (2026-01-27)

**Severity:** CRITICAL - Causes "Refresh Token Not Found" errors

**Location:**
- `ios/App/TidexApp/Native/Services/Network/SupabaseClient.swift`

**Problem:**
The Supabase SDK is configured with `autoRefreshToken: true`, but there's no serialization mechanism for concurrent refresh attempts. When multiple views/services call `supabase.auth.session` simultaneously, they can trigger concurrent refresh attempts.

**Race Condition Scenario:**
1. Request A checks session, token is expired, triggers refresh
2. Request B checks session simultaneously, also triggers refresh
3. Request A completes refresh, gets new tokens, OLD refresh token is invalidated
4. Request B tries to refresh with the OLD token (now invalid)
5. Request B fails with "Refresh Token Not Found"

**Why This Happens:**
- Supabase invalidates the refresh token after use (one-time use)
- Multiple concurrent requests can all see the expired access token
- All trigger refresh simultaneously before any completes
- Only the first succeeds; others fail

**Impact:** Users experience authentication failures, forced logouts, or app crashes during high-concurrency scenarios (app launch, foreground return, multiple simultaneous data fetches).

**Recommended Fix:**
Implement a refresh lock similar to the web app's `withRefreshLock()` pattern:

```swift
// Create a new file: ios/App/TidexApp/Native/Services/Auth/TokenRefreshLock.swift

import Foundation

@MainActor
final class TokenRefreshLock {
    static let shared = TokenRefreshLock()

    private var refreshTask: Task<Void, Error>?
    private var isRefreshing = false

    private init() {}

    /// Executes the given async operation, ensuring only one refresh happens at a time.
    /// If a refresh is already in progress, waits for it to complete.
    func withLock<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        // If a refresh is in progress, wait for it
        if let existingTask = refreshTask {
            _ = try? await existingTask.value
        }

        return try await operation()
    }

    /// Call this when starting a token refresh
    func beginRefresh() async throws {
        guard !isRefreshing else {
            // Wait for existing refresh
            if let task = refreshTask {
                try await task.value
            }
            return
        }

        isRefreshing = true
        refreshTask = Task {
            defer {
                isRefreshing = false
                refreshTask = nil
            }
            // The actual refresh is handled by Supabase SDK
            // This just provides the lock mechanism
        }
    }
}
```

**Alternative Approach:**
Wrap all session access through a single point that handles refresh serialization:

```swift
// Add to SupabaseClient.swift or create AuthSessionManager.swift

@MainActor
final class AuthSessionManager {
    static let shared = AuthSessionManager()

    private var refreshTask: Task<Session, Error>?

    func getSession() async throws -> Session {
        // If refresh is in progress, wait for it
        if let task = refreshTask {
            return try await task.value
        }

        let session = try await supabase.auth.session

        // Check if token needs refresh (within 60 seconds of expiry)
        if session.expiresAt < Date().addingTimeInterval(60) {
            return try await refreshSession()
        }

        return session
    }

    private func refreshSession() async throws -> Session {
        if let task = refreshTask {
            return try await task.value
        }

        let task = Task<Session, Error> {
            defer { refreshTask = nil }
            return try await supabase.auth.refreshSession()
        }

        refreshTask = task
        return try await task.value
    }
}
```

**Files to Create/Modify:**
- Create `ios/App/TidexApp/Native/Services/Auth/AuthSessionManager.swift`
- Update services that access `supabase.auth.session` to use the new manager

**Testing:**
- Simulate multiple concurrent API calls on app launch
- Test returning from background with expired token
- Test rapid navigation between views that fetch data
- Verify no "Refresh Token Not Found" errors occur

**Commit Message Format:** `fix(ios): implement token refresh lock to prevent concurrent refresh race condition`

---

### TASK-003: Alert User When LocalStore Falls Back to In-Memory Storage

**Status:** DONE (2026-01-27)

**Severity:** CRITICAL - Silent data loss

**Location:**
- `ios/App/TidexApp/Native/Storage/LocalStore.swift` lines 56-82

**Problem:**
If persistent storage initialization fails, the app silently falls back to in-memory storage:

```swift
do {
    container = try ModelContainer(for: schema, configurations: [configuration])
} catch {
    // Fallback to in-memory
    let fallbackConfig = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true
    )
    container = try ModelContainer(for: schema, configurations: [fallbackConfig])
}
```

**Why This Is Dangerous:**
- User thinks their data is being saved
- All data is lost when app is terminated
- No indication to user that anything is wrong
- Could happen due to disk space, permissions, corruption

**Impact:** Complete data loss without user awareness. User creates shifts, closes app, all data is gone.

**Recommended Fix:**

1. Track whether we're in fallback mode:
```swift
@MainActor
final class LocalStore {
    static let shared = LocalStore()

    let container: ModelContainer
    let isUsingInMemoryFallback: Bool  // ADD THIS

    private init() {
        // ... existing code ...

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            isUsingInMemoryFallback = false
        } catch {
            logger.error("Failed to create persistent store: \(error). Using in-memory fallback.")
            let fallbackConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
            container = try! ModelContainer(for: schema, configurations: [fallbackConfig])
            isUsingInMemoryFallback = true
        }
    }
}
```

2. Show alert to user in RootView or AppCoordinator:
```swift
// In RootView.swift or appropriate location
.onAppear {
    if LocalStore.shared.isUsingInMemoryFallback {
        // Show alert or banner warning user
        showStorageWarning = true
    }
}

// Alert content:
// Title: "Storage Issue"
// Message: "Unable to save data to device storage. Your changes will not be saved when the app closes. Please restart the app or check device storage."
```

3. Optionally log to analytics for monitoring

**Files to Modify:**
- `ios/App/TidexApp/Native/Storage/LocalStore.swift`
- `ios/App/TidexApp/Native/Core/RootView.swift` (to show alert)

**Testing:**
- Simulate storage failure (can be done by making storage directory read-only in debug)
- Verify alert is shown to user
- Verify app still functions in fallback mode
- Verify normal operation when storage works

**Commit Message Format:** `fix(ios): alert user when LocalStore falls back to in-memory storage`

---

### TASK-004: Add CSRF State Parameter Validation to OAuth Callback Processing

**Status:** DONE (2026-01-27)

**Severity:** CRITICAL - Security vulnerability

**Location:**
- `ios/App/TidexApp/Native/Features/Settings/Security/SecuritySettingsViewModel.swift` lines 273-308

**Problem:**
The app accepts tokens directly from OAuth callbacks without validating their origin:

```swift
if let accessToken = allParams["access_token"],
   let refreshToken = allParams["refresh_token"] {
    try await supabase.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
}
```

**Security Issues:**
1. No state parameter validation (CSRF protection missing)
2. No nonce validation (replay attack protection missing)
3. Direct token acceptance from URL parameters
4. Callback URL scheme (`tidex://auth/callback`) could be registered by malicious apps

**Attack Scenarios:**
- CSRF: Attacker links their OAuth account to victim's Tidex account
- Replay: Attacker captures and replays old OAuth callbacks
- URL scheme hijacking: Malicious app intercepts callbacks

**Recommended Fix:**

1. Generate and store a state parameter before OAuth flow:
```swift
// Before starting OAuth flow
let state = UUID().uuidString
UserDefaults.standard.set(state, forKey: "oauth_state")

// Add state to OAuth URL
queryItems.append(URLQueryItem(name: "state", value: state))
```

2. Validate state parameter in callback:
```swift
func handleOAuthCallback(_ url: URL) async throws {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let queryItems = components.queryItems else {
        throw AuthError.invalidCallback
    }

    let params = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
        item.value.map { (item.name, $0) }
    })

    // VALIDATE STATE PARAMETER
    guard let returnedState = params["state"],
          let savedState = UserDefaults.standard.string(forKey: "oauth_state"),
          returnedState == savedState else {
        UserDefaults.standard.removeObject(forKey: "oauth_state")
        throw AuthError.stateMismatch
    }

    // Clear state after validation
    UserDefaults.standard.removeObject(forKey: "oauth_state")

    // Now safe to process tokens
    if let accessToken = params["access_token"],
       let refreshToken = params["refresh_token"] {
        try await supabase.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
    }
}
```

3. Add state parameter to OAuthWebAuthSession:
```swift
// In OAuthWebAuthSession.swift
func startIdentityLinking(..., state: String) {
    // Include state in the OAuth URL
}
```

**Files to Modify:**
- `ios/App/TidexApp/Native/Features/Settings/Security/SecuritySettingsViewModel.swift`
- `ios/App/TidexApp/Native/Services/Auth/OAuthWebAuthSession.swift`

**Testing:**
- Test OAuth flow with valid state - should succeed
- Test OAuth flow with missing state - should fail
- Test OAuth flow with wrong state - should fail
- Test replay of old callback URL - should fail

**Commit Message Format:** `fix(ios): add CSRF state parameter validation to OAuth callback processing`

---

## HIGH PRIORITY

---

### TASK-005: Fix ScreenshotNotificationService Cooldown Race Condition

**Status:** DONE (2026-01-27)

**Severity:** HIGH - Race condition causes duplicate notifications

**Location:**
- `ios/App/TidexApp/Native/Services/Notification/ScreenshotNotificationService.swift` lines 31-68

**Problem:**
The cooldown timestamp is updated AFTER the async network call completes:

```swift
func reportScreenshot(sharerId: String) async throws {
    if let lastReported = lastReportedTimestamps[sharerId] {
        let elapsed = Date().timeIntervalSince(lastReported)
        if elapsed < cooldownInterval {
            return  // Early return
        }
    }
    // ... network call ...
    lastReportedTimestamps[sharerId] = Date()  // Updated AFTER async
}
```

**Race Condition Scenario:**
1. Call A checks cooldown (passes), starts network call
2. Call B checks cooldown (passes because A hasn't updated yet), starts network call
3. Both complete and update timestamp
4. Result: Two notifications sent within cooldown period

**Recommended Fix:**
Update timestamp BEFORE the network call, or use an "in-flight" set:

```swift
private var lastReportedTimestamps: [String: Date] = [:]
private var inFlightRequests: Set<String> = []  // ADD THIS

func reportScreenshot(sharerId: String) async throws {
    // Check if request is already in flight
    guard !inFlightRequests.contains(sharerId) else {
        return
    }

    // Check cooldown
    if let lastReported = lastReportedTimestamps[sharerId] {
        let elapsed = Date().timeIntervalSince(lastReported)
        if elapsed < cooldownInterval {
            return
        }
    }

    // Mark as in-flight BEFORE async operation
    inFlightRequests.insert(sharerId)
    defer { inFlightRequests.remove(sharerId) }

    // Update timestamp BEFORE network call to prevent races
    lastReportedTimestamps[sharerId] = Date()

    do {
        // ... network call ...
    } catch {
        // On failure, remove timestamp so retry is possible
        lastReportedTimestamps.removeValue(forKey: sharerId)
        throw error
    }
}
```

**Files to Modify:**
- `ios/App/TidexApp/Native/Services/Notification/ScreenshotNotificationService.swift`

**Testing:**
- Rapidly trigger multiple screenshot reports for same sharer
- Verify only one network request is made within cooldown period
- Verify cooldown resets properly after period expires

**Commit Message Format:** `fix(ios): fix ScreenshotNotificationService cooldown race condition`

---

### TASK-006: Add Atomic Sync State Management to SyncCoordinator

**Status:** DONE (2026-01-27)

**Severity:** HIGH - Race condition can cause duplicate syncs and data corruption

**Location:**
- `ios/App/TidexApp/Native/Storage/Sync/SyncCoordinator.swift` lines 95-129

**Problem:**
The check-then-set pattern for `syncInProgress` is not atomic:

```swift
guard !syncInProgress else { return }  // Check
// ... gap where another sync could start ...
syncInProgress = true                   // Set
```

Additionally, `lastAutoSyncAt` is updated at the END of sync, leaving a window for duplicate syncs.

**Recommended Fix:**

Option 1 - Use a dedicated sync state manager:
```swift
@MainActor
final class SyncCoordinator: ObservableObject {
    // Replace separate flags with enum
    private enum SyncState {
        case idle
        case syncing(userId: String, startedAt: Date)
    }

    private var syncState: SyncState = .idle

    func sync(reason: SyncReason, userId: String) async -> SyncResult {
        // Atomic check-and-set
        switch syncState {
        case .syncing:
            return SyncResult(status: .skipped, message: "Sync already in progress")
        case .idle:
            break
        }

        // Check interval BEFORE changing state
        if reason != .manualRefresh && reason != .localChange && reason != .watchRefresh {
            if let lastAuto = lastAutoSyncAt,
               Date().timeIntervalSince(lastAuto) < minimumSyncInterval {
                return SyncResult(status: .skipped, message: "Too soon since last sync")
            }
        }

        // Update state atomically - timestamp IMMEDIATELY to prevent races
        syncState = .syncing(userId: userId, startedAt: Date())
        if reason == .foreground || reason == .appLaunch {
            lastAutoSyncAt = Date()  // Update BEFORE sync, not after
        }
        isSyncing = true

        defer {
            syncState = .idle
            isSyncing = false
        }

        // ... rest of sync logic ...
    }
}
```

Option 2 - Use actor isolation (preferred for true thread safety):
```swift
// Create a separate actor for sync state
actor SyncStateManager {
    private var currentSync: (userId: String, startedAt: Date)?
    private var lastAutoSyncAt: Date?
    private let minimumInterval: TimeInterval = 30

    func tryStartSync(userId: String, reason: SyncReason) -> Bool {
        guard currentSync == nil else { return false }

        if reason != .manualRefresh && reason != .localChange {
            if let last = lastAutoSyncAt,
               Date().timeIntervalSince(last) < minimumInterval {
                return false
            }
        }

        currentSync = (userId, Date())
        if reason == .foreground || reason == .appLaunch {
            lastAutoSyncAt = Date()
        }
        return true
    }

    func endSync() {
        currentSync = nil
    }
}
```

**Files to Modify:**
- `ios/App/TidexApp/Native/Storage/Sync/SyncCoordinator.swift`

**Testing:**
- Trigger multiple sync calls rapidly (app launch + foreground + manual)
- Verify only one sync executes at a time
- Verify interval check prevents rapid auto-syncs
- Verify manual refresh bypasses interval check

**Commit Message Format:** `fix(ios): add atomic sync state management to SyncCoordinator`

---

### TASK-007: Fix AppCoordinator Auth State Initialization Race Condition

**Status:** DONE (2026-01-27)

**Severity:** HIGH - Can cause duplicate MFA screens and state inconsistency

**Location:**
- `ios/App/TidexApp/Native/Core/AppCoordinator.swift` lines 121-146

**Problem:**
There's a race between the auth state listener and the timeout fallback:

```swift
private func setupInitialSessionCheck() {
    Task { [weak self] in
        try? await Task.sleep(nanoseconds: Self.initialSessionTimeout)  // 0.5 seconds

        if self.appState == .loading && !self.didReceiveInitialSession {
            await self.performInitialSessionCheck()  // Could race with listener
        }
    }
}
```

**Race Condition Scenario:**
1. Timeout fires, `appState` is still `.loading`
2. Auth listener emits `.initialSession` simultaneously
3. Both call `checkMFAAndUpdateState()` concurrently
4. State becomes inconsistent (duplicate MFA screens, etc.)

**Recommended Fix:**

1. Store and cancel the timeout task when initial session is received:
```swift
private var initialSessionTimeoutTask: Task<Void, Never>?

private func setupInitialSessionCheck() {
    initialSessionTimeoutTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: Self.initialSessionTimeout)

        guard let self = self,
              !Task.isCancelled,  // Check cancellation
              self.appState == .loading,
              !self.didReceiveInitialSession else {
            return
        }

        await self.performInitialSessionCheck()
    }
}

private func handleInitialSession(_ session: Session?) async {
    // Cancel timeout since we got the session
    initialSessionTimeoutTask?.cancel()
    initialSessionTimeoutTask = nil

    didReceiveInitialSession = true

    if session != nil {
        await checkMFAAndUpdateState()
    } else {
        appState = .unauthenticated
    }
}
```

2. Add synchronization to prevent concurrent state updates:
```swift
private var isUpdatingAuthState = false

private func checkMFAAndUpdateState() async {
    guard !isUpdatingAuthState else { return }
    isUpdatingAuthState = true
    defer { isUpdatingAuthState = false }

    // ... existing MFA check logic ...
}
```

**Files to Modify:**
- `ios/App/TidexApp/Native/Core/AppCoordinator.swift`

**Testing:**
- Test app launch with valid session
- Test app launch with expired session
- Test app launch with no session
- Test slow network where auth state takes time
- Verify no duplicate MFA screens ever appear

**Commit Message Format:** `fix(ios): fix AppCoordinator auth state initialization race condition`

---

### TASK-008: Add Synchronization to Keychain Access Operations

**Status:** PENDING

**Severity:** HIGH - Race condition can corrupt session data

**Location:**
- `ios/App/TidexApp/Native/Services/Network/SupabaseClient.swift` lines 26-67

**Problem:**
The `KeychainLocalStorage` implementation has no synchronization for concurrent access:

```swift
func store(key: String, value: Data) throws {
    let query: [String: Any] = [...]
    SecItemDelete(query as CFDictionary)  // Delete
    // ... gap where another thread could read/write ...
    let status = SecItemAdd(newItem as CFDictionary, nil)  // Add
}
```

**TOCTOU Vulnerability:**
- Thread A: Delete old token
- Thread B: Try to retrieve token (gets nil or corrupted data)
- Thread A: Add new token

**Recommended Fix:**
Use a serial DispatchQueue to serialize Keychain access:

```swift
final class KeychainLocalStorage: AuthLocalStorage {
    private let keychainQueue = DispatchQueue(label: "com.tidex.keychain", qos: .userInitiated)

    func store(key: String, value: Data) throws {
        try keychainQueue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.tidex.supabase",
                kSecAttrAccount as String: key
            ]

            SecItemDelete(query as CFDictionary)

            var newItem = query
            newItem[kSecValueData as String] = value
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            let status = SecItemAdd(newItem as CFDictionary, nil)

            guard status == errSecSuccess else {
                throw KeychainError.unhandledError(status: status)
            }
        }
    }

    func retrieve(key: String) throws -> Data? {
        try keychainQueue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.tidex.supabase",
                kSecAttrAccount as String: key,
                kSecReturnData as String: true
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            switch status {
            case errSecSuccess:
                return result as? Data
            case errSecItemNotFound:
                return nil
            default:
                throw KeychainError.unhandledError(status: status)
            }
        }
    }

    func remove(key: String) throws {
        try keychainQueue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.tidex.supabase",
                kSecAttrAccount as String: key
            ]

            let status = SecItemDelete(query as CFDictionary)

            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unhandledError(status: status)
            }
        }
    }
}

enum KeychainError: Error {
    case unhandledError(status: OSStatus)
}
```

**Files to Modify:**
- `ios/App/TidexApp/Native/Services/Network/SupabaseClient.swift`

**Testing:**
- Test concurrent login/logout operations
- Test concurrent token refresh
- Test app with multiple background refresh scenarios
- Verify no keychain errors occur under concurrent access

**Commit Message Format:** `fix(ios): add synchronization to Keychain access operations`

---

### TASK-009: Add deinit Cleanup to StatsViewModel for Combine Subscriptions

**Status:** PENDING

**Severity:** HIGH - Memory leak from accumulated subscriptions

**Location:**
- `ios/App/TidexApp/Native/Features/Stats/StatsViewModel.swift` lines 56-73

**Problem:**
The ViewModel subscribes to `monthContext.monthChanged` but has no `deinit` to clean up:

```swift
private var cancellables = Set<AnyCancellable>()

private func setupMonthSubscription() {
    monthContext.monthChanged
        .receive(on: DispatchQueue.main)
        .sink { [weak self] year, month in
            // ...
        }
        .store(in: &cancellables)
}
// NO deinit!
```

**Why This Is a Problem:**
- Subscriptions persist even after ViewModel is deallocated
- `[weak self]` prevents retain cycle but subscription itself remains active
- Memory accumulates if ViewModels are created/destroyed frequently

**Recommended Fix:**
Add explicit deinit with cleanup:

```swift
@MainActor
final class StatsViewModel: ObservableObject {
    // ... existing properties ...

    private var cancellables = Set<AnyCancellable>()

    deinit {
        cancellables.removeAll()
        // Note: This explicitly cancels all subscriptions
    }

    // ... rest of implementation ...
}
```

**Also Apply This Pattern To:**
This same fix should be applied to ALL ViewModels with Combine subscriptions:
- `DashboardViewModel.swift`
- `ShiftsViewModel.swift`
- `SharingViewModel.swift`
- Any other ViewModel with `AnyCancellable` storage

**Files to Modify:**
- `ios/App/TidexApp/Native/Features/Stats/StatsViewModel.swift`
- `ios/App/TidexApp/Native/Features/Dashboard/DashboardViewModel.swift`
- `ios/App/TidexApp/Native/Features/Shifts/ShiftsViewModel.swift`
- `ios/App/TidexApp/Native/Features/Sharing/SharingViewModel.swift`

**Testing:**
- Navigate to Stats view multiple times
- Monitor memory usage - should not continuously increase
- Use Instruments to verify no leaked subscriptions

**Commit Message Format:** `fix(ios): add deinit cleanup to ViewModels with Combine subscriptions`

---

### TASK-010: Track and Cancel Background Tasks in AppCoordinator

**Status:** PENDING

**Severity:** HIGH - Untracked tasks can mutate state after deallocation

**Location:**
- `ios/App/TidexApp/Native/Core/AppCoordinator.swift` lines 272-284

**Problem:**
Background tasks are created but never stored:

```swift
private func checkTermsVersionInBackground(termsAcceptedAt: String?) {
    Task { [weak self] in  // NOT STORED - can't be cancelled
        let needsReAcceptance = await TermsVersion.needsTermsReAcceptanceAsync(termsAcceptedAt)
        guard let self = self else { return }
        if needsReAcceptance && self.appState == .authenticated {
            self.isTermsUpdate = termsAcceptedAt != nil
            self.appState = .termsRequired
        }
    }
}
```

**Why This Is a Problem:**
- Task continues running even if user signs out
- Can update state after coordinator is deallocated
- No way to cancel on sign out or app termination

**Recommended Fix:**
Store all background tasks and cancel them appropriately:

```swift
@MainActor
final class AppCoordinator: ObservableObject {
    // ... existing properties ...

    private var backgroundTasks: [Task<Void, Never>] = []

    private func checkTermsVersionInBackground(termsAcceptedAt: String?) {
        let task = Task { [weak self] in
            let needsReAcceptance = await TermsVersion.needsTermsReAcceptanceAsync(termsAcceptedAt)
            guard let self = self, !Task.isCancelled else { return }
            if needsReAcceptance && self.appState == .authenticated {
                self.isTermsUpdate = termsAcceptedAt != nil
                self.appState = .termsRequired
            }
        }
        backgroundTasks.append(task)
    }

    /// Call this when signing out or when coordinator is being deallocated
    private func cancelAllBackgroundTasks() {
        backgroundTasks.forEach { $0.cancel() }
        backgroundTasks.removeAll()
    }

    func signOut() async {
        cancelAllBackgroundTasks()
        // ... existing sign out logic ...
    }

    deinit {
        // Note: Can't call cancelAllBackgroundTasks() directly in deinit
        // because it's @MainActor isolated. Tasks will be cancelled
        // when their weak self references become nil.
    }
}
```

**Alternative - Use a TaskGroup:**
```swift
private var backgroundTaskGroup: Task<Void, Never>?

private func runBackgroundChecks(termsAcceptedAt: String?) {
    backgroundTaskGroup?.cancel()
    backgroundTaskGroup = Task {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                // Terms check
                let needsReAcceptance = await TermsVersion.needsTermsReAcceptanceAsync(termsAcceptedAt)
                guard let self = self, !Task.isCancelled else { return }
                // ... update state ...
            }
            // Add other background tasks here
        }
    }
}
```

**Files to Modify:**
- `ios/App/TidexApp/Native/Core/AppCoordinator.swift`

**Testing:**
- Sign in, then immediately sign out
- Verify no state updates occur after sign out
- Verify no crashes from deallocated references

**Commit Message Format:** `fix(ios): track and cancel background tasks in AppCoordinator`

---

### TASK-011: Add deinit Cleanup to PaySettingsViewModel for Debounce Tasks

**Status:** PENDING

**Severity:** HIGH - Orphaned tasks continue running after deallocation

**Location:**
- `ios/App/TidexApp/Native/Features/Settings/Pay/PaySettingsViewModel.swift` lines 74-75

**Problem:**
Tasks are stored but there's no deinit to cancel them:

```swift
private var monthlyGoalSaveTask: Task<Void, Never>?
private var payrollDaySaveTask: Task<Void, Never>?
// NO deinit!
```

**Why This Is a Problem:**
- If user navigates away while debounce timer is running, task continues
- Task may try to save data for wrong context
- Wasted CPU and potential state corruption

**Recommended Fix:**
Add deinit with task cancellation:

```swift
@MainActor
final class PaySettingsViewModel: ObservableObject {
    // ... existing properties ...

    private var monthlyGoalSaveTask: Task<Void, Never>?
    private var payrollDaySaveTask: Task<Void, Never>?

    deinit {
        monthlyGoalSaveTask?.cancel()
        payrollDaySaveTask?.cancel()
    }

    // ... rest of implementation ...
}
```

**Also Check These ViewModels:**
Apply the same pattern to any ViewModel with stored Tasks:
- `AddShiftViewModel.swift` (has `previewUpdateTask`, `draftSaveTask`)
- `DashboardViewModel.swift` (has `activeNavigationTask`)
- Any other ViewModel with `Task` properties

**Files to Modify:**
- `ios/App/TidexApp/Native/Features/Settings/Pay/PaySettingsViewModel.swift`
- `ios/App/TidexApp/Native/Features/AddShift/AddShiftViewModel.swift`
- `ios/App/TidexApp/Native/Features/Dashboard/DashboardViewModel.swift`

**Testing:**
- Open pay settings, change values rapidly
- Navigate away before debounce completes
- Verify no saves occur after navigation
- Monitor for any crashes or unexpected behavior

**Commit Message Format:** `fix(ios): add deinit cleanup to ViewModels with stored Tasks`

---

### TASK-012: Fix Silent Dirty Fields Decode Failure in UserShift Model

**Status:** PENDING

**Severity:** HIGH - Silent data loss when dirty fields are corrupted

**Location:**
- UserShift model (find exact file - likely in `ios/App/TidexApp/Native/Models/` or similar)

**Problem:**
When decoding dirty fields fails, an empty set is returned silently:

```swift
var dirtyFieldKeys: Set<UserShiftField> {
    get {
        guard let keys = try? syncJSONDecoder.decode([String].self, from: dirtyFields) else {
            return []  // Silent failure - returns empty set
        }
        return Set(keys.compactMap { UserShiftField(rawValue: $0) })
    }
}
```

**Why This Is Dangerous:**
- If `dirtyFields` data is corrupted, returns empty set
- Record appears clean even though it has local changes
- Changes are never pushed to server
- Local edits are silently discarded on next sync

**Recommended Fix:**

Option 1 - Log and track corruption:
```swift
var dirtyFieldKeys: Set<UserShiftField> {
    get {
        guard let data = dirtyFields, !data.isEmpty else {
            return []
        }

        do {
            let keys = try syncJSONDecoder.decode([String].self, from: data)
            return Set(keys.compactMap { UserShiftField(rawValue: $0) })
        } catch {
            // Log corruption for debugging
            logger.error("Failed to decode dirtyFields for shift \(self.id): \(error)")

            // Mark for investigation - don't silently discard
            // Option: Set a flag or add to corruption tracking
            return []
        }
    }
}
```

Option 2 - Treat decode failure as "all fields dirty" (safer):
```swift
var dirtyFieldKeys: Set<UserShiftField> {
    get {
        guard let data = dirtyFields, !data.isEmpty else {
            return []
        }

        do {
            let keys = try syncJSONDecoder.decode([String].self, from: data)
            return Set(keys.compactMap { UserShiftField(rawValue: $0) })
        } catch {
            logger.error("Corrupted dirtyFields for shift \(self.id), treating as fully dirty")
            // Return all fields as dirty to ensure data is pushed
            return Set(UserShiftField.allCases)
        }
    }
}
```

Option 3 - Add validation on write:
```swift
mutating func setDirtyFields(_ fields: Set<UserShiftField>) {
    let keys = fields.map { $0.rawValue }
    do {
        dirtyFields = try syncJSONEncoder.encode(keys)
    } catch {
        logger.error("Failed to encode dirtyFields: \(error)")
        // Fallback: store as simple comma-separated string
        dirtyFields = Data(keys.joined(separator: ",").utf8)
    }
}
```

**Files to Modify:**
- Find and modify the UserShift model file
- Likely `ios/App/TidexApp/Native/Models/UserShift.swift` or similar

**Testing:**
- Corrupt dirty fields data manually in debug
- Verify appropriate logging occurs
- Verify data is not silently lost
- Test normal operation unaffected

**Commit Message Format:** `fix(ios): handle dirty fields decode failure gracefully in UserShift model`

---

### TASK-013: Prevent Empty API Response from Deleting Cached Shared Shifts

**Status:** PENDING

**Severity:** HIGH - Data loss when API returns empty array

**Location:**
- `ios/App/TidexApp/Native/Storage/LocalStoreActor.swift` or similar (shared shifts caching logic)

**Problem:**
When saving shared shifts, the entire month's cache is replaced:

```swift
// Delete existing shifts for this owner/viewer/month
for existing in try modelContext.fetch(descriptor) {
    modelContext.delete(existing)
}
// Insert new shifts
for shift in shifts {
    modelContext.insert(shift)
}
try modelContext.save()
```

**Why This Is Dangerous:**
- If API returns empty array due to error, all cached data is deleted
- User loses all shared shifts for that month
- No way to recover without network

**Recommended Fix:**

Option 1 - Don't delete if new data is empty (with flag to force):
```swift
func saveSharedShifts(_ shifts: [SharedShift], forMonth month: YearMonth, ownerId: String, forceReplace: Bool = false) throws {
    // Fetch existing
    let descriptor = FetchDescriptor<SharedShift>(
        predicate: #Predicate { $0.ownerId == ownerId && $0.month == month.string }
    )
    let existing = try modelContext.fetch(descriptor)

    // Don't delete existing data if new data is empty (unless forced)
    if shifts.isEmpty && !existing.isEmpty && !forceReplace {
        logger.warning("API returned empty shifts for \(month), keeping cached data")
        return
    }

    // Proceed with replacement
    for item in existing {
        modelContext.delete(item)
    }
    for shift in shifts {
        modelContext.insert(shift)
    }
    try modelContext.save()
}
```

Option 2 - Add validation before replacing:
```swift
func saveSharedShifts(_ shifts: [SharedShift], forMonth month: YearMonth, ownerId: String, isValidResponse: Bool) throws {
    guard isValidResponse else {
        logger.warning("Invalid API response for shared shifts, not updating cache")
        return
    }

    // ... existing logic ...
}
```

Option 3 - Track API response status:
```swift
struct SharedShiftsResponse {
    let shifts: [SharedShift]
    let isSuccess: Bool
    let errorMessage: String?
}

func saveSharedShifts(_ response: SharedShiftsResponse, forMonth month: YearMonth, ownerId: String) throws {
    guard response.isSuccess else {
        logger.warning("API error for shared shifts: \(response.errorMessage ?? "unknown")")
        return  // Keep existing cache
    }

    // ... proceed with save ...
}
```

**Files to Modify:**
- Find the shared shifts caching logic (likely in LocalStoreActor or SharingService)
- `ios/App/TidexApp/Native/Storage/LocalStoreActor.swift`
- `ios/App/TidexApp/Native/Services/Data/SharingService.swift`

**Testing:**
- Mock API to return empty array
- Verify existing cached data is preserved
- Verify normal operation with valid empty response works
- Test forced replacement when needed

**Commit Message Format:** `fix(ios): prevent empty API response from deleting cached shared shifts`

---

## MEDIUM PRIORITY

---

### TASK-014: Fix AddShiftViewModel Task Cascade on Rapid Property Changes

**Status:** PENDING

**Severity:** MEDIUM - Performance issue and potential stale data

**Location:**
- `ios/App/TidexApp/Native/Features/AddShift/AddShiftViewModel.swift` lines 53-97

**Problem:**
Multiple `@Published` properties with `didSet` observers trigger Tasks without proper cancellation:

```swift
@Published var startTime: Date? = nil {
    didSet {
        schedulePreviewUpdate()  // Creates Task
        publishStateToCoordinator()
        scheduleDraftSave()  // Creates Task
    }
}
```

When user rapidly changes times (typing in fields), this creates cascading Tasks that may not be properly cancelled.

**Recommended Fix:**
Ensure previous tasks are cancelled before creating new ones:

```swift
private var previewUpdateTask: Task<Void, Never>?
private var draftSaveTask: Task<Void, Never>?

private func schedulePreviewUpdate() {
    previewUpdateTask?.cancel()  // Cancel existing
    previewUpdateTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: Self.previewDebounceDelay)
        guard !Task.isCancelled, let self = self else { return }
        await self.updatePreview()
    }
}

private func scheduleDraftSave() {
    draftSaveTask?.cancel()  // Cancel existing
    draftSaveTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: Self.draftSaveDebounceDelay)
        guard !Task.isCancelled, let self = self else { return }
        await self.saveDraft()
    }
}
```

**Files to Modify:**
- `ios/App/TidexApp/Native/Features/AddShift/AddShiftViewModel.swift`

**Testing:**
- Rapidly change start/end times
- Verify only one preview update and one draft save occur
- Verify final values are correct

**Commit Message Format:** `fix(ios): fix AddShiftViewModel task cascade on rapid property changes`

---

### TASK-015: Use Task.checkCancellation() Instead of Task.isCancelled in DashboardViewModel

**Status:** PENDING

**Severity:** MEDIUM - Ineffective cancellation handling

**Location:**
- `ios/App/TidexApp/Native/Features/Dashboard/DashboardViewModel.swift` lines 335-362

**Problem:**
The code checks `Task.isCancelled` but this is unreliable:

```swift
guard !Task.isCancelled,
      self.displayYear == targetYear,
      self.displayMonth == targetMonth else {
    return
}

await self.loadDashboardForDisplayedMonth(showLoadingState: false)

guard !Task.isCancelled else { return }  // Task could be cancelled BETWEEN check and next line
```

**Why This Is a Problem:**
- A Task can be cancelled between the check and the next line
- The `await` call doesn't automatically propagate cancellation
- Stale data may be displayed or operations continue unnecessarily

**Recommended Fix:**
Use `try Task.checkCancellation()` which throws if cancelled:

```swift
activeNavigationTask = Task { [weak self] in
    guard let self = self else { return }

    do {
        try Task.checkCancellation()

        guard self.displayYear == targetYear,
              self.displayMonth == targetMonth else {
            logger.info("Skipping stale fetch")
            return
        }

        await self.loadDashboardForDisplayedMonth(showLoadingState: false)

        try Task.checkCancellation()

        self.prefetchNeighboringMonths()
    } catch is CancellationError {
        logger.info("Navigation task was cancelled")
    } catch {
        logger.error("Navigation task failed: \(error)")
    }
}
```

**Files to Modify:**
- `ios/App/TidexApp/Native/Features/Dashboard/DashboardViewModel.swift`

**Testing:**
- Navigate months rapidly
- Verify cancelled tasks actually stop
- Verify correct month data is displayed

**Commit Message Format:** `fix(ios): use Task.checkCancellation() in DashboardViewModel for proper cancellation handling`

---

### TASK-016: Add Task Cancellation to Data Services on View Dismissal

**Status:** PENDING

**Severity:** MEDIUM - Resource waste from orphaned network requests

**Location:**
- `ios/App/TidexApp/Native/Services/Data/ShiftsService.swift`
- `ios/App/TidexApp/Native/Services/Data/SharingService.swift`
- `ios/App/TidexApp/Native/Services/Data/SettingsService.swift`

**Problem:**
Data services don't store or cancel tasks when views are dismissed:

```swift
func fetchShifts(...) async throws -> [Shift] {
    // Task is not stored - can't be cancelled if view is dismissed
    let result = try await supabase.from("shifts")...
    return result
}
```

**Why This Is a Problem:**
- Network requests continue even after user navigates away
- Wastes bandwidth and battery
- Response data is discarded anyway

**Recommended Fix:**
Option 1 - Store current task for cancellation:
```swift
@MainActor
final class ShiftsService {
    private var currentFetchTask: Task<[Shift], Error>?

    func fetchShifts(...) async throws -> [Shift] {
        // Cancel any existing fetch
        currentFetchTask?.cancel()

        let task = Task<[Shift], Error> {
            try Task.checkCancellation()
            let result = try await supabase.from("shifts")...
            try Task.checkCancellation()
            return result
        }

        currentFetchTask = task
        return try await task.value
    }

    func cancelCurrentFetch() {
        currentFetchTask?.cancel()
        currentFetchTask = nil
    }
}
```

Option 2 - Use withTaskCancellationHandler:
```swift
func fetchShifts(...) async throws -> [Shift] {
    try await withTaskCancellationHandler {
        // Actual fetch logic
        let result = try await supabase.from("shifts")...
        return result
    } onCancel: {
        // Could log or cleanup here
        logger.info("Shifts fetch was cancelled")
    }
}
```

**Files to Modify:**
- `ios/App/TidexApp/Native/Services/Data/ShiftsService.swift`
- `ios/App/TidexApp/Native/Services/Data/SharingService.swift`
- `ios/App/TidexApp/Native/Services/Data/SettingsService.swift`

**Testing:**
- Start data fetch, navigate away immediately
- Verify request is cancelled (check network activity)
- Verify no errors or warnings logged

**Commit Message Format:** `fix(ios): add task cancellation to data services`

---

### TASK-017: Consolidate URLSession Instances into Shared Factory

**Status:** PENDING

**Severity:** MEDIUM - Resource waste from multiple connection pools

**Location:**
- `ios/App/TidexApp/Native/Services/Data/SharingService.swift`
- `ios/App/TidexApp/Native/Services/Notification/ScreenshotNotificationService.swift`
- `ios/App/TidexApp/Native/Features/Settings/Data/DataSettingsViewModel.swift`

**Problem:**
Each service creates its own URLSession with custom configurations:

```swift
// SharingService
let config = URLSessionConfiguration.default
config.timeoutIntervalForRequest = 30
config.timeoutIntervalForResource = 60
self.urlSession = URLSession(configuration: config)

// ScreenshotNotificationService
config.timeoutIntervalForRequest = 15
self.urlSession = URLSession(configuration: config)

// DataSettingsViewModel
config.timeoutIntervalForRequest = 60
config.timeoutIntervalForResource = 120
```

**Why This Is a Problem:**
- Multiple connection pools waste resources
- Inconsistent timeout handling
- URLSession is designed to be reused

**Recommended Fix:**
Create a shared URLSession factory:

```swift
// Create: ios/App/TidexApp/Native/Services/Network/URLSessionFactory.swift

import Foundation

enum URLSessionFactory {
    /// Standard session for most API calls (30s request, 60s resource)
    static let standard: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    /// Quick session for lightweight calls (15s request, 30s resource)
    static let quick: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    /// Long session for heavy operations (60s request, 120s resource)
    static let longRunning: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()
}

// Usage:
// SharingService: URLSessionFactory.standard
// ScreenshotNotificationService: URLSessionFactory.quick
// DataSettingsViewModel: URLSessionFactory.longRunning
```

**Files to Create:**
- `ios/App/TidexApp/Native/Services/Network/URLSessionFactory.swift`

**Files to Modify:**
- `ios/App/TidexApp/Native/Services/Data/SharingService.swift`
- `ios/App/TidexApp/Native/Services/Notification/ScreenshotNotificationService.swift`
- `ios/App/TidexApp/Native/Features/Settings/Data/DataSettingsViewModel.swift`

**Testing:**
- Verify all network calls still work
- Monitor memory usage - should be reduced
- Verify timeout behavior is correct for each use case

**Commit Message Format:** `refactor(ios): consolidate URLSession instances into shared factory`

---

### TASK-018: Group Related @Published Properties in AdminSettingsViewModel

**Status:** PENDING

**Severity:** MEDIUM - Performance degradation from excessive re-renders

**Location:**
- `ios/App/TidexApp/Native/Features/Admin/AdminSettingsViewModel.swift` lines 237-318

**Problem:**
The ViewModel has 40+ individual `@Published` properties:

```swift
@Published var users: [AdminUserItem] = []
@Published var usersSearchQuery: String = ""
@Published var usersIsLoading: Bool = false
@Published var usersCurrentPage: Int = 1
@Published var usersTotalCount: Int = 0
@Published var usersHasMore: Bool = false
@Published var selectedUser: AdminUserItem?
// ... 30+ more properties
```

**Why This Is a Problem:**
- Every property change triggers all subscribers to re-evaluate
- Complex views re-render unnecessarily
- Difficult to track state mutations
- Performance degradation

**Recommended Fix:**
Group related properties into structs:

```swift
struct UsersState {
    var items: [AdminUserItem] = []
    var searchQuery: String = ""
    var isLoading: Bool = false
    var currentPage: Int = 1
    var totalCount: Int = 0
    var hasMore: Bool = false
    var selected: AdminUserItem?
}

struct FeedbackState {
    var items: [AdminFeedbackItem] = []
    var isLoading: Bool = false
    var currentPage: Int = 1
    var totalCount: Int = 0
    var hasMore: Bool = false
}

// In ViewModel:
@Published var usersState = UsersState()
@Published var feedbackState = FeedbackState()
@Published var analyticsState = AnalyticsState()
// etc.

// Usage:
// Before: usersIsLoading = true
// After: usersState.isLoading = true
```

**Files to Modify:**
- `ios/App/TidexApp/Native/Features/Admin/AdminSettingsViewModel.swift`
- Views that reference these properties will need updates

**Testing:**
- Verify all admin functionality still works
- Monitor re-render counts (use SwiftUI debugging)
- Should see fewer unnecessary re-renders

**Commit Message Format:** `refactor(ios): group related @Published properties in AdminSettingsViewModel`

---

### TASK-019: Fix EntitlementService and StoreKitManager Tier Synchronization

**Status:** PENDING

**Severity:** MEDIUM - Potential for stale tier information

**Location:**
- `ios/App/TidexApp/Native/Services/Subscription/EntitlementService.swift` lines 101-116
- `ios/App/TidexApp/Native/Services/Subscription/StoreKitManager.swift`

**Problem:**
`EntitlementService` reads `StoreKitManager.shared.currentTier` which can be stale:

```swift
func updateEffectiveTier() {
    let storeKitTier = StoreKitManager.shared.currentTier  // Could be stale

    if let cached = cachedEntitlement, !cached.isExpired {
        effectiveTier = max(storeKitTier, cached.tier)
    } else {
        effectiveTier = storeKitTier
    }
}
```

The transaction listener in StoreKitManager runs in a detached task and could update `currentTier` at any time.

**Recommended Fix:**
Add explicit synchronization:

```swift
// In StoreKitManager.swift
@Published private(set) var currentTier: SubscriptionTier = .free

/// Called when tier changes - notifies EntitlementService
private func updateTier(_ newTier: SubscriptionTier) {
    currentTier = newTier
    // Notify EntitlementService to update
    EntitlementService.shared.handleStoreKitTierChange(newTier)
}

// In EntitlementService.swift
func handleStoreKitTierChange(_ storeKitTier: SubscriptionTier) {
    updateEffectiveTier(with: storeKitTier)
}

private func updateEffectiveTier(with storeKitTier: SubscriptionTier? = nil) {
    let tier = storeKitTier ?? StoreKitManager.shared.currentTier

    if let cached = cachedEntitlement, !cached.isExpired {
        effectiveTier = max(tier, cached.tier)
    } else {
        effectiveTier = tier
    }
}
```

**Files to Modify:**
- `ios/App/TidexApp/Native/Services/Subscription/EntitlementService.swift`
- `ios/App/TidexApp/Native/Services/Subscription/StoreKitManager.swift`

**Testing:**
- Purchase subscription while using app
- Verify tier updates immediately
- Test subscription expiration
- Verify no stale tier is displayed

**Commit Message Format:** `fix(ios): synchronize EntitlementService and StoreKitManager tier updates`

---

## LOW PRIORITY

---

### TASK-020: Upgrade Keychain Accessibility to WhenUnlockedThisDeviceOnly

**Status:** PENDING

**Severity:** LOW - Security improvement

**Location:**
- `ios/App/TidexApp/Native/Services/Network/SupabaseClient.swift` line 39

**Problem:**
Current setting allows token access even when device is locked:

```swift
newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
```

**Recommended Fix:**
Use more restrictive accessibility:

```swift
newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
```

**Benefits:**
- Only accessible when device is unlocked
- Prevents backup/migration of tokens (more secure)
- Protects against some physical attack vectors

**Considerations:**
- Background refresh won't work when device is locked
- Need to test impact on background operations

**Files to Modify:**
- `ios/App/TidexApp/Native/Services/Network/SupabaseClient.swift`

**Testing:**
- Test normal auth flow
- Test app behavior when device is locked
- Test background operations

**Commit Message Format:** `security(ios): upgrade Keychain accessibility to WhenUnlockedThisDeviceOnly`

---

### TASK-021: Add Image Cache Expiration

**Status:** PENDING

**Severity:** LOW - Stale images displayed

**Location:**
- Find image caching implementation (likely in a ProfileImageCache or similar)

**Problem:**
The image cache persists indefinitely with no expiration:

```swift
private let memoryCache = NSCache<NSString, UIImage>()
// No TTL, no expiration logic
```

**Recommended Fix:**
Add time-based expiration:

```swift
struct CachedImage {
    let image: UIImage
    let cachedAt: Date

    var isExpired: Bool {
        Date().timeIntervalSince(cachedAt) > 3600  // 1 hour
    }
}

final class ImageCache {
    private let cache = NSCache<NSString, CachedImageWrapper>()

    func get(_ key: String) -> UIImage? {
        guard let wrapper = cache.object(forKey: key as NSString) else {
            return nil
        }
        if wrapper.cachedImage.isExpired {
            cache.removeObject(forKey: key as NSString)
            return nil
        }
        return wrapper.cachedImage.image
    }

    func set(_ image: UIImage, forKey key: String) {
        let wrapper = CachedImageWrapper(CachedImage(image: image, cachedAt: Date()))
        cache.setObject(wrapper, forKey: key as NSString)
    }
}
```

**Files to Modify:**
- Find and modify image caching implementation

**Testing:**
- Change profile picture on web
- Verify iOS app shows new picture after cache expires
- Verify cache still works within expiration period

**Commit Message Format:** `fix(ios): add image cache expiration`

---

### TASK-022: Add Explicit Token Expiration Validation Before Use

**Status:** PENDING

**Severity:** LOW - Defense in depth

**Location:**
- `ios/App/TidexApp/Native/Services/Auth/AuthService.swift`

**Problem:**
The app doesn't validate token expiration before using them - relies entirely on Supabase SDK's auto-refresh.

**Recommended Fix:**
Add proactive expiration checking:

```swift
extension AuthService {
    /// Returns the current session, refreshing if needed
    func getValidSession() async throws -> Session {
        let session = try await supabase.auth.session

        // Check if token expires within the next 5 minutes
        let expirationBuffer: TimeInterval = 5 * 60
        if session.expiresAt < Date().addingTimeInterval(expirationBuffer) {
            // Proactively refresh
            return try await supabase.auth.refreshSession()
        }

        return session
    }
}
```

**Files to Modify:**
- `ios/App/TidexApp/Native/Services/Auth/AuthService.swift`
- Update callers to use the new method

**Testing:**
- Test with token about to expire
- Verify proactive refresh occurs
- Verify normal tokens are not refreshed unnecessarily

**Commit Message Format:** `fix(ios): add explicit token expiration validation before use`

---

## COMPLETED TASKS

### TASK-001: Remove Access Token from URL Parameters in OAuth Flow

**Status:** DONE (2026-01-27)

**Severity:** CRITICAL - Security vulnerability

**Fix Applied:**
Removed the insecure fallback path in `OAuthWebAuthSession.swift` that appended access tokens as URL query parameters. The OAuth flow now:
1. Sends the access token securely via Authorization header to Supabase's identity linking endpoint
2. Captures the redirect URL from Supabase
3. Opens the OAuth provider URL in ASWebAuthenticationSession (no token in URL)
4. Throws an error if the redirect capture fails instead of falling back to insecure URL params

**Files Modified:**
- `ios/App/TidexApp/Native/Services/Auth/OAuthProviders/OAuthWebAuthSession.swift`

---

### TASK-002: Implement Token Refresh Lock to Prevent Concurrent Refresh Race Condition

**Status:** DONE (2026-01-27)

**Severity:** CRITICAL - Causes "Refresh Token Not Found" errors

**Fix Applied:**
Created `AuthSessionManager` to serialize all session access and prevent concurrent token refresh attempts. When multiple views/services need the session simultaneously:
1. The first request triggers the refresh
2. Subsequent requests wait for the existing refresh to complete
3. All requests receive the same refreshed session

The manager also proactively refreshes tokens that are within 60 seconds of expiry to prevent edge cases.

**Files Created:**
- `ios/App/TidexApp/Native/Services/Auth/AuthSessionManager.swift`

**Files Modified:**
- `ios/App/TidexApp/Native/Services/Auth/AuthService.swift` - Uses AuthSessionManager for getSession()
- `ios/App/TidexApp/Native/Core/AppCoordinator.swift` - Uses AuthSessionManager (5 places)
- `ios/App/TidexApp/Native/Services/Data/SharingService.swift` - Uses AuthSessionManager (12 places)
- `ios/App/TidexApp/Native/Services/Data/SettingsService.swift` - Uses AuthSessionManager
- `ios/App/TidexApp/Native/Features/Dashboard/DashboardViewModel.swift` - Uses AuthSessionManager
- `ios/App/TidexApp/Native/Features/Shifts/ShiftsViewModel.swift` - Uses AuthSessionManager
- `ios/App/TidexApp/Native/Features/Sharing/SharingViewModel.swift` - Uses AuthSessionManager
- `ios/App/TidexApp/Native/Features/Stats/Services/StatsService.swift` - Uses AuthSessionManager
- `ios/App/TidexApp/Native/Services/Notification/ScreenshotNotificationService.swift` - Uses AuthSessionManager

---

### TASK-003: Alert User When LocalStore Falls Back to In-Memory Storage

**Status:** DONE (2026-01-27)

**Severity:** CRITICAL - Silent data loss

**Fix Applied:**
Added `isUsingInMemoryFallback` property to `LocalStore` that tracks whether persistent storage initialization failed and the app fell back to in-memory storage. When in fallback mode, RootView now displays an alert warning the user that their data will not be saved when the app closes.

The alert displays:
- Title: "Storage Issue"
- Message: "Unable to save data to device storage. Your changes will not be saved when the app closes. Please restart the app or check your device storage."

**Files Modified:**
- `ios/App/TidexApp/Native/Storage/LocalStore.swift` - Added `isUsingInMemoryFallback` property
- `ios/App/TidexApp/Native/Core/RootView.swift` - Added storage warning alert

---

### TASK-004: Add CSRF State Parameter Validation to OAuth Callback Processing

**Status:** DONE (2026-01-27)

**Severity:** CRITICAL - Security vulnerability

**Fix Applied:**
Implemented CSRF state parameter validation for OAuth identity linking flows. The fix includes:

1. **State Generation**: A UUID-based state parameter is now generated at the start of each OAuth flow and stored in `OAuthWebAuthSession`
2. **State Inclusion**: The state parameter is included in the OAuth authorize URL query parameters
3. **State Validation**: When the OAuth callback is received, the state parameter is validated against the stored value before processing any tokens
4. **Error Handling**: A new `stateMismatch` error case provides specific handling for state validation failures

This prevents CSRF attacks where an attacker could link their OAuth account to a victim's Tidex account.

**Files Modified:**
- `ios/App/TidexApp/Native/Services/Auth/OAuthProviders/OAuthWebAuthSession.swift` - Added state generation, storage, and validation
- `ios/App/TidexApp/Native/Features/Settings/Security/SecuritySettingsViewModel.swift` - Added state validation in callback processing

---

### TASK-005: Fix ScreenshotNotificationService Cooldown Race Condition

**Status:** DONE (2026-01-27)

**Severity:** HIGH - Race condition causes duplicate notifications

**Fix Applied:**
Fixed the race condition where multiple concurrent screenshot reports could bypass the cooldown check. The fix:
1. Added an `inFlightRequests` set to track pending requests
2. Check if request is already in-flight before processing
3. Update timestamp BEFORE the network call to prevent races
4. On failure, remove timestamp so retry is possible

**Files Modified:**
- `ios/App/TidexApp/Native/Services/Notification/ScreenshotNotificationService.swift`

---

### TASK-006: Add Atomic Sync State Management to SyncCoordinator

**Status:** DONE (2026-01-27)

**Severity:** HIGH - Race condition can cause duplicate syncs and data corruption

**Fix Applied:**
Replaced the separate `syncInProgress` flag with an atomic `SyncState` enum for proper check-and-set operations. Key changes:
1. Created private `SyncState` enum with `.idle` and `.syncing(userId:startedAt:)` cases
2. Added computed `syncInProgress` property for backwards compatibility
3. Updated `lastAutoSyncAt` BEFORE starting sync (for interval-guarded syncs) to prevent concurrent syncs from both passing the interval check
4. Added `syncState` and `isSyncing` reset to `resetForUserChange()` for safety

**Files Modified:**
- `ios/App/TidexApp/Native/Storage/Sync/SyncCoordinator.swift`

---

### TASK-007: Fix AppCoordinator Auth State Initialization Race Condition

**Status:** DONE (2026-01-27)

**Severity:** HIGH - Can cause duplicate MFA screens and state inconsistency

**Fix Applied:**
Fixed the race condition between the auth state listener and the timeout fallback. Key changes:
1. Added `initialSessionTimeoutTask` property to store and cancel the timeout task
2. Added `isUpdatingAuthState` flag to prevent concurrent state updates in `checkMFAAndUpdateState()`
3. The timeout task now checks `Task.isCancelled` after sleep to respect cancellation
4. When `.initialSession` is received from the auth listener, the timeout task is immediately cancelled
5. `checkMFAAndUpdateState()` now guards against concurrent calls using the `isUpdatingAuthState` flag with proper defer cleanup

**Files Modified:**
- `ios/App/TidexApp/Native/Core/AppCoordinator.swift`

---

## Notes

- Each task should be completed and committed separately
- Run tests after each fix to ensure no regressions
- Update task status to DONE after committing
- Move completed tasks to the COMPLETED TASKS section

**Last Updated:** 2026-01-27
**Total Tasks:** 22
**Completed:** 7
**Remaining:** 15
