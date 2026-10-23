import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ImpersonationManager")
private let kMinimumImpersonationReasonLength: Int = 5

/// Manages admin impersonation sessions
///
/// Allows admins to temporarily assume the identity of another user for debugging/support.
/// The session lives on the server. While it is open, `users:current` returns the target
/// user and every Convex call acts as that user, so the app keeps the admin's Clerk session.
@MainActor
@Observable
final class ImpersonationManager {
  static let shared = ImpersonationManager()

  // MARK: - Observed State

  /// Whether we are currently impersonating another user. It comes from the current user,
  /// which `users:current` returns as the target during a session.
  var isImpersonating: Bool {
    _ = changeCount
    return AuthSessionManager.shared.localSession()?.user.isImpersonating ?? false
  }

  /// The target user's display name (when impersonating)
  var impersonatedUserName: String? {
    _ = changeCount
    guard let user = AuthSessionManager.shared.localSession()?.user, user.isImpersonating else {
      return nil
    }
    return user.name ?? user.email
  }

  /// When the impersonation session expires. Known after `refresh()` or a start.
  private(set) var expiresAt: Date?

  /// The impersonation session ID. Known after `refresh()` or a start.
  private(set) var sessionId: String?

  /// Changes whenever the state may have changed, so views that read the computed
  /// properties above update.
  private var changeCount = 0
  @ObservationIgnored private var expiryTask: Task<Void, Never>?

  private init() {
    // A launch during an impersonation needs the expiry for the banner and the timer.
    if isImpersonating {
      Task { await refresh() }
    }
  }

  // MARK: - Public API

  /// Loads the open session for the banner and ends the impersonation in the app when it
  /// expires. The manager calls it once at launch. Call it again when the app comes to the
  /// foreground if the session may have ended meanwhile.
  func refresh() async {
    guard let session = try? await AuthSessionManager.shared.getSession() else { return }
    guard session.user.isImpersonating else {
      clearSession()
      return
    }
    do {
      let active: ImpersonationSessionInfo? = try await ConvexAPI.app.query("impersonation:active")
      guard let active else {
        // The session ended on the server, so the user row no longer shows the target.
        await switchUser()
        return
      }
      setSession(active)
    } catch {
      logger.warning("Could not load the impersonation session: \(error.localizedDescription)")
    }
  }

  /// Start impersonating a target user
  /// - Parameters:
  ///   - targetUserId: The user ID to impersonate
  ///   - reason: Reason for impersonation (min 5 chars, required for audit)
  /// - Returns: The impersonation result with session details
  func startImpersonation(targetUserId: String, reason: String) async throws -> ImpersonationResult
  {
    guard reason.count >= kMinimumImpersonationReasonLength else {
      throw ImpersonationError.reasonTooShort
    }

    let admin = try await AuthSessionManager.shared.getSession()
    logger.info("Starting impersonation: admin=\(admin.user.id), target=\(targetUserId)")

    // Clear all cached data BEFORE the server switches users, so no stale admin data shows.
    await AppCoordinator.shared.prepareForUserSwitch()

    let response: ImpersonationStartResponse
    do {
      struct Args: Encodable, Sendable {
        let targetUserId: String
        let reason: String
        enum CodingKeys: String, CodingKey {
          case targetUserId = "target_user_id"
          case reason
        }
      }
      response = try await ConvexAPI.app.mutation(
        "impersonation:start", Args(targetUserId: targetUserId, reason: reason))
    } catch {
      // Nothing changed on the server, so load the admin's own data again.
      await AppCoordinator.shared.completeUserSwitch()
      throw ImpersonationError(error)
    }
    guard response.ok, let info = response.session else {
      await AppCoordinator.shared.completeUserSwitch()
      throw ImpersonationError.serverError("Unknown error")
    }

    // The user row now shows the target.
    let target = try? await AuthSessionManager.shared.forceRefresh()
    setSession(info)
    await AppCoordinator.shared.completeUserSwitch()

    let targetName = impersonatedUserName ?? targetUserId
    logger.info("Impersonation started: target=\(targetName)")

    return ImpersonationResult(
      sessionId: info.id,
      targetName: target?.user.name ?? target?.user.email ?? targetName,
      expiresAt: info.expiresAtDate
    )
  }

  /// Stop the current impersonation and go back to the admin's own data
  func stopImpersonation() async throws {
    guard isImpersonating else {
      throw ImpersonationError.noActiveSession
    }

    logger.info("Stopping impersonation")

    // Clear all cached data BEFORE the server switches back, so no stale target data shows.
    await AppCoordinator.shared.prepareForUserSwitch()

    do {
      if let sessionId = try await openSessionId() {
        struct Args: Encodable, Sendable {
          let sessionId: String
          enum CodingKeys: String, CodingKey { case sessionId = "session_id" }
        }
        _ = try await ConvexAPI.app.mutation(
          "impersonation:stop", Args(sessionId: sessionId), as: ConvexAPI.Ignored.self)
      }
    } catch ConvexAPI.Failure.server(_, let message) {
      // The session is gone already, for example because it expired.
      logger.info("Impersonation already ended: \(message)")
    } catch {
      // Offline or similar. The impersonation continues, so reload the target's data.
      await AppCoordinator.shared.completeUserSwitch()
      throw ImpersonationError(error)
    }

    await switchUser(prepared: true)
    logger.info("Impersonation stopped")
  }

  // MARK: - Private

  private func openSessionId() async throws -> String? {
    if let sessionId { return sessionId }
    let active: ImpersonationSessionInfo? = try await ConvexAPI.app.query("impersonation:active")
    return active?.id
  }

  /// Reads the user row again and reloads the app's data for whoever it shows now.
  private func switchUser(prepared: Bool = false) async {
    if !prepared { await AppCoordinator.shared.prepareForUserSwitch() }
    clearSession()
    _ = try? await AuthSessionManager.shared.forceRefresh()
    await AppCoordinator.shared.completeUserSwitch()
    changeCount += 1
  }

  private func setSession(_ info: ImpersonationSessionInfo) {
    sessionId = info.id
    expiresAt = info.expiresAtDate
    changeCount += 1
    watchExpiry()
  }

  private func clearSession() {
    expiryTask?.cancel()
    expiryTask = nil
    sessionId = nil
    expiresAt = nil
    changeCount += 1
  }

  /// The server ends the session at `expiresAt`. This switches the app back at that time.
  private func watchExpiry() {
    expiryTask?.cancel()
    guard let expiresAt else { return }
    expiryTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(max(expiresAt.timeIntervalSinceNow, 0) + 1))
      guard !Task.isCancelled, let self else { return }
      logger.info("Impersonation session expired")
      // switchUser cancels expiryTask, which is this task, so let it go first.
      expiryTask = nil
      await switchUser()
    }
  }
}
