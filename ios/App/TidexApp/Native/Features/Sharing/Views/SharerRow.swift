import SwiftUI

/// A row displaying a user who shares their shifts with the current user
struct SharerRow: View {
    let sharer: SharedUser
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.localization) private var localization

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                avatarView

                // Name and status
                VStack(alignment: .leading, spacing: 2) {
                    Text(sharer.displayName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.tidexTextPrimary)

                    // Show earnings visibility status
                    HStack(spacing: 4) {
                        Image(systemName: sharer.showEarnings ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 12))
                        Text(sharer.showEarnings
                            ? localization.string("sharing.earningsVisible")
                            : localization.string("sharing.earningsHidden"))
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.tidexTextMuted)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.tidexBlue.opacity(0.1) : Color.tidexSurfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? Color.tidexBlue : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var avatarView: some View {
        if let urlString = sharer.avatarUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                case .failure, .empty:
                    initialsAvatar
                @unknown default:
                    initialsAvatar
                }
            }
        } else {
            initialsAvatar
        }
    }

    private var initialsAvatar: some View {
        Circle()
            .fill(Color.tidexBlue.opacity(0.2))
            .frame(width: 44, height: 44)
            .overlay(
                Text(sharer.initials)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexBlue)
            )
    }
}

// MARK: - Empty State

/// Shown when no one has shared shifts with the user
struct SharerListEmptyState: View {
    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundColor(.tidexTextMuted)

            Text(localization.string("sharing.noSharers"))
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.tidexTextPrimary)

            Text(localization.string("sharing.noSharersDescription"))
                .font(.system(size: 15))
                .foregroundColor(.tidexTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 80)
    }
}

#Preview {
    VStack(spacing: 16) {
        SharerRow(
            sharer: SharedUser(
                id: "1",
                email: "john@example.com",
                phone: nil,
                firstName: "John Doe",
                profilePictureUrl: nil,
                oauthAvatarUrl: nil,
                sharedAt: "2025-01-01",
                showEarnings: true,
                blocked: false
            ),
            isSelected: false,
            onTap: {}
        )

        SharerRow(
            sharer: SharedUser(
                id: "2",
                email: "jane@example.com",
                phone: nil,
                firstName: "Jane",
                profilePictureUrl: nil,
                oauthAvatarUrl: nil,
                sharedAt: "2025-01-01",
                showEarnings: false,
                blocked: false
            ),
            isSelected: true,
            onTap: {}
        )
    }
    .padding()
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
