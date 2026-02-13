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

  /// Prevent conflicting avatar modal presentations from rapid repeated taps
  private var isAvatarActionInProgress: Bool {
    viewModel.isUploadingAvatar || showImageSourcePicker || showRemoveAvatarConfirmation || showGalleryPicker
      || showCamera || showCropSheet
  }

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
      VStack(spacing: Spacing.lg) {
        if viewModel.emailChangeSent {
          // Success state
          emailChangeSentView
        } else {
          // Input state
          emailChangeInputView
        }

        Spacer()
      }
      .padding(Spacing.lg)
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
    VStack(alignment: .leading, spacing: Spacing.mlg) {
      // Instructions
      Text(.profileEmailChangeInstructions)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)

      // Current email (read-only)
      VStack(alignment: .leading, spacing: Spacing.xxxs) {
        Text(.profileEmailChangeCurrentEmailLabel)
          .font(.tidexFootnoteMedium)
          .foregroundColor(.tidexTextSecondary)

        Text(viewModel.email)
          .font(.tidexBody)
          .foregroundColor(.tidexTextMuted)
          .padding(.horizontal, Spacing.sm)
          .padding(.vertical, Spacing.sm)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.tidexSurfaceSecondary.opacity(0.5))
          .cornerRadius(CornerRadius.sm)
      }

      // New email input
      VStack(alignment: .leading, spacing: Spacing.xxxs) {
        Text(.profileEmailChangeNewEmailLabel)
          .font(.tidexFootnoteMedium)
          .foregroundColor(.tidexTextSecondary)

        TextField(
          String(localized: .profileEmailChangeNewEmailPlaceholder), text: $viewModel.newEmail
        )
        .font(.tidexBody)
        .foregroundColor(.tidexTextPrimary)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(Color.tidexSurfaceSecondary)
        .cornerRadius(CornerRadius.sm)
      }

      // Error message
      if let error = viewModel.errorMessage {
        Text(error)
          .font(.tidexFootnote)
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
              .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
              .scaleEffect(0.8)
          }
          Text(
            viewModel.isChangingEmail
              ? String(localized: .profileEmailChangeSending)
              : String(localized: .profileEmailChangeSendConfirmation))
        }
        .font(.tidexButton)
        .foregroundColor(.tidexTextOnBrand)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(viewModel.newEmail.isEmpty ? Color.tidexBlue.opacity(0.5) : Color.tidexBlue)
        .cornerRadius(CornerRadius.md)
      }
      .disabled(viewModel.newEmail.isEmpty || viewModel.isChangingEmail)
    }
  }

  private var emailChangeSentView: some View {
    VStack(spacing: Spacing.mlg) {
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
      VStack(spacing: Spacing.xs) {
        Text(.profileEmailChangeConfirmationSent)
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextPrimary)

        Text(.profileEmailChangeConfirmationMessage)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
          .multilineTextAlignment(.center)
      }

      // Done button
      Button {
        viewModel.resetEmailChangeState()
      } label: {
        Text(.commonDone)
          .font(.tidexButton)
          .foregroundColor(.tidexTextOnBrand)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexBlue)
          .cornerRadius(CornerRadius.md)
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
    HStack(spacing: Spacing.xxxs) {
      if viewModel.isUploadingAvatar {
        ProgressView()
          .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
          .scaleEffect(0.8)
      } else {
        Image(systemName: "arrow.left.arrow.right")
          .font(.tidexCaption)
      }
      Text(uploadButtonText)
        .font(.tidexLabel)
    }
    .foregroundColor(.tidexBlue)
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xs)
    .background(Color.tidexBlue.opacity(0.1))
    .cornerRadius(CornerRadius.sm)
  }

  private var avatarSection: some View {
    HStack(spacing: Spacing.md) {
      // Avatar
      avatarView
        .frame(width: 80, height: 80)

      // Buttons
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Button {
          Task { @MainActor in
            showRemoveAvatarConfirmation = false
            await Task.yield()
            showImageSourcePicker = true
          }
        } label: {
          uploadButtonLabel
        }
        .disabled(isAvatarActionInProgress)
        .buttonStyle(.plain)
        .confirmationDialog(
          String(localized: .profilePersonalInfoChooseImageSource),
          isPresented: $showImageSourcePicker,
          titleVisibility: .visible
        ) {
          Button(String(localized: .profilePersonalInfoTakePhoto)) {
            showImageSourcePicker = false
            Task { @MainActor in
              // Defer until dialog dismissal has settled.
              await Task.yield()
              showCamera = false
              showCamera = true
            }
          }
          Button(String(localized: .profilePersonalInfoChooseFromLibrary)) {
            showImageSourcePicker = false
            Task { @MainActor in
              // Reset to ensure picker can always re-open after cancel.
              selectedPhotoItem = nil
              showGalleryPicker = false
              // Defer until dialog dismissal has settled.
              await Task.yield()
              showGalleryPicker = true
            }
          }
          Button(String(localized: .commonCancel), role: .cancel) {
            showImageSourcePicker = false
          }
        }

        if viewModel.profilePictureUrl != nil {
          Button {
            Task { @MainActor in
              showImageSourcePicker = false
              await Task.yield()
              showRemoveAvatarConfirmation = true
            }
          } label: {
            HStack(spacing: Spacing.xxxs) {
              Image(systemName: "trash")
                .font(.tidexCaption)
              Text(.profilePersonalInfoRemoveImage)
                .font(.tidexLabel)
            }
            .foregroundColor(.tidexError)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Color.tidexError.opacity(0.1))
            .cornerRadius(CornerRadius.sm)
          }
          .disabled(isAvatarActionInProgress)
          .buttonStyle(.plain)
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
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl))
    } else {
      initialAvatar
    }
  }

  private var initialAvatar: some View {
    ZStack {
      RoundedRectangle(cornerRadius: CornerRadius.xxl)
        .fill(Color.tidexBlue.opacity(0.2))

      Text(viewModel.initials)
        .font(.tidexLargeTitle)
        .foregroundColor(.tidexBlue)
    }
  }

  // MARK: - Name Field

  private var nameField: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack {
        Text(.profilePersonalInfoNameLabel)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        Spacer()

        if viewModel.isSavingName {
          HStack(spacing: Spacing.xxs) {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextMuted))
              .scaleEffect(0.6)
            Text(.commonSaving)
              .font(.tidexCaptionRegular)
              .foregroundColor(.tidexTextMuted)
          }
        }
      }

      TextField(
        String(localized: .profilePersonalInfoNamePlaceholder), text: $viewModel.displayName
      )
      .font(.tidexBody)
      .foregroundColor(.tidexTextPrimary)
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.sm)
      .background(Color.tidexSurfaceSecondary)
      .cornerRadius(CornerRadius.sm)
      .onChange(of: viewModel.displayName) { _, _ in
        viewModel.onNameChanged()
      }
    }
  }

  // MARK: - Email Field

  private var emailField: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack {
        Text(.profilePersonalInfoEmailLabel)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        Spacer()

        if viewModel.canChangeEmail {
          Button {
            viewModel.showEmailChangeSheet = true
          } label: {
            Text(.profileEmailChangeChangeButton)
              .font(.tidexFootnoteMedium)
              .foregroundColor(.tidexBlue)
          }
        }
      }

      HStack {
        Text(viewModel.email)
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        if !viewModel.canChangeEmail {
          Image(systemName: "lock.fill")
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
        }
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.sm)
      .background(Color.tidexSurfaceSecondary.opacity(0.5))
      .cornerRadius(CornerRadius.sm)

      // Show appropriate hint based on user's auth type
      if viewModel.isOAuthOnly {
        Text(.profileEmailChangeOauthOnlyHint)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
      } else if viewModel.canChangeEmail {
        Text(.profileEmailChangeCanChangeHint)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
      } else {
        Text(.profilePersonalInfoEmailHint)
          .font(.tidexCaptionRegular)
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
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)

      // Delete account row
      HStack(spacing: Spacing.md) {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(.profileDangerZoneDeleteAccountTitle)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextPrimary)

          Text(.profileDangerZoneDeleteAccountDescription)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
        }

        Spacer()

        Button {
          viewModel.showDeleteConfirmation = true
        } label: {
          Text(.profileDangerZoneDeleteAccountButton)
            .font(.tidexLabelStrong)
            .foregroundColor(.tidexTextOnDanger)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.tidexError)
            .cornerRadius(CornerRadius.sm)
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
