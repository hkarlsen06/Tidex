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
import Observation
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
@Observable
final class AppCoordinator {
  static let shared = AppCoordinator()
  /// UserDefaults key for the cached startup tab, read by `MainTabView` before settings load.
  static let startupTabCacheKey = "defaultStartupTab"

  // MARK: - Navigation State

  enum AppState: Equatable {
    case loading  // Initial app load, checking session
    case unauthenticated  // No valid session, show login
    case mfaRequired  // User logged in but needs MFA verification
    case termsRequired  // User needs to accept updated terms
    case authenticated  // Fully authenticated, show main app
  }

  private(set) var appState: AppState = .loading

  // MARK: - MFA State

  /// MFA factor to verify (when state is .mfaRequired)
  private(set) var pendingMFAFactor: AuthService.MFAFactor?

  // MARK: - Deep Link Navigation State

  /// Pending deep link navigation to execute after authentication/tab setup
  var pendingDeepLink: DeepLink?

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
    case sharingManage(highlightUserId: String?)  // Open a friend's profile, or the add friend sheet
    case friendChat(
      threadId: String,
      messageId: String?,
      senderUserId: String?,
      typingUserId: String?,
      navigationRequestId: UUID?
    )  // Navigate to a direct friend chat thread
    case addShift(mode: AddShiftMode?, date: String?)  // Navigate to Add Shift, optionally selecting a mode/date
    case settings(destination: SettingsDeepLinkDestination?)  // Open settings, optionally at a subpage
    case feedback  // Navigate to feedback settings (for users receiving response)
    case adminFeedback  // Navigate to admin panel with feedback tab (for admins receiving new feedback)
    case adminReport(reportId: String?)  // Open admin panel on reports tab and optionally select a report
  }

  enum SettingsDeepLinkDestination: Equatable {
    case profile
    case security
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
  private(set) var isTermsUpdate: Bool = false

  // MARK: - User Profile State

  /// Current user's ID (lowercase UUID string)
  private(set) var userId: String? {
    didSet {
      if oldValue != userId {
        resetPayrollCaches()
      }
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
        return String(localized: .commonErrorNotAuthenticated)
      }
    }
  }

  // MARK: - Safe User ID Access

  /// Safely get the current user ID, or nil if not authenticated
  /// Use this when the operation can gracefully handle a missing user ID
  func getCurrentUserId() -> String? {
    return userId
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

  /// User's display name (for the profile tab)
  private(set) var userDisplayName: String = ""
  /// User's profile picture URL (for the profile tab)
  private(set) var userAvatarUrl: String?
  /// Whether the user has already completed onboarding (from Supabase user metadata)
  private(set) var hasFinishedOnboardingRemotely: Bool = false

  // MARK: - Sync State

  /// Whether initial sync has completed after authentication
  private(set) var initialSyncComplete = false

  // MARK: - MFA Completion State

  /// Flag indicating MFA was just completed - consumed by DashboardView for haptic feedback
  var didJustCompleteMFA = false

  // MARK: - Dependencies

  private let authService: AuthService
  private let settingsService: SettingsService
  private let syncCoordinator: SyncCoordinator

  // MARK: - Private

  @ObservationIgnored private var authStateTask: Task<Void, Never>?
  @ObservationIgnored private var friendsRealtimeTask: Task<Void, Never>?
  @ObservationIgnored private var appActiveObserver: AnyCancellable?
  @ObservationIgnored private var backgroundTasks: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var foregroundTask: Task<Void, Never>?
  @ObservationIgnored private var didReceiveInitialSession = false
  @ObservationIgnored private var isUpdatingAuthState = false
  @ObservationIgnored private var isUserInitiatedSignOutInProgress = false
  /// Set when the terms check could not reach the manifest. Cleared by `recheckTermsIfPending`.
  @ObservationIgnored private var isTermsRecheckPending = false

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
    #if DEBUG
      if AppStoreScreenshotFixture.isActive {
        userId = AppStoreScreenshotFixture.userId
        userDisplayName = AppStoreScreenshotFixture.displayName
        userAvatarUrl = AppStoreScreenshotFixture.avatarURL
        appState = .authenticated
        initialSyncComplete = true
        hasFinishedOnboardingRemotely = true
        return
      }
    #endif
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
    setupMaxLoadingTimeout()
    launchLog.info("[Launch] AppCoordinator.init END")
  }

  deinit {
    authStateTask?.cancel()
    friendsRealtimeTask?.cancel()
    appActiveObserver?.cancel()
    backgroundTasks.values.forEach { $0.cancel() }
    foregroundTask?.cancel()
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

  // MARK: - Launch Timeouts

  /// Timeout for MFA/terms network checks (in nanoseconds)
  /// If these checks hang (slow network, unresponsive server), fall back to .authenticated
  private static let authCheckTimeout: UInt64 = 10_000_000_000  // 10 seconds

  /// Hard maximum time the app can stay in .loading state (in nanoseconds)
  /// After this, force a transition out regardless of what's pending
  private static let maxLoadingTimeout: UInt64 = 15_000_000_000  // 15 seconds

  /// Number of repeated launch/session timeouts before we force a stable fallback state.
  private static let launchSessionTimeoutRecoveryThreshold = 3
  private static let launchSessionTimeoutCountKey = "auth.launch_session_timeout_count"

  /// Hard deadline: if the app is still in .loading after maxLoadingTimeout,
  /// force a transition out. Prefers .authenticated when a local session exists
  /// (preserving offline usage) and only falls back to .unauthenticated when
  /// there is genuinely no session.
  private func setupMaxLoadingTimeout() {
    runTrackedTask { [weak self] in
      try? await Task.sleep(nanoseconds: Self.maxLoadingTimeout)
      guard let self, !Task.isCancelled, appState == .loading else { return }

      isUpdatingAuthState = false

      let session = await AuthSessionManager.shared.getSessionOrLocal()
      // The normal launch flow may have finished while the stored session loaded.
      guard appState == .loading else { return }

      if let session {
        if await routeToMFAIfRequired(session) { return }
        launchLog.error("[Launch] Hard loading timeout (15s) – proceeding to authenticated")
        AuthDiagnosticsReporter.shared.rememberAuthenticatedUserId(session.normalizedUserId)
        await enterAuthenticatedState(user: session.user)
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
    }
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
          // The client sets emitLocalSessionAsInitialSession, so this event comes from local
          // storage on every launch without waiting for the network.
          didReceiveInitialSession = true

          // On app launch, check if we have a valid session
          if let session {
            AuthDiagnosticsReporter.shared.rememberAuthenticatedUserId(session.normalizedUserId)
            resetLaunchSessionTimeoutCount()
            // Check restored impersonation before asking for the session owner's MFA.
            if await routeToMFAIfRequired(session) { break }
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
          if !isExpectedSignOut {
            // The SDK ended the session (for example a revoked refresh token). The
            // server calls need a session, but the device-local cleanup still applies.
            await clearSignedOutDeviceState()
            // The local store stays, so mark whose it is. A different user signing in wipes it.
            retainLocalData(for: userId)
          }
          applySignedOutState()

        case .tokenRefreshed:
          // A launch without network can leave userId unset. Finish it now that the
          // refresh worked.
          if userId == nil, appState == .authenticated, session != nil {
            await updateUserProfile()
          }

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

    await discardRetainedLocalDataIfUserChanged()

    let stateBeforeCheck = appState
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

    guard !didComplete else { return }
    // The terms check may have been cut short. Check again on the next foreground.
    isTermsRecheckPending = true

    // The task group waits for the cancelled check, and its error fallbacks usually route
    // on their own. Routing again would repeat the profile load and the initial sync.
    guard appState == stateBeforeCheck || appState == .loading else { return }

    // This method is only called when a session is known to exist, so default to
    // authenticated rather than kicking the user to the login screen.
    launchLog.error("[Launch] Auth check timed out after 10s, proceeding to authenticated")
    let session = await AuthSessionManager.shared.getSessionOrLocal()
    if let session, await routeToMFAIfRequired(session) { return }
    await enterAuthenticatedState(user: session?.user)
  }

  /// Performs the actual MFA status check and terms verification.
  /// Extracted from checkMFAAndUpdateState so it can be wrapped in a timeout.
  private func performMFAAndTermsCheck() async {
    if ImpersonationManager.shared.isImpersonating,
      let session = await AuthSessionManager.shared.getSessionOrLocal()
    {
      if await routeToMFAIfRequired(session) { return }
      await checkTermsAndUpdateState(initialSession: session)
      return
    }
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
      // Fall back to the stored session so a failed check can't skip MFA.
      if let session = await AuthSessionManager.shared.getSessionOrLocal(
        allowProactiveRefresh: false
      ), await routeToMFAIfRequired(session) {
        return
      }
      await checkTermsAndUpdateState()
    }
  }

  enum MFARoute {
    case notRequired
    case resume(Session)
    case verification(AuthService.MFAFactor)
    case retry
    case signedOut
  }

  /// Resolve impersonation before inspecting the target user's factors.
  static func resolveMFARoute(
    session: Session,
    isImpersonating: () -> Bool,
    validateImpersonation: () async -> Session?,
    currentSession: () async -> Session?
  ) async -> MFARoute {
    let wasImpersonating = isImpersonating()
    var resolvedSession = session
    if wasImpersonating {
      if let validated = await validateImpersonation() {
        return .resume(validated)
      }
      // Validation leaves the stored impersonation intact on a transient failure.
      guard !isImpersonating() else { return .retry }
      guard let restored = await currentSession() else { return .signedOut }
      resolvedSession = restored
    }
    if assuranceLevel(fromAccessToken: resolvedSession.accessToken) != "aal2",
      let factor = resolvedSession.user.factors?.first(where: {
        $0.factorType == "totp" && $0.status == .verified
      })
    {
      return .verification(AuthService.MFAFactor(
        id: factor.id, type: factor.factorType,
        friendlyName: factor.friendlyName, status: factor.status.rawValue))
    }
    return wasImpersonating ? .resume(resolvedSession) : .notRequired
  }

  /// Returns true when this method handled routing, including restoration of an admin session.
  private func routeToMFAIfRequired(_ session: Session) async -> Bool {
    let impersonation = ImpersonationManager.shared
    let route = await Self.resolveMFARoute(
      session: session,
      isImpersonating: { impersonation.isImpersonating },
      validateImpersonation: { await impersonation.validateSessionOnLaunch() },
      currentSession: { await AuthSessionManager.shared.getSessionOrLocal() })
    switch route {
    case .notRequired:
      return false
    case .resume(let resolvedSession):
      await checkTermsAndUpdateState(initialSession: resolvedSession)
    case .verification(let factor):
      pendingMFAFactor = factor
      appState = .mfaRequired
    case .retry:
      appState = .loading
    case .signedOut:
      appState = .unauthenticated
    }
    return true
  }

  /// Decodes the `aal` claim from a JWT access token without verifying it.
  nonisolated static func assuranceLevel(fromAccessToken token: String) -> String? {
    let segments = token.split(separator: ".")
    guard segments.count == 3 else { return nil }
    var base64 = segments[1]
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    guard let data = Data(base64Encoded: base64),
      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    return payload["aal"] as? String
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
      var needsReAcceptanceImmediate = TermsVersion.needsTermsReAcceptance(termsAcceptedAt)

      // The fallback version is only a guess. A user who accepted before and can't reach
      // the manifest would be stuck on a screen that needs the network, so let them in
      // and check again once online.
      if needsReAcceptanceImmediate, termsAcceptedAt != nil {
        if let live = await TermsVersion.needsTermsReAcceptanceIfReachable(termsAcceptedAt) {
          needsReAcceptanceImmediate = live
        } else {
          needsReAcceptanceImmediate = false
          isTermsRecheckPending = true
        }
      }

      if needsReAcceptanceImmediate {
        // User definitely needs to accept terms (based on cached/fallback version)
        self.isTermsUpdate = termsAcceptedAt != nil
        self.appState = .termsRequired
      } else {
        // Terms appear up to date - proceed to authenticated immediately
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
        await enterAuthenticatedState(user: user)

        // Check in background if API has a newer terms version
        // This handles the case where terms were updated but we're using stale cache
        self.checkTermsVersionInBackground(termsAcceptedAt: termsAcceptedAt)
      }
    } catch {
      // If we can't check terms, proceed to authenticated and let backend handle it
      let session = await AuthSessionManager.shared.getSessionOrLocal(
        allowProactiveRefresh: allowProactiveRefresh
      )
      if let session {
        AuthDiagnosticsReporter.shared.rememberAuthenticatedUserId(session.normalizedUserId)
      }
      await enterAuthenticatedState(user: session?.user)
    }
  }

  /// Shows the main app and loads the profile, which sets `userId` and starts the initial
  /// sync. Don't set `userId` by hand instead: the later recovery paths only load the
  /// profile while `userId` is nil, so the dashboard would wait for a sync that never starts.
  private func enterAuthenticatedState(user: User?) async {
    // Load onboarding state before the state change so post-auth onboarding doesn't flash.
    if let user {
      loadOnboardingStateFromUser(user)
    }
    initialSyncComplete = false
    appState = .authenticated
    await updateUserProfile()
  }

  /// Background check for terms version update
  /// Fetches latest version from API and transitions to termsRequired if needed
  private func checkTermsVersionInBackground(termsAcceptedAt: String?) {
    runTrackedTask { [weak self] in
      // Fetch latest terms version from API (this may take time on slow networks)
      let needsReAcceptance = await TermsVersion.needsTermsReAcceptanceIfReachable(termsAcceptedAt)

      // Check cancellation after async operation to avoid stale state updates
      guard let self, !Task.isCancelled else { return }

      // Offline: the fallback version must not gate the app. Check again when online.
      guard let needsReAcceptance else {
        isTermsRecheckPending = true
        return
      }

      // Only transition if we're still authenticated and terms are actually needed
      if needsReAcceptance, appState == .authenticated {
        isTermsUpdate = termsAcceptedAt != nil
        appState = .termsRequired
      }
    }
  }

  /// Runs the terms check that was skipped because the manifest was unreachable.
  private func recheckTermsIfPending() {
    guard isTermsRecheckPending, appState == .authenticated else { return }
    isTermsRecheckPending = false
    let termsAcceptedAt =
      AuthSessionManager.shared.localSession()?.user.userMetadata["terms_accepted_at"]?.value
      as? String
    checkTermsVersionInBackground(termsAcceptedAt: termsAcceptedAt)
  }

  /// Cancel all tracked background tasks
  /// Called during sign out to prevent stale state updates
  private func cancelAllBackgroundTasks() {
    backgroundTasks.values.forEach { $0.cancel() }
    backgroundTasks.removeAll()
    cancelForegroundWork()
  }

  /// Runs work on the main actor that sign-out can cancel. Keep the work inside this
  /// task: a `Task {}` started from the closure would keep running after cancellation.
  private func runTrackedTask(_ operation: @escaping @MainActor @Sendable () async -> Void) {
    let id = UUID()
    // Runs after this method returns, because both are on the main actor.
    backgroundTasks[id] = Task { @MainActor [weak self] in
      await operation()
      self?.backgroundTasks[id] = nil
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
    let finishedRemotely = (user.userMetadata["finishedOnboarding"]?.value as? Bool) ?? false
    // Onboarding finished offline is recorded locally until the metadata update reaches the server.
    self.hasFinishedOnboardingRemotely =
      finishedRemotely || OnboardingCompletionStore.isCompletedLocally(userId: user.normalizedId)
  }

  // MARK: - User Profile

  /// Update user profile data (display name and avatar)
  /// Also triggers initial sync in background
  private func updateUserProfile() async {
    do {
      let session = try await sessionForProfileLoad()
      let user = session.user

      // Store user ID
      let currentUserId = user.normalizedId
      self.userId = currentUserId

      // Check if onboarding was already completed (from raw_user_meta_data.finishedOnboarding)
      // Note: loadOnboardingStateFromUser is called earlier, but we update again in case metadata changed
      loadOnboardingStateFromUser(user)
      Task { await OnboardingCompletionStore.retryPendingMetadataIfNeeded(userId: currentUserId) }

      userDisplayName = Self.displayName(for: user)

      // Register only if permission already exists. First-run onboarding should not be
      // interrupted by the system notification prompt.
      await NotificationService.shared.registerIfPermissionAlreadyGranted()

      // Trigger initial sync in background after authentication
      triggerInitialSync(userId: currentUserId)

      if let appDelegate = AppDelegate.shared {
        runTrackedTask { [weak self] in
          guard self?.userId == currentUserId else { return }
          await appDelegate.registerCachedAPNsTokenIfNeeded()
        }
      }

      // The sync refreshes these. Until then, use the cached settings.
      applyCachedSettings(userId: currentUserId)
    } catch {
      userDisplayName = "User"
    }
  }

  /// Display name from user metadata, falling back to the email name or phone number.
  private static func displayName(for user: User) -> String {
    if let fullName = user.userMetadata["full_name"]?.value as? String, !fullName.isEmpty {
      return fullName
    }
    if let name = user.userMetadata["name"]?.value as? String, !name.isEmpty {
      return name
    }
    if let email = user.email {
      return email.components(separatedBy: "@").first ?? email
    }
    return user.phone ?? "User"
  }

  /// Applies the avatar, theme and startup tab from the locally stored settings.
  private func applyCachedSettings(userId: String) {
    guard let settings = SettingsRepository.shared.getSettings(for: userId) else { return }
    userAvatarUrl = settings.profile_picture_url
    AppearanceManager.shared.loadFromSettings(settings.theme)
    AppearanceManager.shared.loadCalendarContentColorStyleFromSettings(
      settings.effectiveCalendarContentColorStyle)
    UserDefaults.standard.set(settings.effectiveDefaultStartupTab, forKey: Self.startupTabCacheKey)
  }

  /// Resolves the session for loading the profile. Offline with an expired access token,
  /// the refresh fails, so fall back to the stored session. The user, onboarding state and
  /// cached settings all come from local data, and the sync retries when the network is back.
  private func sessionForProfileLoad() async throws -> Session {
    do {
      // Use AuthSessionManager to prevent concurrent refresh race conditions
      return try await AuthSessionManager.shared.getSession()
    } catch {
      guard AuthSessionManager.shared.isTransientSessionResolutionError(error),
        let stored = AuthSessionManager.shared.localSession()
      else {
        throw error
      }
      launchLog.warning("[Auth] Session refresh failed transiently; using stored session")
      return stored
    }
  }

  // MARK: - Sync Triggers

  /// Trigger initial sync after authentication
  private func triggerInitialSync(userId: String) {
    initialSyncComplete = false
    let coordinator = syncCoordinator

    runTrackedTask { [weak self] in
      await coordinator.loadTrackingState(userId: userId)
      _ = await coordinator.sync(reason: .appLaunch, userId: userId)
      await FriendsMessageOutbox.shared.drain(userId: userId)

      guard let self, self.userId == userId else { return }
      initialSyncComplete = true
      applyCachedSettings(userId: userId)
    }
  }

  /// Delay before foreground work starts. iOS 26 and later can post didBecomeActive
  /// while the device locks or the app moves to the background.
  private static let foregroundDebounce: Duration = .milliseconds(300)

  /// Called when app returns to foreground
  /// Triggers a sync with interval guard (won't sync if recent sync occurred)
  func handleAppForeground() {
    guard appState == .authenticated else { return }

    foregroundTask?.cancel()
    foregroundTask = Task { [weak self] in
      try? await Task.sleep(for: Self.foregroundDebounce)
      guard !Task.isCancelled, let self, self.appState == .authenticated,
        Self.hasForegroundActiveScene()
      else {
        return
      }
      await refreshAfterForeground()
    }
  }

  /// Called by `ConnectivityMonitor` when the network comes back. Pushes local changes,
  /// bypassing the sync interval guard, and sends queued chat messages.
  func handleConnectivityRestored() async {
    guard appState == .authenticated else { return }
    recheckTermsIfPending()

    // A launch without network can leave userId unset. This also starts the initial sync.
    guard let userId else {
      await updateUserProfile()
      return
    }

    _ = await syncCoordinator.sync(reason: .localChange, userId: userId)
    await FriendsMessageOutbox.shared.drain(userId: userId)
    await OnboardingCompletionStore.retryPendingMetadataIfNeeded(userId: userId)
  }

  /// Cancels pending foreground work. Called when the app resigns active or enters
  /// the background.
  func cancelForegroundWork() {
    foregroundTask?.cancel()
    foregroundTask = nil
  }

  private static func hasForegroundActiveScene() -> Bool {
    UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
  }

  private func refreshAfterForeground() async {
    do {
      // Use AuthSessionManager to prevent concurrent refresh race conditions
      let session = try await AuthSessionManager.shared.getSession()
      guard !Task.isCancelled else { return }
      resetLaunchSessionTimeoutCount()
      let userId = session.normalizedUserId

      // If userId already exists, ensure it matches the current session
      if let currentUserId = self.userId, currentUserId != userId {
        return
      }

      recheckTermsIfPending()

      // A launch without network can leave userId unset. This also starts the initial sync.
      if self.userId == nil {
        await updateUserProfile()
        return
      }

      await AppDelegate.shared?.registerCachedAPNsTokenIfNeeded()

      await syncCoordinator.loadTrackingState(userId: userId)
      _ = await syncCoordinator.sync(reason: .foreground, userId: userId)
      await FriendsMessageOutbox.shared.drain(userId: userId)
      await OnboardingCompletionStore.retryPendingMetadataIfNeeded(userId: userId)

      if let currentUserIdAfterSync = self.userId, currentUserIdAfterSync != userId {
        return
      }
      await NotificationService.shared.refreshApplicationBadgeCount(viewerUserId: userId)

      // Re-evaluate completed-shift celebration after foreground sync (or sync skip).
      if let currentUserId = self.userId, currentUserId != userId { return }
      ShiftCompletionCelebrationManager.shared.checkForCelebrationFromLocal(userId: userId)
    } catch {
      // Work cancelled by resign-active or background is not a session failure.
      guard !Task.isCancelled else { return }

      if AuthSessionManager.shared.isSessionRevokedError(error) {
        launchLog.warning(
          "[Auth] Foreground session fetch detected revoked session; transitioning to unauthenticated"
        )
        AuthDiagnosticsReporter.shared.record(
          .revokedSessionDetected,
          severity: .error,
          userId: userId,
          appState: String(describing: appState),
          error: error,
          metadata: authFailureMetadata(
            error,
            reason: "foreground_revoked_session",
            previousState: appState
          )
        )
        // The refresh token is gone, so unsynced changes can't push. Keep them for the same
        // user's next sign-in. Read this before the local sign-out removes the session.
        let unsyncedUserId = await userIdWithUnsyncedChanges()
        try? await supabase.auth.signOut(scope: .local)
        // Run outside this task: clearAllCachedData() cancels foregroundTask.
        Task { @MainActor [weak self] in
          guard let self else { return }
          await clearAllCachedData(retainingLocalDataFor: unsyncedUserId)
          applySignedOutState()
        }
        return
      }

      if AuthSessionManager.shared.isTransientNetworkError(error)
        || (error as? AuthSessionManagerError) != nil
      {
        launchLog.warning(
          "[Auth] Foreground session fetch transient failure; keeping authenticated state")
        AuthDiagnosticsReporter.shared.record(
          .foregroundSessionFailed,
          severity: .warning,
          userId: userId,
          appState: String(describing: appState),
          error: error,
          metadata: authFailureMetadata(
            error,
            reason: "foreground_transient_failure",
            previousState: appState
          )
        )
        if self.userId == nil {
          await updateUserProfile()
        }
        return
      }

      launchLog.warning(
        "[Auth] Foreground session fetch failed: \(error.localizedDescription, privacy: .public)")
      AuthDiagnosticsReporter.shared.record(
        .foregroundSessionFailed,
        severity: .warning,
        userId: userId,
        appState: String(describing: appState),
        error: error,
        metadata: authFailureMetadata(
          error,
          reason: "foreground_session_failure",
          previousState: appState
        )
      )
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
      // After MFA, check if terms acceptance is needed
      await self?.checkTermsAndUpdateState()
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
      await self?.updateUserProfile()
    }
  }

  /// Called when user declines terms (signs out)
  func handleTermsDeclined() async {
    await signOutKeepingUnsyncedChanges()
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

  /// Pushes local changes before a user-initiated sign-out.
  /// - Returns: false when changes are still unsynced, so signing out would delete them.
  func syncPendingChangesBeforeSignOut() async -> Bool {
    // Before the profile loads (MFA, terms) userId is nil, so use the stored session.
    // An unknown user is not safe to wipe.
    guard let userId = userIdForSignOutCheck() else { return false }
    guard await hasPendingChanges(userId: userId) else { return true }
    _ = await syncCoordinator.sync(reason: .manualRefresh, userId: userId)
    await FriendsMessageOutbox.shared.drain(userId: userId)
    return !(await hasPendingChanges(userId: userId))
  }

  /// Sign out from a screen that can't ask what to do with unsynced changes (MFA, terms
  /// decline, password recovery). Tries to push changes first. If some remain, the session
  /// ends but the local store stays for that user. The same user's next sign-in pushes them,
  /// and a different user's sign-in wipes them.
  func signOutKeepingUnsyncedChanges() async {
    guard let userId = userIdForSignOutCheck() else {
      await signOut()
      return
    }
    let canWipe = await syncPendingChangesBeforeSignOut()
    await performSignOut(global: false, retainingLocalDataFor: canWipe ? nil : userId)
  }

  private func userIdForSignOutCheck() -> String? {
    Self.signOutUserId(
      current: userId,
      local: AuthSessionManager.shared.localSession()?.normalizedUserId,
      offlineFallback: { AuthSessionManager.shared.offlineUserIdFallback() }
    )
  }

  nonisolated static func signOutUserId(
    current: String?,
    local: String?,
    offlineFallback: () -> String?
  ) -> String? {
    if let current, !current.isEmpty { return current }
    if let local, !local.isEmpty { return local }
    return offlineFallback()
  }

  private func hasPendingChanges(userId: String) async -> Bool {
    // A failed read counts as pending so it never wipes by mistake.
    (try? await LocalStore.shared.storeActor.hasPendingChanges(userId: userId)) ?? true
  }

  /// The signed-in user's id when they have unsynced changes, otherwise nil.
  private func userIdWithUnsyncedChanges() async -> String? {
    guard let userId = userIdForSignOutCheck() else { return nil }
    return await hasPendingChanges(userId: userId) ? userId : nil
  }

  /// Internal sign out implementation
  /// - Parameter global: If true, signs out from all devices; if false, only this device
  private func performSignOut(global: Bool, retainingLocalDataFor retainedUserId: String? = nil)
    async
  {
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
    // Same for APNs, so the next user of this device doesn't get this user's pushes.
    await AppDelegate.shared?.unregisterCachedAPNsToken()

    // Clear all cached data
    await clearAllCachedData(retainingLocalDataFor: retainedUserId)

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
  /// - Parameter retainedUserId: When set, the local store and defaults stay because this
  ///   user has unsynced changes. See `discardRetainedLocalDataIfUserChanged`.
  private func clearAllCachedData(retainingLocalDataFor retainedUserId: String? = nil) async {
    // Stop messaging realtime first so in-flight callbacks can't write the previous
    // user's threads back after the local store is reset.
    friendsRealtimeTask?.cancel()
    await FriendsMessagingRealtimeCoordinator.shared.stopForAuthenticatedUser()

    // Cancel all tracked background tasks to prevent stale state updates
    cancelAllBackgroundTasks()
    resetPayrollCaches()

    await clearSignedOutDeviceState()

    CalendarSubscriptionStore.shared.resetForUserChange()
    CalendarSubscriptionStore.clearStoredTokensForUserReset()

    // Clear all local data (shifts, settings, sync state, etc.)
    if retainedUserId == nil {
      await LocalStore.shared.resetAllData()
    }

    // Clear image cache
    ImageCache.shared.clearAll()
    NotificationService.shared.setApplicationBadgeCount(0)

    if retainedUserId == nil, let bundleId = Bundle.main.bundleIdentifier {
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

    retainLocalData(for: retainedUserId)
    initialSyncComplete = false
  }

  private static let retainedLocalDataUserIdKey = "auth.retained_local_data_user_id"

  /// Records whose data is still in the local store after a sign-out that kept it.
  private func retainLocalData(for userId: String?) {
    guard let userId, !userId.isEmpty else { return }
    UserDefaults.standard.set(userId, forKey: Self.retainedLocalDataUserIdKey)
  }

  nonisolated static func shouldWipeRetainedData(
    retainedUserId: String?,
    sessionUserId: String
  ) -> Bool {
    guard let retainedUserId, !retainedUserId.isEmpty else { return false }
    return retainedUserId.lowercased() != sessionUserId.lowercased()
  }

  /// Runs at sign-in. The local store has no owner field, so a store kept for user A
  /// must not reach user B. Same user keeps it and pushes the changes.
  private func discardRetainedLocalDataIfUserChanged() async {
    let defaults = UserDefaults.standard
    guard let retainedUserId = defaults.string(forKey: Self.retainedLocalDataUserIdKey),
      let sessionUserId = AuthSessionManager.shared.localSession()?.normalizedUserId
    else {
      return
    }
    if Self.shouldWipeRetainedData(retainedUserId: retainedUserId, sessionUserId: sessionUserId) {
      launchLog.warning("[Auth] Different user signed in; wiping retained local data")
      await clearAllCachedData()
    } else {
      defaults.removeObject(forKey: Self.retainedLocalDataUserIdKey)
    }
  }

  /// Device-local cleanup that needs no session: widgets, the extension keychain token,
  /// and Live Activities. Also runs when the SDK signs the user out on its own.
  private func clearSignedOutDeviceState() async {
    // Invalidate any queued widget refreshes before clearing shared state so
    // background tasks cannot repopulate App Group data after sign-out.
    await NativeWidgetStorage.invalidatePendingRefreshes()

    await AppDelegate.shared?.endAllLiveActivities(reason: "auth/session context reset")

    NativeWidgetStorage.clearWidgetStorage()
    NativeWidgetStorage.clearFriendWidgetStorage()

    // Clear the access token shared with iPhone extensions.
    AuthSessionManager.shared.clearSharedKeychain()
  }

  private func resetPayrollCaches() {
    StatsService.shared.clearCache()
    MonthlyPayrollReadService.shared.invalidateSharedCache()
  }

  private func applySignedOutState() {
    resetLaunchSessionTimeoutCount()
    isUserInitiatedSignOutInProgress = false
    appState = .unauthenticated
    pendingMFAFactor = nil
    pendingDeepLink = nil
    userId = nil
    userDisplayName = ""
    userAvatarUrl = nil
    hasFinishedOnboardingRemotely = false
    initialSyncComplete = false
    NotificationService.shared.setApplicationBadgeCount(0)
  }

  /// Force a session check (useful for debugging or manual refresh)
  func checkSession() async {
    let previousState = appState
    appState = .loading

    do {
      if let session = try await authService.getSession() {
        resetLaunchSessionTimeoutCount()
        if await routeToMFAIfRequired(session) { return }
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
  /// - tidex://sharing/manage?highlight=<userId> → Open that friend's profile, or the add friend sheet
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
      let session = try await sessionForProfileLoad()
      let user = session.user
      let currentUserId = user.normalizedId

      // Store user ID
      self.userId = currentUserId

      loadOnboardingStateFromUser(user)
      userDisplayName = Self.displayName(for: user)

      // Register only if permission already exists. Do not prompt during account switching.
      await NotificationService.shared.registerIfPermissionAlreadyGranted()
      applyCachedSettings(userId: currentUserId)

      // Skip during impersonation to prevent registering the admin's device
      // token under the impersonated user's account
      if !ImpersonationManager.shared.isImpersonating {
        await AppDelegate.shared?.registerCachedAPNsTokenIfNeeded()
      }

      // Run sync and WAIT for it to complete (unlike normal flow which runs in background)
      initialSyncComplete = false
      await syncCoordinator.loadTrackingState(userId: currentUserId)
      _ = await syncCoordinator.sync(reason: .appLaunch, userId: currentUserId)
      initialSyncComplete = true
      applyCachedSettings(userId: currentUserId)
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
    }
  }
#endif
