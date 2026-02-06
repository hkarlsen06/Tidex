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

  /// Current OAuth state parameter for CSRF protection
  /// Generated at the start of an OAuth flow and validated on callback
  private var currentState: String?

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
    // Generate state parameter for CSRF protection
    let state = UUID().uuidString
    currentState = state

    // Construct the identity linking URL
    // Supabase identity linking endpoint: /auth/v1/user/identities/authorize
    let identityURL = APIConfiguration.supabaseURL.appendingPathComponent(
      "auth/v1/user/identities/authorize")
    guard var components = URLComponents(url: identityURL, resolvingAgainstBaseURL: false) else {
      throw OAuthWebAuthError.invalidURL
    }

    components.queryItems = [
      URLQueryItem(name: "provider", value: provider),
      URLQueryItem(name: "redirect_to", value: "tidex://auth/callback"),
      URLQueryItem(name: "state", value: state),
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
    guard let oauthURL = delegate.redirectURL else {
      // No redirect captured - Supabase didn't return the expected redirect
      // This means the identity linking request failed
      throw OAuthWebAuthError.failed("Identity linking failed - no redirect received from server")
    }

    // Open the OAuth URL in ASWebAuthenticationSession
    // The access token was already sent securely via Authorization header
    // in the initial request - it should NOT be passed in the URL
    return try await performWebAuth(url: oauthURL)
  }

  private func performWebAuth(url: URL) async throws -> URL {
    // Get the presentation anchor
    let keyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    guard let resolvedAnchor = keyWindow else {
      throw OAuthWebAuthError.presentationAnchorUnavailable
    }
    presentationAnchor = resolvedAnchor

    return try await withCheckedThrowingContinuation { continuation in
      // SECURITY: The access token is NEVER passed in the URL
      // It was already sent securely via Authorization header in the initial request
      let session = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: "tidex"
      ) { callbackURL, error in
        if let error = error {
          let nsError = error as NSError
          if nsError.domain == ASWebAuthenticationSessionErrorDomain,
            nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
          {
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
    currentState = nil
  }

  /// Validates the state parameter from an OAuth callback and clears the stored state
  /// - Parameter returnedState: The state parameter returned in the callback
  /// - Throws: `OAuthWebAuthError.stateMismatch` if the state doesn't match or is missing
  func validateAndClearState(_ returnedState: String?) throws {
    defer { currentState = nil }

    guard let savedState = currentState else {
      // No state was stored - this shouldn't happen in normal flow
      throw OAuthWebAuthError.stateMismatch
    }

    guard let returnedState = returnedState else {
      // State parameter missing from callback
      throw OAuthWebAuthError.stateMismatch
    }

    guard returnedState == savedState else {
      // State doesn't match - potential CSRF attack
      throw OAuthWebAuthError.stateMismatch
    }

    // State validated successfully
  }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OAuthWebAuthSession: ASWebAuthenticationPresentationContextProviding {
  nonisolated func presentationAnchor(for session: ASWebAuthenticationSession)
    -> ASPresentationAnchor
  {
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
      // Create window from first available scene
      if let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first
      {
        return UIWindow(windowScene: windowScene)
      }
      // Fallback: try to get any window from any scene
      // This should never happen in practice since we already checked for window scenes above
      if let anyWindow = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first
      {
        return anyWindow
      }
      // Last resort: create a new window from the first available window scene
      // Even if we couldn't find one above, try one more time with a fresh query
      assertionFailure("Unexpected: no window scene available for auth presentation")
      let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first!
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
  case stateMismatch
  case presentationAnchorUnavailable
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
    case .stateMismatch:
      return "OAuth state validation failed - possible CSRF attack"
    case .presentationAnchorUnavailable:
      return "Unable to present OAuth"
    case .failed(let message):
      return "OAuth failed: \(message)"
    }
  }

  var isCancellation: Bool {
    if case .userCancelled = self { return true }
    return false
  }
}
