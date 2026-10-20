// setDeviceToken is SPI: the only way to end Clerk's session on the device without the network.
@_spi(FrameworkIntegration) import ClerkKit
import Foundation
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "ConvexBackend")

extension ConvexAPI {
  /// The deployment for this build. The screenshot fixture gets an unreachable address, so
  /// nothing it does reaches a real deployment.
  static var appDeploymentURL: URL {
    #if DEBUG
      if AppStoreScreenshotFixture.isActive { return URL(string: "http://127.0.0.1:1")! }
    #endif
    return configuredURL
  }

  /// Calls as the signed-in user.
  static let app = ConvexAPI(
    deploymentURL: appDeploymentURL,
    token: { forceRefresh in
      try await AuthSessionManager.shared.convexToken(forceRefresh: forceRefresh)
    }
  )

  /// Calls without a user, for public functions such as the session exchange.
  static let anonymous = ConvexAPI(deploymentURL: appDeploymentURL, token: { _ in nil })
}

enum ClerkSetup {
  /// The keychain group every Tidex target shares (`keychain-access-groups`).
  static let sharedAccessGroup = "48ZSLD4RMP.no.tidex.shared"

  /// Call once at launch, before anything reads `Clerk.shared`. Clerk restores the stored
  /// session synchronously, so `Clerk.shared.session` is set when this returns.
  @MainActor
  static func configure() {
    let key = Bundle.main.infoDictionary?["CLERK_PUBLISHABLE_KEY"] as? String ?? ""
    Clerk.configure(
      publishableKey: key,
      options: .init(
        keychainConfig: .init(
          service: SharedKeychainStorage.clerkKeychainService,
          accessGroup: sharedAccessGroup
        )
      )
    )
  }
}

extension ClerkSetup {
  /// Ends the Clerk session on this device without a request, for a sign-out that couldn't
  /// reach Clerk. Clearing the device token also clears Clerk's cached client, so the next
  /// launch is signed out. The server session stays until it expires, with nobody holding it.
  @MainActor
  static func forgetLocalSession() async {
    let current = SharedKeychainStorage.clerkDeviceToken
    _ = try? await Clerk.shared.setDeviceToken(nil, expected: current)
  }
}

/// Keeps users signed in across the update to N+1. Version N stored a GoTrue session. On the
/// first launch without a Clerk session, this refreshes it, trades it for a Clerk sign-in
/// token with `sessionExchange.exchange`, and signs in with that ticket.
@MainActor
enum LegacySessionExchange {
  enum Outcome {
    /// No GoTrue session was stored.
    case none
    case signedIn
    /// Offline or the server could not be reached. The GoTrue session stays for next time.
    case retryLater
    /// GoTrue or Convex refused the session. The user signs in again.
    case failed
  }

  static var hasLegacySession: Bool {
    legacyGoTrue.currentSession != nil
  }

  static func run() async -> Outcome {
    guard hasLegacySession else { return .none }
    do {
      let session = try await legacyGoTrue.refreshSession()
      struct Args: Encodable, Sendable {
        let accessToken: String
        enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
      }
      struct Ticket: Decodable { let ticket: String }
      let ticket: Ticket = try await ConvexAPI.anonymous.action(
        "sessionExchange:exchange", Args(accessToken: session.accessToken))
      try await Clerk.shared.auth.signInWithTicket(ticket.ticket)
      await discardLegacySession()
      logger.info("Exchanged the GoTrue session for a Clerk session")
      return .signedIn
    } catch {
      // Only a definite refusal by GoTrue or the exchange drops the GoTrue session. An outage
      // or a Clerk error waits for the next launch, which gets a new ticket. A manual
      // sign-in discards the GoTrue session too.
      let refused = isLegacyGoTrueRefusal(error) || (error as? ConvexAPI.Failure)?.code != nil
      guard refused else {
        logger.warning("Session exchange postponed: \(error.localizedDescription)")
        return .retryLater
      }
      logger.error("Session exchange refused: \(error.localizedDescription)")
      await discardLegacySession()
      return .failed
    }
  }

  /// Ends the GoTrue session for this device and removes it from the keychain.
  static func discardLegacySession() async {
    try? await legacyGoTrue.signOut(scope: .local)
  }
}
