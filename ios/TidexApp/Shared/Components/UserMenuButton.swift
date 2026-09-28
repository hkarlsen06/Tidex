// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface no_magic_numbers
import SwiftUI

/// Toolbar button that shows a person's first name and avatar.
/// Used for friends in chat and calendar screens.
struct UserMenuButton: View {
  /// User's display name (email or name from profile)
  let displayName: String
  /// Optional profile picture URL
  let avatarUrl: String?
  /// Whether the button responds to taps (false renders a plain label)
  var interactive: Bool = true
  /// Tap action
  var onTap: (() -> Void)?

  var body: some View {
    if interactive {
      Button {
        onTap?()
      } label: {
        menuButton
      }
    } else {
      menuButton
    }
  }

  // MARK: - Computed Properties

  /// Extract first name only from display name
  private var firstName: String {
    displayName.components(separatedBy: " ").first ?? displayName
  }

  private var avatarInitial: String {
    String(displayName.prefix(1)).uppercased()
  }

  // MARK: - Menu Button Label

  private var menuButton: some View {
    HStack(spacing: Spacing.xs) {
      // First name only, truncates if too long
      Text(firstName)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextPrimary)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: 80)  // Limit text width to prevent overly long names

      // Profile picture or initial
      AvatarView(
        url: avatarUrl,
        initials: avatarInitial,
        size: AvatarView.Size.small,
        cornerRadius: CornerRadius.md
      )
      .accessibilityHidden(true)
    }
    .padding(.leading, Spacing.xxxs)
    .padding(.trailing, Spacing.xxs)
    .padding(.vertical, Spacing.xxs)
    .frame(minHeight: 44)
    .contentShape(Rectangle())
    // Fixed height prevents toolbar layout shifts on iPad
    .iPadFixedHeight(44)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Preview

#Preview {
  ZStack {
    Color.tidexBackground
      .ignoresSafeArea()

    VStack(spacing: Spacing.mlg) {
      // Shows "John"
      UserMenuButton(
        displayName: "John Doe",
        avatarUrl: nil
      )

      // Shows "jane@exam…" (truncated by frame constraint)
      UserMenuButton(
        displayName: "jane@example.com",
        avatarUrl: "https://example.com/avatar.jpg"
      )

      // Shows "Hjalmar"
      UserMenuButton(
        displayName: "Hjalmar Karlsen",
        avatarUrl: nil
      )

      // Shows "Christoph…" (truncated by frame constraint)
      UserMenuButton(
        displayName: "Christopherson McAllister",
        avatarUrl: nil
      )
    }
  }
  .environment(AppCoordinator.shared)
}
