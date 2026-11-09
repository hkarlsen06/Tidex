import ClerkKit
import Foundation
// swiftlint:disable:next sorted_imports
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "AuthSessionManager")

enum AuthSessionManagerError: Error, LocalizedError {
  case sessionFetchTimedOut
  case refreshTimedOut
  /// No Clerk session on this device.
  case notSignedIn

  var errorDescription: String? {
    switch self {
    case .sessionFetchTimedOut, .refreshTimedOut:
      return String(localized: .authErrorSessionTimedOut)

    case .notSignedIn:
      return String(localized: .authErrorSessionMissing)
    }
  }
}

/// The signed-in user as `users.current` returns it. `id` is the Tidex user UUID that every
/// row and the local store use, not the Clerk user ID. During an impersonation it is the
/// target user, and `actorId` is the admin.
struct AuthUser: Codable, Equatable, Sendable {
  let id: String
  let email: String?
  let name: String?
  let avatarUrl: String?
  let role: String?
  let termsAcceptedAt: String?
  let finishedOnboarding: Bool
  let isImpersonating: Bool
  let actorId: String

  var normalizedId: String { id.lowercased() }
  var isAdmin: Bool { role == "admin" }

  enum CodingKeys: String, CodingKey {
    case id, email, name, role
    case avatarUrl = "avatar_url"
    case termsAcceptedAt = "terms_accepted_at"
    case finishedOnboarding = "finished_onboarding"
    case isImpersonating = "is_impersonating"
    case actorId = "actor_id"
  }
}

/// A Clerk session and the Tidex user it maps to.
struct AuthSession: Sendable {
  let user: AuthUser
  /// Clerk session token for Convex. It lasts about 60 seconds.
  let accessToken: String
  /// Unix time when `accessToken` expires.
  let expiresAt: TimeInterval
  let clerkSessionId: String

  var normalizedUserId: String { user.normalizedId }
}

struct SharedKeychainAccessTokenPayload: Equatable {
  let token: String
  let expiresAt: Int

  init(session: AuthSession) {
    self.token = session.accessToken
    self.expiresAt = Int(session.expiresAt)
  }
}

/// Resolves the signed-in user for the rest of the app.
///
/// Clerk owns the session and refreshes its token. This adds the Tidex user from
/// `users.current`, which Convex creates or links on the first sign-in through
/// `users.ensureCurrent`. The user is cached in memory and in UserDefaults per Clerk user,
/// so an offline launch still knows whose local data to show.
///
/// ```swift
/// let session = try await AuthSessionManager.shared.getSession()
/// ```
@MainActor
final class AuthSessionManager {
  static let shared = AuthSessionManager()

  private enum SessionPhase: String {
    case clerkToken = "clerk_token"
    case userLookup = "user_lookup"
  }

  @MainActor
  private final class SessionProgress {
    var phase = SessionPhase.clerkToken
  }

  private static let cachedUserKey = "auth.currentUser"

  /// The user for `cachedUserClerkId`. Cleared on sign-out and after impersonation changes.
  private var cachedUser: AuthUser?
  private var cachedUserClerkId: String?
  private struct RememberedToken {
    let token: String
    let expiresAt: TimeInterval
    let sessionId: String
    let published: Bool
  }
  private var lastToken: RememberedToken?
  private var userTask: Task<AuthUser, Error>?
  private var userTaskSessionId: String?
  private var cachedUserSessionId: String?
  private let activeSessionId: () -> String?
  private let activeClerkUserId: () -> String?
  private let defaults: UserDefaults
  private let lookupUser: () async throws -> AuthUser
  /// Bumped whenever the cached user is dropped, so a lookup that started before can't
  /// publish a user that is out of date, such as one from before an impersonation change.
  private var userGeneration = 0

  init(
    activeSessionId: @escaping () -> String? = { Clerk.shared.session?.id },
    activeClerkUserId: @escaping () -> String? = { Clerk.shared.session?.clerkUserId },
    defaults: UserDefaults = .standard,
    lookupUser: @escaping () async throws -> AuthUser = {
      if let user: AuthUser = try await ConvexAPI.app.query("users:current") { return user }
      _ = try await ConvexAPI.app.action("users:ensureCurrent", as: String.self)
      guard let user: AuthUser = try await ConvexAPI.app.query("users:current") else {
        throw AuthSessionManagerError.notSignedIn
      }
      return user
    }
  ) {
    self.activeSessionId = activeSessionId
    self.activeClerkUserId = activeClerkUserId
    self.defaults = defaults
    self.lookupUser = lookupUser
  }

  // MARK: - Public API

  /// The current session with a fresh token.
  /// - Parameters:
  ///   - allowProactiveRefresh: Unused since Clerk refreshes its own token. Kept for callers.
  ///   - reportMissingSessionWarning: Reports a missing session to diagnostics when true.
  /// - Throws: `AuthSessionManagerError.notSignedIn` without a Clerk session, a `URLError`
  ///   offline, or `AuthSessionManagerError.sessionFetchTimedOut`.
  func getSession(
    allowProactiveRefresh _: Bool = true,
    reportMissingSessionWarning: Bool = true
  ) async throws -> AuthSession {
    #if DEBUG
      if AppStoreScreenshotFixture.isActive {
        return AppStoreScreenshotFixture.session
      }
    #endif
    let startedAt = Date()
    let progress = SessionProgress()
    do {
      let generation = userGeneration
      let session = try await withTimeout {
        try await self.resolveSession(skipCache: false, progress: progress)
      }
      guard activeSessionId() == session.clerkSessionId else {
        throw AuthSessionManagerError.notSignedIn
      }
      guard userGeneration == generation else {
        return try await getSession(reportMissingSessionWarning: reportMissingSessionWarning)
      }
      AuthDiagnosticsReporter.shared.rememberAuthenticatedUserId(session.normalizedUserId)
      return session
    } catch {
      let isMissing = isMissingSessionError(error)
      let hadUser = AuthDiagnosticsReporter.shared.hasRememberedAuthenticatedUserId
      let severity: AuthDiagnosticsReporter.Severity =
        Task.isCancelled || (isMissing && !(reportMissingSessionWarning && hadUser))
        ? .debug : .warning
      AuthDiagnosticsReporter.shared.record(
        .sessionFetchFailed,
        severity: severity,
        error: error,
        metadata: [
          "is_missing_session_error": .bool(isMissing),
          "is_transient_network_error": .bool(isTransientNetworkError(error)),
          "session_resolution_phase": .string(progress.phase.rawValue),
          "session_resolution_elapsed_seconds": .double(Date().timeIntervalSince(startedAt)),
        ]
      )
      throw error
    }
  }

  /// Like `getSession`, but returns nil instead of throwing.
  func getSessionIfAvailable(allowProactiveRefresh: Bool = true) async -> AuthSession? {
    try? await getSession(
      allowProactiveRefresh: allowProactiveRefresh, reportMissingSessionWarning: false)
  }

  /// The session from this device's storage only, with no network. The token may be expired.
  /// Nil before the user has been resolved once on this device.
  func localSession() -> AuthSession? {
    #if DEBUG
      if AppStoreScreenshotFixture.isActive {
        return AppStoreScreenshotFixture.session
      }
    #endif
    guard let sessionId = activeSessionId(), let clerkUserId = activeClerkUserId(),
      let user = storedUser(clerkUserId: clerkUserId)
    else { return nil }
    guard !user.isImpersonating || cachedUserSessionId == sessionId else { return nil }
    return AuthSession(
      user: user,
      accessToken: lastToken?.sessionId == sessionId ? lastToken?.token ?? "" : "",
      expiresAt: lastToken?.sessionId == sessionId ? lastToken?.expiresAt ?? 0 : 0,
      clerkSessionId: sessionId
    )
  }

  /// Local presentation requires the SDK's current account. Impersonation is checked
  /// remotely first because the stored target may have expired while the app was closed.
  func localPresentationSession() -> AuthSession? {
    guard let session = localSession(), !session.user.isImpersonating else { return nil }
    return session
  }

  /// Like `getSessionIfAvailable`, but a transient failure (offline, timeout) falls back to
  /// the stored session, so a signed-in user keeps working offline.
  func getSessionOrLocal(allowProactiveRefresh: Bool = true) async -> AuthSession? {
    do {
      return try await getSession(
        allowProactiveRefresh: allowProactiveRefresh, reportMissingSessionWarning: false)
    } catch {
      guard isTransientSessionResolutionError(error) else { return nil }
      logger.info("Using stored session after transient failure")
      return localPresentationSession()
    }
  }

  func getUserId() async throws -> String {
    try await getSession().normalizedUserId
  }

  func getUserIdIfAvailable() async -> String? {
    try? await getUserId()
  }

  /// A new token and a fresh `users.current`. Call it after the user row changes on the
  /// server, such as accepting terms or starting an impersonation.
  @discardableResult
  func forceRefresh() async throws -> AuthSession {
    userGeneration += 1
    cachedUser = nil
    cachedUserSessionId = nil
    userTask = nil
    let generation = userGeneration
    let session = try await withTimeout { try await self.resolveSession(skipCache: true) }
    guard activeSessionId() == session.clerkSessionId else {
      throw AuthSessionManagerError.notSignedIn
    }
    guard userGeneration == generation else { return try await getSession() }
    return session
  }

  /// The token `ConvexAPI.app` sends. Nil when nobody is signed in.
  func convexToken(forceRefresh: Bool) async throws -> String? {
    #if DEBUG
      if AppStoreScreenshotFixture.isActive { return nil }
    #endif
    guard let session = Clerk.shared.session else { return nil }
    let token = try await session.getToken(.init(skipCache: forceRefresh))
    try Task.checkCancellation()
    guard activeSessionId() == session.id else { return nil }
    if let token { remember(token: token, sessionId: session.id) }
    return token
  }

  /// Puts the session's token in the shared keychain for the extensions.
  func publishSessionToSharedKeychain(_ session: AuthSession) {
    guard !session.accessToken.isEmpty, activeSessionId() == session.clerkSessionId else { return }
    remember(token: session.accessToken, sessionId: session.clerkSessionId)
  }

  /// Forgets the cached user. Sign-out and impersonation changes call it.
  func clearCachedUser() {
    userGeneration += 1
    cachedUser = nil
    cachedUserClerkId = nil
    cachedUserSessionId = nil
    userTask = nil
    lastToken = nil
    defaults.removeObject(forKey: Self.cachedUserKey)
    WidgetAppGroup.storeSignedInUserId(nil)
  }

  /// Clerk or Convex refused the session, so the user must sign in again.
  func isSessionRevokedError(_ error: Error) -> Bool {
    if case ConvexAPI.Failure.notSignedIn = error { return true }
    if let error = error as? ClerkAPIError {
      return ["session_not_found", "authentication_invalid", "signed_out", "session_expired"]
        .contains(error.code)
    }
    return false
  }

  func isDefinitiveSessionResolutionError(_ error: Error) -> Bool {
    isMissingSessionError(error) || isSessionRevokedError(error)
  }

  /// No Clerk session, the normal state before the first sign-in.
  func isMissingSessionError(_ error: Error) -> Bool {
    if case AuthSessionManagerError.notSignedIn = error { return true }
    return false
  }

  /// Offline and similar network failures, where the user must not be signed out.
  func isTransientNetworkError(_ error: Error) -> Bool {
    let transientCodes: Set<URLError.Code> = [
      .timedOut,
      .cannotFindHost,
      .cannotConnectToHost,
      .networkConnectionLost,
      .dnsLookupFailed,
      .notConnectedToInternet,
      .internationalRoamingOff,
      .callIsActive,
      .dataNotAllowed,
    ]
    if let urlError = error as? URLError {
      return transientCodes.contains(urlError.code)
    }
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      return transientCodes.contains(URLError.Code(rawValue: nsError.code))
    }
    return false
  }

  /// Transient failures where falling back to the stored session is fine.
  func isTransientSessionResolutionError(_ error: Error) -> Bool {
    if isTransientNetworkError(error) { return true }
    if case AuthSessionManagerError.notSignedIn = error { return false }
    return error is AuthSessionManagerError
  }

  /// The Tidex user this device last resolved for the current Clerk session, for offline
  /// use. Nil when it never resolved, so local data is never opened for a guessed user,
  /// such as a store kept for a previous account.
  func offlineUserIdFallback() -> String? {
    localPresentationSession()?.normalizedUserId
  }

  /// Clears the extensions' token on sign-out.
  func clearSharedKeychain() {
    lastToken = nil
    do {
      try SharedKeychainStorage.clearAccessToken()
    } catch {
      logger.warning("Failed to clear shared keychain: \(error.localizedDescription)")
    }
  }

}

extension AuthSessionManager {
  private func resolveSession(skipCache: Bool, progress: SessionProgress? = nil) async throws
    -> AuthSession
  {
    guard let clerkSession = Clerk.shared.session else {
      throw AuthSessionManagerError.notSignedIn
    }
    guard let token = try await clerkSession.getToken(.init(skipCache: skipCache)) else {
      throw AuthSessionManagerError.notSignedIn
    }
    try Task.checkCancellation()
    guard activeSessionId() == clerkSession.id else {
      throw AuthSessionManagerError.notSignedIn
    }
    progress?.phase = .userLookup
    let user = try await currentUser(
      clerkUserId: clerkSession.clerkUserId, sessionId: clerkSession.id)
    try Task.checkCancellation()
    guard activeSessionId() == clerkSession.id else {
      throw AuthSessionManagerError.notSignedIn
    }
    remember(token: token, sessionId: clerkSession.id)
    return AuthSession(
      user: user,
      accessToken: token,
      expiresAt: lastToken?.expiresAt ?? 0,
      clerkSessionId: clerkSession.id
    )
  }

  /// `users.current`, creating or linking the row with `users.ensureCurrent` on the first
  /// sign-in. Concurrent callers share one lookup.
  func currentUser(clerkUserId: String, sessionId: String) async throws -> AuthUser {
    guard activeSessionId() == sessionId else { throw AuthSessionManagerError.notSignedIn }
    if let cachedUser, cachedUserClerkId == clerkUserId, cachedUserSessionId == sessionId {
      return cachedUser
    }
    let generation = userGeneration
    let task: Task<AuthUser, Error>
    if let userTask, userTaskSessionId == sessionId {
      task = userTask
    } else {
      task = Task { try await self.lookupUser() }
      userTask = task
      userTaskSessionId = sessionId
    }
    defer { if userTask == task { userTask = nil } }
    let user: AuthUser
    do {
      user = try await task.value
    } catch {
      if activeSessionId() == sessionId, userGeneration == generation,
        isDefinitiveSessionResolutionError(error)
      {
        clearCachedUser()
        clearSharedKeychain()
      }
      throw error
    }
    try Task.checkCancellation()
    guard activeSessionId() == sessionId else { throw AuthSessionManagerError.notSignedIn }
    guard userGeneration == generation else {
      return try await currentUser(clerkUserId: clerkUserId, sessionId: sessionId)
    }
    cachedUserSessionId = sessionId
    cachedUser = user
    cachedUserClerkId = clerkUserId
    // The notification service extension redacts pushes meant for another account. Devices
    // register under the signed-in person, the admin during an impersonation.
    WidgetAppGroup.storeSignedInUserId(user.actorId)
    if let data = try? JSONEncoder().encode(StoredUser(clerkUserId: clerkUserId, user: user)) {
      defaults.set(data, forKey: Self.cachedUserKey)
    }
    return user
  }

  private struct StoredUser: Codable {
    let clerkUserId: String
    let user: AuthUser
  }

  private func storedUser(clerkUserId: String) -> AuthUser? {
    if let cachedUser, cachedUserClerkId == clerkUserId { return cachedUser }
    guard let data = defaults.data(forKey: Self.cachedUserKey),
      let stored = try? JSONDecoder().decode(StoredUser.self, from: data),
      stored.clerkUserId == clerkUserId
    else { return nil }
    return stored.user
  }

  private func remember(token: String, sessionId: String) {
    let expiresAt = SharedAuthToken.expiry(ofJWT: token) ?? Date().timeIntervalSince1970 + 50
    if let lastToken, lastToken.token == token, lastToken.sessionId == sessionId,
      lastToken.published
    {
      return
    }
    lastToken = RememberedToken(
      token: token, expiresAt: expiresAt, sessionId: sessionId, published: false)
    do {
      try SharedKeychainStorage.storeAccessToken(token, expiresAt: Int(expiresAt))
      try SharedKeychainStorage.storeClerkSessionId(sessionId)
      lastToken = RememberedToken(
        token: token, expiresAt: expiresAt, sessionId: sessionId, published: true)
    } catch {
      // Extensions fall back to cached data without a token.
      logger.warning("Failed to store token in shared keychain: \(error.localizedDescription)")
    }
  }

}

extension Session {
  /// The Clerk user id. Sessions carry it in `user`, or in `publicUserData` before the user
  /// has loaded. Empty when neither has it, which matches no cached user.
  var clerkUserId: String {
    user?.id ?? publicUserData?.userId ?? ""
  }
}
