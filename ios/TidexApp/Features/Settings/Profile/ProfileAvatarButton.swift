import PhotosUI
import SwiftUI

private enum ProfileAvatarLayout {
  static let size: CGFloat = 96
  static let cameraBadgeSize: CGFloat = 32
  static let cameraIconSize: CGFloat = 13
}

/// Tappable profile picture with the dialogs for changing or removing it.
/// The parent owns the presentation state so it can also show the pickers.
struct ProfileAvatarButton: View {
  let viewModel: ProfileSettingsViewModel
  let isDisabled: Bool
  @Binding var showAvatarActionDialog: Bool
  @Binding var showImageSourcePicker: Bool
  @Binding var showCamera: Bool
  @Binding var showGalleryPicker: Bool
  @Binding var selectedPhotoItem: PhotosPickerItem?
  let onTap: () -> Void
  let onChooseImageSource: () -> Void

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

  var body: some View {
    Button {
      onTap()
    } label: {
      ZStack(alignment: .bottomTrailing) {
        ProfileAvatarImage(
          profilePictureUrl: viewModel.profilePictureUrl,
          initials: viewModel.initials
        )
        .frame(width: ProfileAvatarLayout.size, height: ProfileAvatarLayout.size)
        .overlay {
          if viewModel.isUploadingAvatar {
            RoundedRectangle(cornerRadius: CornerRadius.xxl)
              .fill(Color.tidexTextPrimary.opacity(0.28))

            ProgressView()
              .tint(.white)
          }
        }

        if !viewModel.isUploadingAvatar, !viewModel.isOfflineProfileFallback {
          Image(systemName: "camera.fill")
            .accessibilityHidden(true)
            .font(.system(size: ProfileAvatarLayout.cameraIconSize, weight: .semibold))
            .foregroundColor(.tidexTextOnBrand)
            .frame(
              width: ProfileAvatarLayout.cameraBadgeSize,
              height: ProfileAvatarLayout.cameraBadgeSize
            )
            .background(Color.tidexBlue, in: Circle())
            .overlay(Circle().stroke(Color.tidexBackground, lineWidth: 3))
            .offset(x: 6, y: 6)
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: CornerRadius.xxl))
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .accessibilityLabel(Text(.profilePersonalInfoProfilePicture))
    .accessibilityHint(Text(uploadButtonText))
    .confirmationDialog(
      String(localized: .profilePersonalInfoProfilePicture),
      isPresented: $showAvatarActionDialog,
      titleVisibility: .visible
    ) {
      Button(uploadButtonText) {
        showAvatarActionDialog = false
        Task { @MainActor in
          await Task.yield()
          onChooseImageSource()
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
  }
}
