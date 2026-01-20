import Foundation
import SwiftUI
import Supabase
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

/// View model for profile settings
/// Handles profile data loading, name editing, avatar management, and account deletion
@MainActor
final class ProfileSettingsViewModel: ObservableObject {

    // MARK: - Dependencies

    private let settingsRepository: SettingsRepository
    private let syncCoordinator: SyncCoordinator
    private let localization: LocalizationManager

    // MARK: - Published State

    /// User's display name (editable)
    @Published var displayName: String = ""
    /// User's email address (read-only display)
    @Published var email: String = ""
    /// User's profile picture URL
    @Published var profilePictureUrl: String?
    /// User ID
    @Published private(set) var userId: String?

    /// Whether user has password authentication (can change email)
    @Published private(set) var hasPassword = false
    /// Whether user is OAuth-only (cannot change email)
    @Published private(set) var isOAuthOnly = false

    /// Loading states
    @Published private(set) var isLoading = false
    @Published private(set) var isSavingName = false
    @Published private(set) var isUploadingAvatar = false
    @Published private(set) var isDeletingAccount = false
    @Published private(set) var isChangingEmail = false

    /// Error message to display
    @Published var errorMessage: String?
    /// Success message to display
    @Published var successMessage: String?

    /// Email change state
    @Published var showEmailChangeSheet = false
    @Published var newEmail: String = ""
    @Published var emailChangeSent = false

    /// Delete account confirmation state
    @Published var showDeleteConfirmation = false
    @Published var deleteConfirmText = ""

    // MARK: - Private State

    /// Original display name (for detecting changes)
    private var originalDisplayName: String = ""
    /// Debounce task for auto-saving name
    private var nameSaveTask: Task<Void, Never>?
    /// API base URL for web app routes
    private var apiBaseUrl: String {
        APIConfiguration.webAppBaseURL.absoluteString
    }

    // MARK: - Initialization

    init(
        settingsRepository: SettingsRepository? = nil,
        syncCoordinator: SyncCoordinator? = nil,
        localization: LocalizationManager? = nil
    ) {
        self.settingsRepository = settingsRepository ?? SettingsRepository.shared
        self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
        self.localization = localization ?? LocalizationManager.shared
    }

    // MARK: - Load Profile

    /// Load the user's profile data
    func loadProfile() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch fresh user data to get identities (not available in JWT)
            let freshUser = try await supabase.auth.user()

            userId = freshUser.id.uuidString.lowercased()

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

            // Determine authentication capabilities from identities
            let identities = freshUser.identities ?? []
            let providers = Set(identities.map { $0.provider })

            hasPassword = providers.contains("email")
            let hasGoogle = providers.contains("google")
            let hasApple = providers.contains("apple")
            let hasPhone = providers.contains("phone")
            isOAuthOnly = (hasGoogle || hasApple) && !hasPassword && !hasPhone

            // Get profile picture from local settings
            if let currentUserId = userId,
               let settings = settingsRepository.getSettings(for: currentUserId) {
                profilePictureUrl = settings.profile_picture_url
            }

        } catch {
            print("[ProfileSettingsViewModel] Failed to load profile: \(error)")
            errorMessage = localization.string("profile.errors.loadFailed")
        }

        isLoading = false
    }

    // MARK: - Name Editing

    /// Called when name changes - debounces and auto-saves
    func onNameChanged() {
        // Cancel any pending save
        nameSaveTask?.cancel()

        // Don't save if unchanged
        guard displayName != originalDisplayName else { return }

        // Debounce save for 1 second
        nameSaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            guard !Task.isCancelled else { return }

            await saveName()
        }
    }

    /// Save the display name
    private func saveName() async {
        guard let currentUserId = userId else { return }
        guard displayName != originalDisplayName else { return }

        isSavingName = true
        errorMessage = nil

        do {
            // Update Supabase auth user metadata
            _ = try await supabase.auth.update(user: UserAttributes(
                data: ["full_name": .string(displayName)]
            ))

            // Refresh session to get updated JWT
            _ = try? await supabase.auth.refreshSession()

            originalDisplayName = displayName

            // Update AppCoordinator's display name
            AppCoordinator.shared.updateDisplayName(displayName)

            // Trigger sync to push changes
            Task {
                _ = await syncCoordinator.sync(reason: .foreground, userId: currentUserId)
            }

        } catch {
            print("[ProfileSettingsViewModel] Failed to save name: \(error)")
            errorMessage = localization.string("profile.errors.saveFailed")
        }

        isSavingName = false
    }

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
        guard canChangeEmail else {
            errorMessage = localization.string("profile.emailChange.errors.oauthOnly")
            return
        }

        guard isValidEmail(newEmail) else {
            errorMessage = localization.string("profile.emailChange.errors.invalidEmail")
            return
        }

        guard newEmail.lowercased() != email.lowercased() else {
            errorMessage = localization.string("profile.emailChange.errors.sameEmail")
            return
        }

        isChangingEmail = true
        errorMessage = nil

        do {
            // Supabase will send confirmation emails to both old and new addresses
            _ = try await supabase.auth.update(user: UserAttributes(
                email: newEmail
            ))

            emailChangeSent = true

        } catch {
            print("[ProfileSettingsViewModel] Failed to initiate email change: \(error)")
            errorMessage = localization.string("profile.emailChange.errors.failed")
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

    private let storageBucket = "profile-pictures"

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
            print("[ProfileSettingsViewModel] Failed to delete old avatar: \(error)")
            // Non-fatal - continue with upload
        }
    }

    /// Convert image data to WebP format for smaller file sizes
    /// - Parameter imageData: Source image data (JPEG, PNG, etc.)
    /// - Returns: WebP data or nil if conversion fails
    private func convertToWebP(_ imageData: Data, quality: CGFloat = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let webpData = NSMutableData()
        guard let webpUTType = UTType.webP.identifier as CFString?,
              let destination = CGImageDestinationCreateWithData(
                  webpData,
                  webpUTType,
                  1,
                  nil
              ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return webpData as Data
    }

    /// Upload a new profile picture directly to Supabase Storage
    /// - Parameter imageData: The image data to upload (will be converted to WebP)
    func uploadProfilePicture(_ imageData: Data) async {
        guard let currentUserId = userId else { return }

        isUploadingAvatar = true
        errorMessage = nil

        do {
            // Delete previous image from storage if exists
            if let previousUrl = profilePictureUrl {
                await deleteStorageFile(from: previousUrl)
                // Clear from local cache
                if let url = URL(string: previousUrl) {
                    ImageCache.shared.remove(for: url)
                }
            }

            // Convert to WebP for smaller file size
            let uploadData: Data
            let contentType: String
            let fileExtension: String

            if let webpData = convertToWebP(imageData, quality: 0.8) {
                uploadData = webpData
                contentType = "image/webp"
                fileExtension = "webp"
            } else {
                // Fallback to original JPEG if WebP conversion fails
                uploadData = imageData
                contentType = "image/jpeg"
                fileExtension = "jpg"
            }

            // Generate unique filename
            let filename = "\(currentUserId)/\(UUID().uuidString).\(fileExtension)"

            // Upload directly to Supabase Storage
            try await supabase.storage
                .from(storageBucket)
                .upload(
                    filename,
                    data: uploadData,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: contentType,
                        upsert: true
                    )
                )

            // Get the public URL
            let publicUrl = try supabase.storage
                .from(storageBucket)
                .getPublicURL(path: filename)
                .absoluteString

            profilePictureUrl = publicUrl

            // Update local settings
            _ = try? await settingsRepository.updateSettings(
                for: currentUserId,
                profilePictureUrl: publicUrl
            )

            // Update AppCoordinator's avatar URL
            AppCoordinator.shared.updateAvatarUrl(publicUrl)

            // Trigger sync
            Task {
                _ = await syncCoordinator.sync(reason: .foreground, userId: currentUserId)
            }

        } catch {
            print("[ProfileSettingsViewModel] Failed to upload avatar: \(error)")
            errorMessage = localization.string("profile.errors.uploadFailed")
        }

        isUploadingAvatar = false
    }

    /// Remove the profile picture directly from Supabase Storage
    func removeProfilePicture() async {
        guard let currentUserId = userId else { return }
        guard let currentUrl = profilePictureUrl else { return }

        isUploadingAvatar = true
        errorMessage = nil

        do {
            // Delete from storage
            await deleteStorageFile(from: currentUrl)

            // Clear from local cache
            if let url = URL(string: currentUrl) {
                ImageCache.shared.remove(for: url)
            }

            profilePictureUrl = nil

            // Update Supabase user_settings table directly to set profile_picture_url to null
            // Note: The local repository's updateSettings can't set values to nil,
            // so we update Supabase directly and let sync pull the change back
            try await supabase
                .from("user_settings")
                .update(["profile_picture_url": AnyJSON.null])
                .eq("user_id", value: currentUserId)
                .execute()

            // Update AppCoordinator's avatar URL
            AppCoordinator.shared.updateAvatarUrl(nil)

            // Trigger sync to update local storage
            Task {
                _ = await syncCoordinator.sync(reason: .foreground, userId: currentUserId)
            }

        } catch {
            print("[ProfileSettingsViewModel] Failed to remove avatar: \(error)")
            errorMessage = localization.string("profile.errors.removeFailed")
        }

        isUploadingAvatar = false
    }

    // MARK: - Account Deletion

    /// Expected confirmation text for account deletion
    var expectedDeleteConfirmText: String {
        localization.string("profile.dangerZone.deleteAccount.confirmText")
    }

    /// Whether the delete confirmation text matches
    var canConfirmDelete: Bool {
        deleteConfirmText == expectedDeleteConfirmText
    }

    /// Delete the user's account via API route (requires service role)
    func deleteAccount() async {
        guard canConfirmDelete else {
            errorMessage = localization.string("profile.dangerZone.deleteAccount.errors.confirmMismatch")
            return
        }

        isDeletingAccount = true
        errorMessage = nil

        do {
            // Get the current session for auth
            let session = try await supabase.auth.session
            let accessToken = session.accessToken

            // Call the delete account API route
            guard let url = URL(string: "\(apiBaseUrl)/api/delete-account") else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 200 {
                // Account deleted successfully - sign out locally
                try? await supabase.auth.signOut()

                // Clear local data via AppCoordinator
                await AppCoordinator.shared.signOut()
            } else {
                // Parse error message
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMsg = json["error"] as? String {
                    print("[ProfileSettingsViewModel] Delete account failed: \(errorMsg)")
                }
                throw URLError(.badServerResponse)
            }

        } catch {
            print("[ProfileSettingsViewModel] Failed to delete account: \(error)")
            errorMessage = localization.string("profile.dangerZone.deleteAccount.errors.deleteFailed")
            isDeletingAccount = false
        }
    }

    // MARK: - Helpers

    /// Get initials from display name or email
    var initials: String {
        let name = displayName.isEmpty ? email : displayName
        return name
            .split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map { String($0).uppercased() }
            .joined()
    }

    /// Clear messages
    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}
