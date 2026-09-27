import Foundation
import Supabase

/// Error when session is missing from auth response
enum AuthError: Error, LocalizedError {
  case sessionMissing

  var errorDescription: String? {
    switch self {
    case .sessionMissing:
      return "No session returned from authentication"
    }
  }
}

/// Authentication service for native iOS login
/// Wraps Supabase auth operations and handles session management
///
/// Note: Auth state listening is centralized in `AppCoordinator` which handles
/// all navigation state transitions (loading -> auth -> MFA -> authenticated).
/// This service focuses purely on auth operations without duplicating state listening.
@MainActor
final class AuthService: ObservableObject {
  static let shared = AuthService()
  // ponytail: production has no SMS provider since the 2026-09 self-hosting move.
  // Flip back to true once GOTRUE_SMS_* is configured on the auth server.
  static let isSMSAvailable = false
  static let passwordRecoveryRedirectURL: URL = {
    guard let url = URL(string: "tidex://login-callback/recovery") else {
      preconditionFailure("Invalid password recovery redirect URL")
    }
    return url
  }()

  // MARK: - Published State

  /// Loading indicator for auth operations
  @Published private(set) var isLoading = false

  // MARK: - Initialization

  private init() {}

  // MARK: - Session Management

  /// Get the current session, refreshing if needed.
  /// Uses AuthSessionManager to prevent concurrent refresh race conditions.
  func getSession() async throws -> Session? {
    return try await AuthSessionManager.shared.getSession()
  }

  /// Check if user is currently authenticated
  func checkAuthentication() async -> Bool {
    return await AuthSessionManager.shared.getSessionIfAvailable() != nil
  }

  // MARK: - Email/Password Authentication

  /// Sign in with email and password
  /// - Parameters:
  ///   - email: User's email address
  ///   - password: User's password
  /// - Returns: The authenticated session
  func signInWithPassword(email: String, password: String) async throws -> Session {
    isLoading = true
    defer { isLoading = false }

    return try await supabase.auth.signIn(
      email: email,
      password: password
    )
  }

  /// Sign in with phone and password
  /// - Parameters:
  ///   - phone: User's phone number in E.164 format
  ///   - password: User's password
  /// - Returns: The authenticated session
  func signInWithPassword(phone: String, password: String) async throws -> Session {
    isLoading = true
    defer { isLoading = false }

    return try await supabase.auth.signIn(
      phone: phone,
      password: password
    )
  }

  // MARK: - Sign Up

  /// Sign up with email and password
  /// - Parameters:
  ///   - email: User's email address
  ///   - password: User's password
  ///   - fullName: User's full name (optional)
  /// - Returns: The authenticated session (email verification disabled)
  func signUpWithEmail(email: String, password: String, fullName: String? = nil) async throws
    -> Session
  {
    isLoading = true
    defer { isLoading = false }

    // Build user metadata
    let localeCode =
      Locale.autoupdatingCurrent.language.languageCode?.identifier.lowercased() ?? "en"
    var data: [String: AnyJSON] = [
      "terms_accepted_at": .string(Date().toISO8601String()),
      // Keep metadata locale aligned with current iPhone/app language from first write.
      "locale": .string(localeCode),
    ]
    if let fullName, !fullName.isEmpty {
      data["full_name"] = .string(fullName)
    }

    let response = try await supabase.auth.signUp(
      email: email,
      password: password,
      data: data
    )
    // Email verification disabled - session is returned immediately
    guard let session = response.session else {
      throw AuthError.sessionMissing
    }
    return session
  }

  /// Record that the current authenticated user accepted the current terms.
  func recordTermsAcceptance() async throws {
    _ = try await supabase.auth.update(
      user: UserAttributes(
        data: ["terms_accepted_at": .string(Date().toISO8601String())]
      ))

    // Refresh session to make updated user metadata visible to coordinator checks.
    _ = try await AuthSessionManager.shared.forceRefresh()
  }

  // MARK: - Password Reset

  /// Send password reset email
  /// - Parameter email: User's email address
  func sendPasswordResetEmail(email: String) async throws {
    isLoading = true
    defer { isLoading = false }

    try await supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: Self.passwordRecoveryRedirectURL
    )
  }

  /// Send password reset OTP to phone
  /// - Parameter phone: Phone number in E.164 format
  func sendPasswordResetOTP(phone: String) async throws {
    isLoading = true
    defer { isLoading = false }

    // For phone-based password reset, we use signInWithOTP
    // and then update the password after verification
    try await supabase.auth.signInWithOTP(phone: phone)
  }

  /// Verify password reset OTP and sign in
  /// - Parameters:
  ///   - phone: Phone number in E.164 format
  ///   - token: The OTP code received via SMS
  /// - Returns: The authenticated session (user can then update password)
  func verifyPasswordResetOTP(phone: String, token: String) async throws -> Session {
    isLoading = true
    defer { isLoading = false }

    let response = try await supabase.auth.verifyOTP(
      phone: phone,
      token: token,
      type: .sms
    )
    guard let session = response.session else {
      throw AuthError.sessionMissing
    }
    return session
  }

  /// Verify password reset OTP sent by email and sign in.
  /// - Parameters:
  ///   - email: User's email address
  ///   - token: The OTP code received by email
  /// - Returns: The authenticated session (user can then update password)
  func verifyPasswordResetOTP(email: String, token: String) async throws -> Session {
    isLoading = true
    defer { isLoading = false }

    let response = try await supabase.auth.verifyOTP(
      email: email,
      token: token,
      type: .recovery,
      redirectTo: Self.passwordRecoveryRedirectURL
    )
    guard let session = response.session else {
      throw AuthError.sessionMissing
    }
    return session
  }

  /// Update user's password (requires authenticated session)
  /// - Parameter newPassword: The new password
  func updatePassword(newPassword: String) async throws {
    isLoading = true
    defer { isLoading = false }

    _ = try await supabase.auth.update(
      user: UserAttributes(
        password: newPassword,
        data: ["hasPassword": .bool(true)]
      ))
  }

  // MARK: - Phone OTP Authentication

  /// Send OTP code to phone number
  /// - Parameter phone: Phone number in E.164 format
  func sendOTP(phone: String) async throws {
    isLoading = true
    defer { isLoading = false }

    try await supabase.auth.signInWithOTP(phone: phone)
  }

  /// Verify OTP code
  /// - Parameters:
  ///   - phone: Phone number in E.164 format
  ///   - token: The OTP code received via SMS
  /// - Returns: The authenticated session
  func verifyOTP(phone: String, token: String) async throws -> Session {
    isLoading = true
    defer { isLoading = false }

    let response = try await supabase.auth.verifyOTP(
      phone: phone,
      token: token,
      type: .sms
    )
    guard let session = response.session else {
      throw AuthError.sessionMissing
    }
    return session
  }

  // MARK: - OAuth Sign-In

  /// Sign in with Apple using ID token
  /// - Parameter idToken: The identity token from Apple Sign-In
  /// - Parameter fullName: Optional name components from Apple (only provided on first sign-in)
  /// - Returns: The authenticated session
  func signInWithApple(idToken: String, fullName: PersonNameComponents? = nil) async throws
    -> Session
  {
    isLoading = true
    defer { isLoading = false }

    let response = try await supabase.auth.signInWithIdToken(
      credentials: OpenIDConnectCredentials(
        provider: .apple,
        idToken: idToken
      )
    )

    if let fullName {
      let formatter = PersonNameComponentsFormatter()
      let displayName = formatter.string(from: fullName)
        .trimmingCharacters(in: .whitespacesAndNewlines)

      if !displayName.isEmpty {
        // Best-effort: don't block login if the metadata update fails.
        _ = try? await supabase.auth.update(
          user: UserAttributes(data: ["full_name": .string(displayName)])
        )
      }
    }

    return response
  }

  /// Sign in with Google using ID token
  /// - Parameter idToken: The ID token from Google Sign-In
  /// - Returns: The authenticated session
  func signInWithGoogle(idToken: String) async throws -> Session {
    isLoading = true
    defer { isLoading = false }

    return try await supabase.auth.signInWithIdToken(
      credentials: OpenIDConnectCredentials(
        provider: .google,
        idToken: idToken
      )
    )
  }

  // MARK: - MFA

  /// MFA status for the current user
  struct MFAStatus {
    let currentLevel: String
    let nextLevel: String?
    let factors: [MFAFactor]

    var requiresVerification: Bool {
      currentLevel == "aal1" && nextLevel == "aal2"
    }
  }

  struct MFAFactor {
    let id: String
    let type: String
    let friendlyName: String?
    let status: String
  }

  /// Get MFA status for current session
  func getMFAStatus() async throws -> MFAStatus {
    let aal = try await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
    let factors = try await supabase.auth.mfa.listFactors()

    let mfaFactors = factors.totp.map { factor in
      MFAFactor(
        id: factor.id,
        type: factor.factorType,
        friendlyName: factor.friendlyName,
        status: factor.status.rawValue
      )
    }

    let currentLevelValue: String
    if let level = aal.currentLevel {
      currentLevelValue = "\(level)"
    } else {
      currentLevelValue = "aal1"
    }

    let nextLevelValue: String?
    if let level = aal.nextLevel {
      nextLevelValue = "\(level)"
    } else {
      nextLevelValue = nil
    }

    return MFAStatus(
      currentLevel: currentLevelValue,
      nextLevel: nextLevelValue,
      factors: mfaFactors
    )
  }

  /// Create MFA challenge for a factor
  /// - Parameter factorId: The MFA factor ID
  /// - Returns: The challenge ID
  func createMFAChallenge(factorId: String) async throws -> String {
    let challenge = try await supabase.auth.mfa.challenge(
      params: MFAChallengeParams(factorId: factorId, channel: nil)
    )
    return challenge.id
  }

  /// Verify MFA code
  /// - Parameters:
  ///   - factorId: The MFA factor ID
  ///   - challengeId: The challenge ID from createMFAChallenge
  ///   - code: The TOTP code from the authenticator app
  func verifyMFA(factorId: String, challengeId: String, code: String) async throws {
    isLoading = true
    defer { isLoading = false }

    _ = try await supabase.auth.mfa.verify(
      params: MFAVerifyParams(
        factorId: factorId,
        challengeId: challengeId,
        code: code
      )
    )
  }

  // MARK: - Sign Out

  /// Sign out the current user from this device only (local scope)
  /// Other devices will remain logged in
  func signOut() async throws {
    isLoading = true
    defer { isLoading = false }

    try await supabase.auth.signOut(scope: .local)
  }

  /// Sign out the current user from ALL devices (global scope)
  /// This invalidates all refresh tokens across all devices
  func signOutGlobal() async throws {
    isLoading = true
    defer { isLoading = false }

    try await supabase.auth.signOut(scope: .global)
  }
}
