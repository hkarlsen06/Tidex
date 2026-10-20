import ClerkKit
import Foundation
import Observation

private struct UsernameArgs: Encodable, Sendable {
  let username: String
}

private struct ProfilePictureReply: Decodable {
  let url: String?
}

/// View model for profile settings
/// Handles profile data loading, name editing, avatar management, and account deletion
@MainActor
@Observable
final class ProfileSettingsViewModel {

  // MARK: - Dependencies

  private let settingsRepository: SettingsRepository
  private let syncCoordinator: SyncCoordinator

  // MARK: - Published State

  /// User's display name (editable)
  var displayName: String = ""
  /// User's email address (read-only display)
  var email: String = ""
  /// User's username (editable, used for friend lookup)
  var username: String = ""
  /// User's profile picture URL
  var profilePictureUrl: String?
  /// User ID
  private(set) var userId: String?

  /// Whether user has password authentication (can change email)
  private(set) var hasPassword = false
  /// Whether user is OAuth-only (cannot change email)
  private(set) var isOAuthOnly = false

  /// Loading states
  private(set) var isLoading = false
  private(set) var isSavingName = false
  private(set) var isSavingUsername = false
  private(set) var isUploadingAvatar = false
  private(set) var isDeletingAccount = false
  private(set) var isChangingEmail = false

  /// Error message to display
  var errorMessage: String?
  /// Username-specific validation or save error shown near the username field
  var usernameErrorMessage: String?
  /// Whether profile data was loaded from partial offline fallback state
  private(set) var isOfflineProfileFallback = false

  /// Email change state
  var showEmailChangeSheet = false
  var newEmail: String = ""
  /// Clerk emailed a code to `newEmail`, and the sheet asks for it.
  var awaitingEmailCode = false
  var emailCode: String = ""

  /// Delete account confirmation state
  var showDeleteConfirmation = false
  var deleteConfirmText = ""

  // MARK: - Private State

  /// Original display name (for detecting changes)
  private var originalDisplayName: String = ""
  /// Original username (for detecting changes)
  private var originalUsername: String = ""
  /// The new address while its code is pending.
  private var pendingEmailAddress: EmailAddress?

  // MARK: - Initialization

  init(
    settingsRepository: SettingsRepository? = nil,
    syncCoordinator: SyncCoordinator? = nil,
  ) {
    self.settingsRepository = settingsRepository ?? SettingsRepository.shared
    self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
    hydrateCachedProfileForImmediateDisplay()
  }

  // MARK: - Load Profile

  /// Load the user's profile data
  func loadProfile() async {
    isLoading = true
    errorMessage = nil
    isOfflineProfileFallback = false
    hydrateCachedProfileForImmediateDisplay()

    do {
      let session = try await AuthSessionManager.shared.getSession()
      userId = session.normalizedUserId
      displayName = session.user.name ?? ""
      originalDisplayName = displayName

      // Clerk holds the email and the sign-in methods. They are on the device already.
      let clerkUser = Clerk.shared.user
      email = clerkUser?.primaryEmailAddress?.emailAddress ?? session.user.email ?? ""

      do {
        let name: String? = try await ConvexAPI.app.query("sharing:myUsername")
        username = name ?? ""
        originalUsername = username
      } catch {
        username = ""
        originalUsername = ""
      }

      // Determine authentication capabilities
      hasPassword = clerkUser?.passwordEnabled ?? false
      isOAuthOnly = !hasPassword && !(clerkUser?.verifiedExternalAccounts.isEmpty ?? true)

      // Get profile picture from local settings
      if let currentUserId = userId,
        let settings = settingsRepository.getSettings(for: currentUserId)
      {
        profilePictureUrl = settings.profile_picture_url
      }

    } catch {
      if ErrorTranslations.isOffline(error) {
        loadOfflineProfileFallback()
      } else {
        errorMessage = String(localized: .profileErrorsLoadFailed)
      }
    }

    isLoading = false
  }

  private func applyCachedProfile(offlineUserId: String) {
    userId = offlineUserId

    let cachedDisplayName = AppCoordinator.shared.userDisplayName
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !cachedDisplayName.isEmpty, cachedDisplayName != "User" {
      displayName = cachedDisplayName
      originalDisplayName = displayName
    }

    email = ""
    hasPassword = false
    isOAuthOnly = false

    if let settings = settingsRepository.getSettings(for: offlineUserId) {
      profilePictureUrl = settings.profile_picture_url
    } else {
      profilePictureUrl = AppCoordinator.shared.userAvatarUrl
    }
  }

  private func hydrateCachedProfileForImmediateDisplay() {
    guard
      let cachedUserId = AppCoordinator.shared.getCurrentUserId()
        ?? AuthSessionManager.shared.offlineUserIdFallback()
    else {
      return
    }

    applyCachedProfile(offlineUserId: cachedUserId)
  }

  private func loadOfflineProfileFallback() {
    guard let offlineUserId = AuthSessionManager.shared.offlineUserIdFallback() else {
      errorMessage = String(localized: .profileErrorsLoadFailed)
      return
    }

    applyCachedProfile(offlineUserId: offlineUserId)
    isOfflineProfileFallback = true
  }

  // MARK: - Name Editing

  /// Save the display name
  private func saveName() async {
    guard let currentUserId = userId else { return }
    guard displayName != originalDisplayName else { return }

    let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    if UserGeneratedContentFilter.containsBlockedText(normalizedDisplayName) {
      errorMessage = String(localized: .profileErrorsNameSafetyFilter)
      return
    }

    isSavingName = true
    errorMessage = nil

    do {
      // Friends read the name from Clerk. The users row follows through the sync action.
      let parts = normalizedDisplayName.split(separator: " ", maxSplits: 1).map(String.init)
      _ = try await Clerk.shared.user?.update(
        .init(firstName: parts.first ?? "", lastName: parts.count > 1 ? parts[1] : ""))
      _ = try await ConvexAPI.app.action("users:syncFromClerk", as: ConvexAPI.Ignored.self)
      _ = try? await AuthSessionManager.shared.forceRefresh()

      displayName = normalizedDisplayName
      originalDisplayName = normalizedDisplayName

      // Update AppCoordinator's display name
      AppCoordinator.shared.updateDisplayName(normalizedDisplayName)

      // Trigger sync to push changes
      Task {
        _ = await syncCoordinator.sync(reason: .foreground, userId: currentUserId)
      }

    } catch {
      errorMessage = String(localized: .profileErrorsSaveFailed)
    }

    isSavingName = false
  }

  func saveNameNow() async {
    await saveName()
  }

  // MARK: - Username Editing

  func onUsernameChanged() {
    guard !isOfflineProfileFallback else { return }

    let sanitizedUsername = Self.sanitizeUsernameInput(username)
    if username != sanitizedUsername {
      username = sanitizedUsername
    }

    errorMessage = nil
    usernameErrorMessage = nil
  }

  func saveUsernameNow() async {
    await saveUsername()
  }

  var canSaveUsername: Bool {
    !isOfflineProfileFallback && !isSavingUsername && username != originalUsername
  }

  private func saveUsername() async {
    let normalizedUsername = Self.normalizeUsername(username)
    if username != normalizedUsername {
      username = normalizedUsername
    }

    guard username != originalUsername else { return }

    guard normalizedUsername.isEmpty || Self.isValidUsername(normalizedUsername) else {
      setUsernameError(String(localized: .profileErrorsUsernameInvalid))
      return
    }

    if UserGeneratedContentFilter.containsBlockedText(normalizedUsername) {
      setUsernameError(String(localized: .profileErrorsNameSafetyFilter))
      return
    }

    isSavingUsername = true
    errorMessage = nil
    usernameErrorMessage = nil

    do {
      let saved: String? = try await ConvexAPI.app.mutation(
        "sharing:setMyUsername", UsernameArgs(username: normalizedUsername))
      username = saved ?? ""
      originalUsername = username
    } catch let failure as ConvexAPI.Failure {
      switch failure.code {
      case "username_taken":
        setUsernameError(String(localized: .profileErrorsUsernameTaken))

      case "username_blocked":
        setUsernameError(String(localized: .profileErrorsNameSafetyFilter))

      case "username_invalid":
        setUsernameError(String(localized: .profileErrorsUsernameInvalid))

      default:
        setUsernameError(String(localized: .profileErrorsUsernameSaveFailed))
      }
    } catch {
      setUsernameError(String(localized: .profileErrorsUsernameSaveFailed))
    }

    isSavingUsername = false
  }

  private func setUsernameError(_ message: String) {
    usernameErrorMessage = message
    errorMessage = message
  }

}

extension ProfileSettingsViewModel {
  // MARK: - Email Change

  /// Whether the user can change their email (has password auth)
  var canChangeEmail: Bool {
    hasPassword && !isOAuthOnly
  }

  /// Validate email format
  private func isValidEmail(_ email: String) -> Bool {
    let emailRegex = "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$"
    return email.range(of: emailRegex, options: .regularExpression) != nil
  }

  /// Add the new address in Clerk and email it a code
  func initiateEmailChange() async {
    // Prevent duplicate taps
    guard !isChangingEmail else { return }

    guard canChangeEmail else {
      errorMessage = String(localized: .profileEmailChangeErrorsOauthOnly)
      return
    }

    guard isValidEmail(newEmail) else {
      errorMessage = String(localized: .profileEmailChangeErrorsInvalidEmail)
      return
    }

    guard newEmail.lowercased() != email.lowercased() else {
      errorMessage = String(localized: .profileEmailChangeErrorsSameEmail)
      return
    }

    isChangingEmail = true
    errorMessage = nil

    do {
      guard let user = Clerk.shared.user else { throw AuthError.sessionMissing }
      let address = try await user.createEmailAddress(newEmail)
      pendingEmailAddress = try await address.sendCode()
      awaitingEmailCode = true
    } catch {
      errorMessage = AuthService.message(for: error)
    }

    isChangingEmail = false
  }

  /// Check the code, make the new address the primary one and drop the old one
  func confirmEmailChange() async {
    guard !isChangingEmail, let pending = pendingEmailAddress, let user = Clerk.shared.user
    else { return }

    isChangingEmail = true
    errorMessage = nil

    do {
      let verified = try await pending.verifyCode(emailCode)
      let oldAddress = user.primaryEmailAddress
      _ = try await user.update(.init(primaryEmailAddressId: verified.id))
      // Best-effort: a leftover old address still works for sign-in until it is removed.
      if let oldAddress, oldAddress.id != verified.id {
        _ = try? await oldAddress.destroy()
      }
      _ = try await ConvexAPI.app.action("users:syncFromClerk", as: ConvexAPI.Ignored.self)
      _ = try? await AuthSessionManager.shared.forceRefresh()
      email = verified.emailAddress
      Haptics.play(.success)
      resetEmailChangeState()
    } catch {
      emailCode = ""
      errorMessage =
        AuthService.isInvalidVerificationCode(error)
        ? String(localized: .signupVerifyErrorsInvalidCode) : AuthService.message(for: error)
    }

    isChangingEmail = false
  }

  /// Reset email change state
  func resetEmailChangeState() {
    newEmail = ""
    emailCode = ""
    awaitingEmailCode = false
    pendingEmailAddress = nil
    showEmailChangeSheet = false
  }

  // MARK: - Avatar Upload

  /// Sends the image to the deployment, which stores it and replaces the previous one.
  /// - Returns: The URL of the stored picture.
  private func uploadAvatarFile(_ preparedUpload: ProfileAvatarEncoder.PreparedUpload) async throws
    -> String
  {
    var forceRefresh = false
    while true {
      var request = URLRequest(url: ConvexAPI.configuredSiteURL.appending(path: "profile-picture"))
      request.httpMethod = "POST"
      request.setValue(preparedUpload.contentType, forHTTPHeaderField: "Content-Type")
      if let token = try await AuthSessionManager.shared.convexToken(forceRefresh: forceRefresh) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      }
      let (data, response) = try await URLSession.shared.upload(
        for: request, from: preparedUpload.data)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      if status == 401, !forceRefresh {
        forceRefresh = true
        continue
      }
      guard status == 200,
        let url = try JSONDecoder().decode(ProfilePictureReply.self, from: data).url
      else { throw URLError(.badServerResponse) }
      return url
    }
  }

  /// Upload a new profile picture
  /// - Parameter imageData: The image data to upload (will be converted to WebP)
  func uploadProfilePicture(_ imageData: Data) async {
    // Prevent duplicate taps
    guard !isUploadingAvatar else { return }
    guard let currentUserId = userId else { return }

    isUploadingAvatar = true
    errorMessage = nil
    defer { isUploadingAvatar = false }
    let previousUrl = profilePictureUrl

    do {
      // Convert to modern format for smaller file size off-main.
      // Priority: WebP > HEIC > JPEG.
      let preparedUpload = await ProfileAvatarEncoder.prepareUpload(imageData)

      let publicUrl = try await uploadAvatarFile(preparedUpload)
      _ = try await settingsRepository.updateSettings(
        for: currentUserId, profilePictureUrl: publicUrl)

      if let previousUrl, let url = URL(string: previousUrl) {
        ImageCache.shared.remove(for: url)
      }
      profilePictureUrl = publicUrl

      // Update AppCoordinator's avatar URL
      AppCoordinator.shared.updateAvatarUrl(publicUrl)

      Haptics.play(.success)
    } catch {
      errorMessage = String(localized: .profileErrorsUploadFailed)
      Haptics.play(.error)
    }
  }

  /// Remove the profile picture
  func removeProfilePicture() async {
    guard !isUploadingAvatar else { return }
    guard let currentUserId = userId else { return }
    guard let currentUrl = profilePictureUrl else { return }

    isUploadingAvatar = true
    errorMessage = nil
    defer { isUploadingAvatar = false }

    do {
      _ = try await ConvexAPI.app.mutation(
        "userSettings:clearProfilePicture", as: ConvexAPI.Ignored.self)
      _ = try await settingsRepository.clearProfilePictureUrl(for: currentUserId)

      if let url = URL(string: currentUrl) {
        ImageCache.shared.remove(for: url)
      }
      profilePictureUrl = nil
      AppCoordinator.shared.updateAvatarUrl(nil)

      Haptics.play(.success)
    } catch {
      errorMessage = String(localized: .profileErrorsSaveFailed)
      Haptics.play(.error)
    }
  }

}

extension ProfileSettingsViewModel {
  // MARK: - Account Deletion

  /// Expected confirmation text for account deletion
  var expectedDeleteConfirmText: String {
    String(localized: .profileDangerZoneDeleteAccountConfirmText)
  }

  /// Whether the delete confirmation text matches
  var canConfirmDelete: Bool {
    deleteConfirmText == expectedDeleteConfirmText
  }

  /// Delete the user's account with the Convex `account:deleteAccount` action
  func deleteAccount() async {
    // Prevent duplicate taps
    guard !isDeletingAccount else { return }

    guard canConfirmDelete else {
      errorMessage = String(localized: .profileDangerZoneDeleteAccountErrorsConfirmMismatch)
      return
    }

    isDeletingAccount = true
    errorMessage = nil

    do {
      struct DeleteAccountResponse: Decodable {
        let success: Bool
      }

      let response: DeleteAccountResponse = try await ConvexAPI.app.action("account:deleteAccount")

      if response.success {
        // Account deleted successfully. Clear local data and the Clerk session.
        Haptics.play(.warning)
        await AppCoordinator.shared.signOut()
      } else {
        throw URLError(.badServerResponse)
      }

    } catch {
      errorMessage = String(localized: .profileDangerZoneDeleteAccountErrorsDeleteFailed)
      Haptics.play(.error)
      isDeletingAccount = false
    }
  }
}
