import Foundation
import GoogleSignIn
import UIKit

/// Native Google Sign-In provider using Google Sign-In iOS SDK
/// Provides a native bottom sheet experience instead of web-based OAuth
@MainActor
final class GoogleAuthProvider {
  static let shared = GoogleAuthProvider()

  private init() {
    // Configure Google Sign-In with iOS Client ID
    GIDSignIn.sharedInstance.configuration = GIDConfiguration(
      clientID: APIConfiguration.googleiOSClientID
    )
  }

  // MARK: - Sign In

  /// Perform native Google Sign-In
  /// - Parameter presentingViewController: The view controller to present from
  /// - Returns: The ID token from Google
  func signIn(presenting presentingViewController: UIViewController? = nil) async throws -> String {
    let viewController = presentingViewController ?? getTopViewController()

    guard let viewController = viewController else {
      throw GoogleAuthError.noPresenter
    }

    return try await withCheckedThrowingContinuation { continuation in
      GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { result, error in
        if let error = error {
          let nsError = error as NSError

          // Check for user cancellation
          if nsError.domain == "com.google.GIDSignIn" && nsError.code == -5 {
            continuation.resume(throwing: GoogleAuthError.userCancelled)
            return
          }

          continuation.resume(throwing: GoogleAuthError.failed(error.localizedDescription))
          return
        }

        guard let result = result else {
          continuation.resume(throwing: GoogleAuthError.noResult)
          return
        }

        guard let idToken = result.user.idToken?.tokenString else {
          continuation.resume(throwing: GoogleAuthError.noIDToken)
          return
        }

        continuation.resume(returning: idToken)
      }
    }
  }

  /// Check if user has previously signed in with Google
  func hasPreviousSignIn() -> Bool {
    GIDSignIn.sharedInstance.hasPreviousSignIn()
  }

  /// Restore previous sign-in silently
  /// - Returns: The ID token if restoration succeeded
  func restorePreviousSignIn() async throws -> String? {
    guard hasPreviousSignIn() else { return nil }

    return try await withCheckedThrowingContinuation { continuation in
      GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
        if let error = error {
          continuation.resume(throwing: GoogleAuthError.failed(error.localizedDescription))
          return
        }

        guard let idToken = user?.idToken?.tokenString else {
          continuation.resume(returning: nil)
          return
        }

        continuation.resume(returning: idToken)
      }
    }
  }

  /// Sign out from Google
  func signOut() {
    GIDSignIn.sharedInstance.signOut()
  }

  // MARK: - Helpers

  private func getTopViewController() -> UIViewController? {
    guard
      let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive }),
      let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?
        .rootViewController
    else {
      return nil
    }

    return getTopViewController(from: rootViewController)
  }

  private func getTopViewController(from viewController: UIViewController) -> UIViewController {
    if let presentedViewController = viewController.presentedViewController {
      return getTopViewController(from: presentedViewController)
    }
    if let navigationController = viewController as? UINavigationController,
      let visibleViewController = navigationController.visibleViewController {
      return getTopViewController(from: visibleViewController)
    }
    if let tabBarController = viewController as? UITabBarController,
      let selectedViewController = tabBarController.selectedViewController {
      return getTopViewController(from: selectedViewController)
    }
    return viewController
  }
}

// MARK: - Google Auth Errors

enum GoogleAuthError: Error, LocalizedError {
  case userCancelled
  case noPresenter
  case noResult
  case noIDToken
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .userCancelled:
      return "Google Sign-In was cancelled"
    case .noPresenter:
      return "No view controller available to present Google Sign-In"
    case .noResult:
      return "No result received from Google Sign-In"
    case .noIDToken:
      return "No ID token received from Google"
    case .failed(let message):
      return "Google Sign-In failed: \(message)"
    }
  }

  var isCancellation: Bool {
    if case .userCancelled = self { return true }
    return false
  }
}
