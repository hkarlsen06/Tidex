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

  /// Maximum time to wait for a token or the user lookup.
  private let sessionOperationTimeout: Duration = .seconds(20)

  private static let cachedUserKey = "auth.currentUser"

  /// The user for `cachedUserClerkId`. Cleared on sign-out and after impersonation changes.
  private var cachedUser: AuthUser?
  private var cachedUserClerkId: String?
  private var lastToken: (token: String, expiresAt: TimeInterval)?
  private var userTask: Task<AuthUser, Error>?

  private init() {}

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
    do {
      let session = try await withTimeout { try await self.resolveSession(skipCache: false) }
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
    guard let clerkSession = Clerk.shared.session,
      let user = storedUser(clerkUserId: clerkSession.userId)
    else { return nil }
    return AuthSession(
      user: user,
      accessToken: lastToken?.token ?? "",
      expiresAt: lastToken?.expiresAt ?? 0,
      clerkSessionId: clerkSession.id
    )
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
      return localSession()
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
    cachedUser = nil
    userTask = nil
    return try await withTimeout { try await self.resolveSession(skipCache: true) }
  }

  /// The token `ConvexAPI.app` sends. Nil when nobody is signed in.
  func convexToken(forceRefresh: Bool) async throws -> String? {
    #if DEBUG
      if AppStoreScreenshotFixture.isActive { return nil }
    #endif
    guard let session = Clerk.shared.session else { return nil }
    let token = try await session.getToken(.init(skipCache: forceRefresh))
    if let token { remember(token: token, sessionId: session.id) }
    return token
  }

  /// Puts the session's token in the shared keychain for the extensions.
  func publishSessionToSharedKeychain(_ session: AuthSession) {
    remember(token: session.accessToken, sessionId: session.clerkSessionId)
  }

  /// Forgets the cached user. Sign-out and impersonation changes call it.
  func clearCachedUser() {
    cachedUser = nil
    cachedUserClerkId = nil
    userTask = nil
    lastToken = nil
    UserDefaults.standard.removeObject(forKey: Self.cachedUserKey)
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
    Clerk.shared.session.flatMap { storedUser(clerkUserId: $0.userId) }?.normalizedId
  }

  /// Clears the extensions' token on sign-out.
  func clearSharedKeychain() {
    do {
      try SharedKeychainStorage.clearAccessToken()
    } catch {
      logger.warning("Failed to clear shared keychain: \(error.localizedDescription)")
    }
  }

  // MARK: - Private

  private func resolveSession(skipCache: Bool) async throws -> AuthSession {
    guard let clerkSession = Clerk.shared.session else {
      throw AuthSessionManagerError.notSignedIn
    }
    guard let token = try await clerkSession.getToken(.init(skipCache: skipCache)) else {
      throw AuthSessionManagerError.notSignedIn
    }
    remember(token: token, sessionId: clerkSession.id)
    let user = try await currentUser(clerkUserId: clerkSession.userId)
    return AuthSession(
      user: user,
      accessToken: token,
      expiresAt: lastToken?.expiresAt ?? 0,
      clerkSessionId: clerkSession.id
    )
  }

  /// `users.current`, creating or linking the row with `users.ensureCurrent` on the first
  /// sign-in. Concurrent callers share one lookup.
  private func currentUser(clerkUserId: String) async throws -> AuthUser {
    if let cachedUser, cachedUserClerkId == clerkUserId { return cachedUser }
    if let userTask { return try await userTask.value }
    let task = Task<AuthUser, Error> {
      if let user: AuthUser = try await ConvexAPI.app.query("users:current") { return user }
      _ = try await ConvexAPI.app.action("users:ensureCurrent", as: String.self)
      guard let user: AuthUser = try await ConvexAPI.app.query("users:current") else {
        throw AuthSessionManagerError.notSignedIn
      }
      return user
    }
    userTask = task
    defer { userTask = nil }
    let user = try await task.value
    guard Clerk.shared.session?.userId == clerkUserId else {
      throw AuthSessionManagerError.notSignedIn
    }
    cachedUser = user
    cachedUserClerkId = clerkUserId
    // The notification service extension drops pushes meant for another account. Devices
    // register under the signed-in person, the admin during an impersonation.
    WidgetAppGroup.storeSignedInUserId(user.actorId)
    if let data = try? JSONEncoder().encode(StoredUser(clerkUserId: clerkUserId, user: user)) {
      UserDefaults.standard.set(data, forKey: Self.cachedUserKey)
    }
    return user
  }

  private struct StoredUser: Codable {
    let clerkUserId: String
    let user: AuthUser
  }

  private func storedUser(clerkUserId: String) -> AuthUser? {
    if let cachedUser, cachedUserClerkId == clerkUserId { return cachedUser }
    guard let data = UserDefaults.standard.data(forKey: Self.cachedUserKey),
      let stored = try? JSONDecoder().decode(StoredUser.self, from: data),
      stored.clerkUserId == clerkUserId
    else { return nil }
    return stored.user
  }

  private func remember(token: String, sessionId: String) {
    let expiresAt = SharedAuthToken.expiry(ofJWT: token) ?? Date().timeIntervalSince1970 + 50
    lastToken = (token, expiresAt)
    do {
      try SharedKeychainStorage.storeAccessToken(token, expiresAt: Int(expiresAt))
      try SharedKeychainStorage.storeClerkSessionId(sessionId)
    } catch {
      // Extensions fall back to cached data without a token.
      logger.warning("Failed to store token in shared keychain: \(error.localizedDescription)")
    }
  }

  private func withTimeout<T: Sendable>(
    _ operation: @escaping @MainActor @Sendable () async throws -> T
  ) async throws -> T {
    let timeout = sessionOperationTimeout
    return try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw AuthSessionManagerError.sessionFetchTimedOut
      }
      defer { group.cancelAll() }
      guard let value = try await group.next() else { throw CancellationError() }
      return value
    }
  }
}
