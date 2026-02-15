import Combine
import Foundation
import SwiftUI

/// View model for the signup screen
/// Handles email/password, phone/OTP, and OAuth registration
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
  @Published var otpCode: String = ""

  @Published var currentStep: SignupStep = .input
  @Published var isLoading = false
  @Published var showEmailForm = false

  @Published var errorMessage: String?
  @Published var successMessage: String?

  @Published var fieldErrors = FieldErrors()

  // MARK: - Navigation Callback

  var onNavigateToLogin: (() -> Void)?

  // MARK: - Types

  enum SignupStep {
    case input
    case otp  // Phone OTP verification
  }

  enum InputType {
    case email
    case phone
    case unknown
  }

  struct FieldErrors {
    var firstName: String?
    var lastName: String?
    var emailOrPhone: String?
    var password: String?
    var confirmPassword: String?
    var otp: String?

    mutating func clear() {
      firstName = nil
      lastName = nil
      emailOrPhone = nil
      password = nil
      confirmPassword = nil
      otp = nil
    }
  }

  // MARK: - Private State

  private var authTask: Task<Void, Never>?

  // MARK: - Computed Properties

  /// Detected input type based on current emailOrPhone value
  var inputType: InputType {
    let trimmed = emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines)

    // Check for email
    if trimmed.contains("@") && trimmed.contains(".") {
      return .email
    }

    // Check for phone (starts with + or contains only digits and common phone characters)
    let phoneChars = CharacterSet(charactersIn: "+0123456789 -")
    if trimmed.hasPrefix("+")
      || trimmed.allSatisfy({ String($0).rangeOfCharacter(from: phoneChars) != nil })
    {
      let digits = trimmed.filter { $0.isNumber }
      if digits.count >= 8 {
        return .phone
      }
    }

    return .unknown
  }

  /// Normalized phone number in E.164 format
  var normalizedPhone: String {
    let cleaned = emailOrPhone.filter { $0.isNumber || $0 == "+" }

    // If it already has country code, return as-is
    if cleaned.hasPrefix("+") {
      return cleaned
    }

    // If it starts with 00, replace with +
    if cleaned.hasPrefix("00") {
      return "+" + cleaned.dropFirst(2)
    }

    // Future work: support multi-country local phone parsing instead of hardcoding +47 fallback.
    // Assume Norwegian number if no country code
    // Norwegian numbers are 8 digits
    if cleaned.count == 8 {
      return "+47" + cleaned
    }

    return cleaned
  }

  /// Check if form is valid for submission
  var isFormValid: Bool {
    !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
  }

  /// Full name combined from first and last name
  var fullName: String {
    "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
  }

  // MARK: - Initialization

  init(
    authService: AuthService? = nil,
    appleAuthProvider: AppleAuthProvider? = nil,
    googleAuthProvider: GoogleAuthProvider? = nil,
  ) {
    self.authService = authService ?? AuthService.shared
    self.appleAuthProvider = appleAuthProvider ?? AppleAuthProvider.shared
    self.googleAuthProvider = googleAuthProvider ?? GoogleAuthProvider.shared
  }

  deinit {
    authTask?.cancel()
  }

  // MARK: - Actions

  /// Main sign up action - routes to appropriate method based on input type
  func signUp() async {
    clearMessages()
    fieldErrors.clear()

    guard validateInput() else { return }

    isLoading = true
    defer { isLoading = false }

    do {
      switch inputType {
      case .email:
        try await signUpWithEmail()

      case .phone:
        try await signUpWithPhone()

      case .unknown:
        fieldErrors.emailOrPhone = String(localized: .signupErrorsInvalidEmailOrPhone)
      }
    } catch {
      handleError(error)
    }
  }

  /// Verify OTP code for phone signup
  func verifyOTP() async {
    clearMessages()
    fieldErrors.clear()

    guard !otpCode.isEmpty else {
      fieldErrors.otp = String(localized: .otpErrorsCodeRequired)
      return
    }

    guard otpCode.count == 6 else {
      fieldErrors.otp = String(localized: .otpErrorsCodeInvalid)
      return
    }

    isLoading = true
    defer { isLoading = false }

    do {
      let _ = try await authService.verifyOTP(phone: normalizedPhone, token: otpCode)
      await handleSuccessfulSignup()
    } catch {
      handleError(error)
    }
  }

  /// Sign up with Google
  func signUpWithGoogle() async {
    clearMessages()
    isLoading = true
    defer { isLoading = false }

    do {
      let idToken = try await googleAuthProvider.signIn()
      let _ = try await authService.signInWithGoogle(idToken: idToken)
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
    isLoading = true
    defer { isLoading = false }

    do {
      let result = try await appleAuthProvider.signIn()
      let _ = try await authService.signInWithApple(
        idToken: result.idToken,
        fullName: result.fullName
      )
      await handleSuccessfulSignup()
    } catch let error as AppleAuthError where error.isCancellation {
      // User cancelled - do nothing
    } catch {
      handleError(error)
    }
  }

  /// Go back from OTP/email sent step to input step
  func backToInput() {
    currentStep = .input
    otpCode = ""
    clearMessages()
  }

  /// Resend OTP code
  func resendOTP() async {
    clearMessages()
    isLoading = true
    defer { isLoading = false }

    do {
      try await authService.signUpWithPhone(
        phone: normalizedPhone, password: password, fullName: fullName)
      successMessage = String(localized: .signupSuccessOtpResent)
    } catch {
      handleError(error)
    }
  }

  /// Navigate to login screen
  func navigateToLogin() {
    onNavigateToLogin?()
  }

  // MARK: - Private Methods

  private func signUpWithEmail() async throws {
    // Email verification disabled - session is returned immediately
    let _ = try await authService.signUpWithEmail(
      email: emailOrPhone, password: password, fullName: fullName)
    await handleSuccessfulSignup()
  }

  private func signUpWithPhone() async throws {
    try await authService.signUpWithPhone(
      phone: normalizedPhone, password: password, fullName: fullName)
    successMessage = String(localized: .signupSuccessOtpSent)
    currentStep = .otp
  }

  private func validateInput() -> Bool {
    var isValid = true
    let trimmed = emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines)

    // First name required
    if firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      fieldErrors.firstName = String(localized: .signupErrorsFirstNameRequired)
      isValid = false
    }

    // Last name required
    if lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      fieldErrors.lastName = String(localized: .signupErrorsLastNameRequired)
      isValid = false
    }

    // Email/phone required
    if trimmed.isEmpty {
      fieldErrors.emailOrPhone = String(localized: .signupErrorsEmailOrPhoneRequired)
      isValid = false
    } else if inputType == .unknown {
      fieldErrors.emailOrPhone = String(localized: .signupErrorsInvalidEmailOrPhone)
      isValid = false
    }

    // Password required and minimum length
    if password.isEmpty {
      fieldErrors.password = String(localized: .signupErrorsPasswordRequired)
      isValid = false
    } else if password.count < 8 {
      fieldErrors.password = String(localized: .signupErrorsPasswordTooShort)
      isValid = false
    }

    // Confirm password must match (if visible)
    if !confirmPassword.isEmpty && password != confirmPassword {
      fieldErrors.confirmPassword = String(localized: .signupErrorsPasswordMismatch)
      isValid = false
    }

    return isValid
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
    successMessage = nil
  }
}
