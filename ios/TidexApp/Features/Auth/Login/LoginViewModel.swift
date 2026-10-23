import Foundation
import Observation

/// View model for the login screen
/// Handles all authentication methods: email/password, Google, Apple
@MainActor
@Observable
final class LoginViewModel {

  // MARK: - Dependencies

  private let emailAuth: EmailAuthProviding
  private let authService: AuthService
  private let appleAuthProvider: AppleAuthProvider
  private let onAuthenticated: () async -> Void

  // MARK: - Published State

  var email: String = ""
  var password: String = ""
  var otpCode: String = ""

  var currentStep: LoginStep = .input
  var isLoading = false
  var showEmailForm = false

  var errorMessage: String?
  var successMessage: String?
  var accountCreationPromptMessage: String?

  var fieldErrors = FieldErrors()

  // MARK: - Types

  enum LoginStep {
    case input
    /// Code from the sign-in email, when Clerk asks for a second factor.
    case otp
  }

  static let codeLength = 6

  struct FieldErrors {
    var email: String?
    var password: String?
    var otp: String?

    mutating func clear() {
      email = nil
      password = nil
      otp = nil
    }
  }

  // MARK: - Initialization

  init(
    authService: AuthService? = nil,
    emailAuth: EmailAuthProviding? = nil,
    appleAuthProvider: AppleAuthProvider? = nil,
    onAuthenticated: (() async -> Void)? = nil
  ) {
    self.authService = authService ?? AuthService.shared
    self.emailAuth = emailAuth ?? AuthService.shared
    self.appleAuthProvider = appleAuthProvider ?? AppleAuthProvider.shared
    self.onAuthenticated =
      onAuthenticated ?? {
        await AppCoordinator.shared.handleLoginSuccess()
      }
  }

  // MARK: - Actions

  /// Main sign in action
  func signIn() async {
    clearMessages()
    fieldErrors.clear()

    guard validateInput() else { return }

    isLoading = true
    defer { isLoading = false }

    do {
      let result = try await emailAuth.signInWithPassword(
        email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
      switch result {
      case .signedIn:
        await handleSuccessfulLogin()

      case .needsEmailCode:
        currentStep = .otp
      }
    } catch {
      handleSignInError(error)
    }
  }

  /// Verify the code from the sign-in email
  func verifyOTP() async {
    guard !isLoading else { return }
    clearMessages()
    fieldErrors.clear()

    guard otpCode.count == Self.codeLength else {
      fieldErrors.otp =
        otpCode.isEmpty
        ? String(localized: .otpErrorsCodeRequired) : String(localized: .otpErrorsCodeInvalid)
      return
    }

    isLoading = true
    defer { isLoading = false }

    do {
      try await emailAuth.verifySignInCode(otpCode)
      await handleSuccessfulLogin()
    } catch {
      otpCode = ""
      if AuthService.isInvalidVerificationCode(error) {
        fieldErrors.otp = String(localized: .signupVerifyErrorsInvalidCode)
        Haptics.play(.error)
      } else {
        handleError(error)
      }
    }
  }

  /// Sign in with Google
  func signInWithGoogle() async {
    clearMessages()
    isLoading = true
    defer { isLoading = false }

    do {
      try await authService.signInWithGoogle()
      await handleSuccessfulLogin()
    } catch where AuthService.isCancellation(error) {
      // User cancelled - do nothing
    } catch {
      handleError(error)
    }
  }

  /// Sign in with Apple
  func signInWithApple() async {
    // Before Apple's sheet, so the GoTrue exchange can't sign in the old account meanwhile.
    LegacySessionExchange.manualSignInDidStart()
    clearMessages()
    isLoading = true
    defer { isLoading = false }

    do {
      let result = try await appleAuthProvider.signIn()
      try await authService.signInWithApple(
        idToken: result.idToken,
        fullName: result.fullName
      )
      await handleSuccessfulLogin()
    } catch where AuthService.isCancellation(error) {
      // User cancelled - do nothing
    } catch {
      handleError(error)
    }
  }

  /// Go back from the code step to the input step
  func backToInput() {
    currentStep = .input
    otpCode = ""
    clearMessages()
  }

  /// Send a new sign-in code
  func resendOTP() async {
    clearMessages()
    isLoading = true
    defer { isLoading = false }

    do {
      try await emailAuth.resendSignInCode()
      successMessage = String(localized: .signupVerifyResendSent)
    } catch {
      if AuthService.isRateLimited(error) {
        errorMessage = String(localized: .signupVerifyErrorsTooManyRequests)
      } else {
        handleError(error)
      }
    }
  }

  func applySignupPrefill(email: String, password: String) {
    currentStep = .input
    self.email = email
    self.password = password
    otpCode = ""
    fieldErrors.clear()
    clearMessages()
    showEmailForm = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  // MARK: - Private Methods

  private func validateInput() -> Bool {
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.isEmpty {
      fieldErrors.email = String(localized: .signupErrorsEmailRequired)
      return false
    }

    if !AuthIdentityInput.isEmail(trimmed) {
      fieldErrors.email = String(localized: .signupErrorsInvalidEmail)
      return false
    }

    if password.isEmpty {
      fieldErrors.password = String(localized: .loginErrorsPasswordRequired)
      return false
    }

    return true
  }

  private func handleSuccessfulLogin() async {
    // The AppCoordinator also hears Clerk's sign-in event. Calling this makes it check the
    // user and terms right away.
    Haptics.play(.success)
    await onAuthenticated()
  }

  private func handleSignInError(_ error: Error) {
    if AuthService.isUnknownIdentifier(error) {
      showEmailForm = true
      accountCreationPromptMessage = AuthService.message(for: error)
      Haptics.play(.error)
      return
    }

    handleError(error)
  }

  private func handleError(_ error: Error) {
    errorMessage = AuthService.message(for: error)
    Haptics.play(.error)
  }

  private func clearMessages() {
    errorMessage = nil
    successMessage = nil
    accountCreationPromptMessage = nil
  }
}
