import Foundation
import Observation

/// View model for the reset password screen
/// Handles the flow: Input -> Code verification -> New password. Clerk signs the person in
/// once the new password is set, so the flow has no success step.
@MainActor
@Observable
final class ResetPasswordViewModel {

  // MARK: - Dependencies

  private let authService: AuthService

  // MARK: - Published State

  var email: String = ""
  var otpCode: String = ""
  var newPassword: String = ""
  var confirmPassword: String = ""

  var currentStep: ResetStep = .input
  var isLoading = false

  var errorMessage: String?
  var successMessage: String?

  var fieldErrors = FieldErrors()

  // MARK: - Navigation Callback

  var onNavigateToLogin: (() -> Void)?

  // MARK: - Types

  enum ResetStep {
    case input  // Email input
    case otp  // Code from the reset email
    case newPassword  // Enter new password
  }

  /// `.recovery` served the old reset link. Nothing starts it any more, so `RootView` can
  /// drop its recovery cover and this enum with it.
  enum PresentationMode {
    case standard
    case recovery
  }

  struct FieldErrors {
    var email: String?
    var otp: String?
    var newPassword: String?
    var confirmPassword: String?

    mutating func clear() {
      email = nil
      otp = nil
      newPassword = nil
      confirmPassword = nil
    }
  }

  // MARK: - Private State

  private let presentationMode: PresentationMode

  // MARK: - Computed Properties

  var isRecoveryMode: Bool {
    presentationMode == .recovery
  }

  // MARK: - Initialization

  init(
    authService: AuthService? = nil,
    presentationMode: PresentationMode = .standard
  ) {
    self.authService = authService ?? AuthService.shared
    self.presentationMode = presentationMode

    if presentationMode == .recovery {
      currentStep = .newPassword
    }
  }

  // MARK: - Actions

  /// Send the reset code to the email address
  func sendResetCode() async {
    clearMessages()
    fieldErrors.clear()

    guard validateEmail() else { return }

    isLoading = true
    defer { isLoading = false }

    do {
      try await authService.sendPasswordResetEmail(
        email: email.trimmingCharacters(in: .whitespacesAndNewlines))
      currentStep = .otp
    } catch {
      handleError(error)
    }
  }

  /// Verify the code from the reset email
  func verifyOTP() async {
    clearMessages()
    fieldErrors.clear()

    guard validateOTP() else { return }

    isLoading = true
    defer { isLoading = false }

    do {
      try await authService.verifyPasswordResetCode(otpCode)
      currentStep = .newPassword
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

  /// Set the new password. Clerk signs the person in, and the coordinator moves on.
  func updatePassword() async {
    clearMessages()
    fieldErrors.clear()

    guard validateNewPassword() else { return }

    isLoading = true
    defer { isLoading = false }

    do {
      try await authService.resetPassword(newPassword: newPassword)
      Haptics.play(.success)
      await AppCoordinator.shared.handleLoginSuccess()
    } catch {
      handleError(error)
    }
  }

  /// Go back to previous step
  func goBack() {
    clearMessages()
    fieldErrors.clear()

    if presentationMode == .recovery {
      return
    }

    switch currentStep {
    case .input:
      break

    case .otp:
      otpCode = ""
      currentStep = .input

    case .newPassword:
      // The code is spent, so start over.
      newPassword = ""
      confirmPassword = ""
      otpCode = ""
      currentStep = .input
    }
  }

  /// Send a new reset code
  func resendOTP() async {
    clearMessages()
    isLoading = true
    defer { isLoading = false }

    do {
      try await authService.sendPasswordResetEmail(
        email: email.trimmingCharacters(in: .whitespacesAndNewlines))
      successMessage = String(localized: .resetPasswordSuccessOtpResent)
    } catch {
      if AuthService.isRateLimited(error) {
        errorMessage = String(localized: .signupVerifyErrorsTooManyRequests)
      } else {
        handleError(error)
      }
    }
  }

  /// Navigate to login screen
  func navigateToLogin() {
    onNavigateToLogin?()
  }

  // MARK: - Validation

  private func validateEmail() -> Bool {
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.isEmpty {
      fieldErrors.email = String(localized: .signupErrorsEmailRequired)
      return false
    }

    if !AuthIdentityInput.isEmail(trimmed) {
      fieldErrors.email = String(localized: .signupErrorsInvalidEmail)
      return false
    }

    return true
  }

  private func validateOTP() -> Bool {
    if otpCode.isEmpty {
      fieldErrors.otp = String(localized: .otpErrorsCodeRequired)
      return false
    }

    if otpCode.count != 6 {
      fieldErrors.otp = String(localized: .otpErrorsCodeInvalid)
      return false
    }

    return true
  }

  private func validateNewPassword() -> Bool {
    var isValid = true

    if newPassword.isEmpty {
      fieldErrors.newPassword = String(localized: .resetPasswordErrorsPasswordRequired)
      isValid = false
    } else if newPassword.count < 8 {
      fieldErrors.newPassword = String(localized: .resetPasswordErrorsPasswordTooShort)
      isValid = false
    }

    if confirmPassword.isEmpty {
      fieldErrors.confirmPassword = String(localized: .resetPasswordErrorsConfirmPasswordRequired)
      isValid = false
    } else if newPassword != confirmPassword {
      fieldErrors.confirmPassword = String(localized: .resetPasswordErrorsPasswordMismatch)
      isValid = false
    }

    return isValid
  }

  // MARK: - Private Methods

  private func handleError(_ error: Error) {
    errorMessage = AuthService.message(for: error)
  }

  private func clearMessages() {
    errorMessage = nil
    successMessage = nil
  }
}
