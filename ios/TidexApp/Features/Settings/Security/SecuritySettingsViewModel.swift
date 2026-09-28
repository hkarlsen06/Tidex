import Foundation
import Observation
import os.log
import Supabase

private let logger = Logger(subsystem: "no.tidex.app", category: "SecuritySettings")

/// View model for security settings
/// Handles password management, connected accounts, and MFA
@MainActor
@Observable
final class SecuritySettingsViewModel {

  // MARK: - Dependencies
  private let passkeyAuthService: PasskeyAuthService

  // MARK: - Published State

  /// User's email address
  var email: String = ""
  /// User's phone number
  var phoneNumber: String?

  /// Authentication provider info
  private(set) var hasPassword = false
  private(set) var hasGoogleConnected = false
  private(set) var hasAppleConnected = false
  private(set) var hasPhoneConnected = false
  private(set) var isOAuthOnly = false

  /// Whether user can disconnect providers (must have at least one auth method)
  private(set) var canDisconnectGoogle = false
  private(set) var canDisconnectApple = false
  private(set) var canUnlinkPhone = false

  /// MFA factors
  var mfaFactors: [MFAFactor] = []
  /// Passkeys registered for this account
  var passkeys: [PasskeyAuthService.Passkey] = []

  /// Loading states
  private(set) var isLoading = false
  private(set) var isSettingPassword = false
  private(set) var isConnectingProvider = false
  private(set) var isEnrollingMFA = false
  private(set) var isVerifyingMFA = false
  private(set) var isUnenrollingMFA = false
  private(set) var isRegisteringPasskey = false
  private(set) var isDeletingPasskey = false
  private(set) var isRenamingPasskey = false

  /// Error message to display
  var errorMessage: String?
  /// Whether security settings were opened while account security data is unavailable offline
  private(set) var isOfflineLimited = false

  /// Password form state
  var showPasswordForm = false
  var newPassword = ""
  var confirmPassword = ""

  /// MFA enrollment state
  var showMFAEnrollment = false
  var mfaQRCode: String?
  var mfaSecret: String?
  var mfaTotpUri: String?
  var mfaVerifyCode = ""
  var pendingFactorId: String?

  /// MFA unenroll confirmation
  var showUnenrollConfirmation = false
  var factorToUnenroll: MFAFactor?

  /// Passkey deletion confirmation
  var showDeletePasskeyConfirmation = false
  var passkeyToDelete: PasskeyAuthService.Passkey?
  var showRenamePasskeyAlert = false
  var passkeyToRename: PasskeyAuthService.Passkey?
  var passkeyNameDraft = ""

  // MARK: - Initialization

  init(passkeyAuthService: PasskeyAuthService? = nil) {
    self.passkeyAuthService = passkeyAuthService ?? PasskeyAuthService.shared
  }

  var canSavePasskeyName: Bool {
    let trimmedName = passkeyNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmedName.isEmpty && trimmedName.count <= 120 && !isRenamingPasskey
  }

  // MARK: - Load Security Info

  /// Load the user's security information
  func loadSecurityInfo() async {
    isLoading = true
    errorMessage = nil
    isOfflineLimited = false

    do {
      // Fetch fresh user data to get identities
      let user = try await supabase.auth.user()

      email = user.email ?? ""
      phoneNumber = user.phone

      // Determine authentication capabilities from identities
      let identities = user.identities ?? []
      let providers = Set(identities.map(\.provider))  // swiftlint:disable:this explicit_type_interface

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

      // Load passkeys before calculating disconnect safety because passkeys count as a login method.
      await loadPasskeys()

      // Count total auth methods (password only counts if user has an email identifier)
      let passwordCountsAsMethod = hasPassword && !email.isEmpty
      let authMethodCount = [
        passwordCountsAsMethod, hasGoogleConnected, hasAppleConnected, hasPhoneConnected,
        !passkeys.isEmpty,
      ].filter(\.self).count

      // Can only disconnect if there's more than one auth method
      canDisconnectGoogle = hasGoogleConnected && authMethodCount > 1
      canDisconnectApple = hasAppleConnected && authMethodCount > 1
      canUnlinkPhone = hasPhoneConnected && authMethodCount > 1

      // OAuth-only: has OAuth but no password/phone
      isOAuthOnly =
        (hasGoogleConnected || hasAppleConnected) && !hasPassword && !hasPhoneConnected
        && passkeys.isEmpty

      // Load MFA factors
      await loadMFAFactors()

    } catch {
      logger.error("Failed to load security info: \(error)")
      if AuthSessionManager.shared.isTransientSessionResolutionError(error)
        || AuthSessionManager.shared.offlineUserIdFallback() != nil
      {
        isOfflineLimited = true
      } else {
        errorMessage = String(localized: .securityErrorsLoadFailed)
      }
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

  /// Load registered passkeys.
  private func loadPasskeys() async {
    do {
      passkeys = try await passkeyAuthService.list()
    } catch {
      logger.error("Failed to load passkeys: \(error)")
      passkeys = []
    }
  }

  // MARK: - Passkey Management

  /// Register a passkey for the current account.
  func registerPasskey() async {
    isRegisteringPasskey = true
    errorMessage = nil

    do {
      let passkey = try await passkeyAuthService.register()
      Haptics.play(.success)
      passkeys.insert(passkey, at: 0)
      await loadPasskeys()
    } catch let error as PasskeyAuthError where error.isCancellation {
      // User cancelled - do nothing
    } catch let error as PasskeyAuthError where error.isPasskeyDisabled {
      logger.error("Passkey registration failed because passkeys are disabled: \(error)")
      errorMessage = String(localized: .securityPasskeysErrorsDisabled)
    } catch {
      logger.error("Failed to register passkey: \(error)")
      errorMessage = String(localized: .securityPasskeysErrorsRegisterFailed)
    }

    isRegisteringPasskey = false
  }

  /// Delete a registered passkey.
  func deletePasskey(_ passkey: PasskeyAuthService.Passkey) async {
    isDeletingPasskey = true
    errorMessage = nil

    do {
      try await passkeyAuthService.delete(passkeyId: passkey.id)
      Haptics.play(.success)
      passkeys.removeAll { $0.id == passkey.id }
      showDeletePasskeyConfirmation = false
      passkeyToDelete = nil
    } catch {
      logger.error("Failed to delete passkey: \(error)")
      errorMessage = String(localized: .securityPasskeysErrorsDeleteFailed)
    }

    isDeletingPasskey = false
  }

  /// Prepare the rename dialog for a passkey.
  func startRenamingPasskey(_ passkey: PasskeyAuthService.Passkey) {
    guard !isOfflineLimited else { return }
    passkeyToRename = passkey
    passkeyNameDraft = passkey.displayName
    showRenamePasskeyAlert = true
  }

  /// Cancel passkey renaming and clear the draft.
  func cancelRenamingPasskey() {
    showRenamePasskeyAlert = false
    passkeyToRename = nil
    passkeyNameDraft = ""
  }

  /// Rename the selected passkey.
  func renameSelectedPasskey() async {
    guard let passkey = passkeyToRename else { return }

    let trimmedName = passkeyNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      errorMessage = String(localized: .securityPasskeysErrorsNameRequired)
      return
    }

    guard trimmedName.count <= 120 else {
      errorMessage = String(localized: .securityPasskeysErrorsRenameFailed)
      return
    }

    if trimmedName == passkey.displayName {
      cancelRenamingPasskey()
      return
    }

    isRenamingPasskey = true
    errorMessage = nil

    do {
      let updatedPasskey = try await passkeyAuthService.update(
        passkeyId: passkey.id,
        friendlyName: trimmedName
      )
      if let index = passkeys.firstIndex(where: { $0.id == passkey.id }) {
        passkeys[index] = updatedPasskey
      }
      Haptics.play(.success)
      cancelRenamingPasskey()
    } catch {
      logger.error("Failed to rename passkey: \(error)")
      errorMessage = String(localized: .securityPasskeysErrorsRenameFailed)
    }

    isRenamingPasskey = false
  }

  // MARK: - Password Management

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

    isSettingPassword = true
    errorMessage = nil

    do {
      // Update password
      // Supabase won't always add an "email" identity for OAuth users, so store a metadata flag.
      let passwordMetadata: [String: AnyJSON] = ["hasPassword": .bool(true)]
      if !hasPassword, !email.isEmpty {
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
    errorMessage = nil
  }

  // MARK: - Identity Linking

  /// Connect Google account with the native Google sheet
  func connectGoogle() async {
    await linkIdentity(provider: .google) {
      try await GoogleAuthProvider.shared.signIn()
    }
  }

  /// Connect Apple account with the native Apple sheet
  func connectApple() async {
    await linkIdentity(provider: .apple) {
      try await AppleAuthProvider.shared.signIn().idToken
    }
  }

  /// Link an identity by exchanging a native ID token, so no web OAuth client secret is needed.
  private func linkIdentity(
    provider: OpenIDConnectCredentials.Provider,
    idToken: () async throws -> String
  ) async {
    isConnectingProvider = true
    errorMessage = nil

    do {
      _ = try await supabase.auth.linkIdentityWithIdToken(
        credentials: OpenIDConnectCredentials(provider: provider, idToken: idToken())
      )
      Haptics.play(.success)
      await loadSecurityInfo()
    } catch let error as GoogleAuthError where error.isCancellation {
      logger.debug("User cancelled \(provider.rawValue) linking")
    } catch let error as AppleAuthError where error.isCancellation {
      logger.debug("User cancelled \(provider.rawValue) linking")
    } catch {
      logger.error("Failed to link \(provider.rawValue): \(error)")
      errorMessage = String(localized: .securityConnectionsErrorsLinkFailed)
    }

    isConnectingProvider = false
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
      createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(.appLocale))
    }
  }
}
