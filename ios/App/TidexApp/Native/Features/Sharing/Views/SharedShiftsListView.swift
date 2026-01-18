import SwiftUI

/// List of shared shifts from a specific sharer for the selected month
struct SharedShiftsListView: View {
    let sharer: SharedUser
    let shifts: [ShiftWithComputations]
    let totalHours: Double
    let totalEarnings: Double?
    let shiftCount: Int
    let isLoading: Bool
    let lastCacheTime: Date?
    let onBack: () -> Void

    @Environment(\.localization) private var localization
    @Environment(\.userCurrency) private var currency

    private var today: String {
        todayISO()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            headerView

            // Summary card
            summaryCard
                .padding(.horizontal, 16)
                .padding(.top, 16)

            // Shifts list
            if isLoading && shifts.isEmpty {
                loadingState
            } else if shifts.isEmpty {
                emptyState
            } else {
                shiftsList
            }

            // Last updated indicator
            if let cacheTime = lastCacheTime {
                lastUpdatedView(cacheTime)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // Back button
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text(localization.string("common.back"))
                        .font(.system(size: 17))
                }
                .foregroundColor(.tidexBlue)
            }

            Spacer()

            // Sharer name
            HStack(spacing: 8) {
                if let urlString = sharer.avatarUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                        default:
                            initialsAvatar(size: 28, fontSize: 12)
                        }
                    }
                } else {
                    initialsAvatar(size: 28, fontSize: 12)
                }

                Text(sharer.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)
            }

            Spacer()

            // Placeholder for symmetry
            Color.clear
                .frame(width: 60)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.tidexSurfacePrimary)
    }

    private func initialsAvatar(size: CGFloat, fontSize: CGFloat) -> some View {
        Circle()
            .fill(Color.tidexBlue.opacity(0.2))
            .frame(width: size, height: size)
            .overlay(
                Text(sharer.initials)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(.tidexBlue)
            )
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 20) {
            // Shift count
            statItem(
                value: "\(shiftCount)",
                label: localization.string("sharing.shifts")
            )

            Divider()
                .frame(height: 32)

            // Total hours
            statItem(
                value: formatHours(totalHours),
                label: localization.string("sharing.hours")
            )

            if let earnings = totalEarnings {
                Divider()
                    .frame(height: 32)

                // Total earnings
                statItem(
                    value: formatCurrency(earnings),
                    label: localization.string("sharing.earnings")
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tidexSurfacePrimary)
        )
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.tidexTextPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.tidexTextMuted)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text(localization.string("sharing.loadingShifts"))
                .font(.system(size: 15))
                .foregroundColor(.tidexTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.tidexTextMuted)

            Text(localization.string("sharing.noShiftsThisMonth"))
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.tidexTextPrimary)

            Text(localization.string("sharing.noShiftsDescription"))
                .font(.system(size: 15))
                .foregroundColor(.tidexTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Shifts List

    private var shiftsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(shifts) { shift in
                    SharedShiftRow(
                        shift: shift,
                        isToday: shift.shiftDate == today,
                        showEarnings: sharer.showEarnings
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Last Updated

    private func lastUpdatedView(_ date: Date) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 11))
            Text(localization.string("sharing.lastUpdated"))
            Text(formatRelativeTime(date))
        }
        .font(.system(size: 12))
        .foregroundColor(.tidexTextMuted)
        .padding(.vertical, 8)
    }

    // MARK: - Formatting

    private func formatHours(_ hours: Double) -> String {
        let hoursLabel = localization.currentLocale == .norwegian ? "t" : "h"
        if hours == floor(hours) {
            return String(format: "%.0f %@", hours, hoursLabel)
        }
        return String(format: "%.1f %@", hours, hoursLabel)
    }

    private func formatCurrency(_ amount: Double) -> String {
        CurrencyConfig.format(amount, currency: currency)
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    SharedShiftsListView(
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
        shifts: [],
        totalHours: 32.5,
        totalEarnings: 6500,
        shiftCount: 5,
        isLoading: false,
        lastCacheTime: Date(),
        onBack: {}
    )
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
    .environment(\.userCurrency, "kr")
}
