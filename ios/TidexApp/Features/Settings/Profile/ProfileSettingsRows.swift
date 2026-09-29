import SwiftUI

/// Chevron shown on the trailing side of rows that open something.
struct ProfileDisclosureChevron: View {
  var body: some View {
    Image(systemName: "chevron.forward")
      .font(.tidexCaptionRegular)
      .foregroundColor(.tidexTextMuted)
      .accessibilityHidden(true)
  }
}

/// A title with its current value on the trailing side.
/// Rows without an action show a lock instead of a chevron.
struct ProfileValueRow: View {
  let title: String
  let value: String
  let placeholder: String
  let isSaving: Bool
  let action: (() -> Void)?

  var body: some View {
    let content = HStack(spacing: Spacing.sm) {
      Text(title)
        .foregroundColor(.tidexTextPrimary)

      Spacer(minLength: Spacing.sm)

      Text(value.isEmpty ? placeholder : value)
        .foregroundColor(value.isEmpty ? .tidexTextMuted : .tidexTextSecondary)
        .lineLimit(1)
        .truncationMode(.middle)

      if isSaving {
        ProgressView()
          .controlSize(.small)
      } else if action != nil {
        ProfileDisclosureChevron()
      } else {
        Image(systemName: "lock.fill")
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
          .accessibilityHidden(true)
      }
    }
    .contentShape(Rectangle())

    return Group {
      if let action {
        Button(action: action) { content }
          .disabled(isSaving)
      } else {
        content
          .accessibilityElement(children: .combine)
      }
    }
  }
}

/// Explains why the personal info rows are read-only, or shows the username error.
struct ProfilePersonalInfoFooter: View {
  let viewModel: ProfileSettingsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      if let error = viewModel.usernameErrorMessage {
        Text(error)
          .foregroundColor(.tidexError)
      }

      if viewModel.isOfflineProfileFallback {
        Text(.profileOfflineEditingUnavailable)
      } else if viewModel.isOAuthOnly {
        Text(.profileEmailChangeOauthOnlyHint)
      } else if !viewModel.canChangeEmail {
        Text(.profilePersonalInfoEmailHint)
      }
    }
  }
}

/// The profile picture, or the user's initials when there is none.
struct ProfileAvatarImage: View {
  @Environment(\.displayScale) private var displayScale

  let profilePictureUrl: String?
  let initials: String

  var body: some View {
    if let urlString = profilePictureUrl,
      let url = URL(string: urlString)
    {
      CachedAsyncImage(
        url: url,
        maxPixelSize: 192 * displayScale,
        content: { image in
          image
            .resizable()
            .scaledToFill()
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

      Text(initials)
        .font(.tidexLargeTitle)
        .foregroundColor(.tidexBlue)
    }
  }
}

/// Sign out of this device.
struct ProfileSignOutRow: View {
  let isSigningOut: Bool
  let isDisabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      // Signing out of this device is routine and keeps the account, so only the
      // everywhere action below uses a destructive role.
      if isSigningOut {
        Label {
          Text(.userMenuLoggingOut)
        } icon: {
          ProgressView().controlSize(.small)
        }
      } else {
        Label(String(localized: .userMenuLogout), systemImage: "rectangle.portrait.and.arrow.right")
      }
    }
    .disabled(isDisabled)
  }
}

/// Sign out of every device.
struct ProfileSignOutEverywhereRow: View {
  let isSigningOutGlobal: Bool
  let isDisabled: Bool
  let action: () -> Void

  var body: some View {
    Button(role: .destructive, action: action) {
      if isSigningOutGlobal {
        Label {
          Text(.userMenuLogoutEverywhereLoading)
        } icon: {
          ProgressView().controlSize(.small)
        }
      } else {
        Label(
          String(localized: .userMenuLogoutEverywhere),
          systemImage: "rectangle.portrait.and.arrow.right.fill"
        )
      }
    }
    .disabled(isDisabled)
  }
}

/// Account deletion button with its explanation.
struct ProfileDangerZoneSection: View {
  let isDeleting: Bool
  let onDelete: () -> Void

  var body: some View {
    Section {
      Button(role: .destructive, action: onDelete) {
        HStack(spacing: Spacing.xs) {
          if isDeleting {
            ProgressView()
              .controlSize(.small)
          }

          Text(.profileDangerZoneDeleteAccountButton)
        }
        .frame(maxWidth: .infinity)
      }
      .disabled(isDeleting)
    } footer: {
      Text(.profileDangerZoneDeleteAccountDescription)
    }
  }
}
