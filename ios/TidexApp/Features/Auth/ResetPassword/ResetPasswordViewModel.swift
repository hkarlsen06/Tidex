import Combine
import Foundation

/// View model for the reset password screen
/// Handles three-step flow: Input -> OTP verification -> New password
@MainActor
final class ResetPasswordViewModel: ObservableObject {

  // MARK: - Dependencies

  private let authService: AuthService

  // MARK: - Published State

  @Published var emailOrPhone: String = ""
  @Published var otpCode: String = ""
  @Published var newPassword: String = ""
  @Published var confirmPassword: String = ""

  @Published var currentStep: ResetStep = .input
  @Published var isLoading = false

  @Published var errorMessage: String?
  @Published var successMessage: String?

  @Published var fieldErrors = FieldErrors()

  // MARK: - Navigation Callback

  var onNavigateToLogin: (() -> Void)?

  // MARK: - Types

  enum ResetStep {
    case input  // Email/phone input
    case otp  // OTP verification (for phone)
    case newPassword  // Enter new password
    case success  // Password reset complete
  }

  enum PresentationMode {
    case standard
    case recovery
  }

  typealias InputType = AuthIdentityInputType

  struct FieldErrors {
    var emailOrPhone: String?
    var otp: String?
    var newPassword: String?
    var confirmPassword: String?

    mutating func clear() {
      emailOrPhone = nil
      otp = nil
      newPassword = nil
      confirmPassword = nil
    }
  }

  // MARK: - Private State

  private let presentationMode: PresentationMode
  private var authTask: Task<Void, Never>?

  // MARK: - Computed Properties

  /// Detected input type based on current emailOrPhone value
  var inputType: InputType {
    AuthIdentityInput.detectType(emailOrPhone)
  }

  /// Normalized phone number in E.164 format
  var normalizedPhone: String {
    AuthIdentityInput.normalizedPhone(emailOrPhone)
  }

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

  deinit {
    authTask?.cancel()
  }

  // MARK: - Actions

  /// Send reset code/link based on input type
  func sendResetCode() async {
    clearMessages()
    fieldErrors.clear()

    guard validateEmailOrPhone() else { return }

    isLoading = true
    defer { isLoading = false }

    do {
      switch inputType {
      case .email:
        try await authService.sendPasswordResetEmail(email: emailOrPhone)
        successMessage = String(localized: .resetPasswordSuccessEmailSent)
        currentStep = .otp

      case .phone:
        try await authService.sendPasswordResetOTP(phone: normalizedPhone)
        successMessage = String(localized: .resetPasswordSuccessOtpSent)
        currentStep = .otp

      case .unknown:
        fieldErrors.emailOrPhone = String(localized: .resetPasswordErrorsInvalidEmailOrPhone)
      }
    } catch {
      handleError(error)
    }
  }

  /// Verify OTP code for phone reset
  func verifyOTP() async {
    clearMessages()
    fieldErrors.clear()

    guard validateOTP() else { return }

    isLoading = true
    defer { isLoading = false }

    do {
      switch inputType {
      case .email:
        _ = try await authService.verifyPasswordResetOTP(email: emailOrPhone, token: otpCode)
      case .phone:
        _ = try await authService.verifyPasswordResetOTP(phone: normalizedPhone, token: otpCode)
      case .unknown:
        fieldErrors.otp = String(localized: .otpErrorsCodeInvalid)
        return
      }

      NotificationCenter.default.post(name: .tidexPasswordRecoveryRequested, object: nil)
    } catch {
      handleError(error)
    }
  }

  /// Update password after verification
  func updatePassword() async {
    clearMessages()
    fieldErrors.clear()

    guard validateNewPassword() else { return }

    isLoading = true
    defer { isLoading = false }

    do {
      try await authService.updatePassword(newPassword: newPassword)
      successMessage = String(localized: .resetPasswordSuccessPasswordUpdated)
      currentStep = .success
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
    case .input, .success:
      // Already at start or end
      break
    case .otp:
      otpCode = ""
      currentStep = .input
    case .newPassword:
      newPassword = ""
      confirmPassword = ""
      // If phone flow, go back to OTP
      // If they got here via email magic link, they should start over
      if inputType == .phone {
        currentStep = .otp
      } else {
        currentStep = .input
      }
    }
  }

  /// Resend OTP code
  func resendOTP() async {
    clearMessages()
    isLoading = true
    defer { isLoading = false }

    do {
      switch inputType {
      case .email:
        try await authService.sendPasswordResetEmail(email: emailOrPhone)
        successMessage = String(localized: .resetPasswordSuccessEmailSent)
      case .phone:
        try await authService.sendPasswordResetOTP(phone: normalizedPhone)
        successMessage = String(localized: .resetPasswordSuccessOtpResent)
      case .unknown:
        fieldErrors.emailOrPhone = String(localized: .resetPasswordErrorsInvalidEmailOrPhone)
      }
    } catch {
      handleError(error)
    }
  }

  /// Navigate to login screen
  func navigateToLogin() {
    onNavigateToLogin?()
  }

  func handleSuccessAction() async {
    if presentationMode == .recovery {
      await AppCoordinator.shared.signOut()
    }

    navigateToLogin()
  }

  // MARK: - Validation

  private func validateEmailOrPhone() -> Bool {
    let trimmed = emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.isEmpty {
      fieldErrors.emailOrPhone = String(localized: .resetPasswordErrorsEmailOrPhoneRequired)
      return false
    }

    if inputType == .unknown {
      fieldErrors.emailOrPhone = String(localized: .resetPasswordErrorsInvalidEmailOrPhone)
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
    let translated = ErrorTranslations.translate(error)
    errorMessage = translated
  }

  private func clearMessages() {
    errorMessage = nil
    successMessage = nil
  }
}
