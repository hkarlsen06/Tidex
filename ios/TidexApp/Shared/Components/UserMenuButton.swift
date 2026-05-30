import SwiftUI

/// A user menu button that displays the user's profile picture and name,
/// with a dropdown menu for accessing settings and other quick actions.
/// Inspired by the web UserMenu component.
struct UserMenuButton: View {
  // Theme is handled at UIKit window level - sheets inherit from window

  /// User's display name (email or name from profile)
  let displayName: String
  /// Optional profile picture URL
  let avatarUrl: String?
  /// Whether tapping opens settings (true) or is display-only (false)
  var interactive: Bool = true
  /// Optional custom tap action. When provided, overrides the default settings behavior.
  var onTap: (() -> Void)?
  /// Whether to show the settings sheet
  @State private var showSettings = false

  var body: some View {
    if interactive {
      Button {
        if let onTap {
          onTap()
        } else {
          showSettings = true
        }
      } label: {
        menuButton
      }
      .sheet(isPresented: $showSettings) {
        SettingsView()
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
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
  .environmentObject(AppCoordinator.shared)
}
