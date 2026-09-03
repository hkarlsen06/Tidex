// swiftlint:disable:next blanket_disable_command
// swiftlint:disable closure_body_length conditional_returns_on_newline cyclomatic_complexity discouraged_none_name
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable discouraged_optional_collection enum_case_associated_values_count explicit_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_enum_raw_value explicit_top_level_acl explicit_type_interface file_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable function_body_length line_length multiline_arguments_brackets no_grouping_extension
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers prefixed_toplevel_constant type_body_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable sorted_imports type_contents_order
import Combine
import Foundation
import Supabase
import UIKit
import os

private let launchLog = Logger(subsystem: "no.tidex.app", category: "Launch")

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
  private static let startupTabCacheKey = "defaultStartupTab"

  enum PostAuthOnboardingPresentationState: Equatable {
    case none
    case initial
    case reentry

    var entryMode: PostAuthOnboardingEntryMode? {
      switch self {
      case .none:
        return nil

      case .initial:
        return .initial

      case .reentry:
        return .reentry
      }
    }
  }

  // MARK: - Navigation State

  enum AppState: Equatable {
    case loading  // Initial app load, checking session
    case unauthenticated  // No valid session, show login
    case mfaRequired  // User logged in but needs MFA verification
    case termsRequired  // User needs to accept updated terms
    case authenticated  // Fully authenticated, show main app
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
    case open  // Open shift details sheet (default behavior)
    case highlight  // Just highlight/navigate to the date in calendar, no sheet
  }

  /// Change info from notification payload for highlighting
  struct ShiftChange: Equatable {
    let shiftId: String
    let date: String
    let op: String  // "added", "updated", "deleted"
  }

  /// Supported deep link types
  enum DeepLink: Equatable {
    case shifts(dates: [String]?, shiftIds: [String]?, action: ShiftDeepLinkAction)  // Navigate to shifts view, optionally filtering dates/shifts
    case sharing(sharerId: String?, highlightDates: [String]?, changes: [ShiftChange]?)  // Navigate to sharing tab, select sharer, highlight specific shifts
    case sharingManage(highlightUserId: String?)  // Open sharing management modal, optionally highlighting a user
    case friendChat(
      threadId: String,
      messageId: String?,
      senderUserId: String?,
      typingUserId: String?,
      navigationRequestId: UUID?
    )  // Navigate to a direct friend chat thread
    case wagey  // Navigate to Wagey
    case addShift(mode: AddShiftMode?, date: String?)  // Navigate to Add Shift, optionally selecting a mode/date
    case settings(destination: SettingsDeepLinkDestination?)  // Open settings, optionally at a subpage
    case feedback  // Navigate to feedback settings (for users receiving response)
    case adminFeedback  // Navigate to admin panel with feedback tab (for admins receiving new feedback)
    case adminReport(reportId: String?)  // Open admin panel on reports tab and optionally select a report
  }

  enum SettingsDeepLinkDestination: Equatable {
    case profile
    case security
    case subscription
    case notifications
    case appearance
    case pay(jobId: String?)
    case recurringShifts
    case calendarSync
    case data
    case feedback
    case admin
  }

  // MARK: - Terms Acceptance State

  /// Whether this is an update to terms (user previously accepted older version)
  @Published private(set) var isTermsUpdate: Bool = false

  // MARK: - User Profile State

  /// Current user's ID (lowercase UUID string)
  @Published private(set) var userId: String? {
    didSet {
      syncFriendsRealtimeForCurrentUser()
    }
  }

  // MARK: - User ID Access Errors

  /// Error thrown when user ID is required but not available
  enum UserIdError: Error, LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
      switch self {
      case .notAuthenticated:
        return "User is not authenticated"
      }
    }
  }

  // MARK: - Safe User ID Access

  /// Safely get the current user ID, or nil if not authenticated
  /// Use this when the operation can gracefully handle a missing user ID
  func getCurrentUserId() -> String? {
    return userId
  }

  func currentPostAuthOnboardingPresentation(
    hasCompletedLocally: Bool
  ) -> PostAuthOnboardingPresentationState {
    if postAuthOnboardingPresentation == .reentry {
      return .reentry
    }

    guard appState == .authenticated else {
      return .none
    }

    return !hasCompletedLocally && !hasFinishedOnboardingRemotely ? .initial : .none
  }

  func refreshPostAuthOnboardingPresentation(hasCompletedLocally: Bool) {
    postAuthOnboardingPresentation = currentPostAuthOnboardingPresentation(
      hasCompletedLocally: hasCompletedLocally
    )
  }

  func requestPostAuthOnboardingReentry() {
    guard appState == .authenticated else { return }
    postAuthOnboardingPresentation = .reentry
  }

  func dismissPostAuthOnboarding(markCompletedRemotely: Bool = false) {
    if markCompletedRemotely {
      hasFinishedOnboardingRemotely = true
    }

    postAuthOnboardingPresentation = .none
  }

  /// Get the current user ID, throwing an error if not authenticated
  /// Use this when the operation requires a valid user ID to proceed
  /// - Throws: `UserIdError.notAuthenticated` if no user is logged in
  /// - Returns: The current user's ID
  func requireUserId() throws -> String {
    guard let currentUserId = userId else {
      throw UserIdError.notAuthenticated
    }
    return currentUserId
  }

  /// User's display name (for UserMenuButton)
  @Published private(set) var userDisplayName: String = ""
  /// User's profile picture URL (for UserMenuButton)
  @Published private(set) var userAvatarUrl: String?
  /// Whether the user has already completed onboarding (from Supabase user metadata)
  @Published private(set) var hasFinishedOnboardingRemotely: Bool = false
  @Published private(set) var postAuthOnboardingPresentation: PostAuthOnboardingPresentationState =
    .none

  // MARK: - Sync State

  /// Whether initial sync has completed after authentication
  @Published private(set) var initialSyncComplete = false

  // MARK: - MFA Completion State

  /// Flag indicating MFA was just completed - consumed by DashboardView for haptic feedback
  @Published var didJustCompleteMFA = false

  // MARK: - Dependencies

  private let authService: AuthService
  private let settingsService: SettingsService
  private let syncCoordinator: SyncCoordinator

  // MARK: - Private

  private var authStateTask: Task<Void, Never>?
  private var initialSessionTimeoutTask: Task<Void, Never>?
  private var friendsRealtimeTask: Task<Void, Never>?
  private var appActiveObserver: AnyCancellable?
  private var backgroundTasks: [Task<Void, Never>] = []
  private var didReceiveInitialSession = false
  private var isUpdatingAuthState = false
  private var isUserInitiatedSignOutInProgress = false

  // MARK: - Initialization

  private init(
    authService: AuthService? = nil,
    settingsService: SettingsService? = nil,
    syncCoordinator: SyncCoordinator? = nil
  ) {
    launchLog.info("[Launch] AppCoordinator.init START")
    self.authService = authService ?? AuthService.shared
    self.settingsService = settingsService ?? SettingsService.shared
    self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
    AuthDiagnosticsReporter.shared.record(
      .appLaunch,
      appState: String(describing: appState),
      metadata: [
        "did_receive_initial_session": .bool(didReceiveInitialSession),
        "is_updating_auth_state": .bool(isUpdatingAuthState),
        "launch_session_timeout_count": .integer(currentLaunchSessionTimeoutCount()),
      ]
    )
    setupAuthStateListener()
    setupFriendsRealtimeLifecycle()
    setupInitialSessionCheck()
    setupMaxLoadingTimeout()
    launchLog.info("[Launch] AppCoordinator.init END")
  }

  deinit {
    authStateTask?.cancel()
    initialSessionTimeoutTask?.cancel()
    friendsRealtimeTask?.cancel()
    appActiveObserver?.cancel()
    backgroundTasks.forEach { $0.cancel() }
  }

  private func setupFriendsRealtimeLifecycle() {
    appActiveObserver = NotificationCenter.default
      .publisher(for: .tidexDidBecomeActive)
      .sink { _ in
        Task { @MainActor in
          await FriendsMessagingRealtimeCoordinator.shared.handleAppDidBecomeActive()
        }
      }
  }

  private func syncFriendsRealtimeForCurrentUser() {
    let currentUserId = userId
    friendsRealtimeTask?.cancel()
    friendsRealtimeTask = Task { @MainActor in
      guard !Task.isCancelled else { return }
      if let currentUserId, !currentUserId.isEmpty {
        await FriendsMessagingRealtimeCoordinator.shared.startForAuthenticatedUser(
          viewerUserId: currentUserId
        )
      } else {
        await FriendsMessagingRealtimeCoordinator.shared.stopForAuthenticatedUser()
      }
    }
  }

  // MARK: - Initial Session Check

  /// Timeout for initial session check (in nanoseconds)
  /// If authStateChanges doesn't emit .initialSession within this time, we check manually
  private static let initialSessionTimeout: UInt64 = 500_000_000  // 0.5 seconds

  /// Timeout for MFA/terms network checks (in nanoseconds)
  /// If these checks hang (slow network, unresponsive server), fall back to .unauthenticated
  private static let authCheckTimeout: UInt64 = 10_000_000_000  // 10 seconds

  /// Hard maximum time the app can stay in .loading state (in nanoseconds)
  /// After this, force transition to .unauthenticated regardless of what's pending
  private static let maxLoadingTimeout: UInt64 = 15_000_000_000  // 15 seconds

  /// Number of repeated launch/session timeouts before we force a stable fallback state.
  private static let launchSessionTimeoutRecoveryThreshold = 3
  private static let launchSessionTimeoutCountKey = "auth.launch_session_timeout_count"

  /// Fallback check in case authStateChanges doesn't emit .initialSession promptly
  /// This handles edge cases where the Supabase SDK doesn't emit the initial event
  private func setupInitialSessionCheck() {
    initialSessionTimeoutTask = Task { [weak self] in
      // Wait for authStateChanges to emit - this is a fallback, not the primary flow
      try? await Task.sleep(nanoseconds: Self.initialSessionTimeout)

      guard let self,
        !Task.isCancelled
      else { return }

      // If still loading after timeout AND we haven't received initialSession event,
      // the authStateChanges stream hasn't emitted.
      // This can happen if there's no stored session or the SDK initialization is slow.
      if appState == .loading, !didReceiveInitialSession {
        launchLog.warning(
          "[Launch] AppCoordinator timeout fallback – .initialSession not received in 0.5s")
        AuthDiagnosticsReporter.shared.record(
          .initialSessionTimeout,
          severity: .warning,
          appState: String(describing: appState),
          metadata: [
            "timeout_ms": .integer(Int(Self.initialSessionTimeout / 1_000_000)),
            "did_receive_initial_session": .bool(didReceiveInitialSession),
            "is_updating_auth_state": .bool(isUpdatingAuthState),
            "launch_session_timeout_count": .integer(currentLaunchSessionTimeoutCount()),
          ]
        )
        await performInitialSessionCheck()
      }
    }
  }

  /// Perform initial session check directly (fallback when authStateChanges doesn't emit)
  private func performInitialSessionCheck() async {
    do {
      // session is non-optional - throws if no session exists
      // Use AuthSessionManager to prevent concurrent refresh race conditions
      let session = try await AuthSessionManager.shared.getSession(allowProactiveRefresh: false)
      resetLaunchSessionTimeoutCount()
      AuthDiagnosticsReporter.shared.rememberAuthenticatedUserId(session.normalizedUserId)
      // Returning user — skip MFA, go straight to terms check
      await checkTermsAndUpdateState(initialSession: session, allowProactiveRefresh: false)
    } catch {
      if isLaunchSessionTimeoutError(error) {
        AuthDiagnosticsReporter.shared.record(
          .initialSessionCheckFailed,
          severity: .warning,
          appState: String(describing: appState),
          error: error,
          metadata: [
            "failure_class": .string("launch_session_timeout"),
            "did_receive_initial_session": .bool(didReceiveInitialSession),
            "launch_session_timeout_count": .integer(currentLaunchSessionTimeoutCount()),
            "recovery_threshold": .integer(Self.launchSessionTimeoutRecoveryThreshold),
          ]
        )
        if handleRepeatedLaunchSessionTimeoutIfNeeded() {
          return
        }
        launchLog.warning(
          "[Launch] Initial session check timed out; keeping loading state for retry")
        return
      }

      // Transient timeout/network failures should not immediately force logout.
      if AuthSessionManager.shared.isTransientNetworkError(error)
        || (error as? AuthSessionManagerError) != nil
      {
        launchLog.warning(
          "[Launch] Initial session check transient failure; keeping loading state")
        AuthDiagnosticsReporter.shared.record(
          .initialSessionCheckFailed,
          severity: .warning,
          appState: String(describing: appState),
          error: error,
          metadata: authFailureMetadata(
            error,
            reason: "initial_session_transient_failure",
            previousState: appState
          )
        )
        return
      }
      launchLog.info("[Launch] AppCoordinator → .unauthenticated (no session)")
      AuthDiagnosticsReporter.shared.record(
        .forcedUnauthenticated,
        severity: .warning,
        appState: String(describing: appState),
        error: error,
        metadata: authFailureMetadata(
          error,
          reason: "initial_session_unrecoverable_failure",
          previousState: appState
        )
      )
      appState = .unauthenticated
    }
  }

  /// Hard deadline: if the app is still in .loading after maxLoadingTimeout,
  /// force a transition out. Prefers .authenticated when a local session exists
  /// (preserving offline usage) and only falls back to .unauthenticated when
  /// there is genuinely no session.
  private func setupMaxLoadingTimeout() {
    backgroundTasks.append(
      Task { [weak self] in
        try? await Task.sleep(nanoseconds: Self.maxLoadingTimeout)
        guard let self, !Task.isCancelled else { return }
        guard appState == .loading else { return }

        isUpdatingAuthState = false

        if let session = await AuthSessionManager.shared.getSessionIfAvailable() {
          launchLog.error("[Launch] Hard loading timeout (15s) – proceeding to authenticated")
          AuthDiagnosticsReporter.shared.rememberAuthenticatedUserId(session.normalizedUserId)
          loadOnboardingStateFromUser(session.user)
          userId = session.user.normalizedId
          initialSyncComplete = false
          appState = .authenticated
        } else {
          launchLog.error(
            "[Launch] Hard loading timeout (15s) – no session, forcing unauthenticated")
          AuthDiagnosticsReporter.shared.record(
            .forcedUnauthenticated,
            severity: .error,
            appState: String(describing: appState),
            metadata: [
              "reason": .string("hard_loading_timeout"),
              "timeout_ms": .integer(Int(Self.maxLoadingTimeout / 1_000_000)),
              "did_receive_initial_session": .bool(didReceiveInitialSession),
              "is_updating_auth_state": .bool(isUpdatingAuthState),
              "launch_session_timeout_count": .integer(currentLaunchSessionTimeoutCount()),
            ]
          )
          appState = .unauthenticated
        }
      })
  }

  /// Reset auth state update flag. Called by AppLifecycleHandler's recovery mechanism
  /// to unblock a potentially stuck checkMFAAndUpdateState call.
  func resetAuthUpdateFlag() {
    isUpdatingAuthState = false
  }

  // MARK: - Auth State Listener

  private func setupAuthStateListener() {
    authStateTask = Task { [weak self] in
      launchLog.info("[Launch] AppCoordinator authStateChanges loop entered")
      for await (event, session) in supabase.auth.authStateChanges {
        guard let self else { return }
        recordAuthStateEvent(event, session: session)
        if let session {
          AuthSessionManager.shared.publishSessionToSharedKeychain(session)
        }

        switch event {
        case .initialSession:
          launchLog.info(
            "[Launch] AppCoordinator received .initialSession, hasSession=\(session != nil)")
          // Cancel the timeout task since we received the session event
          initialSessionTimeoutTask?.cancel()
          initialSessionTimeoutTask = nil

          // Mark that we received the initial session event (prevents duplicate check from timeout)
          didReceiveInitialSession = true

          // On app launch, check if we have a valid session
          if let session {
            AuthDiagnosticsReporter.shared.rememberAuthenticatedUserId(session.normalizedUserId)
            resetLaunchSessionTimeoutCount()
            // Returning user with existing session — skip MFA (already at AAL2
            // from a previous login) and go straight to terms check.
            // MFA is only checked on fresh login (.signedIn).
            await checkTermsAndUpdateState(
              initialSession: session,
              allowProactiveRefresh: false
            )
          } else {
            AuthDiagnosticsReporter.shared.record(
              .initialSessionMissing,
              severity: AuthDiagnosticsReporter.shared.hasRememberedAuthenticatedUserId
                ? .warning : .info,
              appState: String(describing: appState),
              authEvent: String(describing: event)
            )
            appState = .unauthenticated
          }

        case .signedIn:
          // User just signed in, check MFA
          // Skip if already authenticated or in terms flow to prevent duplicate checks
          guard appState != .authenticated, appState != .termsRequired else {
            break
          }
          await checkMFAAndUpdateState()

        case .signedOut:
          let isExpectedSignOut =
            isUserInitiatedSignOutInProgress || appState == .unauthenticated
          AuthDiagnosticsReporter.shared.record(
            .signedOutReceived,
            severity: isExpectedSignOut ? .info : .warning,
            userId: userId,
            appState: String(describing: appState),
            authEvent: String(describing: event),
            metadata: [
              "is_user_initiated_sign_out_in_progress": .bool(
                isUserInitiatedSignOutInProgress),
              "is_expected_sign_out": .bool(isExpectedSignOut),
            ]
          )
          applySignedOutState()

        case .tokenRefreshed:
          // Token refreshed, state unchanged
          break

        case .mfaChallengeVerified:
          // MFA verified, user is now fully authenticated
          // Load onboarding state BEFORE setting authenticated to prevent flash
          if let session {
            loadOnboardingStateFromUser(session.user)
          }
          initialSyncComplete = false
          appState = .authenticated
          pendingMFAFactor = nil

        case .passwordRecovery:
          if let session {
            userId = session.user.normalizedId
          }
          NotificationCenter.default.post(name: .tidexPasswordRecoveryRequested, object: nil)

        case .userUpdated, .userDeleted:
          // Handle other events as needed
          break
        }
      }
    }
  }

  // MARK: - MFA Check

  /// Check MFA status and update app state accordingly.
  /// Uses isUpdatingAuthState flag to prevent concurrent state updates from race conditions.
  /// Wraps the actual check in a timeout to prevent hanging on slow/unresponsive networks.
  private func checkMFAAndUpdateState() async {
    // Prevent concurrent state updates from timeout vs auth listener race
    guard !isUpdatingAuthState else { return }
    isUpdatingAuthState = true
    defer { isUpdatingAuthState = false }

    let didComplete = await withTaskGroup(of: Bool.self) { group in
      group.addTask { @MainActor in
        await self.performMFAAndTermsCheck()
        return true
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: Self.authCheckTimeout)
        return false
      }
      let result = await group.next() ?? false
      group.cancelAll()
      return result
    }

    if !didComplete {
      // This method is only called when a session is known to exist, so default to
      // authenticated rather than kicking the user to the login screen. MFA/terms
      // will be re-checked on the next foreground or successful network call.
      launchLog.error("[Launch] Auth check timed out after 10s, proceeding to authenticated")
      if let session = await AuthSessionManager.shared.getSessionIfAvailable() {
        loadOnboardingStateFromUser(session.user)
        userId = session.user.normalizedId
      }
      initialSyncComplete = false
      appState = .authenticated
    }
  }

  /// Performs the actual MFA status check and terms verification.
  /// Extracted from checkMFAAndUpdateState so it can be wrapped in a timeout.
  private func performMFAAndTermsCheck() async {
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
      await checkTermsAndUpdateState()
    }
  }

  // MARK: - Terms Acceptance Check

  /// Check if user needs to accept updated terms
  /// Uses cached/fallback version for immediate check, then verifies in background
  private func checkTermsAndUpdateState(
    initialSession: Session? = nil,
    allowProactiveRefresh: Bool = true
  ) async {
    do {
      let session: Session
      if let initialSession {
        session = initialSession
      } else {
        // Use AuthSessionManager to prevent concurrent refresh race conditions
        session = try await AuthSessionManager.shared.getSession(
          allowProactiveRefresh: allowProactiveRefresh
        )
      }
      let user = session.user
      AuthDiagnosticsReporter.shared.rememberAuthenticatedUserId(session.normalizedUserId)
      AuthSessionManager.shared.publishSessionToSharedKeychain(session)

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
        launchLog.info("[Launch] AppCoordinator → .authenticated")
        AuthDiagnosticsReporter.shared.record(
          .authenticated,
          userId: session.normalizedUserId,
          appState: String(describing: self.appState),
          metadata: AuthDiagnosticsReporter.shared.sessionMetadata(
            session,
            source: "terms_check_authenticated"
          ).merging([
            "terms_accepted_at_present": .bool(termsAcceptedAt != nil),
            "needs_terms_reacceptance_immediate": .bool(needsReAcceptanceImmediate),
          ]) { current, _ in current }
        )
        self.appState = .authenticated
        await updateUserProfile()

        // Validate impersonation session if one was restored from Keychain
        // This ensures stale/expired sessions are cleaned up on app launch
        await ImpersonationManager.shared.validateSessionOnLaunch()

        // Check in background if API has a newer terms version
        // This handles the case where terms were updated but we're using stale cache
        self.checkTermsVersionInBackground(termsAcceptedAt: termsAcceptedAt)
      }
    } catch {
      // If we can't check terms, proceed to authenticated and let backend handle it
      if let session = await AuthSessionManager.shared.getSessionIfAvailable(
        allowProactiveRefresh: allowProactiveRefresh
      ) {
        loadOnboardingStateFromUser(session.user)
        AuthDiagnosticsReporter.shared.rememberAuthenticatedUserId(session.normalizedUserId)
      }
      self.initialSyncComplete = false
      self.appState = .authenticated
      await updateUserProfile()

      // Validate impersonation session if one was restored from Keychain
      await ImpersonationManager.shared.validateSessionOnLaunch()
    }
  }

  /// Background check for terms version update
  /// Fetches latest version from API and transitions to termsRequired if needed
  private func checkTermsVersionInBackground(termsAcceptedAt: String?) {
    runTrackedTask { [weak self] in
      // Fetch latest terms version from API (this may take time on slow networks)
      let needsReAcceptance = await TermsVersion.needsTermsReAcceptanceAsync(termsAcceptedAt)

      // Check cancellation after async operation to avoid stale state updates
      guard !Task.isCancelled else { return }

      await MainActor.run { [weak self] in
        guard let self, !Task.isCancelled else { return }

        // Only transition if we're still authenticated and terms are actually needed
        if needsReAcceptance, appState == .authenticated {
          isTermsUpdate = termsAcceptedAt != nil
          appState = .termsRequired
        }
      }
    }
  }

  /// Cancel all tracked background tasks
  /// Called during sign out to prevent stale state updates
  private func cancelAllBackgroundTasks() {
    backgroundTasks.forEach { $0.cancel() }
    backgroundTasks.removeAll()
  }

  /// Run a background task and track it for cancellation/cleanup.
  private func runTrackedTask(_ operation: @escaping @Sendable () async -> Void) {
    let task = Task {
      await operation()
    }
    backgroundTasks.append(task)
    // Cleanup task waits for completion then removes from tracking array
    Task { [weak self, task] in
      _ = await task.value
      await MainActor.run {
        self?.backgroundTasks.removeAll { $0 == task }
      }
    }
  }

  private func isLaunchSessionTimeoutError(_ error: Error) -> Bool {
    guard let timeoutError = error as? AuthSessionManagerError else { return false }
    switch timeoutError {
    case .sessionFetchTimedOut, .refreshTimedOut:
      return true
    }
  }

  private func incrementLaunchSessionTimeoutCount() -> Int {
    let current = UserDefaults.standard.integer(forKey: Self.launchSessionTimeoutCountKey)
    let updated = current + 1
    UserDefaults.standard.set(updated, forKey: Self.launchSessionTimeoutCountKey)
    return updated
  }

  private func resetLaunchSessionTimeoutCount() {
    UserDefaults.standard.removeObject(forKey: Self.launchSessionTimeoutCountKey)
  }

  /// After repeated launch-time auth session timeouts, force a stable fallback state.
  /// Timeouts can be transient, so avoid destructive cache/session purges here.
  private func handleRepeatedLaunchSessionTimeoutIfNeeded(previousState: AppState = .loading)
    -> Bool
  {
    let timeoutCount = incrementLaunchSessionTimeoutCount()
    guard timeoutCount >= Self.launchSessionTimeoutRecoveryThreshold else {
      return false
    }

    launchLog.error(
      "[Launch] Repeated auth session timeouts (\(timeoutCount)); forcing stable fallback state"
    )

    applyRecoverableAuthFailureFallback(previousState: previousState)
    resetLaunchSessionTimeoutCount()
    return true
  }

  /// Recover from transient auth/session failures without forcing a destructive sign-out.
  /// If we were previously in a stable state, restore it; otherwise pick a safe fallback.
  private func applyRecoverableAuthFailureFallback(previousState: AppState) {
    let fallbackState: AppState
    switch previousState {
    case .authenticated, .termsRequired, .mfaRequired, .unauthenticated:
      fallbackState = previousState

    case .loading:
      fallbackState = userId != nil ? .authenticated : .unauthenticated
    }

    if self.appState != fallbackState {
      launchLog.warning(
        "[Auth] Recoverable session failure; transitioning \(String(describing: self.appState)) -> \(String(describing: fallbackState))"
      )
      self.appState = fallbackState
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
      // Use AuthSessionManager to prevent concurrent refresh race conditions
      let session = try await AuthSessionManager.shared.getSession()
      let user = session.user

      // Store user ID
      let currentUserId = user.normalizedId
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

      // Register only if permission already exists. First-run onboarding should not be
      // interrupted by the system notification prompt.
      await NotificationService.shared.registerIfPermissionAlreadyGranted()

      // Trigger initial sync in background after authentication
      triggerInitialSync(userId: currentUserId)

      if let appDelegate = (UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared {
        let expectedUserId = currentUserId
        runTrackedTask { [weak self] in
          guard let self else { return }
          let isCurrent = await MainActor.run { self.userId == expectedUserId }
          guard isCurrent else { return }
          await appDelegate.registerCachedAPNsTokenIfNeeded()
        }
      }

      // Profile picture and appearance will be loaded from local store after sync completes
      // For now, check local settings repository for cached values
      if let settings = SettingsRepository.shared.getSettings(for: currentUserId) {
        userAvatarUrl = settings.profile_picture_url
        AppearanceManager.shared.loadFromSettings(settings.theme)
        AppearanceManager.shared.loadCalendarContentColorStyleFromSettings(
          settings.effectiveCalendarContentColorStyle)
        UserDefaults.standard.set(
          settings.effectiveDefaultStartupTab,
          forKey: Self.startupTabCacheKey
        )
        WageyViewModel.shared.refreshEntryState()
      }

    } catch {
      userDisplayName = "User"
    }
  }

  // MARK: - StoreKit & Entitlements

  /// Configure StoreKit and entitlement services after authentication
  /// Called once during updateUserProfile() after successful login
  private func configureStoreKitAndEntitlements(userId: String) async {  // swiftlint:disable:this async_without_await
    // 1. Configure StoreKit with user ID (required before purchases)
    StoreKitManager.shared.configure(userId: userId)

    // 2. Load cached entitlement first (fast, offline-safe)
    EntitlementService.shared.loadFromCache(userId: userId)

    // 3. Start StoreKit transaction listener (handles renewals, restores from other devices)
    StoreKitManager.shared.startListening()

    // 4. Start JWS upload worker (process any pending uploads from previous sessions)
    JWSUploadWorker.shared.processQueue()

    // 5. Refresh entitlement from server in background (non-blocking)
    runTrackedTask { [weak self] in
      guard let self else { return }
      let isCurrent = await MainActor.run { self.userId == userId }
      guard isCurrent else { return }
      try? await EntitlementService.shared.refreshFromServer(userId: userId)
      // Silent on success or failure - we have cache fallback
    }

    // 6. Load StoreKit products in background (for paywall)
    runTrackedTask { [weak self] in
      guard let self else { return }
      let isCurrent = await MainActor.run { self.userId == userId }
      guard isCurrent else { return }
      await StoreKitManager.shared.loadProducts()
    }
  }

  // MARK: - Sync Triggers

  /// Trigger initial sync after authentication
  private func triggerInitialSync(userId: String) {
    initialSyncComplete = false
    let coordinator = syncCoordinator

    runTrackedTask { [weak self] in
      guard let self else { return }
      await coordinator.loadTrackingState(userId: userId)
      _ = await coordinator.sync(reason: .appLaunch, userId: userId)

      let settings = await MainActor.run { () -> UserSettings? in
        guard self.userId == userId else { return nil }
        self.initialSyncComplete = true
        let settings = SettingsRepository.shared.getSettings(for: userId)
        WageyViewModel.shared.refreshEntryState()
        return settings
      }

      if let settings {
        await MainActor.run {
          self.userAvatarUrl = settings.profile_picture_url
          AppearanceManager.shared.loadFromSettings(settings.theme)
          AppearanceManager.shared.loadCalendarContentColorStyleFromSettings(
            settings.effectiveCalendarContentColorStyle)
          UserDefaults.standard.set(
            settings.effectiveDefaultStartupTab,
            forKey: Self.startupTabCacheKey
          )
        }
      }

      // Update Apple Watch with latest shift data after initial sync
      let shouldNotifyWatch = await MainActor.run { self.userId == userId }
      if shouldNotifyWatch {
        await MainActor.run {
          WatchConnectivityManager.shared.sendUpdatedData(userId: userId)
        }
      }
    }
  }

  /// Called when app returns to foreground
  /// Triggers a sync with interval guard (won't sync if recent sync occurred)
  func handleAppForeground() {
    guard appState == .authenticated else { return }

    runTrackedTask { [weak self] in
      guard let self else { return }
      do {
        // Use AuthSessionManager to prevent concurrent refresh race conditions
        let session = try await AuthSessionManager.shared.getSession()
        await MainActor.run {
          self.resetLaunchSessionTimeoutCount()
        }
        let userId = session.normalizedUserId

        // If userId already exists, ensure it matches the current session
        let currentUserId = await Task { @MainActor in self.userId }.value
        if let currentUserId, currentUserId != userId {
          return
        }

        if let appDelegate = await MainActor.run(body: {
          (UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared
        }) {
          await appDelegate.registerCachedAPNsTokenIfNeeded()
        }

        await syncCoordinator.loadTrackingState(userId: userId)
        _ = await syncCoordinator.sync(reason: .foreground, userId: userId)

        // Update Apple Watch with latest shift data after foreground sync
        let currentUserIdAfterSync = await Task { @MainActor in self.userId }.value
        if let currentUserIdAfterSync, currentUserIdAfterSync != userId {
          return
        }
        await Task { @MainActor in
          await NotificationService.shared.refreshApplicationBadgeCount(viewerUserId: userId)
        }.value
        await Task { @MainActor in
          WatchConnectivityManager.shared.sendUpdatedData(userId: userId)
        }.value

        // Re-evaluate completed-shift celebration after foreground sync (or sync skip).
        await Task { @MainActor in
          if let currentUserId = self.userId, currentUserId != userId { return }
          ShiftCompletionCelebrationManager.shared.checkForCelebrationFromLocal(userId: userId)
        }.value
      } catch {
        if await AuthSessionManager.shared.isSessionRevokedError(error) {
          launchLog.warning(
            "[Auth] Foreground session fetch detected revoked session; transitioning to unauthenticated"
          )
          await MainActor.run {
            AuthDiagnosticsReporter.shared.record(
              .revokedSessionDetected,
              severity: .error,
              userId: self.userId,
              appState: String(describing: self.appState),
              error: error,
              metadata: self.authFailureMetadata(
                error,
                reason: "foreground_revoked_session",
                previousState: self.appState
              )
            )
          }
          try? await supabase.auth.signOut(scope: .local)
          Task { @MainActor [weak self] in
            guard let self else { return }
            await clearAllCachedData()
            applySignedOutState()
          }
          return
        }

        if await AuthSessionManager.shared.isTransientNetworkError(error)
          || (error as? AuthSessionManagerError) != nil
        {
          launchLog.warning(
            "[Auth] Foreground session fetch transient failure; keeping authenticated state")
          await MainActor.run {
            AuthDiagnosticsReporter.shared.record(
              .foregroundSessionFailed,
              severity: .warning,
              userId: self.userId,
              appState: String(describing: self.appState),
              error: error,
              metadata: self.authFailureMetadata(
                error,
                reason: "foreground_transient_failure",
                previousState: self.appState
              )
            )
          }
          return
        }

        launchLog.warning(
          "[Auth] Foreground session fetch failed: \(error.localizedDescription, privacy: .public)")
        await MainActor.run {
          AuthDiagnosticsReporter.shared.record(
            .foregroundSessionFailed,
            severity: .warning,
            userId: self.userId,
            appState: String(describing: self.appState),
            error: error,
            metadata: self.authFailureMetadata(
              error,
              reason: "foreground_session_failure",
              previousState: self.appState
            )
          )
        }
      }
    }
  }

  /// Called when login is successful
  /// The auth state listener will handle the transition
  func handleLoginSuccess() async {
    await checkMFAAndUpdateState()
  }

  /// Called when MFA verification is successful
  /// Note: We don't clear pendingMFAFactor here - the .mfaChallengeVerified auth event
  /// will clear it after setting appState. Clearing it synchronously before the state
  /// changes causes a flash where RootView shows AuthNavigationView as a fallback.
  func handleMFASuccess() {
    // Set flag for DashboardView to play release haptic when fully rendered
    didJustCompleteMFA = true
    runTrackedTask { [weak self] in
      guard let self else { return }
      // After MFA, check if terms acceptance is needed
      await Task { @MainActor in
        await self.checkTermsAndUpdateState()
      }.value
    }
  }

  /// Called when terms are accepted
  func handleTermsAccepted() {
    isTermsUpdate = false
    // Reset initialSyncComplete BEFORE setting authenticated state
    // This ensures DashboardView shows loading instead of empty state
    initialSyncComplete = false
    appState = .authenticated
    runTrackedTask { [weak self] in
      guard let self else { return }
      await Task { @MainActor in
        await self.updateUserProfile()
      }.value
    }
  }

  /// Called when user declines terms (signs out)
  func handleTermsDeclined() async {
    await signOut()
  }

  /// Sign out the user from this device only (local scope)
  /// Other devices will remain logged in
  func signOut() async {
    await performSignOut(global: false)
  }

  /// Sign out the user from ALL devices (global scope)
  /// This invalidates all refresh tokens across all devices
  func signOutGlobal() async {
    await performSignOut(global: true)
  }

  /// Internal sign out implementation
  /// - Parameter global: If true, signs out from all devices; if false, only this device
  private func performSignOut(global: Bool) async {
    isUserInitiatedSignOutInProgress = true
    AuthDiagnosticsReporter.shared.record(
      .userInitiatedSignOut,
      severity: .info,
      userId: userId,
      appState: String(describing: appState),
      metadata: ["global": .bool(global)]
    )
    OnboardingCurrencyCarryoverStore.clearPreferredCurrency()

    // Remove the authenticated device association before destroying the session so
    // a signed-out device cannot receive push-to-start Live Activity notifications.
    await LiveActivityPushTokenService.shared.unregisterCurrentDevice()

    // Clear all cached data
    await clearAllCachedData()

    do {
      if global {
        try await authService.signOutGlobal()
      } else {
        try await authService.signOut()
      }
    } catch {
      // Fallback: ensure local session is cleared even if primary sign-out call failed.
      try? await supabase.auth.signOut(scope: .local)
    }

    // Always transition immediately; auth listener can still emit signedOut afterward.
    applySignedOutState()
  }

  /// Clear all cached data without signing out
  /// Used during sign out and when switching user context (impersonation)
  private func clearAllCachedData() async {
    // Cancel all tracked background tasks to prevent stale state updates
    cancelAllBackgroundTasks()

    // Invalidate any queued widget refreshes before clearing shared state so
    // background tasks cannot repopulate App Group data after sign-out.
    await NativeWidgetStorage.invalidatePendingRefreshes()

    if let appDelegate = (UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared {
      await appDelegate.endAllLiveActivities(reason: "auth/session context reset")
    }

    // Reset in-memory Wagey state so consent/chat state cannot leak across users
    WageyViewModel.shared.resetForUserChange()

    // Clear widget storage
    NativeWidgetStorage.clearWidgetStorage()
    NativeWidgetStorage.clearFriendWidgetStorage()

    // Clear paired Watch payload so stale shifts are not shown after sign-out.
    WatchConnectivityManager.shared.sendClearedData()

    // Clear shared keychain (widget/watch access token)
    AuthSessionManager.shared.clearSharedKeychain()
    CalendarSubscriptionStore.shared.resetForUserChange()
    CalendarSubscriptionStore.clearStoredTokensForUserReset()

    // Stop StoreKit listener and clear entitlement cache
    StoreKitManager.shared.stopListening()
    await EntitlementService.shared.clearCache()

    // Clear all local data (shifts, settings, sync state, etc.)
    await LocalStore.shared.resetAllData()

    // Clear image cache
    ImageCache.shared.clearAll()
    NotificationService.shared.setApplicationBadgeCount(0)

    if let bundleId = Bundle.main.bundleIdentifier {
      let seenPreAuthOnboarding = UserDefaults.standard.bool(
        forKey: "hasCompletedPreAuthOnboarding")
      UserDefaults.standard.removePersistentDomain(forName: bundleId)
      if seenPreAuthOnboarding {
        UserDefaults.standard.set(true, forKey: "hasCompletedPreAuthOnboarding")
      }
    }

    // Reset sync coordinator state for new user
    // This clears the interval guard so the next user's initial sync isn't blocked
    await syncCoordinator.resetForUserChange()

    initialSyncComplete = false
  }

  private func applySignedOutState() {
    resetLaunchSessionTimeoutCount()
    isUserInitiatedSignOutInProgress = false
    appState = .unauthenticated
    pendingMFAFactor = nil
    userId = nil
    userDisplayName = ""
    userAvatarUrl = nil
    hasFinishedOnboardingRemotely = false
    postAuthOnboardingPresentation = .none
    initialSyncComplete = false
    NotificationService.shared.setApplicationBadgeCount(0)
  }

  /// Force a session check (useful for debugging or manual refresh)
  func checkSession() async {
    let previousState = appState
    appState = .loading

    do {
      if try await authService.getSession() != nil {
        resetLaunchSessionTimeoutCount()
        // Recovery / manual refresh — skip MFA, just check terms
        await checkTermsAndUpdateState()
      } else {
        appState = .unauthenticated
      }
    } catch {
      if isLaunchSessionTimeoutError(error) {
        if handleRepeatedLaunchSessionTimeoutIfNeeded(previousState: previousState) {
          return
        }
        launchLog.warning("[Launch] checkSession timed out; applying non-destructive fallback")
        applyRecoverableAuthFailureFallback(previousState: previousState)
        return
      }

      // Avoid false logout loops when startup auth hits transient network/session timeouts.
      if AuthSessionManager.shared.isTransientNetworkError(error)
        || (error as? AuthSessionManagerError) != nil
      {
        launchLog.warning(
          "[Launch] checkSession transient failure; applying non-destructive fallback")
        AuthDiagnosticsReporter.shared.record(
          .recoverableAuthFailure,
          severity: .warning,
          userId: userId,
          appState: String(describing: previousState),
          error: error,
          metadata: authFailureMetadata(
            error,
            reason: "manual_check_recoverable_failure",
            previousState: previousState
          )
        )
        applyRecoverableAuthFailureFallback(previousState: previousState)
        return
      }
      AuthDiagnosticsReporter.shared.record(
        .forcedUnauthenticated,
        severity: .warning,
        userId: userId,
        appState: String(describing: previousState),
        error: error,
        metadata: authFailureMetadata(
          error,
          reason: "manual_check_forced_unauthenticated",
          previousState: previousState
        )
      )
      appState = .unauthenticated
    }
  }

  private func recordAuthStateEvent(_ event: AuthChangeEvent, session: Session?) {
    let eventName = String(describing: event)
    if let session {
      AuthDiagnosticsReporter.shared.rememberAuthenticatedUserId(session.normalizedUserId)
    }

    var metadata: [String: AnyJSON] = ["has_session": .bool(session != nil)]
    if let session {
      metadata.merge(
        AuthDiagnosticsReporter.shared.sessionMetadata(session, source: "auth_state_event")
      ) { current, _ in current }
    }

    AuthDiagnosticsReporter.shared.record(
      event == .initialSession && session != nil ? .initialSessionReceived : .authStateChanged,
      severity: authStateEventSeverity(event),
      userId: session?.normalizedUserId ?? userId,
      appState: String(describing: appState),
      authEvent: eventName,
      metadata: metadata
    )
  }

  private func authStateEventSeverity(
    _ event: AuthChangeEvent
  ) -> AuthDiagnosticsReporter.Severity {
    switch event {
    case .signedOut:
      return isUserInitiatedSignOutInProgress || appState == .unauthenticated
        ? .info : .warning

    default:
      return .debug
    }
  }

  private func currentLaunchSessionTimeoutCount() -> Int {
    UserDefaults.standard.integer(forKey: Self.launchSessionTimeoutCountKey)
  }

  private func authFailureMetadata(
    _ error: Error,
    reason: String,
    previousState: AppState
  ) -> [String: AnyJSON] {
    [
      "reason": .string(reason),
      "previous_app_state": .string(String(describing: previousState)),
      "current_app_state": .string(String(describing: appState)),
      "did_receive_initial_session": .bool(didReceiveInitialSession),
      "is_updating_auth_state": .bool(isUpdatingAuthState),
      "launch_session_timeout_count": .integer(currentLaunchSessionTimeoutCount()),
      "is_revoked_error": .bool(AuthSessionManager.shared.isSessionRevokedError(error)),
      "is_transient_network_error": .bool(AuthSessionManager.shared.isTransientNetworkError(error)),
      "is_transient_session_resolution_error": .bool(
        AuthSessionManager.shared.isTransientSessionResolutionError(error)
      ),
    ]
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
  /// Called from AppLifecycleHandler when the app receives a tidex:// URL
  ///
  /// Supported URL formats:
  /// - tidex://sharing?user=<userId> → Navigate to sharing tab and select the sharer
  /// - tidex://sharing/manage?highlight=<userId> → Open manage modal and highlight user
  /// - tidex://shifts?dates=2025-01-15,2025-01-16 → Navigate to shifts with dates selected
  /// - tidex://shifts?shiftIds=<uuid>&dates=2025-01-15&action=highlight → Highlight/open specific shifts
  /// - tidex://settings/pay?jobId=<uuid> → Open pay settings
  /// - tidex://admin?tab=reports&reportId=<uuid> → Open admin reports
  func handleDeepLink(_ url: URL) {
    guard let deepLink = AppDeepLinkResolver.resolve(url) else { return }
    pendingDeepLink = deepLink
  }

  /// Clear the pending deep link after it has been consumed
  func clearPendingDeepLink() {
    pendingDeepLink = nil
  }

  // MARK: - Impersonation Support

  /// Prepare for user context switch (before setting new session)
  /// Clears all cached data without signing out
  /// Called by ImpersonationManager BEFORE setting the impersonated user's session
  func prepareForUserSwitch() async {
    await clearAllCachedData()
  }

  /// Complete user context switch (after setting new session)
  /// Reloads user profile and waits for sync to complete
  /// Called by ImpersonationManager AFTER setting the new session
  func completeUserSwitch() async {
    do {
      // Use AuthSessionManager to prevent concurrent refresh race conditions
      let session = try await AuthSessionManager.shared.getSession()
      let user = session.user
      let currentUserId = user.normalizedId

      // Store user ID
      self.userId = currentUserId

      // Load onboarding state
      loadOnboardingStateFromUser(user)

      // Extract display name
      if let fullName = user.userMetadata["full_name"]?.value as? String, !fullName.isEmpty {
        userDisplayName = fullName
      } else if let name = user.userMetadata["name"]?.value as? String, !name.isEmpty {
        userDisplayName = name
      } else if let email = user.email {
        userDisplayName = email.components(separatedBy: "@").first ?? email
      } else if let phone = user.phone {
        userDisplayName = phone
      } else {
        userDisplayName = "User"
      }

      // Configure StoreKit and load entitlements
      await configureStoreKitAndEntitlements(userId: currentUserId)

      // Register only if permission already exists. Do not prompt during account switching.
      await NotificationService.shared.registerIfPermissionAlreadyGranted()

      // Load cached avatar
      if let settings = SettingsRepository.shared.getSettings(for: currentUserId) {
        userAvatarUrl = settings.profile_picture_url
        AppearanceManager.shared.loadFromSettings(settings.theme)
        AppearanceManager.shared.loadCalendarContentColorStyleFromSettings(
          settings.effectiveCalendarContentColorStyle)
        UserDefaults.standard.set(
          settings.effectiveDefaultStartupTab,
          forKey: Self.startupTabCacheKey
        )
      }

      // Register APNs token if available
      // Skip during impersonation to prevent registering the admin's device
      // token under the impersonated user's account
      if !ImpersonationManager.shared.isImpersonating,
        let appDelegate = (UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared
      {
        await appDelegate.registerCachedAPNsTokenIfNeeded()
      }

      // Run sync and WAIT for it to complete (unlike normal flow which runs in background)
      initialSyncComplete = false
      await syncCoordinator.loadTrackingState(userId: currentUserId)
      _ = await syncCoordinator.sync(reason: .appLaunch, userId: currentUserId)
      initialSyncComplete = true

      // Update avatar from synced settings
      if let settings = SettingsRepository.shared.getSettings(for: currentUserId) {
        userAvatarUrl = settings.profile_picture_url
        AppearanceManager.shared.loadFromSettings(settings.theme)
        AppearanceManager.shared.loadCalendarContentColorStyleFromSettings(
          settings.effectiveCalendarContentColorStyle)
        UserDefaults.standard.set(
          settings.effectiveDefaultStartupTab,
          forKey: Self.startupTabCacheKey
        )
      }

      // Update Apple Watch
      WatchConnectivityManager.shared.sendUpdatedData(userId: currentUserId)

    } catch {
      userDisplayName = "User"
    }
  }
}

#if DEBUG
  extension AppCoordinator {
    func configureForUITesting(
      userId: String,
      displayName: String,
      avatarUrl: String? = nil
    ) {
      self.userId = userId
      self.userDisplayName = displayName
      self.userAvatarUrl = avatarUrl
      self.hasFinishedOnboardingRemotely = true
      self.initialSyncComplete = true
      self.appState = .authenticated
      self.pendingDeepLink = nil
      self.pendingMFAFactor = nil
      self.postAuthOnboardingPresentation = .none
    }
  }
#endif
