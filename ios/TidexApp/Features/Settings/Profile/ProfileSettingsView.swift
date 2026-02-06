import PhotosUI
import SwiftUI
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "ProfileSettings")

/// Profile settings view
/// Displays profile picture, name, email, and danger zone (delete account)
struct ProfileSettingsView: View {
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
  /// Image pending crop (from camera or gallery)
  @State private var pendingImage: UIImage?
  /// Whether to show the crop sheet
  @State private var showCropSheet = false

  var body: some View {
    List {
      // Error banner (for avatar upload, name save, etc.)
      if let error = viewModel.errorMessage, !viewModel.showEmailChangeSheet {
        Section {
          ErrorBanner(
            message: error,
            onDismiss: { viewModel.errorMessage = nil }
          )
        }
        .listRowBackground(Color.tidexSurfacePrimary)
      }

      // Personal Info Section
      Section(header: Text(String(localized: .profilePersonalInfoTitle))) {
        avatarSection
        nameField
        emailField
      }
      .listRowBackground(Color.tidexSurfacePrimary)

      // Danger Zone Section
      dangerZoneSection
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(Color.tidexBackground)
    .navigationTitle(String(localized: .profileTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadProfile()
    }
    .onChange(of: selectedPhotoItem) { _, newItem in
      Task {
        await handlePhotoSelection(newItem)
      }
    }
    .alert(
      String(localized: .profileDangerZoneDeleteAccountDialogTitle),
      isPresented: $viewModel.showDeleteConfirmation
    ) {
      TextField(viewModel.expectedDeleteConfirmText, text: $viewModel.deleteConfirmText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()

      Button(String(localized: .commonCancel), role: .cancel) {
        viewModel.deleteConfirmText = ""
      }

      Button(String(localized: .profileDangerZoneDeleteAccountButton), role: .destructive) {
        Task {
          await viewModel.deleteAccount()
        }
      }
      .disabled(!viewModel.canConfirmDelete)
    } message: {
      Text(.profileDangerZoneDeleteAccountDialogDescription)
    }
    .confirmationDialog(
      String(localized: .profilePersonalInfoRemoveImageConfirm),
      isPresented: $showRemoveAvatarConfirmation,
      titleVisibility: .visible
    ) {
      Button(String(localized: .profilePersonalInfoRemoveImage), role: .destructive) {
        Task {
          await viewModel.removeProfilePicture()
        }
      }
      Button(String(localized: .commonCancel), role: .cancel) {}
    }
    .confirmationDialog(
      String(localized: .profilePersonalInfoChooseImageSource),
      isPresented: $showImageSourcePicker,
      titleVisibility: .visible
    ) {
      Button(String(localized: .profilePersonalInfoTakePhoto)) {
        showCamera = true
      }
      Button(String(localized: .profilePersonalInfoChooseFromLibrary)) {
        showGalleryPicker = true
      }
      Button(String(localized: .commonCancel), role: .cancel) {}
    }
    .photosPicker(
      isPresented: $showGalleryPicker,
      selection: $selectedPhotoItem,
      matching: .images,
      photoLibrary: .shared()
    )
    .fullScreenCover(isPresented: $showCamera) {
      CameraPicker { image in
        pendingImage = image
        showCropSheet = true
      }
      .ignoresSafeArea()
    }
    .fullScreenCover(isPresented: $showCropSheet) {
      if let image = pendingImage {
        ProfileImageCropSheet(
          image: image,
          onCrop: { croppedImage in
            Task {
              await handleCroppedImage(croppedImage)
            }
            showCropSheet = false
            pendingImage = nil
          },
          onCancel: {
            showCropSheet = false
            pendingImage = nil
          }
        )
      }
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
      .navigationTitle(String(localized: .profileEmailChangeTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
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
      Text(.profileEmailChangeInstructions)
        .font(.system(size: 14))
        .foregroundColor(.tidexTextSecondary)

      // Current email (read-only)
      VStack(alignment: .leading, spacing: 6) {
        Text(.profileEmailChangeCurrentEmailLabel)
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
        Text(.profileEmailChangeNewEmailLabel)
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(.tidexTextSecondary)

        TextField(
          String(localized: .profileEmailChangeNewEmailPlaceholder), text: $viewModel.newEmail
        )
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
          Text(
            viewModel.isChangingEmail
              ? String(localized: .profileEmailChangeSending)
              : String(localized: .profileEmailChangeSendConfirmation))
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
        Text(.profileEmailChangeConfirmationSent)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.tidexTextPrimary)

        Text(.profileEmailChangeConfirmationMessage)
          .font(.system(size: 14))
          .foregroundColor(.tidexTextSecondary)
          .multilineTextAlignment(.center)
      }

      // Done button
      Button {
        viewModel.resetEmailChangeState()
      } label: {
        Text(.commonDone)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexBlue)
          .cornerRadius(10)
      }
    }
  }

  // MARK: - Avatar Section

  /// Button text for the photo picker - computed to avoid main actor issues in closure
  private var uploadButtonText: String {
    if viewModel.isUploadingAvatar {
      return String(localized: .profilePersonalInfoUploadingImage)
    } else if viewModel.profilePictureUrl != nil {
      return String(localized: .profilePersonalInfoChangeImage)
    } else {
      return String(localized: .profilePersonalInfoUploadImage)
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
              Text(.profilePersonalInfoRemoveImage)
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
      let url = URL(string: urlString)
    {
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
        Text(.profilePersonalInfoNameLabel)
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.tidexTextSecondary)

        Spacer()

        if viewModel.isSavingName {
          HStack(spacing: 4) {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextMuted))
              .scaleEffect(0.6)
            Text(.commonSaving)
              .font(.system(size: 12))
              .foregroundColor(.tidexTextMuted)
          }
        }
      }

      TextField(
        String(localized: .profilePersonalInfoNamePlaceholder), text: $viewModel.displayName
      )
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
        Text(.profilePersonalInfoEmailLabel)
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.tidexTextSecondary)

        Spacer()

        if viewModel.canChangeEmail {
          Button {
            viewModel.showEmailChangeSheet = true
          } label: {
            Text(.profileEmailChangeChangeButton)
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
        Text(.profileEmailChangeOauthOnlyHint)
          .font(.system(size: 12))
          .foregroundColor(.tidexTextMuted)
      } else if viewModel.canChangeEmail {
        Text(.profileEmailChangeCanChangeHint)
          .font(.system(size: 12))
          .foregroundColor(.tidexTextMuted)
      } else {
        Text(.profilePersonalInfoEmailHint)
          .font(.system(size: 12))
          .foregroundColor(.tidexTextMuted)
      }
    }
  }

  // MARK: - Danger Zone Section

  private var dangerZoneSection: some View {
    Section(
      header: Text(String(localized: .profileDangerZoneTitle))
        .foregroundColor(.tidexError)
    ) {
      Text(.profileDangerZoneSubtitle)
        .font(.system(size: 13))
        .foregroundColor(.tidexTextSecondary)

      // Delete account row
      HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text(.profileDangerZoneDeleteAccountTitle)
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.tidexTextPrimary)

          Text(.profileDangerZoneDeleteAccountDescription)
            .font(.system(size: 13))
            .foregroundColor(.tidexTextSecondary)
        }

        Spacer()

        Button {
          viewModel.showDeleteConfirmation = true
        } label: {
          Text(.profileDangerZoneDeleteAccountButton)
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
    .listRowBackground(Color.tidexSurfacePrimary)
  }

  // MARK: - Photo Selection Handler

  private func handlePhotoSelection(_ item: PhotosPickerItem?) async {
    guard let item = item else { return }

    do {
      // Load the image data
      guard let data = try await item.loadTransferable(type: Data.self) else {
        return
      }

      guard let uiImage = UIImage(data: data) else {
        return
      }

      // Show crop sheet with the selected image
      pendingImage = uiImage
      showCropSheet = true

      // Clear selection
      selectedPhotoItem = nil

    } catch {
      logger.error("Failed to load photo: \(error.localizedDescription)")
    }
  }

  /// Handle cropped image from crop sheet
  /// The image is already square from the crop view, just needs resize and compression
  private func handleCroppedImage(_ image: UIImage) async {
    // Resize to 192x192 square (matches server's AVATAR_SIZE for 2x retina)
    let avatarSize: CGFloat = 192

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: avatarSize, height: avatarSize))
    let resizedImage = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: CGSize(width: avatarSize, height: avatarSize)))
    }

    guard let compressedData = resizedImage.jpegData(compressionQuality: 0.8) else {
      logger.error("Failed to compress cropped image")
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
}
