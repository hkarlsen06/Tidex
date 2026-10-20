import AuthenticationServices
import ClerkKit
import Foundation

/// Error when session is missing from auth response
enum AuthError: Error, LocalizedError {
  case sessionMissing

  var errorDescription: String? {
    switch self {
    case .sessionMissing:
      return String(localized: .authErrorSessionMissing)
    }
  }
}

/// Result of an email signup.
enum EmailSignupResult {
  /// Clerk completed the signup at once and the client holds a session.
  case signedIn
  /// Clerk sent a verification code and the signup needs it before a session exists.
  case needsVerification
  /// The email already has an account.
  case alreadyRegistered
}

/// Result of an email and password sign-in.
enum EmailSignInResult {
  case signedIn
  /// Clerk wants a code from the sign-in email first, for example on a device it has not seen.
  case needsEmailCode
}

/// The email and password calls that the signup and login view models make.
/// `AuthService` conforms, and tests substitute a stub.
@MainActor
protocol EmailAuthProviding: AnyObject {
  func signInWithPassword(email: String, password: String) async throws -> EmailSignInResult
  func verifySignInCode(_ code: String) async throws
  func resendSignInCode() async throws
  func signUpWithEmail(email: String, password: String, firstName: String?, lastName: String?)
    async throws -> EmailSignupResult
  func verifySignupCode(_ code: String) async throws
  func resendSignupCode() async throws
}

/// Authentication service for native iOS login
/// Wraps Clerk auth operations. The screens call this and nothing else in Clerk's sign-in API.
///
/// Note: Auth state listening is centralized in `AppCoordinator`, which handles all
/// navigation state transitions (loading -> auth -> authenticated).
/// This service focuses purely on auth operations without duplicating state listening.
@MainActor
final class AuthService: EmailAuthProviding {
  static let shared = AuthService()

  // MARK: - Published State

  /// Loading indicator for auth operations
  private(set) var isLoading = false

  // MARK: - Private State

  /// The sign-in that waits for an email code, and the sign-up that waits for its code.
  private var pendingSignIn: SignIn?
  private var pendingSignUp: SignUp?

  // MARK: - Initialization

  private init() {}

  // MARK: - Session Management

  /// Get the current session, resolving the Tidex user if needed.
  /// Uses AuthSessionManager to prevent concurrent refresh race conditions.
  func getSession() async throws -> AuthSession? {
    return try await AuthSessionManager.shared.getSession()
  }

  /// Check if user is currently authenticated
  func checkAuthentication() async -> Bool {
    return await AuthSessionManager.shared.getSessionIfAvailable() != nil
  }

  // MARK: - Email/Password Authentication

  /// Sign in with email and password
  /// - Returns: `.signedIn` when Clerk created the session, or `.needsEmailCode` when it sent
  ///   a code that `verifySignInCode` must check.
  func signInWithPassword(email: String, password: String) async throws -> EmailSignInResult {
    isLoading = true
    defer { isLoading = false }

    let signIn = try await Clerk.shared.auth.signInWithPassword(
      identifier: email, password: password)
    switch signIn.status {
    case .complete:
      return .signedIn

    case .needsSecondFactor, .needsClientTrust:
      // Authenticator apps and phones are gone, so an email code is the only second factor.
      guard
        let factor = signIn.supportedSecondFactors?.first(where: { $0.strategy == .emailCode })
      else { throw AuthError.sessionMissing }
      pendingSignIn = try await signIn.sendMfaEmailCode(emailAddressId: factor.emailAddressId)
      return .needsEmailCode

    default:
      throw AuthError.sessionMissing
    }
  }

  /// Check the code from the second-factor email.
  func verifySignInCode(_ code: String) async throws {
    isLoading = true
    defer { isLoading = false }

    guard let signIn = pendingSignIn ?? Clerk.shared.auth.currentSignIn else {
      throw AuthError.sessionMissing
    }
    let result = try await signIn.verifyMfaCode(code, type: .emailCode)
    guard result.status == .complete else { throw AuthError.sessionMissing }
    pendingSignIn = nil
  }

  /// Send a new second-factor code.
  func resendSignInCode() async throws {
    isLoading = true
    defer { isLoading = false }

    guard let signIn = pendingSignIn ?? Clerk.shared.auth.currentSignIn else {
      throw AuthError.sessionMissing
    }
    pendingSignIn = try await signIn.sendMfaEmailCode()
  }

  // MARK: - Sign Up

  /// Sign up with email and password. Clerk creates the user once the emailed code is verified.
  /// - Returns: `.signedIn` when Clerk needs no code, or `.needsVerification` when it emailed
  ///   a code that `verifySignupCode` must check, or `.alreadyRegistered` for a known email.
  func signUpWithEmail(
    email: String,
    password: String,
    firstName: String? = nil,
    lastName: String? = nil
  ) async throws -> EmailSignupResult {
    isLoading = true
    defer { isLoading = false }

    do {
      let signUp = try await Clerk.shared.auth.signUp(
        emailAddress: email,
        password: password,
        firstName: firstName?.nilIfEmpty,
        lastName: lastName?.nilIfEmpty,
        legalAccepted: true
      )
      if signUp.status == .complete {
        return .signedIn
      }
      pendingSignUp = try await signUp.sendEmailCode()
      return .needsVerification
    } catch let error as ClerkAPIError where error.code == "form_identifier_exists" {
      return .alreadyRegistered
    }
  }

  /// Verify the code from the signup email. Clerk stores the session it creates.
  func verifySignupCode(_ code: String) async throws {
    isLoading = true
    defer { isLoading = false }

    guard let signUp = pendingSignUp ?? Clerk.shared.auth.currentSignUp else {
      throw AuthError.sessionMissing
    }
    let result = try await signUp.verifyEmailCode(code)
    guard result.status == .complete else { throw AuthError.sessionMissing }
    pendingSignUp = nil
  }

  /// Send a new signup code.
  func resendSignupCode() async throws {
    isLoading = true
    defer { isLoading = false }

    guard let signUp = pendingSignUp ?? Clerk.shared.auth.currentSignUp else {
      throw AuthError.sessionMissing
    }
    pendingSignUp = try await signUp.sendEmailCode()
  }

  /// Records the terms for a person who just signed up. The Convex user row exists only once
  /// the first session lookup has created it, so resolve the session first.
  /// - Returns: false when the lookup or the save failed. The terms screen then asks again.
  func recordTermsAfterSignup() async -> Bool {
    guard (try? await AuthSessionManager.shared.getSession()) != nil else { return false }
    return (try? await recordTermsAcceptance()) != nil
  }

  /// Record that the current authenticated user accepted the current terms.
  func recordTermsAcceptance() async throws {
    _ = try await ConvexAPI.app.mutation("users:acceptTerms", as: String?.self)

    // Refresh the user so the coordinator's terms check sees the new timestamp.
    _ = try await AuthSessionManager.shared.forceRefresh()
  }

  // MARK: - Password Reset

  /// Send a password reset code to the email address.
  func sendPasswordResetEmail(email: String) async throws {
    isLoading = true
    defer { isLoading = false }

    let signIn = try await Clerk.shared.auth.signIn(email)
    pendingSignIn = try await signIn.sendResetPasswordEmailCode()
  }

  /// Verify the reset code. The sign-in then waits for a new password.
  func verifyPasswordResetCode(_ code: String) async throws {
    isLoading = true
    defer { isLoading = false }

    guard let signIn = pendingSignIn ?? Clerk.shared.auth.currentSignIn else {
      throw AuthError.sessionMissing
    }
    let result = try await signIn.verifyCode(code)
    guard result.status == .needsNewPassword else { throw AuthError.sessionMissing }
    pendingSignIn = result
  }

  /// Set the new password after `verifyPasswordResetCode`. Clerk signs the user in with it.
  func resetPassword(newPassword: String) async throws {
    isLoading = true
    defer { isLoading = false }

    guard let signIn = pendingSignIn ?? Clerk.shared.auth.currentSignIn else {
      throw AuthError.sessionMissing
    }
    let result = try await signIn.resetPassword(newPassword: newPassword)
    guard result.status == .complete else { throw AuthError.sessionMissing }
    pendingSignIn = nil
  }

  /// Change the password of the signed-in user. `currentPassword` is nil for a user who has none.
  func updatePassword(currentPassword: String?, newPassword: String) async throws {
    isLoading = true
    defer { isLoading = false }

    guard let user = Clerk.shared.user else { throw AuthError.sessionMissing }
    try await user.updatePassword(
      .init(currentPassword: currentPassword, newPassword: newPassword))
  }

  // MARK: - OAuth Sign-In

  /// Sign in with Apple using the ID token from the native sheet.
  /// - Parameter fullName: Name components from Apple, which sends them only on the first sign-in.
  func signInWithApple(idToken: String, fullName: PersonNameComponents? = nil) async throws {
    isLoading = true
    defer { isLoading = false }

    let result = try await Clerk.shared.auth.signInWithIdToken(
      idToken, provider: .apple, transferable: true)
    let isNewUser = try await finish(result)

    // Best-effort: don't block login if Clerk refuses the name.
    if isNewUser, let fullName,
      fullName.givenName?.nilIfEmpty != nil || fullName.familyName?.nilIfEmpty != nil
    {
      _ = try? await Clerk.shared.user?.update(
        .init(firstName: fullName.givenName?.nilIfEmpty, lastName: fullName.familyName?.nilIfEmpty)
      )
    }
  }

  /// Sign in with Google in a web sheet. Clerk has no native Google ID token path.
  func signInWithGoogle() async throws {
    isLoading = true
    defer { isLoading = false }

    let result = try await Clerk.shared.auth.signInWithOAuth(provider: .google)
    _ = try await finish(result)
  }

  /// Makes sure a sign-in or sign-up from Apple or Google ended with a session.
  /// - Returns: true when the person is new.
  private func finish(_ result: TransferFlowResult) async throws -> Bool {
    switch result {
    case .signIn(let signIn):
      guard signIn.status == .complete else { throw AuthError.sessionMissing }
      return false

    case .signUp(var signUp):
      // Only when the Clerk instance requires legal consent at sign-up.
      if signUp.status != .complete, signUp.missingFields.contains(.legalAccepted) {
        signUp = try await signUp.update(legalAccepted: true)
      }
      guard signUp.status == .complete else { throw AuthError.sessionMissing }
      return true
    }
  }

  // MARK: - Sign Out

  /// Sign out the current user from this device only
  /// Other devices will remain logged in
  func signOut() async throws {
    isLoading = true
    defer { isLoading = false }

    try await Clerk.shared.auth.signOut()
  }

  /// Sign out the current user from ALL devices
  /// This revokes every other Clerk session of the user, then ends this one.
  func signOutGlobal() async throws {
    isLoading = true
    defer { isLoading = false }

    // Best-effort: this device still signs out when the session list is unavailable.
    if let user = Clerk.shared.user, let sessions = try? await user.getSessions() {
      let currentId = Clerk.shared.session?.id
      for session in sessions where session.id != currentId {
        _ = try? await Clerk.shared.auth.revokeSession(session)
      }
    }
    try await Clerk.shared.auth.signOut()
  }
}

// MARK: - Error Classification

extension AuthService {
  /// True when the person closed the Apple sheet or the Google web sheet.
  nonisolated static func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let error = error as? ASWebAuthenticationSessionError {
      return error.code == .canceledLogin
    }
    return (error as? AppleAuthError)?.isCancellation == true
  }

  /// True when Clerk rejected a verification code as wrong or expired.
  nonisolated static func isInvalidVerificationCode(_ error: Error) -> Bool {
    guard let code = (error as? ClerkAPIError)?.code else { return false }
    return ["form_code_incorrect", "verification_expired", "verification_failed"].contains(code)
  }

  /// True when Clerk refused a request because of a rate limit.
  nonisolated static func isRateLimited(_ error: Error) -> Bool {
    (error as? ClerkAPIError)?.code == "too_many_requests"
  }

  /// True when Clerk has no user for the email, so the person has to sign up.
  nonisolated static func isUnknownIdentifier(_ error: Error) -> Bool {
    (error as? ClerkAPIError)?.code == "form_identifier_not_found"
  }

  private static let messages: [String: LocalizedStringResource] = [
    "form_password_incorrect": .authErrorInvalidLoginCredentials,
    "strategy_for_user_invalid": .authErrorInvalidLoginCredentials,
    "form_identifier_not_found": .authErrorUserNotFound,
    "form_identifier_exists": .authErrorUserAlreadyRegistered,
    "external_account_exists": .authErrorUserAlreadyRegistered,
    "form_password_length_too_short": .authErrorPasswordMin8,
    "form_password_not_strong_enough": .authErrorPasswordMin8,
    "form_password_validation_failed": .authErrorPasswordMin8,
    "form_password_size_in_bytes_exceeded": .authErrorPasswordMin8,
    "form_param_format_invalid": .authErrorInvalidEmailFormat,
    "form_code_incorrect": .authErrorInvalidCode,
    "verification_failed": .authErrorInvalidCode,
    "verification_expired": .authErrorCodeExpired,
    "too_many_requests": .authErrorRequestRateLimited,
  ]

  /// The text to show for a failed auth call. Clerk's known codes get the app's own copy.
  @MainActor
  static func message(for error: Error) -> String {
    guard let clerkError = error as? ClerkAPIError else {
      return ErrorTranslations.translate(error)
    }
    if let known = messages[clerkError.code] {
      return String(localized: known)
    }
    return clerkError.errorDescription ?? ErrorTranslations.translate(error)
  }
}

extension String {
  fileprivate var nilIfEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
