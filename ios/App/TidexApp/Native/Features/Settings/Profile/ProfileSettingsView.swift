import os.log
import PhotosUI
import SwiftUI

private let logger = Logger(subsystem: "no.tidex.app", category: "ProfileSettings")

/// Profile settings view
/// Displays profile picture, name, email, and danger zone (delete account)
struct ProfileSettingsView: View {
    @Environment(\.localization) private var localization
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ProfileSettingsViewModel()

    /// Photo picker selection
    @State private var selectedPhotoItem: PhotosPickerItem?
    /// Whether to show the remove avatar confirmation
    @State private var showRemoveAvatarConfirmation = false
    /// Whether to show the image source picker (camera vs gallery)
    @State private var showImageSourcePicker = false
    /// Whether to show the gallery picker
    @State private var showGalleryPicker = false
    /// Whether to show the camera picker
    @State private var showCamera = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Personal Info Section
                personalInfoSection

                // Danger Zone Section
                dangerZoneSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color.tidexBackground)
        .navigationTitle(localization.string("profile.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.tidexBackground, for: .navigationBar)
        .task {
            await viewModel.loadProfile()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                await handlePhotoSelection(newItem)
            }
        }
        .alert(localization.string("profile.dangerZone.deleteAccount.dialogTitle"), isPresented: $viewModel.showDeleteConfirmation) {
            TextField(viewModel.expectedDeleteConfirmText, text: $viewModel.deleteConfirmText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button(localization.string("common.cancel"), role: .cancel) {
                viewModel.deleteConfirmText = ""
            }

            Button(localization.string("profile.dangerZone.deleteAccount.button"), role: .destructive) {
                Task {
                    await viewModel.deleteAccount()
                }
            }
            .disabled(!viewModel.canConfirmDelete)
        } message: {
            Text(localization.string("profile.dangerZone.deleteAccount.dialogDescription"))
        }
        .confirmationDialog(
            localization.string("profile.personalInfo.removeImageConfirm"),
            isPresented: $showRemoveAvatarConfirmation,
            titleVisibility: .visible
        ) {
            Button(localization.string("profile.personalInfo.removeImage"), role: .destructive) {
                Task {
                    await viewModel.removeProfilePicture()
                }
            }
            Button(localization.string("common.cancel"), role: .cancel) {}
        }
        .confirmationDialog(
            localization.string("profile.personalInfo.chooseImageSource"),
            isPresented: $showImageSourcePicker,
            titleVisibility: .visible
        ) {
            Button(localization.string("profile.personalInfo.takePhoto")) {
                showCamera = true
            }
            Button(localization.string("profile.personalInfo.chooseFromLibrary")) {
                showGalleryPicker = true
            }
            Button(localization.string("common.cancel"), role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showGalleryPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                Task {
                    await handleCameraImage(image)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $viewModel.showEmailChangeSheet) {
            emailChangeSheet
        }
    }

    // MARK: - Email Change Sheet

    private var emailChangeSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if viewModel.emailChangeSent {
                    // Success state
                    emailChangeSentView
                } else {
                    // Input state
                    emailChangeInputView
                }

                Spacer()
            }
            .padding(24)
            .background(Color.tidexBackground)
            .navigationTitle(localization.string("profile.emailChange.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.string("common.cancel")) {
                        viewModel.resetEmailChangeState()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var emailChangeInputView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Instructions
            Text(localization.string("profile.emailChange.instructions"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)

            // Current email (read-only)
            VStack(alignment: .leading, spacing: 6) {
                Text(localization.string("profile.emailChange.currentEmailLabel"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)

                Text(viewModel.email)
                    .font(.system(size: 16))
                    .foregroundColor(.tidexTextMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.tidexSurfaceSecondary.opacity(0.5))
                    .cornerRadius(8)
            }

            // New email input
            VStack(alignment: .leading, spacing: 6) {
                Text(localization.string("profile.emailChange.newEmailLabel"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)

                TextField(localization.string("profile.emailChange.newEmailPlaceholder"), text: $viewModel.newEmail)
                    .font(.system(size: 16))
                    .foregroundColor(.tidexTextPrimary)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.tidexSurfaceSecondary)
                    .cornerRadius(8)
            }

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexError)
            }

            // Submit button
            Button {
                Task {
                    await viewModel.initiateEmailChange()
                }
            } label: {
                HStack {
                    if viewModel.isChangingEmail {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(viewModel.isChangingEmail
                         ? localization.string("profile.emailChange.sending")
                         : localization.string("profile.emailChange.sendConfirmation"))
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(viewModel.newEmail.isEmpty ? Color.tidexBlue.opacity(0.5) : Color.tidexBlue)
                .cornerRadius(10)
            }
            .disabled(viewModel.newEmail.isEmpty || viewModel.isChangingEmail)
        }
    }

    private var emailChangeSentView: some View {
        VStack(spacing: 20) {
            // Success icon
            ZStack {
                Circle()
                    .fill(Color.tidexSuccess.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.tidexSuccess)
            }

            // Success message
            VStack(spacing: 8) {
                Text(localization.string("profile.emailChange.confirmationSent"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Text(localization.string("profile.emailChange.confirmationMessage"))
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextSecondary)
                    .multilineTextAlignment(.center)
            }

            // Done button
            Button {
                viewModel.resetEmailChangeState()
            } label: {
                Text(localization.string("common.done"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.tidexBlue)
                    .cornerRadius(10)
            }
        }
    }

    // MARK: - Personal Info Section

    private var personalInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            Text(localization.string("profile.personalInfo.title"))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.tidexTextPrimary)

            VStack(spacing: 20) {
                // Avatar section
                avatarSection

                Divider()
                    .background(Color.tidexBorder)

                // Name field
                nameField

                Divider()
                    .background(Color.tidexBorder)

                // Email field (read-only)
                emailField
            }
            .padding(16)
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(12)
        }
    }

    // MARK: - Avatar Section

    /// Button text for the photo picker - computed to avoid main actor issues in closure
    private var uploadButtonText: String {
        if viewModel.isUploadingAvatar {
            return localization.string("profile.personalInfo.uploadingImage")
        } else if viewModel.profilePictureUrl != nil {
            return localization.string("profile.personalInfo.changeImage")
        } else {
            return localization.string("profile.personalInfo.uploadImage")
        }
    }

    /// Upload button label - extracted to avoid main actor isolation issues in PhotosPicker closure
    private var uploadButtonLabel: some View {
        HStack(spacing: 6) {
            if viewModel.isUploadingAvatar {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .medium))
            }
            Text(uploadButtonText)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(.tidexBlue)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.tidexBlue.opacity(0.1))
        .cornerRadius(8)
    }

    private var avatarSection: some View {
        HStack(spacing: 16) {
            // Avatar
            avatarView
                .frame(width: 80, height: 80)

            // Buttons
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showImageSourcePicker = true
                } label: {
                    uploadButtonLabel
                }
                .disabled(viewModel.isUploadingAvatar)

                if viewModel.profilePictureUrl != nil {
                    Button {
                        showRemoveAvatarConfirmation = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                            Text(localization.string("profile.personalInfo.removeImage"))
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.tidexError)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.tidexError.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .disabled(viewModel.isUploadingAvatar)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let urlString = viewModel.profilePictureUrl,
           let url = URL(string: urlString) {
            CachedAsyncImage(
                url: url,
                content: { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                },
                placeholder: {
                    initialAvatar
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            initialAvatar
        }
    }

    private var initialAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tidexBlue.opacity(0.2))

            Text(viewModel.initials)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.tidexBlue)
        }
    }

    // MARK: - Name Field

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localization.string("profile.personalInfo.nameLabel"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)

                Spacer()

                if viewModel.isSavingName {
                    HStack(spacing: 4) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextMuted))
                            .scaleEffect(0.6)
                        Text(localization.string("common.saving"))
                            .font(.system(size: 12))
                            .foregroundColor(.tidexTextMuted)
                    }
                }
            }

            TextField(localization.string("profile.personalInfo.namePlaceholder"), text: $viewModel.displayName)
                .font(.system(size: 16))
                .foregroundColor(.tidexTextPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, Spacing.sm)
                .background(Color.tidexSurfaceSecondary)
                .cornerRadius(8)
                .onChange(of: viewModel.displayName) { _, _ in
                    viewModel.onNameChanged()
                }
        }
    }

    // MARK: - Email Field

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localization.string("profile.personalInfo.emailLabel"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)

                Spacer()

                if viewModel.canChangeEmail {
                    Button {
                        viewModel.showEmailChangeSheet = true
                    } label: {
                        Text(localization.string("profile.emailChange.changeButton"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.tidexBlue)
                    }
                }
            }

            HStack {
                Text(viewModel.email)
                    .font(.system(size: 16))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()

                if !viewModel.canChangeEmail {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.tidexTextMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, Spacing.sm)
            .background(Color.tidexSurfaceSecondary.opacity(0.5))
            .cornerRadius(8)

            // Show appropriate hint based on user's auth type
            if viewModel.isOAuthOnly {
                Text(localization.string("profile.emailChange.oauthOnlyHint"))
                    .font(.system(size: 12))
                    .foregroundColor(.tidexTextMuted)
            } else if viewModel.canChangeEmail {
                Text(localization.string("profile.emailChange.canChangeHint"))
                    .font(.system(size: 12))
                    .foregroundColor(.tidexTextMuted)
            } else {
                Text(localization.string("profile.personalInfo.emailHint"))
                    .font(.system(size: 12))
                    .foregroundColor(.tidexTextMuted)
            }
        }
    }

    // MARK: - Danger Zone Section

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            Text(localization.string("profile.dangerZone.title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.tidexError)

            VStack(alignment: .leading, spacing: 12) {
                Text(localization.string("profile.dangerZone.subtitle"))
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextSecondary)

                Divider()
                    .background(Color.tidexError.opacity(0.3))

                // Delete account row
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localization.string("profile.dangerZone.deleteAccount.title"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.tidexTextPrimary)

                        Text(localization.string("profile.dangerZone.deleteAccount.description"))
                            .font(.system(size: 13))
                            .foregroundColor(.tidexTextSecondary)
                    }

                    Spacer()

                    Button {
                        viewModel.showDeleteConfirmation = true
                    } label: {
                        Text(localization.string("profile.dangerZone.deleteAccount.button"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, Spacing.sm)
                            .background(Color.tidexError)
                            .cornerRadius(8)
                    }
                    .disabled(viewModel.isDeletingAccount)
                }
            }
            .padding(16)
            .background(Color.tidexSurfacePrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.tidexError.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(12)
        }
    }

    // MARK: - Photo Selection Handler

    private func handlePhotoSelection(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }

        do {
            // Load the image data
            guard let data = try await item.loadTransferable(type: Data.self) else {
                return
            }

            // Compress and resize the image
            guard let uiImage = UIImage(data: data) else {
                return
            }

            // Resize to 192x192 square (matches server's AVATAR_SIZE for 2x retina)
            // Use "cover" fit - crop to square from center, then resize
            let avatarSize: CGFloat = 192
            let sourceSize = uiImage.size

            // Calculate crop rect for center square
            let shortSide = min(sourceSize.width, sourceSize.height)
            let cropRect = CGRect(
                x: (sourceSize.width - shortSide) / 2,
                y: (sourceSize.height - shortSide) / 2,
                width: shortSide,
                height: shortSide
            )

            // Crop to square
            guard let cgImage = uiImage.cgImage,
                  let croppedCGImage = cgImage.cropping(to: cropRect) else {
                return
            }
            let croppedImage = UIImage(cgImage: croppedCGImage, scale: uiImage.scale, orientation: uiImage.imageOrientation)

            // Resize to avatar size
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: avatarSize, height: avatarSize))
            let resizedImage = renderer.image { _ in
                croppedImage.draw(in: CGRect(origin: .zero, size: CGSize(width: avatarSize, height: avatarSize)))
            }

            guard let compressedData = resizedImage.jpegData(compressionQuality: 0.8) else {
                return
            }

            // Upload the image
            await viewModel.uploadProfilePicture(compressedData)

            // Clear selection
            selectedPhotoItem = nil

        } catch {
            logger.error("Failed to process photo: \(error.localizedDescription)")
        }
    }

    /// Handle image captured from camera
    private func handleCameraImage(_ image: UIImage) async {
        // Resize to 192x192 square (matches server's AVATAR_SIZE for 2x retina)
        // Use "cover" fit - crop to square from center, then resize
        let avatarSize: CGFloat = 192
        let sourceSize = image.size

        // Calculate crop rect for center square
        let shortSide = min(sourceSize.width, sourceSize.height)
        let cropRect = CGRect(
            x: (sourceSize.width - shortSide) / 2,
            y: (sourceSize.height - shortSide) / 2,
            width: shortSide,
            height: shortSide
        )

        // Crop to square
        guard let cgImage = image.cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {
            logger.error("Failed to crop camera image")
            return
        }
        let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)

        // Resize to avatar size
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: avatarSize, height: avatarSize))
        let resizedImage = renderer.image { _ in
            croppedImage.draw(in: CGRect(origin: .zero, size: CGSize(width: avatarSize, height: avatarSize)))
        }

        guard let compressedData = resizedImage.jpegData(compressionQuality: 0.8) else {
            logger.error("Failed to compress camera image")
            return
        }

        // Upload the image
        await viewModel.uploadProfilePicture(compressedData)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProfileSettingsView()
    }
    .environment(\.localization, LocalizationManager.shared)
}
