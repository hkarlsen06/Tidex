import AuthenticationServices
import Foundation
import Supabase
import UIKit

/// Native passkey support for Supabase Auth while supabase-swift does not yet expose
/// the experimental passkey namespace.
@MainActor
final class PasskeyAuthService: NSObject {
  static let shared = PasskeyAuthService()

  private static let requestTimeout: UInt64 = 120_000_000_000

  private let urlSession: URLSession
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  private var continuation: CheckedContinuation<ASAuthorization, Error>?
  private var activeRequestID: UUID?
  private var authorizationController: ASAuthorizationController?
  private var timeoutTask: Task<Void, Never>?
  private var presentationAnchor: UIWindow?

  init(urlSession: URLSession = .shared) {
    self.urlSession = urlSession
    super.init()
  }

  // MARK: - Sign In

  func signIn(from anchor: UIWindow? = nil) async throws -> Session {
    let challenge = try await startAuthentication()
    let credential = try await performAuthentication(
      options: challenge.options,
      anchor: anchor
    )
    let response = try await verifyAuthentication(
      challengeId: challenge.challengeId,
      credential: credential
    )

    return try await supabase.auth.setSession(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken
    )
  }

  // MARK: - Registration

  func register(from anchor: UIWindow? = nil) async throws -> Passkey {
    let session = try await AuthSessionManager.shared.getSession()
    let challenge = try await startRegistration(accessToken: session.accessToken)
    let credential = try await performRegistration(
      options: challenge.options,
      anchor: anchor
    )
    return try await verifyRegistration(
      challengeId: challenge.challengeId,
      credential: credential,
      accessToken: session.accessToken
    )
  }

  // MARK: - Management

  func list() async throws -> [Passkey] {
    let session = try await AuthSessionManager.shared.getSession()
    return try await request(
      method: "GET",
      path: "passkeys",
      accessToken: session.accessToken,
      responseType: [Passkey].self
    )
  }

  func update(passkeyId: String, friendlyName: String) async throws -> Passkey {
    let session = try await AuthSessionManager.shared.getSession()
    return try await request(
      method: "PATCH",
      path: "passkeys/\(passkeyId)",
      accessToken: session.accessToken,
      body: PasskeyUpdateRequest(friendlyName: friendlyName),
      responseType: Passkey.self
    )
  }

  func delete(passkeyId: String) async throws {
    let session = try await AuthSessionManager.shared.getSession()
    let _: EmptyResponse = try await request(
      method: "DELETE",
      path: "passkeys/\(passkeyId)",
      accessToken: session.accessToken,
      responseType: EmptyResponse.self
    )
  }

  // MARK: - Supabase Passkey API

  private func startRegistration(accessToken: String) async throws -> RegistrationOptionsResponse {
    try await request(
      method: "POST",
      path: "passkeys/registration/options",
      accessToken: accessToken,
      body: EmptyRequest(),
      responseType: RegistrationOptionsResponse.self
    )
  }

  private func verifyRegistration(
    challengeId: String,
    credential: RegistrationCredentialJSON,
    accessToken: String
  ) async throws -> Passkey {
    try await request(
      method: "POST",
      path: "passkeys/registration/verify",
      accessToken: accessToken,
      body: VerifyRegistrationRequest(challengeId: challengeId, credential: credential),
      responseType: Passkey.self
    )
  }

  private func startAuthentication() async throws -> AuthenticationOptionsResponse {
    try await request(
      method: "POST",
      path: "passkeys/authentication/options",
      body: StartAuthenticationRequest(gotrueMetaSecurity: EmptyRequest()),
      responseType: AuthenticationOptionsResponse.self
    )
  }

  private func verifyAuthentication(
    challengeId: String,
    credential: AuthenticationCredentialJSON
  ) async throws -> SessionTokenResponse {
    try await request(
      method: "POST",
      path: "passkeys/authentication/verify",
      body: VerifyAuthenticationRequest(challengeId: challengeId, credential: credential),
      responseType: SessionTokenResponse.self
    )
  }

  private func request<Response: Decodable>(
    method: String,
    path: String,
    accessToken: String? = nil,
    responseType: Response.Type
  ) async throws -> Response {
    try await request(
      method: method,
      path: path,
      accessToken: accessToken,
      body: Optional<EmptyRequest>.none,
      responseType: responseType
    )
  }

  private func request<Body: Encodable, Response: Decodable>(
    method: String,
    path: String,
    accessToken: String? = nil,
    body: Body?,
    responseType: Response.Type
  ) async throws -> Response {
    let url = authURL.appendingPathComponents(path)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue(APIConfiguration.supabaseAnonKey, forHTTPHeaderField: "apikey")
    request.setValue(
      "Bearer \(accessToken ?? APIConfiguration.supabaseAnonKey)",
      forHTTPHeaderField: "Authorization"
    )

    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try encoder.encode(body)
    }

    let (data, response) = try await urlSession.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw PasskeyAuthError.invalidServerResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      throw decodeAPIError(from: data, statusCode: httpResponse.statusCode)
    }

    if data.isEmpty, let emptyResponse = EmptyResponse() as? Response {
      return emptyResponse
    }

    do {
      return try decoder.decode(Response.self, from: data)
    } catch {
      throw PasskeyAuthError.decodingFailed(error)
    }
  }

  private var authURL: URL {
    APIConfiguration.supabaseURL
      .appendingPathComponent("auth")
      .appendingPathComponent("v1")
  }

  private func decodeAPIError(from data: Data, statusCode: Int) -> PasskeyAuthError {
    guard !data.isEmpty else {
      return .api(code: nil, message: "Supabase Auth request failed with HTTP \(statusCode)")
    }

    if let error = try? decoder.decode(SupabaseAuthErrorResponse.self, from: data) {
      return .api(
        code: error.errorCode ?? error.code ?? error.error,
        message: error.message ?? error.msg ?? error.errorDescription ?? error.error
          ?? error.errorCode
          ?? "Supabase Auth request failed with HTTP \(statusCode)"
      )
    }

    let message =
      String(data: data, encoding: .utf8)
      ?? "Supabase Auth request failed with HTTP \(statusCode)"
    return .api(code: nil, message: message)
  }

  // MARK: - WebAuthn Ceremony

  private func performRegistration(
    options: PublicKeyCredentialCreationOptions,
    anchor: UIWindow?
  ) async throws -> RegistrationCredentialJSON {
    let challenge = try Data(base64URLEncoded: options.challenge)
    let userID = try Data(base64URLEncoded: options.user.id)
    let relyingPartyID = options.rp.id ?? APIConfiguration.passkeyRelyingPartyID
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
      relyingPartyIdentifier: relyingPartyID
    )
    let request = provider.createCredentialRegistrationRequest(
      challenge: challenge,
      name: options.user.name,
      userID: userID
    )
    request.displayName = options.user.displayName
    request.userVerificationPreference = userVerificationPreference(
      from: options.authenticatorSelection?.userVerification
    )
    request.attestationPreference = attestationPreference(from: options.attestation)

    let authorization = try await performAuthorizationRequest([request], anchor: anchor)
    guard
      let registration = authorization.credential
        as? ASAuthorizationPlatformPublicKeyCredentialRegistration
    else {
      throw PasskeyAuthError.invalidCredentialResponse
    }

    guard let attestationObject = registration.rawAttestationObject else {
      throw PasskeyAuthError.invalidCredentialResponse
    }

    let credentialID = registration.credentialID.base64URLEncodedString()
    return RegistrationCredentialJSON(
      id: credentialID,
      rawId: credentialID,
      response: AuthenticatorAttestationResponseJSON(
        clientDataJSON: registration.rawClientDataJSON.base64URLEncodedString(),
        attestationObject: attestationObject.base64URLEncodedString()
      ),
      authenticatorAttachment: registration.attachment.webAuthnValue,
      clientExtensionResults: [:],
      type: "public-key"
    )
  }

  private func performAuthentication(
    options: PublicKeyCredentialRequestOptions,
    anchor: UIWindow?
  ) async throws -> AuthenticationCredentialJSON {
    let challenge = try Data(base64URLEncoded: options.challenge)
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
      relyingPartyIdentifier: options.rpId ?? APIConfiguration.passkeyRelyingPartyID
    )
    let request = provider.createCredentialAssertionRequest(challenge: challenge)
    request.userVerificationPreference = userVerificationPreference(from: options.userVerification)

    if let allowCredentials = options.allowCredentials, !allowCredentials.isEmpty {
      request.allowedCredentials = try allowCredentials.map { descriptor in
        ASAuthorizationPlatformPublicKeyCredentialDescriptor(
          credentialID: try Data(base64URLEncoded: descriptor.id)
        )
      }
    }

    let authorization = try await performAuthorizationRequest([request], anchor: anchor)
    guard
      let assertion = authorization.credential
        as? ASAuthorizationPlatformPublicKeyCredentialAssertion
    else {
      throw PasskeyAuthError.invalidCredentialResponse
    }

    let credentialID = assertion.credentialID.base64URLEncodedString()
    return AuthenticationCredentialJSON(
      id: credentialID,
      rawId: credentialID,
      response: AuthenticatorAssertionResponseJSON(
        clientDataJSON: assertion.rawClientDataJSON.base64URLEncodedString(),
        authenticatorData: assertion.rawAuthenticatorData.base64URLEncodedString(),
        signature: assertion.signature.base64URLEncodedString(),
        userHandle: assertion.userID.isEmpty ? nil : assertion.userID.base64URLEncodedString()
      ),
      authenticatorAttachment: assertion.attachment.webAuthnValue,
      clientExtensionResults: [:],
      type: "public-key"
    )
  }

  private func performAuthorizationRequest(
    _ requests: [ASAuthorizationRequest],
    anchor: UIWindow?
  ) async throws -> ASAuthorization {
    guard continuation == nil else {
      throw PasskeyAuthError.requestInProgress
    }

    guard let resolvedAnchor = resolvePresentationAnchor(preferredAnchor: anchor) else {
      throw PasskeyAuthError.presentationAnchorUnavailable
    }
    presentationAnchor = resolvedAnchor
    defer { presentationAnchor = nil }

    let requestID = UUID()

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard self.continuation == nil else {
          continuation.resume(throwing: PasskeyAuthError.requestInProgress)
          return
        }

        self.continuation = continuation
        self.activeRequestID = requestID

        let controller = ASAuthorizationController(authorizationRequests: requests)
        controller.delegate = self
        controller.presentationContextProvider = self
        self.authorizationController = controller

        self.timeoutTask = Task { [weak self] in
          do {
            try await Task.sleep(nanoseconds: Self.requestTimeout)
          } catch {
            return
          }

          self?.completeRequest(id: requestID, result: .failure(PasskeyAuthError.timedOut))
        }

        controller.performRequests()
      }
    } onCancel: { [weak self] in
      Task { @MainActor in
        self?.completeRequest(id: requestID, result: .failure(PasskeyAuthError.userCancelled))
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

  private func userVerificationPreference(
    from value: String?
  ) -> ASAuthorizationPublicKeyCredentialUserVerificationPreference {
    switch value {
    case "required":
      return .required
    case "discouraged":
      return .discouraged
    default:
      return .preferred
    }
  }

  private func attestationPreference(
    from value: String?
  ) -> ASAuthorizationPublicKeyCredentialAttestationKind {
    switch value {
    case "direct":
      return .direct
    case "indirect":
      return .indirect
    case "enterprise":
      return .enterprise
    default:
      return .none
    }
  }
}

// MARK: - ASAuthorizationControllerDelegate

extension PasskeyAuthService: ASAuthorizationControllerDelegate {
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
        let passkeyError: PasskeyAuthError
        switch authError.code {
        case .canceled:
          passkeyError = .userCancelled
        case .failed:
          passkeyError = .failed(authError.localizedDescription)
        case .invalidResponse:
          passkeyError = .invalidCredentialResponse
        case .notHandled:
          passkeyError = .notHandled
        case .notInteractive:
          passkeyError = .notInteractive
        case .unknown:
          passkeyError = .unknown
        case .matchedExcludedCredential:
          passkeyError = .matchedExcludedCredential
        case .credentialImport, .credentialExport, .preferSignInWithApple,
          .deviceNotConfiguredForPasskeyCreation:
          passkeyError = .unknown
        @unknown default:
          passkeyError = .unknown
        }
        completeRequest(controller: controller, result: .failure(passkeyError))
      } else {
        completeRequest(controller: controller, result: .failure(error))
      }
    }
  }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension PasskeyAuthService: ASAuthorizationControllerPresentationContextProviding {
  nonisolated func presentationAnchor(for controller: ASAuthorizationController)
    -> ASPresentationAnchor
  {
    MainActor.assumeIsolated {
      guard let anchor = presentationAnchor ?? resolvePresentationAnchor() else {
        preconditionFailure(
          "PasskeyAuthService.presentationAnchor requested without an active window scene")
      }

      return anchor
    }
  }
}

// MARK: - API Models

extension PasskeyAuthService {
  struct Passkey: Identifiable, Decodable, Equatable {
    let id: String
    let friendlyName: String?
    let createdAt: String
    let lastUsedAt: String?

    var displayName: String {
      if let friendlyName, !friendlyName.isEmpty {
        return friendlyName
      }
      return String(localized: .securityPasskeysDefaultName)
    }

    var formattedCreatedAt: String {
      Self.formatDate(createdAt)
    }

    var formattedLastUsedAt: String? {
      guard let lastUsedAt else { return nil }
      return Self.formatDate(lastUsedAt)
    }

    private enum CodingKeys: String, CodingKey {
      case id
      case friendlyName = "friendly_name"
      case createdAt = "created_at"
      case lastUsedAt = "last_used_at"
    }

    private static func formatDate(_ value: String) -> String {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

      let date =
        formatter.date(from: value)
        ?? ISO8601DateFormatter().date(from: value)
        ?? Date()

      let displayFormatter = DateFormatter()
      displayFormatter.dateStyle = .medium
      return displayFormatter.string(from: date)
    }
  }
}

private struct EmptyRequest: Codable {}
private struct EmptyResponse: Decodable {}

private struct RegistrationOptionsResponse: Decodable {
  let challengeId: String
  let options: PublicKeyCredentialCreationOptions

  private enum CodingKeys: String, CodingKey {
    case challengeId = "challenge_id"
    case options
  }
}

private struct AuthenticationOptionsResponse: Decodable {
  let challengeId: String
  let options: PublicKeyCredentialRequestOptions

  private enum CodingKeys: String, CodingKey {
    case challengeId = "challenge_id"
    case options
  }
}

private struct PublicKeyCredentialCreationOptions: Decodable {
  let rp: RelyingParty
  let user: User
  let challenge: String
  let authenticatorSelection: AuthenticatorSelection?
  let attestation: String?

  struct RelyingParty: Decodable {
    let id: String?
  }

  struct User: Decodable {
    let id: String
    let name: String
    let displayName: String
  }
}

private struct PublicKeyCredentialRequestOptions: Decodable {
  let challenge: String
  let rpId: String?
  let allowCredentials: [CredentialDescriptor]?
  let userVerification: String?
}

private struct AuthenticatorSelection: Decodable {
  let userVerification: String?
}

private struct CredentialDescriptor: Decodable {
  let id: String
}

private struct VerifyRegistrationRequest: Encodable {
  let challengeId: String
  let credential: RegistrationCredentialJSON

  private enum CodingKeys: String, CodingKey {
    case challengeId = "challenge_id"
    case credential
  }
}

private struct VerifyAuthenticationRequest: Encodable {
  let challengeId: String
  let credential: AuthenticationCredentialJSON

  private enum CodingKeys: String, CodingKey {
    case challengeId = "challenge_id"
    case credential
  }
}

private struct StartAuthenticationRequest: Encodable {
  let gotrueMetaSecurity: EmptyRequest

  private enum CodingKeys: String, CodingKey {
    case gotrueMetaSecurity = "gotrue_meta_security"
  }
}

private struct PasskeyUpdateRequest: Encodable {
  let friendlyName: String

  private enum CodingKeys: String, CodingKey {
    case friendlyName = "friendly_name"
  }
}

private struct RegistrationCredentialJSON: Encodable {
  let id: String
  let rawId: String
  let response: AuthenticatorAttestationResponseJSON
  let authenticatorAttachment: String?
  let clientExtensionResults: [String: String]
  let type: String
}

private struct AuthenticatorAttestationResponseJSON: Encodable {
  let clientDataJSON: String
  let attestationObject: String
}

private struct AuthenticationCredentialJSON: Encodable {
  let id: String
  let rawId: String
  let response: AuthenticatorAssertionResponseJSON
  let authenticatorAttachment: String?
  let clientExtensionResults: [String: String]
  let type: String
}

private struct AuthenticatorAssertionResponseJSON: Encodable {
  let clientDataJSON: String
  let authenticatorData: String
  let signature: String
  let userHandle: String?
}

private struct SessionTokenResponse: Decodable {
  let accessToken: String
  let refreshToken: String

  private enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
  }
}

private struct SupabaseAuthErrorResponse: Decodable {
  let code: String?
  let errorCode: String?
  let message: String?
  let msg: String?
  let error: String?
  let errorDescription: String?

  private enum CodingKeys: String, CodingKey {
    case code
    case errorCode = "error_code"
    case message
    case msg
    case error
    case errorDescription = "error_description"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    code = try container.decodeFlexibleStringIfPresent(forKey: .code)
    errorCode = try container.decodeFlexibleStringIfPresent(forKey: .errorCode)
    message = try container.decodeFlexibleStringIfPresent(forKey: .message)
    msg = try container.decodeFlexibleStringIfPresent(forKey: .msg)
    error = try container.decodeFlexibleStringIfPresent(forKey: .error)
    errorDescription = try container.decodeFlexibleStringIfPresent(forKey: .errorDescription)
  }
}

// MARK: - Errors

enum PasskeyAuthError: Error, LocalizedError {
  case userCancelled
  case api(code: String?, message: String)
  case invalidBase64URL
  case invalidServerResponse
  case invalidCredentialResponse
  case decodingFailed(Error)
  case presentationAnchorUnavailable
  case requestInProgress
  case timedOut
  case failed(String)
  case notHandled
  case notInteractive
  case matchedExcludedCredential
  case unknown

  var errorDescription: String? {
    switch self {
    case .userCancelled:
      return nil
    case .api(_, let message):
      return message
    case .invalidBase64URL:
      return "Invalid WebAuthn challenge encoding."
    case .invalidServerResponse:
      return "Invalid Supabase Auth response."
    case .invalidCredentialResponse:
      return "Invalid passkey credential response."
    case .decodingFailed(let error):
      return error.localizedDescription
    case .presentationAnchorUnavailable:
      return "No active window was available for passkey authentication."
    case .requestInProgress:
      return "A passkey request is already in progress."
    case .timedOut:
      return "Passkey authentication timed out."
    case .failed(let message):
      return message
    case .notHandled:
      return "No passkey provider handled this request."
    case .notInteractive:
      return "Passkey authentication is not interactive right now."
    case .matchedExcludedCredential:
      return "This passkey is already registered."
    case .unknown:
      return "Passkey authentication failed."
    }
  }

  var isCancellation: Bool {
    if case .userCancelled = self {
      return true
    }
    return false
  }

  var isPasskeyDisabled: Bool {
    if case .api(let code, _) = self {
      return code == "passkey_disabled"
    }
    return false
  }

  var isVerificationFailed: Bool {
    if case .api(let code, let message) = self {
      return code == "webauthn_verification_failed"
        || message.contains("webauthn_verification_failed")
        || message.contains("Credential verification failed")
    }
    return false
  }
}

// MARK: - Helpers

extension KeyedDecodingContainer {
  fileprivate func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
    if let value = try? decodeIfPresent(String.self, forKey: key) {
      return value
    }

    if let value = try? decodeIfPresent(Int.self, forKey: key) {
      return String(value)
    }

    return nil
  }
}

extension APIConfiguration {
  fileprivate static let passkeyRelyingPartyID = "app.tidex.no"
}

extension Data {
  fileprivate init(base64URLEncoded value: String) throws {
    var base64 =
      value
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")

    let padding = base64.count % 4
    if padding > 0 {
      base64.append(String(repeating: "=", count: 4 - padding))
    }

    guard let data = Data(base64Encoded: base64) else {
      throw PasskeyAuthError.invalidBase64URL
    }

    self = data
  }

  fileprivate func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

extension URL {
  fileprivate func appendingPathComponents(_ path: String) -> URL {
    path.split(separator: "/").reduce(self) { url, component in
      url.appendingPathComponent(String(component))
    }
  }
}

extension ASAuthorizationPublicKeyCredentialAttachment {
  fileprivate var webAuthnValue: String {
    switch self {
    case .platform:
      return "platform"
    case .crossPlatform:
      return "cross-platform"
    @unknown default:
      return "platform"
    }
  }
}
