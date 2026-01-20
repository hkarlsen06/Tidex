import Foundation
import SwiftUI
import Supabase
import UIKit

/// Central coordinator for app-wide authentication state and navigation
/// Manages the flow: Splash -> Login -> MFA (if needed) -> Dashboard
///
/// This is the single source of truth for auth state in the app.
/// It listens to Supabase auth events and handles all navigation transitions.
/// Individual services (like `AuthService`) perform auth operations but don't
/// duplicate state listening - they rely on this coordinator for state management.
///
/// Also triggers SyncCoordinator after authentication and on foreground.
@MainActor
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    // MARK: - Navigation State

    enum AppState: Equatable {
        case loading           // Initial app load, checking session
        case unauthenticated   // No valid session, show login
        case mfaRequired       // User logged in but needs MFA verification
        case termsRequired     // User needs to accept updated terms
        case authenticated     // Fully authenticated, show main app
    }

    @Published private(set) var appState: AppState = .loading

    // MARK: - MFA State

    /// MFA factor to verify (when state is .mfaRequired)
    @Published private(set) var pendingMFAFactor: AuthService.MFAFactor?

    // MARK: - Deep Link Navigation State

    /// Pending deep link navigation to execute after authentication/tab setup
    @Published var pendingDeepLink: DeepLink?

    /// Action to take when opening a shift deeplink
    enum ShiftDeepLinkAction: String, Equatable {
        case open      // Open shift details sheet (default behavior)
        case highlight // Just highlight/navigate to the date in calendar, no sheet
    }

    /// Supported deep link types
    enum DeepLink: Equatable {
        case shifts(dates: [String]?, action: ShiftDeepLinkAction) // Navigate to shifts view, optionally filtering dates
        case sharing(sharerId: String?)         // Navigate to sharing tab, optionally selecting a sharer
        case sharingManage(highlightUserId: String?) // Open sharing management modal, optionally highlighting a user
    }

    // MARK: - Terms Acceptance State

    /// Whether this is an update to terms (user previously accepted older version)
    @Published private(set) var isTermsUpdate: Bool = false

    // MARK: - User Profile State

    /// Current user's ID (lowercase UUID string)
    @Published private(set) var userId: String?
    /// User's display name (for UserMenuButton)
    @Published private(set) var userDisplayName: String = ""
    /// User's profile picture URL (for UserMenuButton)
    @Published private(set) var userAvatarUrl: String?
    /// Whether the user has already completed onboarding (from Supabase user metadata)
    @Published private(set) var hasFinishedOnboardingRemotely: Bool = false

    // MARK: - Sync State

    /// Whether initial sync has completed after authentication
    @Published private(set) var initialSyncComplete = false

    // MARK: - Dependencies

    private let authService: AuthService
    private let settingsService: SettingsService
    private let syncCoordinator: SyncCoordinator

    // MARK: - Private

    private var authStateTask: Task<Void, Never>?
    private var didReceiveInitialSession = false

    // MARK: - Initialization

    private init(
        authService: AuthService? = nil,
        settingsService: SettingsService? = nil,
        syncCoordinator: SyncCoordinator? = nil
    ) {
        self.authService = authService ?? AuthService.shared
        self.settingsService = settingsService ?? SettingsService.shared
        self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
        setupAuthStateListener()
        setupInitialSessionCheck()
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - Initial Session Check

    /// Timeout for initial session check (in nanoseconds)
    /// If authStateChanges doesn't emit .initialSession within this time, we check manually
    private static let initialSessionTimeout: UInt64 = 500_000_000 // 0.5 seconds

    /// Fallback check in case authStateChanges doesn't emit .initialSession promptly
    /// This handles edge cases where the Supabase SDK doesn't emit the initial event
    private func setupInitialSessionCheck() {
        Task { [weak self] in
            // Wait for authStateChanges to emit - this is a fallback, not the primary flow
            try? await Task.sleep(nanoseconds: Self.initialSessionTimeout)

            guard let self = self else { return }

            // If still loading after timeout AND we haven't received initialSession event,
            // the authStateChanges stream hasn't emitted.
            // This can happen if there's no stored session or the SDK initialization is slow.
            if self.appState == .loading && !self.didReceiveInitialSession {
                print("[AppCoordinator] Initial session timeout - performing manual session check")
                await self.performInitialSessionCheck()
            }
        }
    }

    /// Perform initial session check directly (fallback when authStateChanges doesn't emit)
    private func performInitialSessionCheck() async {
        do {
            // session is non-optional - throws if no session exists
            _ = try await supabase.auth.session
            print("[AppCoordinator] Manual session check: session found")
            await checkMFAAndUpdateState()
        } catch {
            print("[AppCoordinator] Manual session check: no session (\(error.localizedDescription))")
            appState = .unauthenticated
        }
    }

    // MARK: - Auth State Listener

    private func setupAuthStateListener() {
        authStateTask = Task { [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                guard let self = self else { return }

                print("[AppCoordinator] Auth event: \(event), session: \(session != nil ? "present" : "nil")")

                switch event {
                case .initialSession:
                    // Mark that we received the initial session event (prevents duplicate check from timeout)
                    self.didReceiveInitialSession = true

                    // On app launch, check if we have a valid session
                    if session != nil {
                        await self.checkMFAAndUpdateState()
                    } else {
                        self.appState = .unauthenticated
                    }

                case .signedIn:
                    // User just signed in, check MFA
                    // Skip if already authenticated or in terms flow to prevent duplicate checks
                    guard self.appState != .authenticated && self.appState != .termsRequired else {
                        print("[AppCoordinator] Skipping signedIn handling - already in state: \(self.appState)")
                        break
                    }
                    await self.checkMFAAndUpdateState()

                case .signedOut:
                    self.appState = .unauthenticated
                    self.pendingMFAFactor = nil

                case .tokenRefreshed:
                    // Token refreshed, state unchanged
                    break

                case .mfaChallengeVerified:
                    // MFA verified, user is now fully authenticated
                    // Load onboarding state BEFORE setting authenticated to prevent flash
                    if let session = session {
                        self.loadOnboardingStateFromUser(session.user)
                    }
                    self.initialSyncComplete = false
                    self.appState = .authenticated
                    self.pendingMFAFactor = nil

                case .userUpdated, .userDeleted, .passwordRecovery:
                    // Handle other events as needed
                    break
                }
            }
        }
    }

    // MARK: - MFA Check

    /// Check MFA status and update app state accordingly
    private func checkMFAAndUpdateState() async {
        do {
            let mfaStatus = try await authService.getMFAStatus()

            if mfaStatus.requiresVerification {
                // User needs to complete MFA
                // Find the first verified TOTP factor
                if let factor = mfaStatus.factors.first(where: { $0.status == "verified" }) {
                    self.pendingMFAFactor = factor
                    self.appState = .mfaRequired
                } else {
                    // No verified factors, but MFA is required - shouldn't happen normally
                    // Fall back to checking terms (backend will handle MFA enforcement)
                    await checkTermsAndUpdateState()
                }
            } else {
                // No MFA required, check terms acceptance
                await checkTermsAndUpdateState()
            }
        } catch {
            // If MFA check fails, check terms and let backend handle MFA
            print("[AppCoordinator] MFA check failed: \(error)")
            await checkTermsAndUpdateState()
        }
    }

    // MARK: - Terms Acceptance Check

    /// Check if user needs to accept updated terms
    /// Uses cached/fallback version for immediate check, then verifies in background
    private func checkTermsAndUpdateState() async {
        do {
            let session = try await supabase.auth.session
            let user = session.user

            // Get terms_accepted_at from user metadata
            let termsAcceptedAt = user.userMetadata["terms_accepted_at"]?.value as? String

            // Quick sync check with cached/fallback version - doesn't block on API
            let needsReAcceptanceImmediate = TermsVersion.needsTermsReAcceptance(termsAcceptedAt)

            if needsReAcceptanceImmediate {
                // User definitely needs to accept terms (based on cached/fallback version)
                self.isTermsUpdate = termsAcceptedAt != nil
                self.appState = .termsRequired
            } else {
                // Terms appear up to date - proceed to authenticated immediately
                loadOnboardingStateFromUser(user)
                self.initialSyncComplete = false
                self.appState = .authenticated
                await updateUserProfile()

                // Check in background if API has a newer terms version
                // This handles the case where terms were updated but we're using stale cache
                self.checkTermsVersionInBackground(termsAcceptedAt: termsAcceptedAt)
            }
        } catch {
            // If we can't check terms, proceed to authenticated and let backend handle it
            print("[AppCoordinator] Terms check failed: \(error)")
            if let session = try? await supabase.auth.session {
                loadOnboardingStateFromUser(session.user)
            }
            self.initialSyncComplete = false
            self.appState = .authenticated
            await updateUserProfile()
        }
    }

    /// Background check for terms version update
    /// Fetches latest version from API and transitions to termsRequired if needed
    private func checkTermsVersionInBackground(termsAcceptedAt: String?) {
        Task { [weak self] in
            // Fetch latest terms version from API (this may take time on slow networks)
            let needsReAcceptance = await TermsVersion.needsTermsReAcceptanceAsync(termsAcceptedAt)

            guard let self = self else { return }

            // Only transition if we're still authenticated and terms are actually needed
            if needsReAcceptance && self.appState == .authenticated {
                print("[AppCoordinator] Background terms check: user needs to accept updated terms")
                self.isTermsUpdate = termsAcceptedAt != nil
                self.appState = .termsRequired
            }
        }
    }

    /// Load onboarding completion state from user metadata
    /// Called before setting appState to .authenticated to prevent PostAuthOnboarding flash
    private func loadOnboardingStateFromUser(_ user: User) {
        if let finishedOnboarding = user.userMetadata["finishedOnboarding"]?.value as? Bool {
            self.hasFinishedOnboardingRemotely = finishedOnboarding
        } else {
            self.hasFinishedOnboardingRemotely = false
        }
    }

    // MARK: - User Profile

    /// Update user profile data (display name and avatar)
    /// Also triggers initial sync in background
    private func updateUserProfile() async {
        do {
            let session = try await supabase.auth.session
            let user = session.user

            // Store user ID
            let currentUserId = user.id.uuidString.lowercased()
            self.userId = currentUserId

            // Check if onboarding was already completed (from raw_user_meta_data.finishedOnboarding)
            // Note: loadOnboardingStateFromUser is called earlier, but we update again in case metadata changed
            loadOnboardingStateFromUser(user)

            // Extract display name from user metadata or fall back to email
            if let fullName = user.userMetadata["full_name"]?.value as? String, !fullName.isEmpty {
                userDisplayName = fullName
            } else if let name = user.userMetadata["name"]?.value as? String, !name.isEmpty {
                userDisplayName = name
            } else if let email = user.email {
                // Use the part before @ for email
                userDisplayName = email.components(separatedBy: "@").first ?? email
            } else if let phone = user.phone {
                userDisplayName = phone
            } else {
                userDisplayName = "User"
            }

            // Configure StoreKit and load entitlements
            await configureStoreKitAndEntitlements(userId: currentUserId)

            // Request notification permission and register for APNs
            await NotificationService.shared.requestPermissionAndRegister()

            // Trigger initial sync in background after authentication
            triggerInitialSync(userId: currentUserId)

            if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                Task {
                    await appDelegate.registerCachedAPNsTokenIfNeeded()
                }
            }

            // Profile picture will be loaded from local store after sync completes
            // For now, check local settings repository
            if let settings = SettingsRepository.shared.getSettings(for: currentUserId) {
                userAvatarUrl = settings.profile_picture_url
            }

        } catch {
            print("[AppCoordinator] Failed to update user profile: \(error)")
            userDisplayName = "User"
        }
    }

    // MARK: - StoreKit & Entitlements

    /// Configure StoreKit and entitlement services after authentication
    /// Called once during updateUserProfile() after successful login
    private func configureStoreKitAndEntitlements(userId: String) async {
        // 1. Configure StoreKit with user ID (required before purchases)
        StoreKitManager.shared.configure(userId: userId)

        // 2. Load cached entitlement first (fast, offline-safe)
        EntitlementService.shared.loadFromCache(userId: userId)

        // 3. Start StoreKit transaction listener (handles renewals, restores from other devices)
        StoreKitManager.shared.startListening()

        // 4. Start JWS upload worker (process any pending uploads from previous sessions)
        JWSUploadWorker.shared.processQueue()

        // 5. Refresh entitlement from server in background (non-blocking)
        Task {
            try? await EntitlementService.shared.refreshFromServer(userId: userId)
            // Silent on success or failure - we have cache fallback
        }

        // 6. Load StoreKit products in background (for paywall)
        Task {
            await StoreKitManager.shared.loadProducts()
        }
    }

    // MARK: - Sync Triggers

    /// Trigger initial sync after authentication
    private func triggerInitialSync(userId: String) {
        initialSyncComplete = false

        Task {
            let result = await syncCoordinator.sync(reason: .appLaunch, userId: userId)

            if result.success && (result.totalRowsProcessed > 0 || result.totalRowsPushed > 0) {
                print("[AppCoordinator] Initial sync: \(result.totalRowsProcessed) pulled, \(result.totalRowsPushed) pushed")
            }
            // Silent on failure - SyncCoordinator logs errors

            initialSyncComplete = true

            // Update avatar from synced settings
            if let settings = SettingsRepository.shared.getSettings(for: userId) {
                userAvatarUrl = settings.profile_picture_url
            }
        }
    }

    /// Called when app returns to foreground
    /// Triggers a sync with interval guard (won't sync if recent sync occurred)
    func handleAppForeground() {
        guard appState == .authenticated else { return }

        Task {
            do {
                let session = try await supabase.auth.session
                let userId = session.user.id.uuidString.lowercased()

                if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                    Task {
                        await appDelegate.registerCachedAPNsTokenIfNeeded()
                    }
                }

                let result = await syncCoordinator.sync(reason: .foreground, userId: userId)

                // Only log if sync actually ran and had data
                if result.success && result.totalRowsProcessed > 0 {
                    print("[AppCoordinator] Foreground sync: \(result.totalRowsProcessed) rows")
                }
            } catch {
                print("[AppCoordinator] Foreground sync skipped (no session): \(error)")
            }
        }
    }

    // MARK: - Public Actions

    /// Called when login is successful
    /// The auth state listener will handle the transition
    func handleLoginSuccess() async {
        await checkMFAAndUpdateState()
    }

    /// Called when MFA verification is successful
    func handleMFASuccess() {
        pendingMFAFactor = nil
        Task {
            // After MFA, check if terms acceptance is needed
            await checkTermsAndUpdateState()
        }
    }

    /// Called when terms are accepted
    func handleTermsAccepted() {
        isTermsUpdate = false
        // Reset initialSyncComplete BEFORE setting authenticated state
        // This ensures DashboardView shows loading instead of empty state
        initialSyncComplete = false
        appState = .authenticated
        Task {
            await updateUserProfile()
        }
    }

    /// Called when user declines terms (signs out)
    func handleTermsDeclined() async {
        await signOut()
    }

    /// Sign out the user
    func signOut() async {
        // Clear widget storage before sign out
        NativeWidgetStorage.clearWidgetStorage()

        // Stop StoreKit listener and clear entitlement cache
        StoreKitManager.shared.stopListening()
        await EntitlementService.shared.clearCache()

        // Clear all local data (shifts, settings, sync state, etc.)
        await LocalStore.shared.resetAllData()

        // Clear image cache
        ImageCache.shared.clearAll()

        // Reset sync coordinator state for new user
        // This clears the interval guard so the next user's initial sync isn't blocked
        syncCoordinator.resetForUserChange()

        do {
            try await authService.signOut()
            // Auth state listener will update appState to .unauthenticated
            initialSyncComplete = false
            userId = nil
            // Clear user profile data to prevent stale data showing for next user
            userDisplayName = ""
            userAvatarUrl = nil
        } catch {
            print("[AppCoordinator] Sign out failed: \(error)")
            // Force state change even if sign out fails
            appState = .unauthenticated
            initialSyncComplete = false
            userId = nil
            // Clear user profile data to prevent stale data showing for next user
            userDisplayName = ""
            userAvatarUrl = nil
        }
    }

    /// Force a session check (useful for debugging or manual refresh)
    func checkSession() async {
        appState = .loading

        do {
            if let _ = try await authService.getSession() {
                await checkMFAAndUpdateState()
            } else {
                appState = .unauthenticated
            }
        } catch {
            appState = .unauthenticated
        }
    }

    // MARK: - Profile Updates

    /// Update the user's display name
    /// Called from ProfileSettingsViewModel after successfully saving the name
    func updateDisplayName(_ name: String) {
        userDisplayName = name
    }

    /// Update the user's avatar URL
    /// Called from ProfileSettingsViewModel after uploading/removing the avatar
    func updateAvatarUrl(_ url: String?) {
        userAvatarUrl = url
    }

    // MARK: - Deep Link Handling

    /// Handle a deep link URL and set pendingDeepLink for navigation
    /// Called from SceneDelegate when the app receives a tidex:// URL
    ///
    /// Supported URL formats:
    /// - tidex://sharing?user=<userId> → Navigate to sharing tab and select the sharer
    /// - tidex://sharing/manage?highlight=<userId> → Open manage modal and highlight user
    /// - tidex://shifts?dates=2025-01-15,2025-01-16 → Navigate to shifts with dates selected
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "tidex" else { return }

        let host = url.host?.lowercased()
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        print("[AppCoordinator] Handling deep link: \(url)")

        switch host {
        case "sharing":
            // Check for manage path
            if url.path == "/manage" || url.pathComponents.contains("manage") {
                let highlightUserId = queryItems.first(where: { $0.name == "highlight" })?.value
                pendingDeepLink = .sharingManage(highlightUserId: highlightUserId)
                print("[AppCoordinator] Deep link: sharing/manage, highlight=\(highlightUserId ?? "nil")")
            } else {
                // Navigate to sharer
                let sharerId = queryItems.first(where: { $0.name == "user" })?.value
                pendingDeepLink = .sharing(sharerId: sharerId)
                print("[AppCoordinator] Deep link: sharing, user=\(sharerId ?? "nil")")
            }

        case "shifts":
            let datesString = queryItems.first(where: { $0.name == "dates" })?.value
            let dates = datesString?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            // Parse action parameter: "open" (default) or "highlight"
            let actionString = queryItems.first(where: { $0.name == "action" })?.value?.lowercased()
            let action: ShiftDeepLinkAction = actionString == "highlight" ? .highlight : .open
            pendingDeepLink = .shifts(dates: dates, action: action)
            print("[AppCoordinator] Deep link: shifts, dates=\(dates ?? []), action=\(action.rawValue)")

        default:
            print("[AppCoordinator] Unknown deep link host: \(host ?? "nil")")
        }
    }

    /// Clear the pending deep link after it has been consumed
    func clearPendingDeepLink() {
        pendingDeepLink = nil
    }
}
