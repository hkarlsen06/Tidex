import PhotosUI
import SwiftUI
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "ProfileSettings")

/// Profile settings view
/// Profile picture, personal details, sign-in links, sessions and account deletion
struct ProfileSettingsView: View {
  @Environment(AppCoordinator.self) private var coordinator
  @Environment(\.dismiss) private var dismiss
  @State private var viewModel: ProfileSettingsViewModel

  private let onOpenSecurity: () -> Void

  init(
    viewModel: ProfileSettingsViewModel? = nil,
    onOpenSecurity: @escaping () -> Void = {}
  ) {
    _viewModel = State(wrappedValue: viewModel ?? ProfileSettingsViewModel())
    self.onOpenSecurity = onOpenSecurity
  }

  /// Photo picker selection
  @State private var selectedPhotoItem: PhotosPickerItem?
  /// Whether to show profile picture actions
  @State private var showAvatarActionDialog = false
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
  /// Whether sign out is in progress
  @State private var isSigningOut = false
  /// Whether global sign out is in progress
  @State private var isSigningOutGlobal = false
  /// Whether to show the global sign out confirmation alert
  @State private var showSignOutEverywhereAlert = false
  /// Whether to warn that signing out deletes unsynced changes
  @State private var showUnsyncedSignOutAlert = false
  /// Whether the unsynced-changes warning belongs to a global sign out
  @State private var unsyncedSignOutIsGlobal = false
  /// Whether to show the display name edit alert
  @State private var showNameEditAlert = false
  /// Whether to show the username edit alert
  @State private var showUsernameEditAlert = false
  /// Draft display name while the edit alert is open
  @State private var draftDisplayName = ""
  /// Draft username while the edit alert is open
  @State private var draftUsername = ""

  /// Prevent conflicting avatar modal presentations from rapid repeated taps
  private var isAvatarActionInProgress: Bool {
    viewModel.isUploadingAvatar || showAvatarActionDialog || showImageSourcePicker
      || showGalleryPicker
      || showCamera || showCropSheet
  }

  var body: some View {
    Form {
      Group {
        // Error banner (for avatar upload, name save, etc.)
        if let error = viewModel.errorMessage, viewModel.usernameErrorMessage == nil,
          !viewModel.showEmailChangeSheet
        {
          ErrorBanner(
            message: error,
            onDismiss: { viewModel.errorMessage = nil }
          )
        }

        profileHeaderSection
        personalInfoSection
        accountAccessSection
        sessionsSection
        dangerZoneSection
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
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
      String(localized: .profilePersonalInfoNameLabel),
      isPresented: $showNameEditAlert
    ) {
      TextField(
        String(localized: .profilePersonalInfoNamePlaceholder),
        text: $draftDisplayName
      )

      Button(String(localized: .commonCancel), role: .cancel) {
        draftDisplayName = viewModel.displayName
      }

      Button(String(localized: .commonSave)) {
        Task {
          await saveEditedName()
        }
      }
      .disabled(viewModel.isSavingName || viewModel.isOfflineProfileFallback)
    }
    .alert(
      String(localized: .profilePersonalInfoUsernameLabel),
      isPresented: $showUsernameEditAlert
    ) {
      TextField(
        String(localized: .profilePersonalInfoUsernamePlaceholder),
        text: $draftUsername
      )
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()

      Button(String(localized: .commonCancel), role: .cancel) {
        draftUsername = viewModel.username
      }

      Button(String(localized: .commonSave)) {
        Task {
          await saveEditedUsername()
        }
      }
      .disabled(viewModel.isSavingUsername || viewModel.isOfflineProfileFallback)
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
    .alert(
      String(localized: .userMenuLogoutEverywhereConfirmTitle),
      isPresented: $showSignOutEverywhereAlert
    ) {
      Button(String(localized: .userMenuLogoutEverywhereConfirmCancel), role: .cancel) {}
      Button(String(localized: .userMenuLogoutEverywhereConfirmAction), role: .destructive) {
        Task {
          await signOutGlobal()
        }
      }
    } message: {
      Text(.userMenuLogoutEverywhereConfirmDescription)
    }
    .alert(
      String(localized: .profileSignOutUnsyncedTitle),
      isPresented: $showUnsyncedSignOutAlert
    ) {
      Button(String(localized: .commonCancel), role: .cancel) {}
      Button(String(localized: .profileSignOutUnsyncedConfirm), role: .destructive) {
        Task {
          if unsyncedSignOutIsGlobal {
            await signOutGlobal(discardingUnsyncedChanges: true)
          } else {
            await signOut(discardingUnsyncedChanges: true)
          }
        }
      }
    } message: {
      Text(.profileSignOutUnsyncedMessage)
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
        .ignoresSafeArea()
      }
    }
    .sheet(isPresented: $viewModel.showEmailChangeSheet) {
      ProfileEmailChangeSheet(viewModel: viewModel)
    }
  }
}

extension ProfileSettingsView {
  // MARK: - Profile Header

  private var profileNameLabels: some View {
    VStack(spacing: Spacing.xxs) {
      Text(
        viewModel.displayName.isEmpty
          ? String(localized: .profilePersonalInfoNamePlaceholder)
          : viewModel.displayName
      )
      .font(.tidexTitle)
      .foregroundColor(viewModel.displayName.isEmpty ? .tidexTextMuted : .tidexTextPrimary)
      .multilineTextAlignment(.center)
      .lineLimit(2)

      if !viewModel.username.isEmpty {
        Text(usernameDisplayText)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
          .lineLimit(1)
      }
    }
  }

  private var profileHeaderSection: some View {
    Section {
      VStack(spacing: Spacing.sm) {
        ProfileAvatarButton(
          viewModel: viewModel,
          isDisabled: isAvatarActionInProgress || viewModel.isOfflineProfileFallback,
          showAvatarActionDialog: $showAvatarActionDialog,
          showImageSourcePicker: $showImageSourcePicker,
          showCamera: $showCamera,
          showGalleryPicker: $showGalleryPicker,
          selectedPhotoItem: $selectedPhotoItem,
          onTap: presentAvatarActionDialog,
          onChooseImageSource: presentImageSourcePicker
        )

        profileNameLabels
      }
      .frame(maxWidth: .infinity)
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())
    }
  }

  // MARK: - Personal Info Section

  private var personalInfoSection: some View {
    Section {
      ProfileValueRow(
        title: String(localized: .profilePersonalInfoNameLabel),
        value: viewModel.displayName,
        placeholder: String(localized: .profilePersonalInfoNamePlaceholder),
        isSaving: viewModel.isSavingName,
        action: viewModel.isOfflineProfileFallback ? nil : { startEditingName() }
      )

      ProfileValueRow(
        title: String(localized: .profilePersonalInfoUsernameLabel),
        value: viewModel.username.isEmpty ? "" : usernameDisplayText,
        placeholder: String(localized: .profilePersonalInfoUsernamePlaceholder),
        isSaving: viewModel.isSavingUsername,
        action: viewModel.isOfflineProfileFallback ? nil : { startEditingUsername() }
      )

      ProfileValueRow(
        title: String(localized: .profilePersonalInfoEmailLabel),
        value: viewModel.email,
        placeholder: "",
        isSaving: false,
        action: viewModel.canChangeEmail ? { viewModel.showEmailChangeSheet = true } : nil
      )
    } header: {
      Text(String(localized: .profilePersonalInfoTitle))
    } footer: {
      ProfilePersonalInfoFooter(viewModel: viewModel)
    }
  }

  private var usernameDisplayText: String {
    let username = viewModel.username.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !username.isEmpty else {
      return String(localized: .profilePersonalInfoUsernamePlaceholder)
    }
    return username.hasPrefix("@") ? username : "@\(username)"
  }

  private func startEditingName() {
    guard !viewModel.isOfflineProfileFallback else { return }
    draftDisplayName = viewModel.displayName
    showNameEditAlert = true
  }

  private func startEditingUsername() {
    guard !viewModel.isOfflineProfileFallback else { return }
    draftUsername = viewModel.username
    showUsernameEditAlert = true
  }

  private func saveEditedName() async {
    viewModel.displayName = draftDisplayName
    await viewModel.saveNameNow()
  }

  private func saveEditedUsername() async {
    viewModel.username = draftUsername
    viewModel.onUsernameChanged()
    await viewModel.saveUsernameNow()
  }

  // MARK: - Account Access Section

  private var accountAccessSection: some View {
    Section {
      Button(action: onOpenSecurity) {
        HStack(spacing: Spacing.sm) {
          Label(String(localized: .settingsMenuSecurityLabel), systemImage: "lock.shield")
            .foregroundColor(.tidexTextPrimary)

          Spacer(minLength: Spacing.sm)

          ProfileDisclosureChevron()
        }
        .contentShape(Rectangle())
      }
    }
  }

  // MARK: - Sessions Section

  private var sessionsSection: some View {
    Section(String(localized: .profileSessionsTitle)) {
      ProfileSignOutRow(
        isSigningOut: isSigningOut,
        isDisabled: isSigningOut || isSigningOutGlobal
      ) {
        Task {
          await signOut()
        }
      }

      ProfileSignOutEverywhereRow(
        isSigningOutGlobal: isSigningOutGlobal,
        isDisabled: isSigningOut || isSigningOutGlobal
      ) {
        showSignOutEverywhereAlert = true
      }
    }
  }

  // MARK: - Danger Zone Section

  private var dangerZoneSection: some View {
    ProfileDangerZoneSection(isDeleting: viewModel.isDeletingAccount) {
      viewModel.showDeleteConfirmation = true
    }
  }

  // MARK: - Actions

  private func presentAvatarActionDialog() {
    guard !isAvatarActionInProgress, !viewModel.isOfflineProfileFallback else { return }

    if viewModel.profilePictureUrl == nil {
      presentImageSourcePicker()
    } else {
      showAvatarActionDialog = true
    }
  }

  private func presentImageSourcePicker() {
    guard !viewModel.isOfflineProfileFallback, !viewModel.isUploadingAvatar,
      !showImageSourcePicker, !showGalleryPicker, !showCamera, !showCropSheet
    else {
      return
    }

    showAvatarActionDialog = false
    showImageSourcePicker = true
  }

  private func signOut(discardingUnsyncedChanges: Bool = false) async {
    isSigningOut = true
    if !discardingUnsyncedChanges, !(await coordinator.syncPendingChangesBeforeSignOut()) {
      isSigningOut = false
      unsyncedSignOutIsGlobal = false
      showUnsyncedSignOutAlert = true
      return
    }
    await coordinator.signOut()
    dismiss()
    isSigningOut = false
  }

  private func signOutGlobal(discardingUnsyncedChanges: Bool = false) async {
    isSigningOutGlobal = true
    if !discardingUnsyncedChanges, !(await coordinator.syncPendingChangesBeforeSignOut()) {
      isSigningOutGlobal = false
      unsyncedSignOutIsGlobal = true
      showUnsyncedSignOutAlert = true
      return
    }
    await coordinator.signOutGlobal()
    dismiss()
    isSigningOutGlobal = false
  }

  // MARK: - Photo Selection Handler

  private func handlePhotoSelection(_ item: PhotosPickerItem?) async {
    guard let item else { return }  // swiftlint:disable:this conditional_returns_on_newline

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

    let resizedImage = Self.resizedAvatarImage(image, to: avatarSize)

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
