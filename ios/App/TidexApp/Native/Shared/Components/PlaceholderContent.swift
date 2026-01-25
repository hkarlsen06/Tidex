import SwiftUI

/// Placeholder content for tabs under development
/// Displays a centered icon, title, and description
struct PlaceholderContent: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.tidexTextMuted)

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            Text(description)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }
}

/// Convenience view for placeholder screens using AppTab configuration
struct TabPlaceholder: View {
    @Environment(\.localization) private var localization

    let tab: AppTab

    var body: some View {
        GeometryReader { geometry in
            PlaceholderContent(
                icon: tab.icon,
                title: localization.string(tab.titleKey),
                description: localization.string(tab.descriptionKey)
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
    .environment(\.localization, LocalizationManager.shared)
}
