import Foundation
import SwiftUI
import Combine

/// View model for the login screen
/// Handles all authentication methods: email/password, phone/OTP, Google, Apple
@MainActor
final class LoginViewModel: ObservableObject {

    // MARK: - Dependencies

    private let authService: AuthService
    private let appleAuthProvider: AppleAuthProvider
    private let googleAuthProvider: GoogleAuthProvider

    // MARK: - Published State

    @Published var emailOrPhone: String = ""
    @Published var password: String = ""
    @Published var otpCode: String = ""

    @Published var currentStep: LoginStep = .input
    @Published var isLoading = false
    @Published var showEmailForm = false

    @Published var errorMessage: String?
    @Published var successMessage: String?

    @Published var fieldErrors = FieldErrors()

    // MARK: - Types

    enum LoginStep {
        case input
        case otp
    }

    enum InputType {
        case email
        case phone
        case unknown
    }

    struct FieldErrors {
        var emailOrPhone: String?
        var password: String?
        var otp: String?

        mutating func clear() {
            emailOrPhone = nil
            password = nil
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

        // If it already has country code, return as-is
        if cleaned.hasPrefix("+") {
            return cleaned
        }

        // If it starts with 00, replace with +
        if cleaned.hasPrefix("00") {
            return "+" + cleaned.dropFirst(2)
        }

        // Assume Norwegian number if no country code
        // Norwegian numbers are 8 digits
        if cleaned.count == 8 {
            return "+47" + cleaned
        }

        return cleaned
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

    /// Main sign in action - routes to appropriate method based on input type
    func signIn() async {
        clearMessages()
        fieldErrors.clear()

        guard validateInput() else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            switch inputType {
            case .email:
                try await signInWithEmail()

            case .phone:
                if password.isEmpty {
                    try await sendPhoneOTP()
                } else {
                    try await signInWithPhone()
                }

            case .unknown:
                fieldErrors.emailOrPhone = String(localized: .loginErrorsInvalidEmailOrPhone)
            }
        } catch {
            handleError(error)
        }
    }

    /// Verify OTP code for phone login
    func verifyOTP() async {
        clearMessages()
        fieldErrors.clear()

        guard !otpCode.isEmpty else {
            fieldErrors.otp = String(localized: .loginErrorsFillEmailOrPhone)
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let _ = try await authService.verifyOTP(phone: normalizedPhone, token: otpCode)
            await handleSuccessfulLogin()
        } catch {
            handleError(error)
        }
    }

    /// Sign in with Google
    func signInWithGoogle() async {
        clearMessages()
        isLoading = true
        defer { isLoading = false }

        do {
            let idToken = try await googleAuthProvider.signIn()
            let _ = try await authService.signInWithGoogle(idToken: idToken)
            await handleSuccessfulLogin()
        } catch let error as GoogleAuthError where error.isCancellation {
            // User cancelled - do nothing
        } catch {
            handleError(error)
        }
    }

    /// Sign in with Apple
    func signInWithApple() async {
        clearMessages()
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await appleAuthProvider.signIn()
            let _ = try await authService.signInWithApple(
                idToken: result.idToken,
                fullName: result.fullName
            )
            await handleSuccessfulLogin()
        } catch let error as AppleAuthError where error.isCancellation {
            // User cancelled - do nothing
        } catch {
            handleError(error)
        }
    }

    /// Go back from OTP step to input step
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
            try await authService.sendOTP(phone: normalizedPhone)
            successMessage = String(localized: .loginSuccessSmsSent)
        } catch {
            handleError(error)
        }
    }

    // MARK: - Private Methods

    private func signInWithEmail() async throws {
        let _ = try await authService.signInWithPassword(email: emailOrPhone, password: password)
        await handleSuccessfulLogin()
    }

    private func signInWithPhone() async throws {
        let _ = try await authService.signInWithPassword(phone: normalizedPhone, password: password)
        await handleSuccessfulLogin()
    }

    private func sendPhoneOTP() async throws {
        try await authService.sendOTP(phone: normalizedPhone)
        successMessage = String(localized: .loginSuccessSmsSent)
        currentStep = .otp
    }

    private func validateInput() -> Bool {
        let trimmed = emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            fieldErrors.emailOrPhone = String(localized: .loginErrorsFillEmailOrPhone)
            return false
        }

        if inputType == .unknown {
            fieldErrors.emailOrPhone = String(localized: .loginErrorsInvalidEmailOrPhone)
            return false
        }

        // Password is required for email login
        if inputType == .email && password.isEmpty {
            fieldErrors.password = String(localized: .loginErrorsPasswordRequired)
            return false
        }

        return true
    }

    private func handleSuccessfulLogin() async {
        // The AppCoordinator listens to Supabase auth state changes
        // and will automatically transition to the appropriate state
        // (MFA required or authenticated) when the session is established.
        //
        // We call handleLoginSuccess() to ensure the coordinator
        // immediately checks MFA status after successful login.
        Haptics.play(.success)
        await AppCoordinator.shared.handleLoginSuccess()
    }

    private func handleError(_ error: Error) {
        // Translate the error message
        let translated = ErrorTranslations.translate(error)
        errorMessage = translated
        Haptics.play(.error)
    }

    private func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let nativeLoginComplete = Notification.Name("nativeLoginComplete")
    static let requiresMFA = Notification.Name("requiresMFA")
}
