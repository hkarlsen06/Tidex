import Combine
import Foundation
import UIKit

/// Manages push notification registration state and failure alerts.
/// Tracks both APNs registration failures and server-side token registration failures.
@MainActor
final class PushNotificationManager: ObservableObject {
  static let shared = PushNotificationManager()

  /// Represents the current state of push notification registration
  enum RegistrationState: Equatable {
    case unknown  // Haven't attempted registration yet
    case registered  // Successfully registered
    case permissionDenied  // User denied notification permission
    case apnsFailed(String)  // APNs registration failed (iOS-level failure)
    case serverFailed(String)  // Server API registration failed
  }

  @Published private(set) var registrationState: RegistrationState = .unknown

  /// Whether the user has dismissed the failure alert
  @Published private(set) var hasUserDismissedAlert: Bool

  /// UserDefaults key for tracking if user has dismissed the alert
  private let alertDismissedKey = "push_notification_alert_dismissed"

  /// Whether an alert should be shown
  var shouldShowAlert: Bool {
    guard !hasUserDismissedAlert else { return false }

    switch registrationState {
    case .apnsFailed, .serverFailed:
      return true
    default:
      return false
    }
  }

  /// The error message to display in the alert
  var alertMessage: String? {
    switch registrationState {
    case .apnsFailed(let message):
      return message
    case .serverFailed(let message):
      return message
    default:
      return nil
    }
  }

  private init() {
    self.hasUserDismissedAlert = UserDefaults.standard.bool(forKey: alertDismissedKey)
  }

  private func isTransientNetworkError(_ error: Error) -> Bool {
    let transientCodes: Set<URLError.Code> = [
      .timedOut,
      .cannotFindHost,
      .cannotConnectToHost,
      .networkConnectionLost,
      .cancelled,
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
    if nsError.domain == NSURLErrorDomain,
      let code = URLError.Code(rawValue: nsError.code) as URLError.Code?
    {
      return transientCodes.contains(code)
    }

    return false
  }

  private func messageLooksTransientNetworkFailure(_ message: String) -> Bool {
    let lowercased = message.lowercased()
    return
      lowercased.contains("offline")
      || lowercased.contains("cancelled")
      || lowercased.contains("avbrutt")
      || lowercased.contains("timed out")
      || lowercased.contains("network connection")
      || lowercased.contains("could not connect")
      || lowercased.contains("cannot connect")
      || lowercased.contains("could not find host")
      || lowercased.contains("dns")
  }

  // MARK: - State Updates

  /// Called when push registration succeeds
  func registrationSucceeded() {
    registrationState = .registered
    setAlertDismissed(false)
  }

  /// Called when user denies notification permission
  func permissionDenied() {
    registrationState = .permissionDenied
  }

  /// Called when APNs registration fails (iOS-level failure)
  func apnsRegistrationFailed(_ error: Error) {
    if isTransientNetworkError(error) {
      return
    }
    registrationState = .apnsFailed(error.localizedDescription)
  }

  /// Called when server API registration fails
  func serverRegistrationFailed(_ message: String, underlying error: Error? = nil) {
    if let error, isTransientNetworkError(error) {
      return
    }
    if messageLooksTransientNetworkFailure(message) {
      return
    }
    registrationState = .serverFailed(message)
  }

  /// Called when user dismisses the failure alert
  func dismissAlert() {
    setAlertDismissed(true)
  }

  /// Reset state (e.g., on logout)
  func reset() {
    registrationState = .unknown
    setAlertDismissed(false)
  }

  private func setAlertDismissed(_ value: Bool) {
    hasUserDismissedAlert = value
    UserDefaults.standard.set(value, forKey: alertDismissedKey)
  }

  /// Open the app's notification settings
  func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
}
