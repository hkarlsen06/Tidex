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

    /// Maximum time to wait for an existing refresh task before timing out (30 seconds)
    private let refreshTaskTimeout: UInt64 = 30_000_000_000  // nanoseconds

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
        // If a refresh is already in progress, wait for it with timeout
        if let existingTask = refreshTask {
            logger.debug("Refresh in progress, waiting for existing task...")
            if let session = try await waitForRefreshTask(existingTask) {
                return session
            }
            // Timeout occurred, existing task will be cancelled and we'll start fresh below
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

    /// Get the current authenticated user ID.
    ///
    /// Centralizes session access to avoid refresh race conditions.
    func getUserId() async throws -> String {
        let session = try await getSession()
        return session.normalizedUserId
    }

    /// Get the current authenticated user ID if available.
    ///
    /// Returns nil instead of throwing on auth errors.
    func getUserIdIfAvailable() async -> String? {
        do {
            return try await getUserId()
        } catch {
            logger.debug("No user ID available: \(error.localizedDescription)")
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
        // If refresh is already in progress, wait for it with timeout
        if let existingTask = refreshTask {
            logger.debug("Force refresh requested but refresh already in progress, waiting...")
            if let session = try await waitForRefreshTask(existingTask) {
                return session
            }
            // Timeout occurred, existing task will be cancelled and we'll start fresh below
        }

        return try await performRefresh()
    }

    // MARK: - Private Methods

    /// Waits for an existing refresh task with a timeout to prevent deadlocks.
    ///
    /// If the task completes within the timeout, returns the session.
    /// If timeout occurs, cancels the stuck task and returns nil to signal caller should start fresh.
    ///
    /// - Parameter task: The existing refresh task to wait for
    /// - Returns: The session if completed in time, or nil if timeout occurred
    /// - Throws: Re-throws any error from the task (except cancellation on timeout)
    private func waitForRefreshTask(_ task: Task<Session, Error>) async throws -> Session? {
        do {
            return try await withThrowingTaskGroup(of: Session?.self) { group in
                // Add the existing refresh task
                group.addTask {
                    try await task.value
                }

                // Add a timeout task
                group.addTask {
                    try await Task.sleep(nanoseconds: self.refreshTaskTimeout)
                    return nil  // Timeout signal
                }

                // Wait for whichever completes first
                if let result = try await group.next() {
                    // Cancel the other task
                    group.cancelAll()

                    if let session = result {
                        return session
                    } else {
                        // Timeout occurred
                        logger.warning("Refresh task timed out after 30s, cancelling stuck task and starting fresh...")
                        task.cancel()
                        self.refreshTask = nil
                        self.isRefreshing = false
                        return nil
                    }
                }

                return nil
            }
        } catch is CancellationError {
            // Task was cancelled (likely due to timeout race), return nil to start fresh
            logger.debug("Refresh task wait was cancelled")
            return nil
        }
    }

    /// Performs the actual refresh operation, ensuring only one refresh happens at a time.
    private func performRefresh() async throws -> Session {
        // Double-check we're not already refreshing (for safety)
        if let existingTask = refreshTask {
            if let session = try await waitForRefreshTask(existingTask) {
                return session
            }
            // Timeout occurred, continue with fresh refresh
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
