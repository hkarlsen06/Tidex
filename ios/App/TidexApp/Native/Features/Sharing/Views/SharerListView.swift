import SwiftUI

/// List of users who share their shifts with the current user
/// Sorts sharers by shift proximity to match Next.js behavior:
/// 1. Active shifts first (currently happening)
/// 2. Upcoming shifts next (soonest first)
/// 3. Past shifts next (most recent first)
/// 4. No shifts last
struct SharerListView: View {
    let sharers: [SharedUser]
    let selectedSharer: SharedUser?
    let shiftPreviews: [String: SharerShiftPreview]
    let isLoading: Bool
    let isLoadingPreviews: Bool
    let onSelectSharer: (SharedUser) -> Void

    @Environment(\.localization) private var localization

    /// Sharers sorted by shift proximity (matches Next.js SharersList.tsx sorting)
    private var sortedSharers: [SharedUser] {
        // If no previews loaded yet, return original order
        guard !shiftPreviews.isEmpty else { return sharers }

        return sharers.sorted { a, b in
            let previewA = shiftPreviews[a.id]
            let previewB = shiftPreviews[b.id]

            // Priority: active > upcoming > past > no shift
            let priorityA = statusPriority(for: previewA?.status)
            let priorityB = statusPriority(for: previewB?.status)

            if priorityA != priorityB {
                return priorityA < priorityB
            }

            // Within same status, sort by time
            guard let shiftA = previewA?.shift, let shiftB = previewB?.shift else {
                return false
            }

            let timeA = shiftStartTime(for: shiftA)
            let timeB = shiftStartTime(for: shiftB)

            guard let timeA = timeA, let timeB = timeB else { return false }

            switch previewA?.status {
            case .upcoming:
                // Upcoming: soonest first (ascending)
                return timeA < timeB
            case .past:
                // Past: most recent first (descending)
                return timeA > timeB
            default:
                return false
            }
        }
    }

    /// Get priority value for status (lower = higher priority)
    private func statusPriority(for status: ShiftPreviewStatus?) -> Int {
        switch status {
        case .active: return 0
        case .upcoming: return 1
        case .past: return 2
        case .none: return 3
        }
    }

    /// Parse shift start time for sorting
    private func shiftStartTime(for shift: SharedShiftData) -> Date? {
        guard let shiftDate = Date.fromISODateString(shift.shift_date) else { return nil }

        let components = shift.start_time.split(separator: ":").compactMap { Int($0) }
        guard components.count >= 2 else { return nil }

        return Calendar.current.date(
            bySettingHour: components[0],
            minute: components[1],
            second: 0,
            of: shiftDate
        )
    }

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

            // Sharers - sorted by shift proximity
            ForEach(sortedSharers) { sharer in
                SharerRow(
                    sharer: sharer,
                    preview: shiftPreviews[sharer.id],
                    isSelected: selectedSharer?.id == sharer.id,
                    isLoadingPreview: isLoadingPreviews && shiftPreviews[sharer.id] == nil,
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
        shiftPreviews: [:],
        isLoading: false,
        isLoadingPreviews: false,
        onSelectSharer: { _ in }
    )
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
