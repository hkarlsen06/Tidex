import SwiftUI

// MARK: - Friend Section Type

/// Identifies which section a friend row belongs to
enum FriendSectionType {
    case mutual        // Both share with each other
    case outgoing      // Only I share with them
    case incoming      // Only they share with me
}

// MARK: - Friend Row

/// A row displaying a friend in the sharing management modal
/// Shows different action buttons based on the relationship type
struct FriendRow: View {
    let friend: Friend
    let sectionType: FriendSectionType
    let isActionInProgress: Bool
    var isHighlighted: Bool = false
    let onToggleMuted: () -> Void
    let onToggleBlocked: () -> Void
    let onToggleEarnings: () -> Void
    let onShareBack: () -> Void
    let onRemove: () -> Void

    @Environment(\.localization) private var localization

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            avatarView

            // Name and contact info - with truncation fade effect
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.tidexTextPrimary)
                    .lineLimit(1)

                if let contactInfo = friend.contactInfo {
                    Text(contactInfo)
                        .font(.system(size: 13))
                        .foregroundColor(.tidexTextMuted)
                        .lineLimit(1)
                }
            }
            .truncationFade()

            Spacer(minLength: 8)

            // Action buttons based on section type
            actionButtons
                .layoutPriority(1) // Ensure buttons get priority over name
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(isActionInProgress ? 0.6 : 1.0)
        .background(
            // Highlight background for deep link navigation
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.tidexBlue.opacity(isHighlighted ? 0.15 : 0))
                .animation(.easeInOut(duration: 0.8).repeatCount(3, autoreverses: true), value: isHighlighted)
        )
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatarView: some View {
        if let urlString = friend.avatarUrl, let url = URL(string: urlString) {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } placeholder: {
                initialsAvatar
            }
        } else {
            initialsAvatar
        }
    }

    private var initialsAvatar: some View {
        Circle()
            .fill(Color.tidexBlue.opacity(0.2))
            .frame(width: 40, height: 40)
            .overlay(
                Text(friend.initials)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexBlue)
            )
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            switch sectionType {
            case .mutual:
                // Mute, Block, Earnings, Remove
                muteButton
                blockButton
                earningsToggle
                removeButton

            case .outgoing:
                // Earnings, Remove
                earningsToggle
                removeButton

            case .incoming:
                // Mute, Block, Share Back, Remove
                muteButton
                blockButton
                shareBackButton
                removeButton
            }
        }
    }

    // MARK: - Individual Buttons

    private var muteButton: some View {
        Button(action: onToggleMuted) {
            Image(systemName: friend.sharesWithMe?.isMuted == true ? "bell.slash.fill" : "bell.fill")
                .font(.system(size: 16))
                .foregroundColor(friend.sharesWithMe?.isMuted == true ? .tidexTextMuted : .tidexBlue)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isActionInProgress)
    }

    private var blockButton: some View {
        Button(action: onToggleBlocked) {
            Image(systemName: friend.sharesWithMe?.blocked == true ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 16))
                .foregroundColor(friend.sharesWithMe?.blocked == true ? .red : .tidexBlue)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isActionInProgress)
    }

    private var earningsToggle: some View {
        HStack(spacing: 4) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.tidexBlue)

            Toggle("", isOn: .init(
                get: { friend.iShareWith?.showEarningsToThem ?? false },
                set: { _ in onToggleEarnings() }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: .tidexBlue))
            .scaleEffect(0.8)
        }
        .disabled(isActionInProgress)
    }

    private var shareBackButton: some View {
        Button(action: onShareBack) {
            Text(localization.string("sharing.shareBack"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(Color.tidexBlue)
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isActionInProgress)
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "trash")
                .font(.system(size: 14))
                .foregroundColor(.red.opacity(0.8))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isActionInProgress)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        FriendRow(
            friend: Friend(
                id: "1",
                email: "ole@example.com",
                phone: nil,
                firstName: "Ole Hansen",
                profilePictureUrl: nil,
                oauthAvatarUrl: nil,
                sharesWithMe: Friend.SharesWithMe(
                    blocked: false,
                    showEarningsToMe: true,
                    sharedAt: "2025-01-01",
                    notificationFrequency: "instant"
                ),
                iShareWith: Friend.IShareWith(
                    showEarningsToThem: true,
                    sharedAt: "2025-01-01"
                )
            ),
            sectionType: .mutual,
            isActionInProgress: false,
            onToggleMuted: {},
            onToggleBlocked: {},
            onToggleEarnings: {},
            onShareBack: {},
            onRemove: {}
        )

        Divider()
            .padding(.leading, 68)

        FriendRow(
            friend: Friend(
                id: "2",
                email: "kari@example.com",
                phone: nil,
                firstName: "Kari Berg",
                profilePictureUrl: nil,
                oauthAvatarUrl: nil,
                sharesWithMe: nil,
                iShareWith: Friend.IShareWith(
                    showEarningsToThem: false,
                    sharedAt: "2025-01-01"
                )
            ),
            sectionType: .outgoing,
            isActionInProgress: false,
            onToggleMuted: {},
            onToggleBlocked: {},
            onToggleEarnings: {},
            onShareBack: {},
            onRemove: {}
        )

        Divider()
            .padding(.leading, 68)

        FriendRow(
            friend: Friend(
                id: "3",
                email: "lisa@example.com",
                phone: nil,
                firstName: "Lisa Olsen",
                profilePictureUrl: nil,
                oauthAvatarUrl: nil,
                sharesWithMe: Friend.SharesWithMe(
                    blocked: false,
                    showEarningsToMe: false,
                    sharedAt: "2025-01-01",
                    notificationFrequency: "muted"
                ),
                iShareWith: nil
            ),
            sectionType: .incoming,
            isActionInProgress: false,
            onToggleMuted: {},
            onToggleBlocked: {},
            onToggleEarnings: {},
            onShareBack: {},
            onRemove: {}
        )
    }
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(12)
    .padding()
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
