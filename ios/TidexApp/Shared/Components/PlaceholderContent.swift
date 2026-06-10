// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image explicit_acl explicit_top_level_acl file_types_order
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers
import SwiftUI

/// Placeholder content for tabs under development
/// Displays a centered icon, title, and description
struct PlaceholderContent: View {
  let icon: String
  let title: String
  let description: String

  var body: some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: icon)
        .font(.system(size: 48))
        .foregroundColor(.tidexTextMuted)

      Text(title)
        .font(.tidexTitle2)
        .foregroundColor(.tidexTextPrimary)

      Text(description)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, Spacing.xxl)
  }
}

/// Convenience view for placeholder screens using AppTab configuration
struct TabPlaceholder: View {

  let tab: AppTab

  var body: some View {
    GeometryReader { geometry in
      PlaceholderContent(
        icon: tab.icon,
        title: String(localized: tab.titleKey),
        description: String(localized: tab.descriptionKey)
      )
      .frame(maxWidth: .infinity, minHeight: geometry.size.height - 200)
    }
  }
}

#Preview("PlaceholderContent") {
  ZStack {
    Color.tidexBackground.ignoresSafeArea()
    PlaceholderContent(
      icon: "calendar",
      title: "Shifts",
      description: "View and manage your work shifts"
    )
  }
}

#Preview("TabPlaceholder") {
  ZStack {
    Color.tidexBackground.ignoresSafeArea()
    TabPlaceholder(tab: .shifts)
  }
}
