import Foundation
import os
import UIKit

private let authDiagnosticsLog = Logger(subsystem: "com.tidex.app", category: "AuthDiagnostics")

@MainActor
final class AuthDiagnosticsReporter {
  static let shared = AuthDiagnosticsReporter()

  enum EventType: String {
    case appLaunch = "app_launch"
    case initialSessionReceived = "initial_session_received"
    case initialSessionMissing = "initial_session_missing"
    case initialSessionCheckFailed = "initial_session_check_failed"
    case initialSessionTimeout = "initial_session_timeout"
    case authStateChanged = "auth_state_changed"
    case authenticated
    case signedOutReceived = "signed_out_received"
    case userInitiatedSignOut = "user_initiated_sign_out"
    case sessionFetchFailed = "session_fetch_failed"
    case tokenRefreshStarted = "token_refresh_started"
    case tokenRefreshSucceeded = "token_refresh_succeeded"
    case tokenRefreshFailed = "token_refresh_failed"
    case foregroundSessionFailed = "foreground_session_failed"
    case revokedSessionDetected = "revoked_session_detected"
    case recoverableAuthFailure = "recoverable_auth_failure"
    case forcedUnauthenticated = "forced_unauthenticated"
  }

  enum Severity: String {
    case debug
    case info
    case warning
    case error
  }

  private struct Response: Decodable {
    let success: Bool
  }

  private struct PendingEvent {
    let eventType: EventType
    let severity: Severity
    let userId: String?
    let appState: String?
    let authEvent: String?
    let error: Error?
    let metadata: [String: AnyJSON]
  }

  private static let installIdKey = "auth_diagnostics.install_id"
  private static let appSessionIdKey = "auth_diagnostics.app_session_id"
  private static let lastAuthenticatedUserIdKey = "auth_diagnostics.last_authenticated_user_id"

  private let appSessionId: String
  private let launchDate = Date()
  private var eventSequence = 0

  private init() {
    appSessionId = UUID().uuidString
    UserDefaults.standard.set(appSessionId, forKey: Self.appSessionIdKey)

    if UserDefaults.standard.string(forKey: Self.installIdKey) == nil {
      UserDefaults.standard.set(UUID().uuidString, forKey: Self.installIdKey)
    }
  }

  func rememberAuthenticatedUserId(_ userId: String) {
    guard !userId.isEmpty else { return }
    UserDefaults.standard.set(userId.lowercased(), forKey: Self.lastAuthenticatedUserIdKey)
  }

  var hasRememberedAuthenticatedUserId: Bool {
    lastAuthenticatedUserId != nil
  }

  func sessionMetadata(_ session: AuthSession, source: String) -> [String: AnyJSON] {
    let expiresAt = Date(timeIntervalSince1970: session.expiresAt)
    return [
      "session_source": .string(source),
      "session_user_id": .string(session.normalizedUserId),
      "session_expires_at": .string(String(Int(session.expiresAt))),
      "session_seconds_until_expiry": .double(expiresAt.timeIntervalSinceNow),
    ]
  }

  func record(
    _ eventType: EventType,
    severity: Severity = .info,
    userId: String? = nil,
    appState: String? = nil,
    authEvent: String? = nil,
    error: Error? = nil,
    metadata: [String: AnyJSON] = [:]
  ) {
    let pendingEvent = PendingEvent(
      eventType: eventType,
      severity: severity,
      userId: userId,
      appState: appState,
      authEvent: authEvent,
      error: error,
      metadata: metadata
    )
    Task { [weak self] in
      await self?.send(pendingEvent)
    }
  }

  private func send(_ pendingEvent: PendingEvent) async {
    eventSequence += 1
    var params = eventParams(for: pendingEvent)
    params["metadata"] = .object(eventMetadata(for: pendingEvent))

    do {
      let response: Response = try await ConvexAPI.app.mutation(
        "diagnostics:recordAuthEvent", params)

      if !response.success {
        authDiagnosticsLog.debug("Auth diagnostic returned success=false")
      }
    } catch {
      authDiagnosticsLog.debug(
        "Failed to record auth diagnostic: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func eventParams(for pendingEvent: PendingEvent) -> [String: AnyJSON] {
    // Convex rejects null for an optional argument, so a missing value is left out.
    var params: [String: AnyJSON] = [
      "event_type": .string(pendingEvent.eventType.rawValue),
      "severity": .string(pendingEvent.severity.rawValue),
      "os_version": .string("iOS \(UIDevice.current.systemVersion)"),
      "device_model": .string(UIDevice.current.model),
      "locale": .string(Locale.autoupdatingCurrent.identifier),
    ]
    if let appState = pendingEvent.appState { params["app_state"] = .string(appState) }
    if let authEvent = pendingEvent.authEvent { params["auth_event"] = .string(authEvent) }
    if let appVersion { params["app_version"] = .string(appVersion) }
    if let buildNumber { params["build_number"] = .string(buildNumber) }
    if let error = pendingEvent.error {
      params["error_kind"] = .string(String(describing: type(of: error)))
      params["error_message"] = .string(Self.sanitizedErrorMessage(error))
    }
    if let reportUserId = normalizedUserId(pendingEvent.userId) {
      params["user_id"] = .string(reportUserId)
    }
    return params
  }

  private func eventMetadata(for pendingEvent: PendingEvent) -> [String: AnyJSON] {
    var eventMetadata = pendingEvent.metadata
    if let lastAuthenticatedUserId = normalizedUserId(lastAuthenticatedUserId) {
      eventMetadata["client_last_authenticated_user_id"] = .string(lastAuthenticatedUserId)
    }
    eventMetadata["install_id"] = .string(installId)
    eventMetadata["app_session_id"] = .string(appSessionId)
    eventMetadata["event_sequence"] = .integer(eventSequence)
    eventMetadata["process_uptime_seconds"] = .double(Date().timeIntervalSince(launchDate))
    eventMetadata["has_last_authenticated_user_id"] = .bool(lastAuthenticatedUserId != nil)
    eventMetadata["app_lifecycle_state"] = .string(applicationStateDescription)
    eventMetadata["low_power_mode_enabled"] = .bool(ProcessInfo.processInfo.isLowPowerModeEnabled)
    if let error = pendingEvent.error {
      for (key, value) in Self.errorMetadata(error) {
        eventMetadata[key] = value
      }
    }
    if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
      eventMetadata["vendor_id"] = .string(vendorId)
    }
    return eventMetadata
  }

  private var installId: String {
    if let existing = UserDefaults.standard.string(forKey: Self.installIdKey) {
      return existing
    }
    let created = UUID().uuidString
    UserDefaults.standard.set(created, forKey: Self.installIdKey)
    return created
  }

  private var lastAuthenticatedUserId: String? {
    UserDefaults.standard.string(forKey: Self.lastAuthenticatedUserIdKey)
  }

  private var appVersion: String? {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
  }

  private var buildNumber: String? {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String
  }

  private var applicationStateDescription: String {
    switch UIApplication.shared.applicationState {
    case .active:
      return "active"

    case .inactive:
      return "inactive"

    case .background:
      return "background"

    @unknown default:
      return "unknown"
    }
  }

  private func normalizedUserId(_ userId: String?) -> String? {
    guard let userId = userId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      UUID(uuidString: userId) != nil
    else {
      return nil
    }
    return userId
  }

  private static func errorMetadata(_ error: Error) -> [String: AnyJSON] {
    let nsError = error as NSError
    return [
      "error_domain": .string(nsError.domain),
      "error_code": .integer(nsError.code),
      "error_is_cancellation": .bool(error is CancellationError),
    ]
  }

  private static func sanitizedErrorMessage(_ error: Error) -> String {
    let raw = error.localizedDescription
    let withoutBearer = raw.replacingOccurrences(
      of: #"Bearer\s+[A-Za-z0-9._~+/=-]+"#,
      with: "Bearer [redacted]",
      options: .regularExpression
    )
    let withoutJWT = withoutBearer.replacingOccurrences(
      of: #"[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#,
      with: "[redacted_token]",
      options: .regularExpression
    )
    return String(withoutJWT.prefix(500))
  }
}
