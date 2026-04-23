import AuthenticationServices
import Foundation
import UIKit

/// Native Apple Sign-In provider using ASAuthorizationController
/// Provides a native Apple sign-in experience instead of web-based OAuth
@MainActor
final class AppleAuthProvider: NSObject {
  static let shared = AppleAuthProvider()
  private static let requestTimeout: UInt64 = 120_000_000_000

  struct SignInResult {
    let idToken: String
    let fullName: PersonNameComponents?
  }

  private var continuation: CheckedContinuation<ASAuthorization, Error>?
  private var activeRequestID: UUID?
  private var authorizationController: ASAuthorizationController?
  private var timeoutTask: Task<Void, Never>?
  private var presentationAnchor: UIWindow?

  // MARK: - Sign In

  /// Perform native Apple Sign-In
  /// - Parameter anchor: The window to present the sign-in sheet
  /// - Returns: The identity token and optional name from Apple
  func signIn(from anchor: UIWindow? = nil) async throws -> SignInResult {
    guard continuation == nil else {
      throw AppleAuthError.requestInProgress
    }

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
    let requestID = UUID()

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard self.continuation == nil else {
          continuation.resume(throwing: AppleAuthError.requestInProgress)
          return
        }

        self.continuation = continuation
        self.activeRequestID = requestID

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.authorizationController = controller

        self.timeoutTask = Task { [weak self] in
          do {
            try await Task.sleep(nanoseconds: Self.requestTimeout)
          } catch {
            return
          }

          self?.completeRequest(id: requestID, result: .failure(AppleAuthError.timedOut))
        }

        controller.performRequests()
      }
    } onCancel: { [weak self] in
      Task { @MainActor in
        self?.completeRequest(id: requestID, result: .failure(AppleAuthError.userCancelled))
      }
    }
  }

  private func completeRequest(id requestID: UUID, result: Result<ASAuthorization, Error>) {
    guard activeRequestID == requestID else { return }
    completeActiveRequest(result: result)
  }

  private func completeRequest(
    controller: ASAuthorizationController,
    result: Result<ASAuthorization, Error>
  ) {
    guard authorizationController === controller else { return }
    completeActiveRequest(result: result)
  }

  private func completeActiveRequest(result: Result<ASAuthorization, Error>) {
    guard let continuation else { return }

    self.continuation = nil
    activeRequestID = nil
    authorizationController?.delegate = nil
    authorizationController?.presentationContextProvider = nil
    authorizationController = nil
    timeoutTask?.cancel()
    timeoutTask = nil
    presentationAnchor = nil

    continuation.resume(with: result)
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
      completeRequest(controller: controller, result: .success(authorization))
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
        completeRequest(controller: controller, result: .failure(appleError))
      } else {
        completeRequest(controller: controller, result: .failure(error))
      }
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
  case requestInProgress
  case timedOut
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
    case .requestInProgress:
      return "Apple Sign-In is already in progress"
    case .timedOut:
      return "Apple Sign-In timed out"
    case .unknown:
      return "An unknown error occurred during Apple Sign-In"
    }
  }

  var isCancellation: Bool {
    if case .userCancelled = self { return true }
    return false
  }
}
