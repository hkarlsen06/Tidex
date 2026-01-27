import SwiftUI

/// Reusable avatar component with image loading and initials fallback
/// Used across Friends tab, Sharing views, and profile displays
struct AvatarView: View {
    let url: String?
    let initials: String
    let size: CGFloat

    /// Standard avatar sizes for consistency
    enum Size {
        /// Small avatar (28pt) - used in toolbars
        static let small: CGFloat = 28
        /// Medium avatar (40pt) - used in list rows
        static let medium: CGFloat = 40
        /// Large avatar (44pt) - used in cards
        static let large: CGFloat = 44
    }

    var body: some View {
        if let urlString = url, let imageUrl = URL(string: urlString) {
            CachedAsyncImage(url: imageUrl) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } placeholder: {
                initialsView
            }
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        Circle()
            .fill(Color.tidexBlue.opacity(0.2))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(.tidexBlue)
            )
    }

    /// Calculate appropriate font size based on avatar size
    private var fontSize: CGFloat {
        // Scale font relative to avatar size (roughly 35% of avatar size)
        max(10, size * 0.35)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // With image URL
        AvatarView(
            url: "https://example.com/avatar.jpg",
            initials: "JD",
            size: AvatarView.Size.large
        )

        // With initials (no URL)
        HStack(spacing: 16) {
            AvatarView(url: nil, initials: "JD", size: AvatarView.Size.small)
            AvatarView(url: nil, initials: "AB", size: AvatarView.Size.medium)
            AvatarView(url: nil, initials: "XY", size: AvatarView.Size.large)
        }

        // Various initials
        HStack(spacing: 16) {
            AvatarView(url: nil, initials: "O", size: AvatarView.Size.medium)
            AvatarView(url: nil, initials: "KH", size: AvatarView.Size.medium)
            AvatarView(url: nil, initials: "?", size: AvatarView.Size.medium)
        }
    }
    .padding()
    .background(Color.tidexBackground)
}
