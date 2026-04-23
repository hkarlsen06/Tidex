import AuthenticationServices
import Foundation
import UIKit

/// Helper for OAuth flows using ASWebAuthenticationSession (in-app browser overlay)
/// Used for identity linking where native SDK flows aren't available
@MainActor
final class OAuthWebAuthSession: NSObject {
  static let shared = OAuthWebAuthSession()
  private static let requestTimeout: UInt64 = 120_000_000_000
  private static let redirectRequestTimeout: TimeInterval = 15

  private var webAuthSession: ASWebAuthenticationSession?
  private var continuation: CheckedContinuation<URL, Error>?
  private var activeSessionID: UUID?
  private var timeoutTask: Task<Void, Never>?
  private var presentationAnchor: UIWindow?

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
    guard currentState == nil, continuation == nil, webAuthSession == nil else {
      throw OAuthWebAuthError.requestInProgress
    }

    // Generate state parameter for CSRF protection
    let state = UUID().uuidString

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

    currentState = state

    // Create a URL session delegate that doesn't follow redirects
    // so we can capture the OAuth provider URL
    let delegate = RedirectCaptureDelegate()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = Self.redirectRequestTimeout
    configuration.timeoutIntervalForResource = Self.redirectRequestTimeout
    configuration.waitsForConnectivity = false
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    defer { session.invalidateAndCancel() }

    // Create a URL request with the access token and API key
    var request = URLRequest(url: authURL, timeoutInterval: Self.redirectRequestTimeout)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue(APIConfiguration.supabaseAnonKey, forHTTPHeaderField: "apikey")

    // Make the request - the delegate will capture any redirect
    _ = try? await session.data(for: request)

    // Check if we captured a redirect URL
    guard let oauthURL = delegate.redirectURL else {
      // No redirect captured - Supabase didn't return the expected redirect
      // This means the identity linking request failed
      currentState = nil
      throw OAuthWebAuthError.failed("Identity linking failed - no redirect received from server")
    }

    // Open the OAuth URL in ASWebAuthenticationSession
    // The access token was already sent securely via Authorization header
    // in the initial request - it should NOT be passed in the URL
    do {
      return try await performWebAuth(url: oauthURL)
    } catch {
      currentState = nil
      throw error
    }
  }

  private func performWebAuth(url: URL) async throws -> URL {
    guard let resolvedAnchor = resolvePresentationAnchor() else {
      throw OAuthWebAuthError.presentationAnchorUnavailable
    }
    presentationAnchor = resolvedAnchor
    let sessionID = UUID()

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard self.continuation == nil, self.webAuthSession == nil else {
          continuation.resume(throwing: OAuthWebAuthError.requestInProgress)
          return
        }

        self.continuation = continuation
        self.activeSessionID = sessionID

        self.timeoutTask = Task { [weak self] in
          do {
            try await Task.sleep(nanoseconds: Self.requestTimeout)
          } catch {
            return
          }

          self?.completeWebAuthSession(
            id: sessionID,
            result: .failure(OAuthWebAuthError.timedOut),
            cancelSession: true
          )
        }

        let session = self.makeWebAuthSession(url: url, sessionID: sessionID)
        self.webAuthSession = session

        if !session.start() {
          self.completeWebAuthSession(
            id: sessionID,
            result: .failure(OAuthWebAuthError.sessionStartFailed)
          )
        }
      }
    } onCancel: { [weak self] in
      Task { @MainActor in
        self?.completeWebAuthSession(
          id: sessionID,
          result: .failure(OAuthWebAuthError.userCancelled),
          cancelSession: true
        )
      }
    }
  }

  private func makeWebAuthSession(url: URL, sessionID: UUID) -> ASWebAuthenticationSession {
    // SECURITY: The access token is NEVER passed in the URL
    // It was already sent securely via Authorization header in the initial request
    let session = ASWebAuthenticationSession(
      url: url,
      callbackURLScheme: "tidex"
    ) { callbackURL, error in
      Task { @MainActor [weak self] in
        self?.completeWebAuthSession(
          id: sessionID,
          result: Self.webAuthResult(callbackURL: callbackURL, error: error)
        )
      }
    }

    session.presentationContextProvider = self
    session.prefersEphemeralWebBrowserSession = false

    return session
  }

  private static func webAuthResult(callbackURL: URL?, error: Error?) -> Result<URL, Error> {
    if let error = error {
      let nsError = error as NSError
      if nsError.domain == ASWebAuthenticationSessionErrorDomain,
        nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
      {
        return .failure(OAuthWebAuthError.userCancelled)
      } else {
        return .failure(OAuthWebAuthError.failed(error.localizedDescription))
      }
    }

    guard let callbackURL = callbackURL else {
      return .failure(OAuthWebAuthError.noCallback)
    }

    return .success(callbackURL)
  }

  private func completeWebAuthSession(
    id sessionID: UUID,
    result: Result<URL, Error>,
    cancelSession: Bool = false
  ) {
    guard activeSessionID == sessionID, let continuation else { return }

    let session = webAuthSession
    self.continuation = nil
    activeSessionID = nil
    webAuthSession = nil
    timeoutTask?.cancel()
    timeoutTask = nil
    presentationAnchor = nil

    if cancelSession {
      session?.cancel()
    }

    continuation.resume(with: result)
  }

  private func resolvePresentationAnchor() -> UIWindow? {
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
    guard let activeSessionID else {
      currentState = nil
      presentationAnchor = nil
      return
    }

    currentState = nil
    completeWebAuthSession(
      id: activeSessionID,
      result: .failure(OAuthWebAuthError.userCancelled),
      cancelSession: true
    )
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
      guard let anchor = presentationAnchor ?? resolvePresentationAnchor() else {
        preconditionFailure(
          "OAuthWebAuthSession.presentationAnchor requested without an active window scene")
      }

      return anchor
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
  case requestInProgress
  case timedOut
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
    case .requestInProgress:
      return "OAuth is already in progress"
    case .timedOut:
      return "OAuth timed out"
    case .failed(let message):
      return "OAuth failed: \(message)"
    }
  }

  var isCancellation: Bool {
    if case .userCancelled = self { return true }
    return false
  }
}
