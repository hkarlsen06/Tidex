import AuthenticationServices
import Foundation
import UIKit

/// Native Apple Sign-In provider using ASAuthorizationController
/// Provides a native Apple sign-in experience instead of web-based OAuth
@MainActor
final class AppleAuthProvider: NSObject {
    static let shared = AppleAuthProvider()

    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private weak var presentationAnchor: UIWindow?

    // MARK: - Sign In

    /// Perform native Apple Sign-In
    /// - Parameter anchor: The window to present the sign-in sheet
    /// - Returns: The identity token from Apple
    func signIn(from anchor: UIWindow? = nil) async throws -> String {
        self.presentationAnchor = anchor ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }

        let authorization = try await performRequest()

        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AppleAuthError.invalidCredentials
        }

        return tokenString
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
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            if let authError = error as? ASAuthorizationError {
                let appleError: AppleAuthError = switch authError.code {
                case .canceled: .userCancelled
                case .failed: .failed(authError.localizedDescription)
                case .invalidResponse: .invalidResponse
                case .notHandled: .notHandled
                case .notInteractive: .notInteractive
                case .unknown: .unknown
                case .matchedExcludedCredential: .unknown
                @unknown default: .unknown
                }
                continuation?.resume(throwing: appleError)
            } else {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleAuthProvider: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Access MainActor-isolated property safely
        return MainActor.assumeIsolated {
            presentationAnchor ?? UIWindow()
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
        case .unknown:
            return "An unknown error occurred during Apple Sign-In"
        }
    }

    var isCancellation: Bool {
        if case .userCancelled = self { return true }
        return false
    }
}
