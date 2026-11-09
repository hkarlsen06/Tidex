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
  @Binding var avatarFlow: AvatarFlow
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
              .fill(Color.black.opacity(0.45))

            ProgressView()
              .tint(.white)
          }
        }

        if !viewModel.isUploadingAvatar, !viewModel.isOfflineProfileFallback {
          Image(systemName: "camera.fill")
            .accessibilityHidden(true)
            .font(.system(size: ProfileAvatarLayout.cameraIconSize, weight: .semibold))
            .foregroundStyle(Color.tidexTextOnBrand)
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
    .onChange(of: viewModel.isUploadingAvatar) { _, isUploading in
      if isUploading {
        AccessibilityNotification.Announcement(
          String(localized: .profilePersonalInfoUploadingImage)
        ).post()
      } else if viewModel.errorMessage == nil {
        AccessibilityNotification.Announcement(
          String(localized: .settingsAccessibilityProfilePictureUpdated)
        ).post()
      }
    }
    .confirmationDialog(
      String(localized: .profilePersonalInfoProfilePicture),
      isPresented: $avatarFlow.isAt(.actions),
      titleVisibility: .visible
    ) {
      Button(uploadButtonText) {
        avatarFlow = .idle
        Task { @MainActor in
          await Task.yield()
          onChooseImageSource()
        }
      }

      if viewModel.profilePictureUrl != nil {
        Button(String(localized: .profilePersonalInfoRemoveImage), role: .destructive) {
          avatarFlow = .idle
          Task {
            await viewModel.removeProfilePicture()
          }
        }
      }

      Button(String(localized: .commonCancel), role: .cancel) {
        avatarFlow = .idle
      }
    }
    .confirmationDialog(
      String(localized: .profilePersonalInfoChooseImageSource),
      isPresented: $avatarFlow.isAt(.sourcePicker),
      titleVisibility: .visible
    ) {
      Button(String(localized: .profilePersonalInfoTakePhoto)) {
        avatarFlow = .idle
        Task { @MainActor in
          // Defer until dialog dismissal has settled.
          await Task.yield()
          avatarFlow = .camera
        }
      }
      Button(String(localized: .profilePersonalInfoChooseFromLibrary)) {
        avatarFlow = .idle
        Task { @MainActor in
          // Reset to ensure picker can always re-open after cancel.
          selectedPhotoItem = nil
          // Defer until dialog dismissal has settled.
          await Task.yield()
          avatarFlow = .library
        }
      }
      Button(String(localized: .commonCancel), role: .cancel) {
        avatarFlow = .idle
      }
    }
  }
}

/// The profile picture change, one step at a time, so rapid taps cannot stack dialogs or pickers.
enum AvatarFlow: Equatable {
  case idle
  case actions
  case sourcePicker
  case camera
  case library
  case cropping(UIImage)

  var imageToCrop: UIImage? {
    if case .cropping(let image) = self { return image }
    return nil
  }
}

extension Binding where Value == AvatarFlow {
  /// True while the flow is at `step`. Dismissing that step's dialog or picker returns to idle,
  /// unless the flow has already moved on.
  func isAt(_ step: AvatarFlow) -> Binding<Bool> {
    Binding<Bool>(
      get: { wrappedValue == step },
      set: { if !$0, wrappedValue == step { wrappedValue = .idle } }
    )
  }
}
