import Foundation
import Observation

/// View model for the signup screen
/// Handles email/password and OAuth registration
@MainActor
@Observable
final class SignupViewModel {

  // MARK: - Dependencies

  private let authService: AuthService
  private let emailAuth: EmailAuthProviding
  private let onAuthenticated: () async -> Void
  private let appleAuthProvider: AppleAuthProvider

  // MARK: - Published State

  var firstName: String = ""
  var lastName: String = ""
  var email: String = ""
  var password: String = ""
  var confirmPassword: String = ""
  var otpCode: String = ""

  var step: Step = .form
  var isLoading = false
  var showEmailForm = false

  var errorMessage: String?
  var successMessage: String?

  var fieldErrors = FieldErrors()

  // MARK: - Navigation Callback

  var onNavigateToLogin: (() -> Void)?

  // MARK: - Types

  enum Step {
    /// Name, email and password.
    case form
    /// Code from the confirmation email. Clerk creates the user only after it is verified.
    case verifyEmail
  }

  /// Seconds before the server accepts another confirmation email for the same address.
  static let resendCooldown: TimeInterval = 60
  static let codeLength = 6

  struct FieldErrors {
    var firstName: String?
    var lastName: String?
    var email: String?
    var password: String?
    var confirmPassword: String?
    var otp: String?

    mutating func clear() {
      otp = nil
      firstName = nil
      lastName = nil
      email = nil
      password = nil
      confirmPassword = nil
    }
  }

  // MARK: - Computed Properties

  /// Full name combined from first and last name
  var fullName: String {
    "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
  }

  // MARK: - Private State

  /// The address that received the confirmation code.
  private(set) var pendingEmail = ""
  private(set) var resendAvailableAt: Date?

  // MARK: - Initialization

  init(
    authService: AuthService? = nil,
    emailAuth: EmailAuthProviding? = nil,
    appleAuthProvider: AppleAuthProvider? = nil,
    onAuthenticated: (() async -> Void)? = nil
  ) {
    self.authService = authService ?? AuthService.shared
    self.emailAuth = emailAuth ?? AuthService.shared
    self.onAuthenticated =
      onAuthenticated ?? {
        // The person accepted the terms on this screen.
        if await AuthService.shared.recordTermsAfterSignup(),
          AppCoordinator.shared.appState == .termsRequired
        {
          // The coordinator checked the terms before they were saved.
          AppCoordinator.shared.handleTermsAccepted()
          return
        }
        await AppCoordinator.shared.handleLoginSuccess()
      }
    self.appleAuthProvider = appleAuthProvider ?? AppleAuthProvider.shared
  }

  // MARK: - Actions

  /// Sign up with email and password.
  func signUp() async {
    clearMessages()
    fieldErrors.clear()

    guard validateInput() else { return }

    isLoading = true
    defer { isLoading = false }

    do {
      let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
      let result = try await emailAuth.signUpWithEmail(
        email: trimmedEmail,
        password: password,
        firstName: firstName,
        lastName: lastName
      )
      switch result {
      case .signedIn:
        await handleSuccessfulSignup()
      case .needsVerification:
        showEmailVerification(email: trimmedEmail)
        startResendCooldown()
      case .alreadyRegistered:
        errorMessage = String(localized: .authErrorUserAlreadyRegistered)
      }
    } catch {
      handleError(error)
    }
  }

  /// Verify the code from the confirmation email, then continue like an immediate signup.
  func verifyEmailCode() async {
    guard !isLoading else { return }
    clearMessages()
    fieldErrors.clear()

    guard otpCode.count == Self.codeLength else {
      if otpCode.isEmpty {
        fieldErrors.otp = String(localized: .otpErrorsCodeRequired)
      } else {
        fieldErrors.otp = String(localized: .otpErrorsCodeInvalid)
      }
      return
    }

    isLoading = true
    defer { isLoading = false }

    do {
      try await emailAuth.verifySignupCode(otpCode)
      await handleSuccessfulSignup()
    } catch {
      otpCode = ""
      if AuthService.isInvalidVerificationCode(error) {
        fieldErrors.otp = String(localized: .signupVerifyErrorsInvalidCode)
        Haptics.play(.error)
      } else if AuthService.isRateLimited(error) {
        errorMessage = String(localized: .signupVerifyErrorsTooManyRequests)
      } else {
        handleError(error)
      }
    }
  }

  /// Send a new confirmation code. Does nothing while the cooldown runs.
  func resendCode() async {
    guard !isLoading, resendSecondsRemaining() == 0 else { return }
    clearMessages()
    fieldErrors.clear()

    isLoading = true
    defer { isLoading = false }

    do {
      try await emailAuth.resendSignupCode()
      successMessage = String(localized: .signupVerifyResendSent)
      startResendCooldown()
    } catch {
      if AuthService.isRateLimited(error) {
        errorMessage = String(localized: .signupVerifyErrorsTooManyRequests)
        startResendCooldown()
      } else {
        handleError(error)
      }
    }
  }

  /// Open the code step for an address that has a pending confirmation.
  func showEmailVerification(email: String) {
    pendingEmail = email
    self.email = email
    otpCode = ""
    fieldErrors.clear()
    clearMessages()
    resendAvailableAt = nil
    showEmailForm = true
    step = .verifyEmail
  }

  /// Leave the code step to fix the email address or the other fields.
  func cancelEmailVerification() {
    otpCode = ""
    fieldErrors.clear()
    clearMessages()
    step = .form
  }

  /// Whole seconds until the resend button works again.
  func resendSecondsRemaining(at now: Date = Date()) -> Int {
    guard let resendAvailableAt else { return 0 }
    return max(0, Int(resendAvailableAt.timeIntervalSince(now).rounded(.up)))
  }

  /// Sign up with Google
  func signUpWithGoogle() async {
    clearMessages()
    fieldErrors.clear()

    isLoading = true
    defer { isLoading = false }

    do {
      try await authService.signInWithGoogle()
      await handleSuccessfulSignup()
    } catch where AuthService.isCancellation(error) {
      // User cancelled - do nothing
    } catch {
      handleError(error)
    }
  }

  /// Sign up with Apple
  func signUpWithApple() async {
    clearMessages()
    fieldErrors.clear()

    isLoading = true
    defer { isLoading = false }

    do {
      let result = try await appleAuthProvider.signIn()
      try await authService.signInWithApple(
        idToken: result.idToken,
        fullName: result.fullName
      )
      await handleSuccessfulSignup()
    } catch where AuthService.isCancellation(error) {
      // User cancelled - do nothing
    } catch {
      handleError(error)
    }
  }

  /// Navigate to login screen
  func navigateToLogin() {
    onNavigateToLogin?()
  }

  func applyLoginPrefill(email: String, password: String) {
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
    let isEmail = AuthIdentityInput.isEmail(trimmed)

    self.email = isEmail ? trimmed : ""
    self.password = isEmail ? password : ""
    otpCode = ""
    step = .form
    fieldErrors.clear()
    clearMessages()
    showEmailForm = isEmail
  }

  // MARK: - Private Methods

  private func validateInput() -> Bool {
    var isValid = true
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)

    if firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      fieldErrors.firstName = String(localized: .signupErrorsFirstNameRequired)
      isValid = false
    }

    if lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      fieldErrors.lastName = String(localized: .signupErrorsLastNameRequired)
      isValid = false
    }

    if trimmed.isEmpty {
      fieldErrors.email = String(localized: .signupErrorsEmailRequired)
      isValid = false
    } else if !AuthIdentityInput.isEmail(trimmed) {
      fieldErrors.email = String(localized: .signupErrorsInvalidEmail)
      isValid = false
    }

    if password.isEmpty {
      fieldErrors.password = String(localized: .signupErrorsPasswordRequired)
      isValid = false
    } else if password.count < 8 {
      fieldErrors.password = String(localized: .signupErrorsPasswordTooShort)
      isValid = false
    }

    if !confirmPassword.isEmpty, password != confirmPassword {
      fieldErrors.confirmPassword = String(localized: .signupErrorsPasswordMismatch)
      isValid = false
    }

    return isValid
  }

  private func handleSuccessfulSignup() async {
    await onAuthenticated()
  }

  private func startResendCooldown() {
    resendAvailableAt = Date().addingTimeInterval(Self.resendCooldown)
  }

  private func handleError(_ error: Error) {
    errorMessage = AuthService.message(for: error)
  }

  private func clearMessages() {
    errorMessage = nil
    successMessage = nil
  }
}
