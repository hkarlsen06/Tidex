import Foundation
import GoogleSignIn
import UIKit

/// Native Google Sign-In provider using Google Sign-In iOS SDK
/// Provides a native bottom sheet experience instead of web-based OAuth
@MainActor
final class GoogleAuthProvider {
  static let shared = GoogleAuthProvider()
  private static let requestTimeout: UInt64 = 120_000_000_000

  private var activeRequestID: UUID?
  private var continuation: CheckedContinuation<String?, Error>?
  private var timeoutTask: Task<Void, Never>?

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

    guard
      let idToken = try await performRequest(start: { requestID in
        GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { result, error in
          Task { @MainActor [weak self] in
            self?.completeRequest(
              id: requestID,
              result: Self.signInResult(result: result, error: error)
            )
          }
        }
      })
    else {
      throw GoogleAuthError.noIDToken
    }

    return idToken
  }

  private static func signInResult(
    result: GIDSignInResult?,
    error: Error?
  ) -> Result<String?, Error> {
    if let error = error {
      let nsError = error as NSError

      // Check for user cancellation
      if nsError.domain == "com.google.GIDSignIn" && nsError.code == -5 {
        return .failure(GoogleAuthError.userCancelled)
      }

      return .failure(GoogleAuthError.failed(error.localizedDescription))
    }

    guard let result = result else {
      return .failure(GoogleAuthError.noResult)
    }

    guard let idToken = result.user.idToken?.tokenString else {
      return .failure(GoogleAuthError.noIDToken)
    }

    return .success(idToken)
  }

  private func performRequest(start: (UUID) -> Void) async throws -> String? {
    let requestID = UUID()

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard self.continuation == nil else {
          continuation.resume(throwing: GoogleAuthError.requestInProgress)
          return
        }

        self.continuation = continuation
        self.activeRequestID = requestID
        self.timeoutTask = Task { [weak self] in
          do {
            try await Task.sleep(nanoseconds: Self.requestTimeout)
          } catch {
            return
          }

          self?.completeRequest(id: requestID, result: .failure(GoogleAuthError.timedOut))
        }

        start(requestID)
      }
    } onCancel: { [weak self] in
      Task { @MainActor in
        self?.completeRequest(id: requestID, result: .failure(GoogleAuthError.userCancelled))
      }
    }
  }

  private func completeRequest(id requestID: UUID, result: Result<String?, Error>) {
    guard activeRequestID == requestID, let continuation else { return }

    self.continuation = nil
    activeRequestID = nil
    timeoutTask?.cancel()
    timeoutTask = nil

    continuation.resume(with: result)
  }

  /// Check if user has previously signed in with Google
  func hasPreviousSignIn() -> Bool {
    GIDSignIn.sharedInstance.hasPreviousSignIn()
  }

  /// Restore previous sign-in silently
  /// - Returns: The ID token if restoration succeeded
  func restorePreviousSignIn() async throws -> String? {
    guard hasPreviousSignIn() else { return nil }

    return try await performRequest(start: { requestID in
      GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
        Task { @MainActor [weak self] in
          if let error = error {
            self?.completeRequest(
              id: requestID,
              result: .failure(GoogleAuthError.failed(error.localizedDescription))
            )
            return
          }

          self?.completeRequest(id: requestID, result: .success(user?.idToken?.tokenString))
        }
      }
    })
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
      let visibleViewController = navigationController.visibleViewController
    {
      return getTopViewController(from: visibleViewController)
    }
    if let tabBarController = viewController as? UITabBarController,
      let selectedViewController = tabBarController.selectedViewController
    {
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
  case requestInProgress
  case timedOut
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
    case .requestInProgress:
      return "Google Sign-In is already in progress"
    case .timedOut:
      return "Google Sign-In timed out"
    case .failed(let message):
      return "Google Sign-In failed: \(message)"
    }
  }

  var isCancellation: Bool {
    if case .userCancelled = self { return true }
    return false
  }
}
