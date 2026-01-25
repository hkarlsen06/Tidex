import AuthenticationServices
import Foundation
import UIKit

/// Helper for OAuth flows using ASWebAuthenticationSession (in-app browser overlay)
/// Used for identity linking where native SDK flows aren't available
@MainActor
final class OAuthWebAuthSession: NSObject {
    static let shared = OAuthWebAuthSession()

    private var webAuthSession: ASWebAuthenticationSession?
    private weak var presentationAnchor: UIWindow?

    // MARK: - Identity Linking

    /// Link an identity using ASWebAuthenticationSession
    /// - Parameters:
    ///   - provider: The OAuth provider (google, apple)
    ///   - accessToken: The current user's access token
    /// - Returns: The callback URL containing the result
    func linkIdentity(
        provider: String,
        accessToken: String
    ) async throws -> URL {
        // Construct the identity linking URL
        // Supabase identity linking endpoint: /auth/v1/user/identities/authorize
        var components = URLComponents(
            url: APIConfiguration.supabaseURL.appendingPathComponent("auth/v1/user/identities/authorize"),
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: "tidex://auth/callback")
        ]

        guard let authURL = components.url else {
            throw OAuthWebAuthError.invalidURL
        }

        // Create a URL session delegate that doesn't follow redirects
        // so we can capture the OAuth provider URL
        let delegate = RedirectCaptureDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        // Create a URL request with the access token and API key
        var request = URLRequest(url: authURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(APIConfiguration.supabaseAnonKey, forHTTPHeaderField: "apikey")

        // Make the request - the delegate will capture any redirect
        _ = try? await session.data(for: request)

        // Check if we captured a redirect URL
        if let oauthURL = delegate.redirectURL {
            // Open the OAuth URL in ASWebAuthenticationSession
            return try await performWebAuth(url: oauthURL)
        }

        // If no redirect captured, the endpoint might be configured differently
        // Fall back to opening the authorize URL directly with apikey as query param
        // (since ASWebAuthenticationSession doesn't support custom headers)
        var fallbackComponents = URLComponents(url: authURL, resolvingAgainstBaseURL: false)
        var queryItems = fallbackComponents?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "apikey", value: APIConfiguration.supabaseAnonKey))
        fallbackComponents?.queryItems = queryItems

        guard let fallbackURL = fallbackComponents?.url else {
            throw OAuthWebAuthError.invalidURL
        }

        return try await performWebAuth(url: fallbackURL, accessToken: accessToken)
    }

    private func performWebAuth(url: URL, accessToken: String? = nil) async throws -> URL {
        // Get the presentation anchor
        presentationAnchor = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }

        return try await withCheckedThrowingContinuation { continuation in
            // If we have an access token, we need to append it as a query parameter
            // since ASWebAuthenticationSession doesn't support custom headers
            var finalURL = url
            if let accessToken = accessToken {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                var queryItems = components?.queryItems ?? []
                queryItems.append(URLQueryItem(name: "access_token", value: accessToken))
                components?.queryItems = queryItems
                if let newURL = components?.url {
                    finalURL = newURL
                }
            }

            let session = ASWebAuthenticationSession(
                url: finalURL,
                callbackURLScheme: "tidex"
            ) { callbackURL, error in
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: OAuthWebAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: OAuthWebAuthError.failed(error.localizedDescription))
                    }
                    return
                }

                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: OAuthWebAuthError.noCallback)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false

            self.webAuthSession = session

            if !session.start() {
                continuation.resume(throwing: OAuthWebAuthError.sessionStartFailed)
            }
        }
    }
}

// MARK: - Redirect Capture Delegate

/// URLSession delegate that captures redirect URLs instead of following them
private final class RedirectCaptureDelegate: NSObject, URLSessionTaskDelegate {
    var redirectURL: URL?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Capture the redirect URL
        redirectURL = request.url
        // Return nil to prevent following the redirect
        completionHandler(nil)
    }
}

// MARK: - OAuthWebAuthSession Extensions

extension OAuthWebAuthSession {
    /// Cancel any active web auth session
    func cancel() {
        webAuthSession?.cancel()
        webAuthSession = nil
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OAuthWebAuthSession: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            if let anchor = presentationAnchor {
                return anchor
            }
            let keyWindow = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
            if let keyWindow {
                return keyWindow
            }
            // Create window from first available scene (required in iOS 26+)
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else {
                fatalError("No UIWindowScene available - this should never happen in a running app")
            }
            return UIWindow(windowScene: windowScene)
        }
    }
}

// MARK: - OAuth Web Auth Errors

enum OAuthWebAuthError: Error, LocalizedError {
    case userCancelled
    case invalidURL
    case noCallback
    case sessionStartFailed
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "OAuth was cancelled"
        case .invalidURL:
            return "Invalid OAuth URL"
        case .noCallback:
            return "No callback received from OAuth"
        case .sessionStartFailed:
            return "Failed to start OAuth session"
        case .failed(let message):
            return "OAuth failed: \(message)"
        }
    }

    var isCancellation: Bool {
        if case .userCancelled = self { return true }
        return false
    }
}
