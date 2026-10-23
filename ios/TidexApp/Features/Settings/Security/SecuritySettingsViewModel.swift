import ClerkKit
import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "SecuritySettings")

/// View model for security settings
/// Handles password management and connected accounts
@MainActor
@Observable
final class SecuritySettingsViewModel {

  // MARK: - Published State

  /// User's email address
  var email: String = ""

  /// Authentication provider info
  private(set) var hasPassword = false
  private(set) var hasGoogleConnected = false
  private(set) var hasAppleConnected = false
  private(set) var isOAuthOnly = false

  /// Whether user can disconnect providers (must have at least one auth method)
  private(set) var canDisconnectGoogle = false
  private(set) var canDisconnectApple = false

  /// Loading states
  private(set) var isLoading = false
  private(set) var isSettingPassword = false
  private(set) var isConnectingProvider = false

  /// Error message to display
  var errorMessage: String?
  /// Whether security settings were opened while account security data is unavailable offline
  private(set) var isOfflineLimited = false

  /// Password form state
  var showPasswordForm = false
  var currentPassword = ""
  var newPassword = ""
  var confirmPassword = ""

  // MARK: - Load Security Info

  /// Load the user's security information
  func loadSecurityInfo() async {
    isLoading = true
    errorMessage = nil
    isOfflineLimited = false

    do {
      // Reload so the list of connected accounts is current.
      guard let user = Clerk.shared.user else { throw AuthError.sessionMissing }
      let fresh = try await user.reload()
      apply(fresh)
    } catch {
      logger.error("Failed to load security info: \(error)")
      if ErrorTranslations.isOffline(error) {
        isOfflineLimited = true
        if let user = Clerk.shared.user { apply(user) }
      } else {
        errorMessage = String(localized: .securityErrorsLoadFailed)
      }
    }

    isLoading = false
  }

  private func apply(_ user: User) {
    email = user.primaryEmailAddress?.emailAddress ?? ""
    hasPassword = user.passwordEnabled
    hasGoogleConnected = user.verifiedExternalAccounts.contains { Self.name(of: $0) == "google" }
    hasAppleConnected = user.verifiedExternalAccounts.contains { Self.name(of: $0) == "apple" }

    // Count total auth methods (a password only counts if the user has an email to sign in with)
    let authMethodCount = [hasPassword && !email.isEmpty, hasGoogleConnected, hasAppleConnected]
      .filter(\.self).count

    // Can only disconnect if there's more than one auth method
    canDisconnectGoogle = hasGoogleConnected && authMethodCount > 1
    canDisconnectApple = hasAppleConnected && authMethodCount > 1

    // OAuth-only: has OAuth but no password
    isOAuthOnly = (hasGoogleConnected || hasAppleConnected) && !hasPassword
  }

  /// Clerk names providers "google" or "oauth_google" depending on the endpoint.
  private static func name(of account: ExternalAccount) -> String {
    account.provider.replacingOccurrences(of: "oauth_", with: "")
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
      // A user who has a password must prove it. One who signed in with Apple or Google has none.
      try await AuthService.shared.updatePassword(
        currentPassword: hasPassword ? currentPassword : nil,
        newPassword: newPassword
      )

      Haptics.play(.success)

      // Reset form
      resetPasswordForm()

      // Reload to update state
      await loadSecurityInfo()

    } catch {
      logger.error("Failed to set password: \(error)")
      errorMessage = AuthService.message(for: error)
    }

    isSettingPassword = false
  }

  /// Reset password form state
  func resetPasswordForm() {
    showPasswordForm = false
    currentPassword = ""
    newPassword = ""
    confirmPassword = ""
    errorMessage = nil
  }

  // MARK: - Identity Linking

  /// Connect a Google account in a web sheet
  func connectGoogle() async {
    await link(provider: "google") { user in
      let account = try await user.createExternalAccount(provider: .google)
      _ = try await account.reauthorize()
    }
  }

  /// Connect an Apple account with the native Apple sheet
  func connectApple() async {
    await link(provider: "apple") { user in
      let idToken = try await AppleAuthProvider.shared.signIn().idToken
      _ = try await user.createExternalAccount(provider: .apple, idToken: idToken)
    }
  }

  private func link(provider: String, _ connect: (User) async throws -> Void) async {
    isConnectingProvider = true
    errorMessage = nil

    do {
      guard let user = Clerk.shared.user else { throw AuthError.sessionMissing }
      try await connect(user)
      Haptics.play(.success)
      await loadSecurityInfo()
    } catch where AuthService.isCancellation(error) {
      logger.debug("User cancelled \(provider) linking")
    } catch {
      logger.error("Failed to link \(provider): \(error)")
      errorMessage = String(localized: .securityConnectionsErrorsLinkFailed)
    }

    isConnectingProvider = false
  }

  /// Disconnect a provider account
  func disconnectProvider(_ provider: String) async {
    isConnectingProvider = true
    errorMessage = nil

    do {
      guard
        let account = Clerk.shared.user?.externalAccounts.first(where: {
          Self.name(of: $0) == provider
        })
      else {
        errorMessage = String(localized: .securityConnectionsErrorsNotFound)
        isConnectingProvider = false
        return
      }

      _ = try await account.destroy()

      Haptics.play(.success)

      // Reload to update state
      await loadSecurityInfo()

    } catch {
      logger.error("Failed to unlink \(provider): \(error)")
      errorMessage = String(localized: .securityConnectionsErrorsUnlinkFailed)
    }

    isConnectingProvider = false
  }

  /// Clear messages
  func clearMessages() {
    errorMessage = nil
  }
}
