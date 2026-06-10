import Combine
import Foundation

/// View model for the signup screen
/// Handles email/password and OAuth registration
@MainActor
final class SignupViewModel: ObservableObject {

  // MARK: - Dependencies

  private let authService: AuthService
  private let appleAuthProvider: AppleAuthProvider
  private let googleAuthProvider: GoogleAuthProvider

  // MARK: - Published State

  @Published var firstName: String = ""
  @Published var lastName: String = ""
  @Published var emailOrPhone: String = ""
  @Published var password: String = ""
  @Published var confirmPassword: String = ""
  @Published var hasAcceptedTerms = false

  @Published var isLoading = false
  @Published var showEmailForm = false

  @Published var errorMessage: String?

  @Published var fieldErrors = FieldErrors()

  // MARK: - Navigation Callback

  var onNavigateToLogin: (() -> Void)?

  // MARK: - Types

  struct FieldErrors {
    var firstName: String?
    var lastName: String?
    var emailOrPhone: String?
    var password: String?
    var confirmPassword: String?
    var terms: String?

    mutating func clear() {
      firstName = nil
      lastName = nil
      emailOrPhone = nil
      password = nil
      confirmPassword = nil
      terms = nil
    }
  }

  // MARK: - Computed Properties

  /// Full name combined from first and last name
  var fullName: String {
    "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
  }

  // MARK: - Initialization

  init(
    authService: AuthService? = nil,
    appleAuthProvider: AppleAuthProvider? = nil,
    googleAuthProvider: GoogleAuthProvider? = nil
  ) {
    self.authService = authService ?? AuthService.shared
    self.appleAuthProvider = appleAuthProvider ?? AppleAuthProvider.shared
    self.googleAuthProvider = googleAuthProvider ?? GoogleAuthProvider.shared
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
      let email = emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines)
      _ = try await authService.signUpWithEmail(
        email: email,
        password: password,
        fullName: fullName
      )
      await handleSuccessfulSignup()
    } catch {
      handleError(error)
    }
  }

  /// Sign up with Google
  func signUpWithGoogle() async {
    clearMessages()
    fieldErrors.clear()

    guard validateTermsAgreement() else { return }

    isLoading = true
    defer { isLoading = false }

    do {
      let idToken = try await googleAuthProvider.signIn()
      _ = try await authService.signInWithGoogle(idToken: idToken)
      try await authService.recordTermsAcceptance()
      await handleSuccessfulSignup()
    } catch let error as GoogleAuthError where error.isCancellation {
      // User cancelled - do nothing
    } catch {
      handleError(error)
    }
  }

  /// Sign up with Apple
  func signUpWithApple() async {
    clearMessages()
    fieldErrors.clear()

    guard validateTermsAgreement() else { return }

    isLoading = true
    defer { isLoading = false }

    do {
      let result = try await appleAuthProvider.signIn()
      _ = try await authService.signInWithApple(
        idToken: result.idToken,
        fullName: result.fullName
      )
      try await authService.recordTermsAcceptance()
      await handleSuccessfulSignup()
    } catch let error as AppleAuthError where error.isCancellation {
      // User cancelled - do nothing
    } catch {
      handleError(error)
    }
  }

  /// Navigate to login screen
  func navigateToLogin() {
    onNavigateToLogin?()
  }

  func applyLoginPrefill(emailOrPhone: String, password: String) {
    let trimmed = emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines)
    let isEmail = AuthIdentityInput.detectType(trimmed) == .email

    self.emailOrPhone = isEmail ? trimmed : ""
    self.password = isEmail ? password : ""
    fieldErrors.clear()
    clearMessages()
    showEmailForm = isEmail
  }

  // MARK: - Private Methods

  private func validateInput() -> Bool {
    var isValid = true
    let trimmed = emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines)

    if firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      fieldErrors.firstName = String(localized: .signupErrorsFirstNameRequired)
      isValid = false
    }

    if lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      fieldErrors.lastName = String(localized: .signupErrorsLastNameRequired)
      isValid = false
    }

    if trimmed.isEmpty {
      fieldErrors.emailOrPhone = String(localized: .signupErrorsEmailRequired)
      isValid = false
    } else if AuthIdentityInput.detectType(trimmed) != .email {
      fieldErrors.emailOrPhone = String(localized: .signupErrorsInvalidEmail)
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

    return validateTermsAgreement() && isValid
  }

  private func validateTermsAgreement() -> Bool {
    guard hasAcceptedTerms else {
      fieldErrors.terms = String(localized: .acceptTermsDescription)
      return false
    }

    fieldErrors.terms = nil
    return true
  }

  private func handleSuccessfulSignup() async {
    // The AppCoordinator listens to Supabase auth state changes
    // and will automatically transition to the appropriate state
    await AppCoordinator.shared.handleLoginSuccess()
  }

  private func handleError(_ error: Error) {
    let translated = ErrorTranslations.translate(error)
    errorMessage = translated
  }

  private func clearMessages() {
    errorMessage = nil
  }
}
