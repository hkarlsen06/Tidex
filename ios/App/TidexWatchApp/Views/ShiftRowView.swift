import Combine
import SwiftUI
import UIKit

/// Card-style row view for displaying a shift on the Watch
/// Shows avatar and name at top, with shift details card below
struct ShiftRowView: View {
    let shift: WatchShiftDTO
    let isCurrentUser: Bool
    let locale: String
    let isRefreshing: Bool

    private var isNorwegian: Bool { locale == "no" }

    // Timer for countdown updates (under 24 hours)
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: avatar + name
            HStack(spacing: 8) {
                avatarView

                Text(shift.personName)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()
            }

            // Shift details card
            shiftCard
        }
        .listRowBackground(Color.clear)
        .onReceive(timer) { _ in
            // Only update if we're in countdown range (under 24 hours)
            if shouldCountdown {
                currentTime = Date()
            }
        }
    }

    // MARK: - Countdown Logic

    /// Whether we should show a live countdown (under 24 hours before shift)
    private var shouldCountdown: Bool {
        guard shift.status == .upcoming,
              let shiftStart = shiftStartDate else { return false }

        let secondsUntil = shiftStart.timeIntervalSince(currentTime)
        let hoursUntil = secondsUntil / 3600

        return hoursUntil > 0 && hoursUntil <= 24
    }

    private var shiftStartDate: Date? {
        guard let shiftDate = parseDate(shift.shiftDate) else { return nil }

        let calendar = Calendar.current
        let startParts = shift.startTime.split(separator: ":").compactMap { Int($0) }
        guard startParts.count >= 2 else { return nil }

        var startComponents = calendar.dateComponents([.year, .month, .day], from: shiftDate)
        startComponents.hour = startParts[0]
        startComponents.minute = startParts[1]

        return calendar.date(from: startComponents)
    }

    // MARK: - Shift Card

    private var shiftCard: some View {
        Group {
            if isRefreshing {
                shiftCardSkeleton
            } else {
                shiftCardContent
            }
        }
    }

    private var shiftCardContent: some View {
        HStack(spacing: 4) {
            // Date and time - fixed size to prevent wrapping
            VStack(alignment: .leading, spacing: 1) {
                Text(formattedDate)
                    .font(.caption2)
                    .fontWeight(.medium)

                Text("\(shift.startTime)–\(shift.endTime)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()

            Spacer(minLength: 0)

            // Status badge - allowed to overlap if needed
            statusBadge
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.15))
        )
        .overlay(
            // Progress indicator for active shifts
            GeometryReader { geometry in
                if shift.status == .active {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: geometry.size.width * progress)
                }
            }
        )
    }

    private var shiftCardSkeleton: some View {
        HStack(spacing: 4) {
            // Date and time skeleton
            VStack(alignment: .leading, spacing: 2) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 60, height: 10)

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 45, height: 9)
            }

            Spacer(minLength: 0)

            // Status badge skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 35, height: 14)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.15))
        )
        .shimmer(duration: 1.2)
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        Text(statusText)
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(statusBackgroundColor)
            )
            .foregroundStyle(statusColor)
            .fixedSize()
    }

    private var statusText: String {
        switch shift.status {
        case .active:
            return isNorwegian ? "Aktiv" : "Active"
        case .upcoming, .past:
            return relativeTimeText
        }
    }

    private var statusColor: Color {
        switch shift.status {
        case .active:
            return .green
        case .upcoming:
            return .blue
        case .past:
            return .secondary
        }
    }

    private var statusBackgroundColor: Color {
        switch shift.status {
        case .active:
            return .green.opacity(0.2)
        case .upcoming:
            return .blue.opacity(0.2)
        case .past:
            return .secondary.opacity(0.2)
        }
    }

    // MARK: - Date Formatting

    private var formattedDate: String {
        guard let date = parseDate(shift.shiftDate) else { return shift.shiftDate }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isNorwegian ? "nb_NO" : "en_US")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }

    // MARK: - Progress for Active Shifts

    private var progress: Double {
        guard shift.status == .active,
              let shiftDate = parseDate(shift.shiftDate) else { return 0 }

        let now = Date()
        let calendar = Calendar.current

        // Parse start time
        let startParts = shift.startTime.split(separator: ":").compactMap { Int($0) }
        guard startParts.count >= 2 else { return 0 }

        var startComponents = calendar.dateComponents([.year, .month, .day], from: shiftDate)
        startComponents.hour = startParts[0]
        startComponents.minute = startParts[1]

        guard let shiftStart = calendar.date(from: startComponents) else { return 0 }

        // Parse end time
        let endParts = shift.endTime.split(separator: ":").compactMap { Int($0) }
        guard endParts.count >= 2 else { return 0 }

        var endComponents = calendar.dateComponents([.year, .month, .day], from: shiftDate)
        endComponents.hour = endParts[0]
        endComponents.minute = endParts[1]

        var shiftEnd = calendar.date(from: endComponents) ?? shiftStart

        // Handle cross-midnight
        if shiftEnd <= shiftStart {
            shiftEnd = calendar.date(byAdding: .day, value: 1, to: shiftEnd) ?? shiftEnd
        }

        let totalDuration = shiftEnd.timeIntervalSince(shiftStart)
        let elapsed = now.timeIntervalSince(shiftStart)

        return min(1, max(0, elapsed / totalDuration))
    }

    // MARK: - Relative Time

    private var relativeTimeText: String {
        guard let shiftDate = parseDate(shift.shiftDate) else { return "" }

        let now = currentTime
        let calendar = Calendar.current

        // Parse start time for upcoming shifts
        let startParts = shift.startTime.split(separator: ":").compactMap { Int($0) }
        guard startParts.count >= 2 else { return "" }

        var startComponents = calendar.dateComponents([.year, .month, .day], from: shiftDate)
        startComponents.hour = startParts[0]
        startComponents.minute = startParts[1]

        guard let shiftStart = calendar.date(from: startComponents) else { return "" }

        // Parse end time for past shifts
        let endParts = shift.endTime.split(separator: ":").compactMap { Int($0) }
        guard endParts.count >= 2 else { return "" }

        var endComponents = calendar.dateComponents([.year, .month, .day], from: shiftDate)
        endComponents.hour = endParts[0]
        endComponents.minute = endParts[1]

        var shiftEnd = calendar.date(from: endComponents) ?? shiftStart

        // Handle cross-midnight
        if shiftEnd <= shiftStart {
            shiftEnd = calendar.date(byAdding: .day, value: 1, to: shiftEnd) ?? shiftEnd
        }

        let referenceTime = shift.status == .past ? shiftEnd : shiftStart
        let diffSeconds = referenceTime.timeIntervalSince(now)
        let isFuture = diffSeconds > 0
        let absDiffSeconds = abs(diffSeconds)

        let totalSeconds = Int(absDiffSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        // Check for day boundaries
        let startOfNow = calendar.startOfDay(for: now)
        let startOfRef = calendar.startOfDay(for: referenceTime)
        let dayDiff = calendar.dateComponents([.day], from: startOfNow, to: startOfRef).day ?? 0

        // More than 24 hours away - show days
        if abs(dayDiff) > 1 {
            let days = abs(dayDiff)
            return isFuture ? "\(days)d" : "-\(days)d"
        }

        // For upcoming shifts under 24 hours, show countdown with seconds
        if shift.status == .upcoming && isFuture && hours < 24 {
            let hourLabel = isNorwegian ? "t" : "h"
            let minLabel = isNorwegian ? "m" : "m"
            let secLabel = "s"

            if hours > 0 {
                return "\(hours)\(hourLabel)\(minutes)\(minLabel)\(seconds)\(secLabel)"
            } else if minutes > 0 {
                return "\(minutes)\(minLabel)\(seconds)\(secLabel)"
            } else {
                return "\(seconds)\(secLabel)"
            }
        }

        // Tomorrow/Yesterday for shifts more than 24 hours away
        if dayDiff == 1 {
            return isNorwegian ? "I morgen" : "Tomorrow"
        } else if dayDiff == -1 {
            return isNorwegian ? "I går" : "Yesterday"
        }

        // Past shifts - compact format without seconds
        let hourLabel = isNorwegian ? "t" : "h"
        let minLabel = isNorwegian ? "m" : "m"

        if hours == 0 {
            return "-\(minutes)\(minLabel)"
        } else {
            return "-\(hours)\(hourLabel)"
        }
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatarView: some View {
        // Prefer pre-downloaded image data (JPEG from iOS)
        if let imageData = shift.avatarImageData,
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 24, height: 24)
                .clipShape(Circle())
        } else if let url = shift.effectiveAvatarURL {
            // Fall back to URL loading (may fail for WebP)
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderAvatar
                case .empty:
                    placeholderAvatar
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.4)
                        }
                @unknown default:
                    placeholderAvatar
                }
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())
        } else {
            placeholderAvatar
        }
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(.secondary.opacity(0.3))
            .frame(width: 24, height: 24)
            .overlay {
                Text(initials)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
    }

    private var initials: String {
        let components = shift.personName.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(shift.personName.prefix(2)).uppercased()
    }
}

#Preview {
    List {
        ShiftRowView(
            shift: WatchShiftDTO(
                id: "1",
                personId: "user1",
                personName: "Hjalmar",
                personProfilePictureUrl: nil,
                personOauthAvatarUrl: nil,
                shiftDate: "2026-01-21",
                startTime: "07:00",
                endTime: "15:00",
                status: .active,
                avatarImageData: nil
            ),
            isCurrentUser: true,
            locale: "no",
            isRefreshing: false
        )

        ShiftRowView(
            shift: WatchShiftDTO(
                id: "2",
                personId: "user2",
                personName: "Anna Berg",
                personProfilePictureUrl: nil,
                personOauthAvatarUrl: nil,
                shiftDate: "2026-01-22",
                startTime: "09:00",
                endTime: "17:00",
                status: .upcoming,
                avatarImageData: nil
            ),
            isCurrentUser: false,
            locale: "no",
            isRefreshing: true
        )

        ShiftRowView(
            shift: WatchShiftDTO(
                id: "3",
                personId: "user3",
                personName: "Erik Olsen",
                personProfilePictureUrl: nil,
                personOauthAvatarUrl: nil,
                shiftDate: "2026-01-20",
                startTime: "08:00",
                endTime: "16:00",
                status: .past,
                avatarImageData: nil
            ),
            isCurrentUser: false,
            locale: "en",
            isRefreshing: false
        )
    }
}
