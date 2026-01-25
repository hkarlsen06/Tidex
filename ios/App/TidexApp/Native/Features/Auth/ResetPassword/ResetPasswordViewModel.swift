import Foundation
import SwiftUI
import Combine

/// View model for the reset password screen
/// Handles three-step flow: Input -> OTP verification -> New password
@MainActor
final class ResetPasswordViewModel: ObservableObject {

    // MARK: - Dependencies

    private let authService: AuthService
    private let localization: LocalizationManager

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
        case input         // Email/phone input
        case otp           // OTP verification (for phone)
        case newPassword   // Enter new password
        case success       // Password reset complete
    }

    enum InputType {
        case email
        case phone
        case unknown
    }

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

    // MARK: - Computed Properties

    /// Detected input type based on current emailOrPhone value
    var inputType: InputType {
        let trimmed = emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for email
        if trimmed.contains("@") && trimmed.contains(".") {
            return .email
        }

        // Check for phone
        let phoneChars = CharacterSet(charactersIn: "+0123456789 -")
        if trimmed.hasPrefix("+") || trimmed.allSatisfy({ String($0).rangeOfCharacter(from: phoneChars) != nil }) {
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

        if cleaned.hasPrefix("+") {
            return cleaned
        }

        if cleaned.hasPrefix("00") {
            return "+" + cleaned.dropFirst(2)
        }

        // Assume Norwegian number
        if cleaned.count == 8 {
            return "+47" + cleaned
        }

        return cleaned
    }

    // MARK: - Initialization

    init(
        authService: AuthService? = nil,
        localization: LocalizationManager? = nil
    ) {
        self.authService = authService ?? AuthService.shared
        self.localization = localization ?? LocalizationManager.shared
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
                successMessage = localization.string("resetPassword.success.emailSent")
                // For email, they'll receive a link - show success state
                currentStep = .success

            case .phone:
                try await authService.sendPasswordResetOTP(phone: normalizedPhone)
                successMessage = localization.string("resetPassword.success.otpSent")
                currentStep = .otp

            case .unknown:
                fieldErrors.emailOrPhone = localization.string("resetPassword.errors.invalidEmailOrPhone")
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
            // Verify OTP and get session
            _ = try await authService.verifyPasswordResetOTP(phone: normalizedPhone, token: otpCode)
            // Move to new password step
            currentStep = .newPassword
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
            successMessage = localization.string("resetPassword.success.passwordUpdated")
            currentStep = .success
        } catch {
            handleError(error)
        }
    }

    /// Go back to previous step
    func goBack() {
        clearMessages()
        fieldErrors.clear()

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
            try await authService.sendPasswordResetOTP(phone: normalizedPhone)
            successMessage = localization.string("resetPassword.success.otpResent")
        } catch {
            handleError(error)
        }
    }

    /// Navigate to login screen
    func navigateToLogin() {
        onNavigateToLogin?()
    }

    // MARK: - Validation

    private func validateEmailOrPhone() -> Bool {
        let trimmed = emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            fieldErrors.emailOrPhone = localization.string("resetPassword.errors.emailOrPhoneRequired")
            return false
        }

        if inputType == .unknown {
            fieldErrors.emailOrPhone = localization.string("resetPassword.errors.invalidEmailOrPhone")
            return false
        }

        return true
    }

    private func validateOTP() -> Bool {
        if otpCode.isEmpty {
            fieldErrors.otp = localization.string("otp.errors.codeRequired")
            return false
        }

        if otpCode.count != 6 {
            fieldErrors.otp = localization.string("otp.errors.codeInvalid")
            return false
        }

        return true
    }

    private func validateNewPassword() -> Bool {
        var isValid = true

        if newPassword.isEmpty {
            fieldErrors.newPassword = localization.string("resetPassword.errors.passwordRequired")
            isValid = false
        } else if newPassword.count < 8 {
            fieldErrors.newPassword = localization.string("resetPassword.errors.passwordTooShort")
            isValid = false
        }

        if confirmPassword.isEmpty {
            fieldErrors.confirmPassword = localization.string("resetPassword.errors.confirmPasswordRequired")
            isValid = false
        } else if newPassword != confirmPassword {
            fieldErrors.confirmPassword = localization.string("resetPassword.errors.passwordMismatch")
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
