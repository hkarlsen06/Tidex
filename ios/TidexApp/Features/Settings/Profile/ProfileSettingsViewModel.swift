import Foundation
import ImageIO
import Observation
import Supabase
import UniformTypeIdentifiers

private struct ProfileUsernameRow: Decodable {
  let username: String?
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
  var emailChangeSent = false

  /// Delete account confirmation state
  var showDeleteConfirmation = false
  var deleteConfirmText = ""

  // MARK: - Private State

  /// Original display name (for detecting changes)
  private var originalDisplayName: String = ""
  /// Original username (for detecting changes)
  private var originalUsername: String = ""
  private let storageBucket = "profile-pictures"

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
      // Fetch fresh user data to get identities (not available in JWT)
      let freshUser = try await supabase.auth.user()

      userId = freshUser.normalizedId

      // Extract display name from user metadata
      if let fullName = freshUser.userMetadata["full_name"]?.value as? String, !fullName.isEmpty {
        displayName = fullName
      } else if let name = freshUser.userMetadata["name"]?.value as? String, !name.isEmpty {
        displayName = name
      } else {
        displayName = ""
      }
      originalDisplayName = displayName

      // Extract email
      email = freshUser.email ?? ""

      do {
        let usernameResponse: ProfileUsernameRow =
          try await supabase
          .rpc("get_my_profile_username")
          .single()
          .execute()
          .value
        username = usernameResponse.username ?? ""
        originalUsername = username
      } catch {
        username = ""
        originalUsername = ""
      }

      // Determine authentication capabilities from identities
      let identities = freshUser.identities ?? []
      let providers = Set(identities.map(\.provider))  // swiftlint:disable:this explicit_type_interface

      // Supabase may not add an "email" identity when setting a password on OAuth users.
      let metadataHasPassword = freshUser.userMetadata["hasPassword"]?.value as? Bool ?? false
      let appMetadataProviders =
        freshUser.appMetadata["providers"]?.value as? [String]
        ?? (freshUser.appMetadata["providers"]?.value as? [Any])?.compactMap { $0 as? String }
        ?? []
      let hasEmailProvider = providers.contains("email") || appMetadataProviders.contains("email")

      hasPassword = hasEmailProvider || metadataHasPassword
      let hasGoogle = providers.contains("google")
      let hasApple = providers.contains("apple")
      let hasPhone = providers.contains("phone")
      isOAuthOnly = (hasGoogle || hasApple) && !hasPassword && !hasPhone

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
      // Update Supabase auth user metadata
      _ = try await supabase.auth.update(
        user: UserAttributes(
          data: ["full_name": .string(normalizedDisplayName)]
        ))

      // Refresh session to get updated JWT via serialized auth path
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
      let params: [String: AnyJSON] = ["p_username": .string(normalizedUsername)]
      let response: ProfileUsernameRow =
        try await supabase
        .rpc(
          "set_my_profile_username",
          params: params
        )
        .single()
        .execute()
        .value

      username = response.username ?? ""
      originalUsername = username
    } catch let error as PostgrestError {
      if Self.isUsernameTaken(error) {
        setUsernameError(String(localized: .profileErrorsUsernameTaken))
      } else if Self.isUsernameSafetyFilterViolation(error) {
        setUsernameError(String(localized: .profileErrorsNameSafetyFilter))
      } else if Self.isUsernameCheckConstraintViolation(error) {
        setUsernameError(String(localized: .profileErrorsUsernameInvalid))
      } else {
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

  /// Initiate email change - sends confirmation to both old and new email
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
      // Supabase will send confirmation emails to both old and new addresses
      _ = try await supabase.auth.update(
        user: UserAttributes(
          email: newEmail
        ))

      emailChangeSent = true

    } catch {
      errorMessage = ErrorTranslations.translate(error)
    }

    isChangingEmail = false
  }

  /// Reset email change state
  func resetEmailChangeState() {
    newEmail = ""
    emailChangeSent = false
    showEmailChangeSheet = false
  }

  // MARK: - Avatar Upload

  /// Extract storage path from a public URL
  /// e.g. "https://xxx.supabase.co/storage/v1/object/public/profile-pictures/user-id/file.jpg"
  /// returns "user-id/file.jpg"
  private func extractStoragePath(from url: String) -> String? {
    let marker = "/storage/v1/object/public/\(storageBucket)/"
    guard let range = url.range(of: marker) else { return nil }
    return String(url[range.upperBound...])
  }

  /// Delete a file from storage given its public URL
  private func deleteStorageFile(from url: String) async {
    guard let path = extractStoragePath(from: url) else { return }
    do {
      try await supabase.storage
        .from(storageBucket)
        .remove(paths: [path])
    } catch {
      // Best-effort cleanup after the settings change has been saved.
    }
  }

  /// Uploads the encoded avatar under a unique name and returns its public URL.
  private func uploadAvatarFile(
    _ preparedUpload: ProfileAvatarEncoder.PreparedUpload,
    userId: String
  ) async throws -> String {
    let filename = "\(userId)/\(UUID().uuidString).\(preparedUpload.fileExtension)"

    // Upload directly to Supabase Storage
    try await supabase.storage
      .from(storageBucket)
      .upload(
        filename,
        data: preparedUpload.data,
        options: FileOptions(
          cacheControl: "3600",
          contentType: preparedUpload.contentType,
          upsert: true
        )
      )

    // Get the public URL
    return try supabase.storage
      .from(storageBucket)
      .getPublicURL(path: filename)
      .absoluteString
  }

  /// Upload a new profile picture directly to Supabase Storage
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

      let publicUrl = try await uploadAvatarFile(preparedUpload, userId: currentUserId)

      try await Self.commitAvatarChange(from: previousUrl, to: publicUrl) {
        try await self.settingsRepository.updateSettings(
          for: currentUserId, profilePictureUrl: publicUrl
        ) != nil
      } removeStoredAvatar: { url in
        await self.deleteStorageFile(from: url)
      }

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

  /// Remove the profile picture directly from Supabase Storage
  func removeProfilePicture() async {
    guard !isUploadingAvatar else { return }
    guard let currentUserId = userId else { return }
    guard let currentUrl = profilePictureUrl else { return }

    isUploadingAvatar = true
    errorMessage = nil
    defer { isUploadingAvatar = false }

    do {
      try await Self.commitAvatarChange(from: currentUrl, to: nil) {
        try await self.settingsRepository.clearProfilePictureUrl(for: currentUserId) != nil
      } removeStoredAvatar: { url in
        await self.deleteStorageFile(from: url)
      }

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

  /// Delete the user's account via Edge Function (requires service role)
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

      let response: DeleteAccountResponse = try await supabase.functions.invoke(
        "delete-account",
        options: FunctionInvokeOptions(body: AnyJSON.object([:]))
      )

      if response.success {
        // Account deleted successfully - sign out locally
        Haptics.play(.warning)
        try? await supabase.auth.signOut(scope: .local)

        // Clear local data via AppCoordinator
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
