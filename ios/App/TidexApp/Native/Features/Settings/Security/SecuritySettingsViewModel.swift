import AuthenticationServices
import Foundation
import os.log
import Supabase
import SwiftUI

private let logger = Logger(subsystem: "no.tidex.app", category: "SecuritySettings")

/// View model for security settings
/// Handles password management, connected accounts, and MFA
@MainActor
final class SecuritySettingsViewModel: ObservableObject {

    // MARK: - Dependencies

    private let localization: LocalizationManager

    // MARK: - Published State

    /// User's email address
    @Published var email: String = ""
    /// User's phone number
    @Published var phoneNumber: String?

    /// Authentication provider info
    @Published private(set) var hasPassword = false
    @Published private(set) var hasGoogleConnected = false
    @Published private(set) var hasAppleConnected = false
    @Published private(set) var hasPhoneConnected = false
    @Published private(set) var isOAuthOnly = false

    /// Whether user can disconnect providers (must have at least one auth method)
    @Published private(set) var canDisconnectGoogle = false
    @Published private(set) var canDisconnectApple = false
    @Published private(set) var canUnlinkPhone = false

    /// MFA factors
    @Published var mfaFactors: [MFAFactor] = []

    /// Loading states
    @Published private(set) var isLoading = false
    @Published private(set) var isSettingPassword = false
    @Published private(set) var isConnectingProvider = false
    @Published private(set) var isEnrollingMFA = false
    @Published private(set) var isVerifyingMFA = false
    @Published private(set) var isUnenrollingMFA = false

    /// Error message to display
    @Published var errorMessage: String?
    /// Success message to display
    @Published var successMessage: String?

    /// Password form state
    @Published var showPasswordForm = false
    @Published var newPassword = ""
    @Published var confirmPassword = ""
    @Published var phoneOtp = ""
    @Published var otpSent = false

    /// MFA enrollment state
    @Published var showMFAEnrollment = false
    @Published var mfaQRCode: String?
    @Published var mfaSecret: String?
    @Published var mfaTotpUri: String?
    @Published var mfaVerifyCode = ""
    @Published var pendingFactorId: String?

    /// MFA unenroll confirmation
    @Published var showUnenrollConfirmation = false
    @Published var factorToUnenroll: MFAFactor?

    // MARK: - Initialization

    init(localization: LocalizationManager? = nil) {
        self.localization = localization ?? LocalizationManager.shared
    }

    // MARK: - Load Security Info

    /// Load the user's security information
    func loadSecurityInfo() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch fresh user data to get identities
            let user = try await supabase.auth.user()

            email = user.email ?? ""
            phoneNumber = user.phone

            // Determine authentication capabilities from identities
            let identities = user.identities ?? []
            let providers = Set(identities.map { $0.provider })

            hasPassword = providers.contains("email")
            hasGoogleConnected = providers.contains("google")
            hasAppleConnected = providers.contains("apple")
            hasPhoneConnected = providers.contains("phone")

            // Count total auth methods
            let authMethodCount = [hasPassword, hasGoogleConnected, hasAppleConnected, hasPhoneConnected].filter { $0 }.count

            // Can only disconnect if there's more than one auth method
            canDisconnectGoogle = hasGoogleConnected && authMethodCount > 1
            canDisconnectApple = hasAppleConnected && authMethodCount > 1
            canUnlinkPhone = hasPhoneConnected && authMethodCount > 1

            // OAuth-only: has OAuth but no password/phone
            isOAuthOnly = (hasGoogleConnected || hasAppleConnected) && !hasPassword && !hasPhoneConnected

            // Load MFA factors
            await loadMFAFactors()

        } catch {
            logger.error("Failed to load security info: \(error)")
            errorMessage = localization.string("security.errors.loadFailed")
        }

        isLoading = false
    }

    /// Load enrolled MFA factors
    private func loadMFAFactors() async {
        do {
            let response = try await supabase.auth.mfa.listFactors()

            // Get verified TOTP factors only
            mfaFactors = response.totp
                .filter { $0.status == .verified }
                .map { factor in
                    MFAFactor(
                        id: factor.id,
                        friendlyName: factor.friendlyName,
                        createdAt: factor.createdAt
                    )
                }
        } catch {
            logger.error("Failed to load MFA factors: \(error)")
        }
    }

    // MARK: - Password Management

    /// Request OTP for phone-only users to set password
    func requestPasswordOTP() async {
        guard hasPhoneConnected, let phone = phoneNumber else { return }

        isSettingPassword = true
        errorMessage = nil

        do {
            // Request reauthentication via phone OTP
            try await supabase.auth.signInWithOTP(phone: phone)
            otpSent = true
            successMessage = localization.string("security.password.codeSent")
        } catch {
            logger.error("Failed to request OTP: \(error)")
            errorMessage = localization.string("security.password.errors.otpFailed")
        }

        isSettingPassword = false
    }

    /// Set or change password
    func setPassword() async {
        // Validate password
        guard !newPassword.isEmpty else {
            errorMessage = localization.string("security.password.errors.required")
            return
        }

        guard newPassword.count >= 8 else {
            errorMessage = localization.string("security.password.errors.tooShort")
            return
        }

        guard newPassword == confirmPassword else {
            errorMessage = localization.string("security.password.errors.mismatch")
            return
        }

        // For phone-only users, verify OTP first
        if !hasPassword && hasPhoneConnected {
            guard !phoneOtp.isEmpty else {
                errorMessage = localization.string("security.password.errors.otpRequired")
                return
            }

            guard phoneOtp.count == 6, phoneOtp.allSatisfy({ $0.isNumber }) else {
                errorMessage = localization.string("security.password.errors.otpInvalid")
                return
            }
        }

        isSettingPassword = true
        errorMessage = nil

        do {
            // If phone-only, verify OTP first
            if !hasPassword && hasPhoneConnected, let phone = phoneNumber {
                try await supabase.auth.verifyOTP(phone: phone, token: phoneOtp, type: .sms)
            }

            // Update password
            try await supabase.auth.update(user: UserAttributes(password: newPassword))

            // Refresh session
            _ = try? await supabase.auth.refreshSession()

            successMessage = hasPassword
                ? localization.string("security.password.success.updated")
                : localization.string("security.password.success.set")

            // Reset form
            resetPasswordForm()

            // Reload to update state
            await loadSecurityInfo()

        } catch {
            logger.error("Failed to set password: \(error)")
            errorMessage = localization.string("security.password.errors.failed")
        }

        isSettingPassword = false
    }

    /// Reset password form state
    func resetPasswordForm() {
        showPasswordForm = false
        newPassword = ""
        confirmPassword = ""
        phoneOtp = ""
        otpSent = false
        errorMessage = nil
    }

    // MARK: - Identity Linking

    /// Connect Google account using OAuth flow with in-app browser
    func connectGoogle() async {
        await linkIdentity(provider: .google)
    }

    /// Connect Apple account using OAuth flow with in-app browser
    func connectApple() async {
        await linkIdentity(provider: .apple)
    }

    /// Link an identity using ASWebAuthenticationSession for in-app browser overlay
    private func linkIdentity(provider: Provider) async {
        isConnectingProvider = true
        errorMessage = nil

        do {
            // Get current session for access token
            let session = try await AuthSessionManager.shared.getSession()
            let accessToken = session.accessToken

            // Use OAuthWebAuthSession to show in-app browser overlay
            let callbackURL = try await OAuthWebAuthSession.shared.linkIdentity(
                provider: provider.rawValue,
                accessToken: accessToken
            )

            // Process the callback URL to complete the identity linking
            // The callback URL contains the auth result that Supabase needs to process
            logger.debug("OAuth callback received: \(callbackURL)")

            // Parse both fragment and query for parameters
            // Errors can be in either location depending on the flow
            var allParams: [String: String] = [:]
            if let fragment = callbackURL.fragment {
                allParams.merge(parseQueryString(fragment)) { _, new in new }
            }
            if let query = callbackURL.query {
                allParams.merge(parseQueryString(query)) { _, new in new }
            }

            // Validate CSRF state parameter before processing any tokens
            try OAuthWebAuthSession.shared.validateAndClearState(allParams["state"])

            // Check for errors first
            if let error = allParams["error"] {
                // URL decode the error description (+ becomes space, then percent decode)
                let rawDescription = allParams["error_description"] ?? error
                let errorDescription = rawDescription
                    .replacingOccurrences(of: "+", with: " ")
                    .removingPercentEncoding ?? rawDescription
                logger.error("OAuth error: \(error) - \(errorDescription)")
                errorMessage = errorDescription
                isConnectingProvider = false
                return
            }

            // Extract tokens/code from callback and refresh session
            // The callback format is: tidex://auth/callback#access_token=...&refresh_token=...
            // or: tidex://auth/callback?code=...
            var linkingSucceeded = false

            if let accessToken = allParams["access_token"],
               let refreshToken = allParams["refresh_token"] {
                // Set the new session
                try await supabase.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
                linkingSucceeded = true
            } else if let code = allParams["code"] {
                // Exchange code for session
                _ = try await supabase.auth.exchangeCodeForSession(authCode: code)
                linkingSucceeded = true
            }

            if linkingSucceeded {
                successMessage = localization.string("security.connections.success.connected")
            } else {
                // No tokens or code found - something went wrong
                logger.warning("No tokens or code in callback URL")
                errorMessage = localization.string("security.connections.errors.linkFailed")
            }

            // Reload to update state
            await loadSecurityInfo()

        } catch let error as OAuthWebAuthError where error.isCancellation {
            // User cancelled - don't show error
            logger.debug("User cancelled \(provider.rawValue) linking")
        } catch OAuthWebAuthError.stateMismatch {
            // State validation failed - potential CSRF attack
            logger.error("OAuth state validation failed for \(provider.rawValue) - possible CSRF attack")
            errorMessage = localization.string("security.connections.errors.linkFailed")
        } catch {
            logger.error("Failed to link \(provider.rawValue): \(error)")
            errorMessage = localization.string("security.connections.errors.linkFailed")
        }

        isConnectingProvider = false
    }

    /// Parse a query string into a dictionary
    private func parseQueryString(_ queryString: String) -> [String: String] {
        var params: [String: String] = [:]
        let pairs = queryString.split(separator: "&")
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                params[key] = value
            }
        }
        return params
    }

    /// Disconnect a provider identity
    func disconnectProvider(_ provider: String) async {
        isConnectingProvider = true
        errorMessage = nil

        do {
            // Get user identities
            let user = try await supabase.auth.user()
            guard let identities = user.identities,
                  let identity = identities.first(where: { $0.provider == provider }) else {
                errorMessage = localization.string("security.connections.errors.notFound")
                isConnectingProvider = false
                return
            }

            // Unlink the identity
            try await supabase.auth.unlinkIdentity(identity)

            successMessage = localization.string("security.connections.success.disconnected")

            // Reload to update state
            await loadSecurityInfo()

        } catch {
            logger.error("Failed to unlink \(provider): \(error)")
            errorMessage = localization.string("security.connections.errors.unlinkFailed")
        }

        isConnectingProvider = false
    }

    // MARK: - MFA Management

    /// Start MFA enrollment
    func startMFAEnrollment() async {
        isEnrollingMFA = true
        errorMessage = nil

        do {
            let friendlyName = "Tidex 2FA"

            let response = try await supabase.auth.mfa.enroll(
                params: .totp(issuer: "Tidex", friendlyName: friendlyName)
            )

            pendingFactorId = response.id
            mfaQRCode = response.totp?.qrCode
            mfaSecret = response.totp?.secret
            mfaTotpUri = response.totp?.uri
            showMFAEnrollment = true

        } catch {
            logger.error("Failed to start MFA enrollment: \(error)")
            errorMessage = localization.string("security.mfa.errors.enrollFailed")
        }

        isEnrollingMFA = false
    }

    /// Verify MFA enrollment with code
    func verifyMFAEnrollment() async {
        guard let factorId = pendingFactorId else {
            errorMessage = localization.string("security.mfa.errors.noFactor")
            return
        }

        guard mfaVerifyCode.count == 6 else {
            errorMessage = localization.string("security.mfa.errors.codeRequired")
            return
        }

        isVerifyingMFA = true
        errorMessage = nil

        do {
            // Challenge and verify in one step
            try await supabase.auth.mfa.challengeAndVerify(
                params: MFAChallengeAndVerifyParams(
                    factorId: factorId,
                    code: mfaVerifyCode
                )
            )

            successMessage = localization.string("security.mfa.success.enrolled")

            // Reset enrollment state
            resetMFAEnrollment()

            // Reload factors
            await loadMFAFactors()

        } catch {
            logger.error("Failed to verify MFA: \(error)")
            errorMessage = localization.string("security.mfa.errors.invalidCode")
        }

        isVerifyingMFA = false
    }

    /// Cancel MFA enrollment
    func cancelMFAEnrollment() async {
        // Unenroll the pending factor if it exists
        if let factorId = pendingFactorId {
            do {
                try await supabase.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: factorId))
            } catch {
                // Ignore errors when canceling
                logger.error("Failed to unenroll pending factor: \(error)")
            }
        }

        resetMFAEnrollment()
    }

    /// Reset MFA enrollment state
    private func resetMFAEnrollment() {
        showMFAEnrollment = false
        mfaQRCode = nil
        mfaSecret = nil
        mfaTotpUri = nil
        mfaVerifyCode = ""
        pendingFactorId = nil
        errorMessage = nil
    }

    /// Unenroll an MFA factor
    func unenrollMFA(_ factor: MFAFactor) async {
        isUnenrollingMFA = true
        errorMessage = nil

        do {
            try await supabase.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: factor.id))

            successMessage = localization.string("security.mfa.success.unenrolled")
            showUnenrollConfirmation = false
            factorToUnenroll = nil

            // Reload factors
            await loadMFAFactors()

        } catch {
            logger.error("Failed to unenroll MFA: \(error)")
            errorMessage = localization.string("security.mfa.errors.unenrollFailed")
        }

        isUnenrollingMFA = false
    }

    /// Clear messages
    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}

// MARK: - MFA Factor Model

extension SecuritySettingsViewModel {
    struct MFAFactor: Identifiable {
        let id: String
        let friendlyName: String?
        let createdAt: Date

        var displayName: String {
            friendlyName ?? "Authenticator"
        }

        var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: createdAt)
        }
    }
}
