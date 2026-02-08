import Foundation
import SwiftUI
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
    registrationState = .apnsFailed(error.localizedDescription)
  }

  /// Called when server API registration fails
  func serverRegistrationFailed(_ message: String) {
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
