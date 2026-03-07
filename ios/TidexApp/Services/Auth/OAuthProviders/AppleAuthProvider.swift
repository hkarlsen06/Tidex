import AuthenticationServices
import Foundation
import UIKit

/// Native Apple Sign-In provider using ASAuthorizationController
/// Provides a native Apple sign-in experience instead of web-based OAuth
@MainActor
final class AppleAuthProvider: NSObject {
  static let shared = AppleAuthProvider()

  struct SignInResult {
    let idToken: String
    let fullName: PersonNameComponents?
  }

  private var continuation: CheckedContinuation<ASAuthorization, Error>?
  private var presentationAnchor: UIWindow?

  // MARK: - Sign In

  /// Perform native Apple Sign-In
  /// - Parameter anchor: The window to present the sign-in sheet
  /// - Returns: The identity token and optional name from Apple
  func signIn(from anchor: UIWindow? = nil) async throws -> SignInResult {
    guard let resolvedAnchor = resolvePresentationAnchor(preferredAnchor: anchor) else {
      throw AppleAuthError.presentationAnchorUnavailable
    }
    presentationAnchor = resolvedAnchor
    defer { presentationAnchor = nil }

    let authorization = try await performRequest()

    guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
      let identityToken = appleIDCredential.identityToken,
      let tokenString = String(data: identityToken, encoding: .utf8)
    else {
      throw AppleAuthError.invalidCredentials
    }

    return SignInResult(idToken: tokenString, fullName: appleIDCredential.fullName)
  }

  private func performRequest() async throws -> ASAuthorization {
    let provider = ASAuthorizationAppleIDProvider()
    let request = provider.createRequest()
    request.requestedScopes = [.email, .fullName]

    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation

      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = self
      controller.presentationContextProvider = self
      controller.performRequests()
    }
  }

  private func resolvePresentationAnchor(preferredAnchor: UIWindow? = nil) -> UIWindow? {
    if let preferredAnchor {
      return preferredAnchor
    }

    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

    if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
      return keyWindow
    }

    if let existingWindow = scenes.flatMap(\.windows).first {
      return existingWindow
    }

    if let firstScene = scenes.first {
      return UIWindow(windowScene: firstScene)
    }

    return nil
  }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleAuthProvider: ASAuthorizationControllerDelegate {
  nonisolated func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    Task { @MainActor in
      continuation?.resume(returning: authorization)
      continuation = nil
      presentationAnchor = nil
    }
  }

  nonisolated func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithError error: Error
  ) {
    Task { @MainActor in
      if let authError = error as? ASAuthorizationError {
        let appleError: AppleAuthError
        switch authError.code {
        case .canceled:
          appleError = .userCancelled
        case .failed:
          appleError = .failed(authError.localizedDescription)
        case .invalidResponse:
          appleError = .invalidResponse
        case .notHandled:
          appleError = .notHandled
        case .notInteractive:
          appleError = .notInteractive
        case .unknown:
          appleError = .unknown
        case .matchedExcludedCredential:
          appleError = .matchedExcludedCredential
        case .credentialImport, .credentialExport, .preferSignInWithApple,
          .deviceNotConfiguredForPasskeyCreation:
          appleError = .unknown
        @unknown default:
          appleError = .unknown
        }
        continuation?.resume(throwing: appleError)
      } else {
        continuation?.resume(throwing: error)
      }
      continuation = nil
      presentationAnchor = nil
    }
  }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleAuthProvider: ASAuthorizationControllerPresentationContextProviding {
  nonisolated func presentationAnchor(for controller: ASAuthorizationController)
    -> ASPresentationAnchor
  {
    MainActor.assumeIsolated {
      guard let anchor = presentationAnchor ?? resolvePresentationAnchor() else {
        preconditionFailure(
          "AppleAuthProvider.presentationAnchor requested without an active window scene")
      }

      return anchor
    }
  }
}

// MARK: - Apple Auth Errors

enum AppleAuthError: Error, LocalizedError {
  case userCancelled
  case failed(String)
  case invalidResponse
  case invalidCredentials
  case notHandled
  case notInteractive
  case matchedExcludedCredential
  case presentationAnchorUnavailable
  case unknown

  var errorDescription: String? {
    switch self {
    case .userCancelled:
      return "Apple Sign-In was cancelled"
    case .failed(let message):
      return "Apple Sign-In failed: \(message)"
    case .invalidResponse:
      return "Invalid response from Apple"
    case .invalidCredentials:
      return "Invalid credentials from Apple Sign-In"
    case .notHandled:
      return "Apple Sign-In request was not handled"
    case .notInteractive:
      return "Apple Sign-In requires user interaction"
    case .matchedExcludedCredential:
      return "Apple Sign-In credential was excluded"
    case .presentationAnchorUnavailable:
      return "Unable to present Apple Sign-In"
    case .unknown:
      return "An unknown error occurred during Apple Sign-In"
    }
  }

  var isCancellation: Bool {
    if case .userCancelled = self { return true }
    return false
  }
}
