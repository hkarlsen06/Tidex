import PhotosUI
import SwiftUI
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "ProfileSettings")

private enum ProfileActionRowLayout {
  static let rowHeight: CGFloat = 48
  static let iconSize: CGFloat = 32
  static let horizontalPadding: CGFloat = Spacing.md
  static var dividerLeadingPadding: CGFloat { horizontalPadding + iconSize + Spacing.sm }
}

private enum ProfileAvatarLayout {
  static let size: CGFloat = 80
  static let cameraBadgeSize: CGFloat = 30
  static let cameraIconSize: CGFloat = 10
}

/// Profile settings view
/// Displays profile picture, name, email, and danger zone (delete account)
struct ProfileSettingsView: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @Environment(\.dismiss) private var dismiss
  @Environment(\.displayScale) private var displayScale
  @StateObject private var viewModel = ProfileSettingsViewModel()

  private let onOpenSecurity: () -> Void

  init(onOpenSecurity: @escaping () -> Void = {}) {
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
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        // Error banner (for avatar upload, name save, etc.)
        if let error = viewModel.errorMessage, viewModel.usernameErrorMessage == nil,
          !viewModel.showEmailChangeSheet
        {
          ErrorBanner(
            message: error,
            onDismiss: { viewModel.errorMessage = nil }
          )
        }

        // Personal Info Section
        settingsSection(title: String(localized: .profilePersonalInfoTitle)) {
          avatarSection
          settingsDivider
          emailField
        }

        accountAccessSection
        sessionsSection
        dangerZoneSection
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.lg)
    }
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
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

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
    }
    if viewModel.profilePictureUrl != nil {
      return String(localized: .profilePersonalInfoChangeImage)
    }
    return String(localized: .profilePersonalInfoUploadImage)
  }

  private var avatarSection: some View {
    HStack(spacing: Spacing.md) {
      ZStack(alignment: .bottomTrailing) {
        Button {
          presentAvatarActionDialog()
        } label: {
          avatarView
            .frame(width: ProfileAvatarLayout.size, height: ProfileAvatarLayout.size)
        }
        .disabled(isAvatarActionInProgress || viewModel.isOfflineProfileFallback)
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.profilePersonalInfoProfilePicture))
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.xxl))

        if viewModel.isUploadingAvatar {
          RoundedRectangle(cornerRadius: CornerRadius.xxl)
            .fill(Color.tidexTextPrimary.opacity(0.28))
            .frame(width: ProfileAvatarLayout.size, height: ProfileAvatarLayout.size)

          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
        } else {
          Button {
            presentImageSourcePicker()
          } label: {
            Image(systemName: "camera.fill")
              .font(.system(size: ProfileAvatarLayout.cameraIconSize, weight: .semibold))
              .foregroundColor(.tidexTextOnBrand)
              .frame(
                width: ProfileAvatarLayout.cameraBadgeSize,
                height: ProfileAvatarLayout.cameraBadgeSize
              )
              .background(Color.tidexBlue)
              .clipShape(Circle())
              .overlay(
                Circle()
                  .stroke(Color.tidexSurfacePrimary, lineWidth: 2)
              )
          }
          .disabled(isAvatarActionInProgress || viewModel.isOfflineProfileFallback)
          .buttonStyle(.plain)
          .accessibilityLabel(Text(uploadButtonText))
        }
      }
      .confirmationDialog(
        String(localized: .profilePersonalInfoProfilePicture),
        isPresented: $showAvatarActionDialog,
        titleVisibility: .visible
      ) {
        Button(uploadButtonText) {
          showAvatarActionDialog = false
          Task { @MainActor in
            await Task.yield()
            presentImageSourcePicker()
          }
        }

        if viewModel.profilePictureUrl != nil {
          Button(String(localized: .profilePersonalInfoRemoveImage), role: .destructive) {
            showAvatarActionDialog = false
            Task {
              await viewModel.removeProfilePicture()
            }
          }
        }

        Button(String(localized: .commonCancel), role: .cancel) {
          showAvatarActionDialog = false
        }
      }
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

      VStack(alignment: .leading, spacing: 0) {
        profileNameRow
        profileUsernameRow

        if viewModel.isOfflineProfileFallback {
          Text(.profileOfflineEditingUnavailable)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let error = viewModel.usernameErrorMessage {
          Text(error)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexError)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .opacity(viewModel.isOfflineProfileFallback ? 0.65 : 1)
  }

  private var profileNameRow: some View {
    HStack(spacing: Spacing.xs) {
      Text(
        viewModel.displayName.isEmpty
          ? String(localized: .profilePersonalInfoNamePlaceholder)
          : viewModel.displayName
      )
      .font(.tidexTitle)
      .foregroundColor(viewModel.displayName.isEmpty ? .tidexTextMuted : .tidexTextPrimary)
      .lineLimit(2)
      .fixedSize(horizontal: false, vertical: true)
      .minimumScaleFactor(0.85)
      .layoutPriority(1)

      profileEditAccessory(isSaving: viewModel.isSavingName, font: .tidexSubheadline) {
        startEditingName()
      }

      Spacer(minLength: Spacing.xs)
    }
    .disabled(viewModel.isOfflineProfileFallback)
  }

  private var profileUsernameRow: some View {
    HStack(spacing: Spacing.xs) {
      Text(usernameDisplayText)
        .font(.tidexSubheadline)
        .foregroundColor(viewModel.username.isEmpty ? .tidexTextMuted : .tidexTextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)

      profileEditAccessory(isSaving: viewModel.isSavingUsername, font: .tidexSubheadline) {
        startEditingUsername()
      }

      Spacer(minLength: Spacing.xs)
    }
    .disabled(viewModel.isOfflineProfileFallback)
  }

  private var usernameDisplayText: String {
    let username = viewModel.username.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !username.isEmpty else {
      return String(localized: .profilePersonalInfoUsernamePlaceholder)
    }
    return username.hasPrefix("@") ? username : "@\(username)"
  }

  private func profileEditAccessory(
    isSaving: Bool,
    font: Font,
    onEdit: @escaping () -> Void
  ) -> some View {
    Group {
      if isSaving {
        ProgressView()
          .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextMuted))
          .scaleEffect(0.6)
      } else {
        Button(action: onEdit) {
          Image(systemName: "pencil")
            .font(font)
            .foregroundColor(.tidexTextPrimary)
        }
        .buttonStyle(.plain)
      }
    }
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

  @ViewBuilder
  private var avatarView: some View {
    if let urlString = viewModel.profilePictureUrl,
      let url = URL(string: urlString)
    {
      CachedAsyncImage(
        url: url,
        maxPixelSize: 192 * displayScale,
        content: { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        },
        placeholder: {
          initialAvatar
            .overlay(
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
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

  // MARK: - Account Access Section

  private var accountAccessSection: some View {
    TidexSettingsSection(
      title: String(localized: .profileAccountAccessTitle),
      contentPadding: 0
    ) {
      VStack(alignment: .leading, spacing: 0) {
        settingsNavigationRow(
          icon: "lock.shield",
          title: String(localized: .settingsMenuSecurityLabel),
          tint: .tidexBlue,
          action: onOpenSecurity
        )
      }
    }
  }

  // MARK: - Sessions Section

  private var sessionsSection: some View {
    TidexSettingsSection(
      title: String(localized: .profileSessionsTitle),
      contentPadding: 0
    ) {
      VStack(alignment: .leading, spacing: 0) {
        signOutRow
        compactSettingsDivider
        signOutEverywhereRow
      }
    }
  }

  private var signOutRow: some View {
    Button {
      Task {
        await signOut()
      }
    } label: {
      HStack(spacing: Spacing.sm) {
        TidexSettingsIcon(
          systemName: "rectangle.portrait.and.arrow.right",
          foregroundColor: .tidexError,
          size: ProfileActionRowLayout.iconSize
        )

        if isSigningOut {
          ProgressView()
            .controlSize(.small)
            .tint(.tidexError)
          Text(.userMenuLoggingOut)
            .font(.tidexBody)
            .foregroundColor(.tidexError)
        } else {
          Text(.userMenuLogout)
            .font(.tidexBody)
            .foregroundColor(.tidexError)
        }

        Spacer()
      }
      .padding(.horizontal, ProfileActionRowLayout.horizontalPadding)
      .frame(minHeight: ProfileActionRowLayout.rowHeight)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isSigningOut || isSigningOutGlobal)
  }

  private var signOutEverywhereRow: some View {
    Button {
      showSignOutEverywhereAlert = true
    } label: {
      HStack(spacing: Spacing.sm) {
        TidexSettingsIcon(
          systemName: "rectangle.portrait.and.arrow.right.fill",
          foregroundColor: .tidexError,
          size: ProfileActionRowLayout.iconSize
        )

        if isSigningOutGlobal {
          ProgressView()
            .controlSize(.small)
            .tint(.tidexError)
          Text(.userMenuLogoutEverywhereLoading)
            .font(.tidexBody)
            .foregroundColor(.tidexError)
        } else {
          Text(.userMenuLogoutEverywhere)
            .font(.tidexBody)
            .foregroundColor(.tidexError)
        }

        Spacer()
      }
      .padding(.horizontal, ProfileActionRowLayout.horizontalPadding)
      .frame(minHeight: ProfileActionRowLayout.rowHeight)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isSigningOut || isSigningOutGlobal)
  }

  private func settingsNavigationRow(
    icon: String,
    title: String,
    tint: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: Spacing.sm) {
        TidexSettingsIcon(
          systemName: icon,
          foregroundColor: tint,
          size: ProfileActionRowLayout.iconSize
        )

        Text(title)
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Image(systemName: "chevron.right")
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
      }
      .padding(.horizontal, ProfileActionRowLayout.horizontalPadding)
      .frame(minHeight: ProfileActionRowLayout.rowHeight)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  // MARK: - Danger Zone Section

  private var dangerZoneSection: some View {
    settingsSection(
      title: String(localized: .profileDangerZoneTitle),
      titleColor: .tidexTextSecondary
    ) {
      Text(.profileDangerZoneSubtitle)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)

      settingsDivider

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
            .font(.tidexLabel)
            .foregroundColor(.tidexError)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.tidexError.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .stroke(Color.tidexError.opacity(0.18), lineWidth: 1)
            }
        }
        .disabled(viewModel.isDeletingAccount)
        .opacity(viewModel.isDeletingAccount ? 0.55 : 1)
      }
    }
  }

  @ViewBuilder
  private func settingsSection<Content: View>(
    title: String,
    titleColor: Color = .tidexTextSecondary,
    @ViewBuilder content: () -> Content
  ) -> some View {
    TidexSettingsSection(title: title, titleColor: titleColor) {
      VStack(alignment: .leading, spacing: 0) {
        content()
      }
    }
  }

  private var settingsDivider: some View {
    TidexSettingsDivider()
  }

  private var compactSettingsDivider: some View {
    Divider()
      .background(Color.tidexSeparator)
      .padding(.leading, ProfileActionRowLayout.dividerLeadingPadding)
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
