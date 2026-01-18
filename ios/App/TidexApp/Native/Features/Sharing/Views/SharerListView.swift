import SwiftUI

/// List of users who share their shifts with the current user
struct SharerListView: View {
    let sharers: [SharedUser]
    let selectedSharer: SharedUser?
    let isLoading: Bool
    let onSelectSharer: (SharedUser) -> Void

    @Environment(\.localization) private var localization

    var body: some View {
        Group {
            if isLoading && sharers.isEmpty {
                loadingState
            } else if sharers.isEmpty {
                SharerListEmptyState()
            } else {
                sharersList
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text(localization.string("sharing.loading"))
                .font(.system(size: 15))
                .foregroundColor(.tidexTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 80)
    }

    private var sharersList: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text(localization.string("sharing.peopleWhoShareWithYou"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.tidexTextMuted)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            // Sharers
            ForEach(sharers) { sharer in
                SharerRow(
                    sharer: sharer,
                    isSelected: selectedSharer?.id == sharer.id,
                    onTap: {
                        onSelectSharer(sharer)
                    }
                )
            }
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    SharerListView(
        sharers: [
            SharedUser(
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
            SharedUser(
                id: "2",
                email: "jane@example.com",
                phone: nil,
                firstName: "Jane Smith",
                profilePictureUrl: nil,
                oauthAvatarUrl: nil,
                sharedAt: "2025-01-01",
                showEarnings: false,
                blocked: false
            )
        ],
        selectedSharer: nil,
        isLoading: false,
        onSelectSharer: { _ in }
    )
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
