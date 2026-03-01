import Combine
import Foundation
import Supabase
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "SecuritySettings")

/// View model for security settings
/// Handles password management, connected accounts, and MFA
@MainActor
final class SecuritySettingsViewModel: ObservableObject {

  // MARK: - Dependencies

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

  /// Phone linking state
  @Published var showPhoneLinkingSheet = false
  @Published var phoneLinkStep: PhoneLinkStep = .input
  @Published var phoneLinkInput = ""
  @Published var phoneLinkOtp = ""
  @Published private(set) var isLinkingPhone = false

  enum PhoneLinkStep {
    case input
    case otp
  }

  // MARK: - Biometric Lock

  /// Biometric service for app lock
  private let biometricService = BiometricAuthService.shared

  /// Whether biometric lock is enabled
  var isBiometricLockEnabled: Bool {
    biometricService.isEnabled
  }

  /// Whether biometrics are available on this device
  var isBiometricAvailable: Bool {
    biometricService.isAvailable
  }

  /// The type of biometric (Face ID, Touch ID)
  var biometricTypeName: String {
    biometricService.biometricTypeName
  }

  /// SF Symbol for the biometric type
  var biometricIconName: String {
    biometricService.biometricIconName
  }

  /// Toggle biometric lock state
  @Published private(set) var isTogglingBiometric = false

  // MARK: - Initialization

  init() {}

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

      // Supabase does not always create an "email" identity when setting a password on OAuth users.
      // Track a metadata flag as a fallback (set when password is created/updated).
      let metadataHasPassword = user.userMetadata["hasPassword"]?.value as? Bool ?? false
      let appMetadataProviders =
        user.appMetadata["providers"]?.value as? [String]
        ?? (user.appMetadata["providers"]?.value as? [Any])?.compactMap { $0 as? String }
        ?? []
      let hasEmailProvider = providers.contains("email") || appMetadataProviders.contains("email")

      hasPassword = hasEmailProvider || metadataHasPassword
      hasGoogleConnected = providers.contains("google")
      hasAppleConnected = providers.contains("apple")
      hasPhoneConnected = providers.contains("phone")

      // Count total auth methods (password only counts if user has an email identifier)
      let passwordCountsAsMethod = hasPassword && !email.isEmpty
      let authMethodCount = [
        passwordCountsAsMethod, hasGoogleConnected, hasAppleConnected, hasPhoneConnected,
      ].filter { $0 }.count

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
      errorMessage = String(localized: .securityErrorsLoadFailed)
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
      Haptics.play(.success)
    } catch {
      logger.error("Failed to request OTP: \(error)")
      errorMessage = String(localized: .securityPasswordErrorsOtpFailed)
    }

    isSettingPassword = false
  }

  /// Set or change password
  func setPassword() async {
    // Validate password
    guard !newPassword.isEmpty else {
      errorMessage = String(localized: .securityPasswordErrorsRequired)
      return
    }

    guard newPassword.count >= 8 else {
      errorMessage = String(localized: .securityPasswordErrorsTooShort)
      return
    }

    guard newPassword == confirmPassword else {
      errorMessage = String(localized: .securityPasswordErrorsMismatch)
      return
    }

    // For phone-only users, verify OTP first
    if !hasPassword && hasPhoneConnected {
      guard !phoneOtp.isEmpty else {
        errorMessage = String(localized: .securityPasswordErrorsOtpRequired)
        return
      }

      guard phoneOtp.count == 6, phoneOtp.allSatisfy({ $0.isNumber }) else {
        errorMessage = String(localized: .securityPasswordErrorsOtpInvalid)
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
      // Supabase won't always add an "email" identity for OAuth users, so store a metadata flag.
      let passwordMetadata: [String: AnyJSON] = ["hasPassword": .bool(true)]
      if !hasPassword && !email.isEmpty {
        try await supabase.auth.update(
          user: UserAttributes(
            email: email,
            password: newPassword,
            data: passwordMetadata
          ))
      } else {
        try await supabase.auth.update(
          user: UserAttributes(
            password: newPassword,
            data: passwordMetadata
          ))
      }

      // Refresh session via serialized auth path to avoid refresh races
      _ = try? await AuthSessionManager.shared.forceRefresh()

      Haptics.play(.success)

      // Reset form
      resetPasswordForm()

      // Reload to update state
      await loadSecurityInfo()

    } catch {
      logger.error("Failed to set password: \(error)")
      errorMessage = ErrorTranslations.translate(error)
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
        let errorDescription =
          rawDescription
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
        let refreshToken = allParams["refresh_token"]
      {
        // Set the new session
        try await supabase.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
        linkingSucceeded = true
      } else if let code = allParams["code"] {
        // Exchange code for session
        _ = try await supabase.auth.exchangeCodeForSession(authCode: code)
        linkingSucceeded = true
      }

      if linkingSucceeded {
        Haptics.play(.success)
      } else {
        // No tokens or code found - something went wrong
        logger.warning("No tokens or code in callback URL")
        errorMessage = String(localized: .securityConnectionsErrorsLinkFailed)
      }

      // Reload to update state
      await loadSecurityInfo()

    } catch let error as OAuthWebAuthError where error.isCancellation {
      // User cancelled - don't show error
      logger.debug("User cancelled \(provider.rawValue) linking")
    } catch OAuthWebAuthError.stateMismatch {
      // State validation failed - potential CSRF attack
      logger.error("OAuth state validation failed for \(provider.rawValue) - possible CSRF attack")
      errorMessage = String(localized: .securityConnectionsErrorsLinkFailed)
    } catch {
      logger.error("Failed to link \(provider.rawValue): \(error)")
      errorMessage = String(localized: .securityConnectionsErrorsLinkFailed)
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
        let identity = identities.first(where: { $0.provider == provider })
      else {
        errorMessage = String(localized: .securityConnectionsErrorsNotFound)
        isConnectingProvider = false
        return
      }

      // Unlink the identity
      try await supabase.auth.unlinkIdentity(identity)

      Haptics.play(.success)

      // Reload to update state
      await loadSecurityInfo()

    } catch {
      logger.error("Failed to unlink \(provider): \(error)")
      errorMessage = String(localized: .securityConnectionsErrorsUnlinkFailed)
    }

    isConnectingProvider = false
  }

  // MARK: - Phone Linking

  /// Start phone linking by sending OTP to the phone number
  func connectPhone() async {
    // Validate phone number (Norwegian format: 8 digits)
    let cleanedPhone = phoneLinkInput.filter { $0.isNumber }
    guard cleanedPhone.count == 8 else {
      errorMessage = String(localized: .securityPhoneLinkingErrorsPhoneInvalid)
      return
    }

    // Format to E.164 (Norwegian: +47)
    let phoneE164 = "+47\(cleanedPhone)"

    isLinkingPhone = true
    errorMessage = nil

    do {
      // Update user with new phone number - this sends an OTP
      try await supabase.auth.update(user: UserAttributes(phone: phoneE164))

      // Move to OTP step
      phoneLinkStep = .otp
      Haptics.play(.success)

    } catch {
      logger.error("Failed to initiate phone linking: \(error)")
      errorMessage = String(localized: .securityPhoneLinkingErrorsSendFailed)
    }

    isLinkingPhone = false
  }

  /// Verify the OTP and complete phone linking
  func verifyPhoneLinkOTP() async {
    // Validate OTP
    guard phoneLinkOtp.count == 6, phoneLinkOtp.allSatisfy({ $0.isNumber }) else {
      errorMessage = String(localized: .securityPhoneLinkingErrorsOtpInvalid)
      return
    }

    // Format phone to E.164
    let cleanedPhone = phoneLinkInput.filter { $0.isNumber }
    let phoneE164 = "+47\(cleanedPhone)"

    isLinkingPhone = true
    errorMessage = nil

    do {
      // Verify the OTP with phone_change type
      try await supabase.auth.verifyOTP(
        phone: phoneE164,
        token: phoneLinkOtp,
        type: .phoneChange
      )

      // Refresh session via serialized auth path to avoid refresh races
      _ = try? await AuthSessionManager.shared.forceRefresh()

      Haptics.play(.success)

      // Reset phone linking state
      resetPhoneLinkingForm()

      // Reload security info to update UI
      await loadSecurityInfo()

    } catch {
      logger.error("Failed to verify phone OTP: \(error)")
      errorMessage = String(localized: .securityPhoneLinkingErrorsVerifyFailed)
    }

    isLinkingPhone = false
  }

  /// Reset phone linking form state
  func resetPhoneLinkingForm() {
    showPhoneLinkingSheet = false
    phoneLinkStep = .input
    phoneLinkInput = ""
    phoneLinkOtp = ""
    errorMessage = nil
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
      errorMessage = String(localized: .securityMfaErrorsEnrollFailed)
    }

    isEnrollingMFA = false
  }

  /// Verify MFA enrollment with code
  func verifyMFAEnrollment() async {
    guard let factorId = pendingFactorId else {
      errorMessage = String(localized: .securityMfaErrorsNoFactor)
      return
    }

    guard mfaVerifyCode.count == 6 else {
      errorMessage = String(localized: .securityMfaErrorsCodeRequired)
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

      Haptics.play(.success)

      // Reset enrollment state
      resetMFAEnrollment()

      // Reload factors
      await loadMFAFactors()

    } catch {
      logger.error("Failed to verify MFA: \(error)")
      errorMessage = String(localized: .securityMfaErrorsInvalidCode)
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
    } catch {
      logger.error("Failed to unenroll MFA: \(error)")
      errorMessage = String(localized: .securityMfaErrorsUnenrollFailed)
      isUnenrollingMFA = false
      return
    }

    Haptics.play(.success)
    showUnenrollConfirmation = false
    factorToUnenroll = nil

    // Remove factor from local list immediately for instant UI feedback
    mfaFactors.removeAll { $0.id == factor.id }

    // Refresh session so the cached user data no longer includes the removed factor.
    // listFactors() reads from the cached session, so without this it would still
    // return the old factor on subsequent loads.
    _ = try? await AuthSessionManager.shared.forceRefresh()

    // Re-fetch factors from server to confirm deletion and ensure consistency
    await loadMFAFactors()

    isUnenrollingMFA = false
  }

  /// Clear messages
  func clearMessages() {
    errorMessage = nil
  }

  // MARK: - Biometric Lock Management

  /// Toggle biometric lock on/off
  func toggleBiometricLock() async {
    isTogglingBiometric = true
    errorMessage = nil

    if isBiometricLockEnabled {
      // Disable - no authentication required
      biometricService.disableBiometricLock()
      Haptics.play(.success)
    } else {
      // Enable - requires authentication
      let success = await biometricService.enableBiometricLock()
      if success {
        Haptics.play(.success)
      } else {
        errorMessage = String(localized: .securityBiometricErrorsAuthFailed)
      }
    }

    // Force UI update since we're reading from biometricService
    objectWillChange.send()
    isTogglingBiometric = false
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
