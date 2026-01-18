import SwiftUI

/// A row displaying a user who shares their shifts with the current user
/// Shows their name, avatar, and a preview of their next/active/past shift
struct SharerRow: View {
    let sharer: SharedUser
    let preview: SharerShiftPreview?
    let isSelected: Bool
    let isLoadingPreview: Bool
    let onTap: () -> Void

    @Environment(\.localization) private var localization

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Header row: avatar, name, chevron
                HStack(spacing: 12) {
                    avatarView

                    VStack(alignment: .leading, spacing: 2) {
                        Text(sharer.displayName)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.tidexTextPrimary)

                        // Contact info (email or phone)
                        if let contactInfo = sharer.contactInfo {
                            Text(contactInfo)
                                .font(.system(size: 13))
                                .foregroundColor(.tidexTextMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.tidexTextMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                // Shift preview (if available)
                if let preview = preview, let shift = preview.shift, let status = preview.status {
                    ShiftPreviewCard(shift: shift, status: status)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                } else if isLoadingPreview {
                    ShiftPreviewSkeleton()
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
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
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
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
            .frame(width: 44, height: 44)
            .overlay(
                Text(sharer.initials)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexBlue)
            )
    }
}

// MARK: - Shift Preview Card

/// Compact preview of a shift (shown under sharer info)
private struct ShiftPreviewCard: View {
    let shift: SharedShiftData
    let status: ShiftPreviewStatus

    @Environment(\.localization) private var localization

    // Real-time status tracking
    @State private var currentStatus: ShiftPreviewStatus
    @State private var progress: Double = 0
    @State private var timer: Timer?

    init(shift: SharedShiftData, status: ShiftPreviewStatus) {
        self.shift = shift
        self.status = status
        self._currentStatus = State(initialValue: status)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Date and time info
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDate)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextPrimary)

                Text(formattedTimeRange)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextMuted)
            }

            Spacer()

            // Status badge
            statusBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tidexSurfaceSecondary.opacity(0.5))
        )
        .overlay(
            // Progress bar for active shifts
            GeometryReader { geometry in
                if currentStatus == .active {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.1))
                        .frame(width: geometry.size.width * progress / 100)
                        .animation(.linear(duration: 1), value: progress)
                }
            }
        )
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startTimer() {
        updateStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            updateStatus()
        }
    }

    private func updateStatus() {
        let now = Date()
        guard let shiftDate = Date.fromISODateString(shift.shift_date) else { return }

        let startComponents = shift.start_time.split(separator: ":").compactMap { Int($0) }
        let endComponents = shift.end_time.split(separator: ":").compactMap { Int($0) }

        guard startComponents.count >= 2, endComponents.count >= 2 else { return }

        let start = Calendar.current.date(
            bySettingHour: startComponents[0],
            minute: startComponents[1],
            second: 0,
            of: shiftDate
        ) ?? shiftDate

        var end = Calendar.current.date(
            bySettingHour: endComponents[0],
            minute: endComponents[1],
            second: 0,
            of: shiftDate
        ) ?? shiftDate

        // Handle cross-midnight
        if end <= start {
            end = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
        }

        // Update status
        if now >= start && now <= end {
            currentStatus = .active
            let totalDuration = end.timeIntervalSince(start)
            let elapsed = now.timeIntervalSince(start)
            progress = min(100, max(0, (elapsed / totalDuration) * 100))
        } else if now < start {
            currentStatus = .upcoming
            progress = 0
        } else {
            currentStatus = .past
            progress = 100
        }
    }

    private var formattedDate: String {
        guard let date = Date.fromISODateString(shift.shift_date) else { return "" }

        let formatter = DateFormatter()
        let isNorwegian = localization.currentLocale == .norwegian
        formatter.locale = Locale(identifier: isNorwegian ? "nb_NO" : "en_US")

        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: date).capitalized

        formatter.dateFormat = "d"
        let dayNumber = formatter.string(from: date)

        formatter.dateFormat = "MMM"
        let monthName = formatter.string(from: date).lowercased()

        return "\(dayName) · \(dayNumber) \(monthName)"
    }

    private var formattedTimeRange: String {
        let start = String(shift.start_time.prefix(5))
        let end = String(shift.end_time.prefix(5))
        return "\(start)–\(end)"
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(statusText)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(statusBackgroundColor)
            )
            .foregroundColor(statusTextColor)
    }

    private var statusText: String {
        switch currentStatus {
        case .active:
            return localization.string("sharing.statusActive")
        case .upcoming:
            return relativeTimeText
        case .past:
            return relativeTimeText
        }
    }

    private var relativeTimeText: String {
        guard let shiftDate = Date.fromISODateString(shift.shift_date) else { return "" }

        let startComponents = shift.start_time.split(separator: ":").compactMap { Int($0) }
        guard startComponents.count >= 2 else { return "" }

        guard let shiftTime = Calendar.current.date(
            bySettingHour: startComponents[0],
            minute: startComponents[1],
            second: 0,
            of: shiftDate
        ) else { return "" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: shiftTime, relativeTo: Date())
    }

    private var statusBackgroundColor: Color {
        switch currentStatus {
        case .active:
            return Color.green.opacity(0.15)
        case .upcoming:
            return Color.blue.opacity(0.15)
        case .past:
            return Color.tidexSurfaceSecondary
        }
    }

    private var statusTextColor: Color {
        switch currentStatus {
        case .active:
            return Color.green
        case .upcoming:
            return Color.blue
        case .past:
            return Color.tidexTextMuted
        }
    }
}

// MARK: - Shift Preview Skeleton

private struct ShiftPreviewSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.tidexSurfaceSecondary)
                    .frame(width: 120, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.tidexSurfaceSecondary)
                    .frame(width: 80, height: 12)
            }

            Spacer()

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.tidexSurfaceSecondary)
                .frame(width: 60, height: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tidexSurfaceSecondary.opacity(0.5))
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
            preview: nil,
            isSelected: false,
            isLoadingPreview: true,
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
            preview: nil,
            isSelected: true,
            isLoadingPreview: false,
            onTap: {}
        )
    }
    .padding()
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
