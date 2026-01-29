import Foundation
import OSLog
import Supabase

private let logger = Logger(subsystem: "com.tidex.app", category: "AuthSessionManager")

/// Manages auth session access with refresh serialization to prevent race conditions.
///
/// ## Problem Solved
/// When multiple views/services call `supabase.auth.session` simultaneously with an expired token,
/// they can all trigger concurrent refresh attempts. Since Supabase invalidates refresh tokens after use
/// (one-time use), only the first refresh succeeds while others fail with "Refresh Token Not Found" errors.
///
/// ## Solution
/// This manager serializes all session access through a single point. If a refresh is already in progress,
/// subsequent requests wait for that refresh to complete rather than triggering their own refresh attempts.
///
/// ## Usage
/// Instead of calling `supabase.auth.session` directly, use:
/// ```swift
/// let session = try await AuthSessionManager.shared.getSession()
/// ```
@MainActor
final class AuthSessionManager: ObservableObject {
    static let shared = AuthSessionManager()

    // MARK: - Configuration

    /// Buffer time before token expiry to trigger proactive refresh (60 seconds)
    private let refreshBuffer: TimeInterval = 60

    // MARK: - State

    /// The current refresh task, if one is in progress
    private var refreshTask: Task<Session, Error>?

    /// Whether a refresh is currently in progress
    @Published private(set) var isRefreshing = false

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Get the current session, refreshing if needed.
    ///
    /// This is the primary method services should use to get a session. It:
    /// 1. Checks if a refresh is already in progress and waits for it if so
    /// 2. Gets the current session from Supabase
    /// 3. Proactively refreshes if the token is close to expiry
    /// 4. Stores the token in shared keychain for widget/watch access
    ///
    /// - Returns: A valid session with a fresh access token
    /// - Throws: Auth errors if session cannot be obtained or refreshed
    func getSession() async throws -> Session {
        // If a refresh is already in progress, wait for it
        if let existingTask = refreshTask {
            logger.debug("Refresh in progress, waiting for existing task...")
            return try await existingTask.value
        }

        // Get the current session
        let session = try await supabase.auth.session

        // Check if token is close to expiry and needs proactive refresh
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(session.expiresAt))
        let timeUntilExpiry = expiresAt.timeIntervalSinceNow

        if timeUntilExpiry < refreshBuffer {
            logger.info("Token expires in \(timeUntilExpiry)s, proactively refreshing...")
            return try await performRefresh()
        }

        // Store token in shared keychain for widget/watch access
        storeTokenInSharedKeychain(session)

        return session
    }

    /// Get session if available, returning nil instead of throwing on error.
    ///
    /// Useful for optional session checks where authentication errors should be handled gracefully.
    func getSessionIfAvailable() async -> Session? {
        do {
            return try await getSession()
        } catch {
            logger.debug("No session available: \(error.localizedDescription)")
            return nil
        }
    }

    /// Force a token refresh, serializing with any existing refresh operation.
    ///
    /// Use this when you know the token needs refreshing (e.g., after a 401 response).
    ///
    /// - Returns: The refreshed session
    /// - Throws: Auth errors if refresh fails
    func forceRefresh() async throws -> Session {
        // If refresh is already in progress, wait for it
        if let existingTask = refreshTask {
            logger.debug("Force refresh requested but refresh already in progress, waiting...")
            return try await existingTask.value
        }

        return try await performRefresh()
    }

    // MARK: - Private Methods

    /// Performs the actual refresh operation, ensuring only one refresh happens at a time.
    private func performRefresh() async throws -> Session {
        // Double-check we're not already refreshing (for safety)
        if let existingTask = refreshTask {
            return try await existingTask.value
        }

        logger.info("Starting token refresh...")
        isRefreshing = true

        let task = Task<Session, Error> { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.refreshTask = nil
                    self?.isRefreshing = false
                    logger.info("Token refresh completed")
                }
            }

            do {
                let session = try await supabase.auth.refreshSession()
                logger.info("Token refreshed successfully, new expiry: \(session.expiresAt)")

                // Store refreshed token in shared keychain
                await MainActor.run {
                    self?.storeTokenInSharedKeychain(session)
                }

                return session
            } catch {
                logger.error("Token refresh failed: \(error.localizedDescription)")
                throw error
            }
        }

        refreshTask = task
        return try await task.value
    }

    // MARK: - Shared Keychain Storage

    /// Store the access token in shared keychain for widget/watch access
    private func storeTokenInSharedKeychain(_ session: Session) {
        do {
            try SharedKeychainStorage.storeAccessToken(
                session.accessToken,
                expiresAt: Int(session.expiresAt)
            )
            logger.debug("Stored access token in shared keychain (expires: \(session.expiresAt))")
        } catch {
            // Non-fatal: widget/watch will fall back to cached data
            logger.warning("Failed to store token in shared keychain: \(error.localizedDescription)")
        }
    }

    /// Clear the access token from shared keychain (called on sign out)
    func clearSharedKeychain() {
        do {
            try SharedKeychainStorage.clearAccessToken()
            logger.info("Cleared shared keychain")
        } catch {
            logger.warning("Failed to clear shared keychain: \(error.localizedDescription)")
        }
    }
}
