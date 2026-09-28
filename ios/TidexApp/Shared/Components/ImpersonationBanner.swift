// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image closure_body_length explicit_acl explicit_top_level_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_type_interface file_types_order line_length multiline_arguments_brackets
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_empty_block no_magic_numbers number_separator
import SwiftUI

/// Banner displayed when an admin is impersonating another user
///
/// Shows the target user's name, session expiration, and a stop button.
/// Should be displayed at the top of the app when impersonation is active.
struct ImpersonationBanner: View {
  let targetName: String
  let expiresAt: Date?
  let onStop: () -> Void

  @State private var isLoading = false

  var body: some View {
    HStack(spacing: Spacing.sm) {
      // Warning icon
      Image(systemName: "person.crop.circle.badge.exclamationmark")
        .font(.system(size: 24))
        .foregroundStyle(Color.tidexWarning)

      // Info text
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(.impersonationBannerImpersonatingUser(targetName))
          .font(.tidexLabelStrong)
          .foregroundStyle(Color.tidexTextPrimary)

        if let expiresAt {
          ExpirationText(expiresAt: expiresAt)
        }
      }

      Spacer()

      // Stop button
      Button {
        isLoading = true
        onStop()
      } label: {
        if isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnDanger))
            .frame(width: 16, height: 16)
        } else {
          Text(.commonStop)
            .font(.tidexLabelStrong)
        }
      }
      .disabled(isLoading)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.xs)
      .background(Color.tidexError)
      .foregroundStyle(Color.tidexTextOnDanger)
      .cornerRadius(CornerRadius.sm)
    }
    .padding(Spacing.sm)
    .background(Color.tidexWarning.opacity(0.15))
    .overlay(
      Rectangle()
        .frame(height: 2)
        .foregroundStyle(Color.tidexWarning),
      alignment: .bottom
    )
  }
}

// MARK: - Expiration Text

/// Pure formatter for the impersonation session countdown text, kept separate from the
/// view so its text logic can be unit tested without going through `TimelineView`.
enum ImpersonationExpirationFormatter {
  static func text(remaining: TimeInterval) -> String {
    if remaining <= 0 {
      return String(localized: .impersonationBannerSessionExpiredState)
    }

    let hours = Int(remaining) / 3_600
    let minutes = (Int(remaining) % 3_600) / 60
    let seconds = Int(remaining) % 60

    if hours > 0 {
      return
        "\(String(localized: .impersonationBannerExpiresInPrefix)) \(hours)\(String(localized: .commonHoursShort)) \(minutes)\(String(localized: .commonMinutesShort))"
    } else if minutes > 0 {
      return String(
        localized: .impersonationBannerExpiresInMinutesSeconds(Int32(minutes), Int32(seconds)))
    } else {
      return String(localized: .impersonationBannerExpiresInSeconds(Int32(seconds)))
    }
  }
}

private struct ExpirationText: View {
  let expiresAt: Date

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let remaining = expiresAt.timeIntervalSince(context.date)
      Text(ImpersonationExpirationFormatter.text(remaining: remaining))
        .font(.tidexCaptionRegular)
        .foregroundStyle(remaining < 300 ? Color.tidexError : Color.tidexTextSecondary)
    }
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.mlg) {
    ImpersonationBanner(
      targetName: "John Doe",
      expiresAt: Date().addingTimeInterval(3_600),
      onStop: {}
    )

    ImpersonationBanner(
      targetName: "test@example.com",
      expiresAt: Date().addingTimeInterval(120),
      onStop: {}
    )

    ImpersonationBanner(
      targetName: "Long Username Here That Might Wrap",
      expiresAt: nil,
      onStop: {}
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
