// swiftlint:disable file_length type_body_length
// Watch views require all size variations in a single file
import Combine
import SwiftUI
import UIKit

/// Card-style row view for displaying a shift on the Watch
/// Shows avatar and name at top, with shift details card below
struct ShiftRowView: View {
  @Environment(WatchDataStore.self) private var store

  let shift: WatchShiftDTO
  let isCurrentUser: Bool
  let isRefreshing: Bool

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

  /// Whether we should update the timer (upcoming within 24h or active)
  private var shouldCountdown: Bool {
    guard let shiftStart = store.startDate(for: shift),
      let shiftEnd = store.endDate(for: shift)
    else { return false }

    let now = Date()

    // Update during active shifts (for progress bar and status transition)
    if now >= shiftStart && now < shiftEnd {
      return true
    }

    // Update during upcoming shifts within 24 hours
    let secondsUntil = shiftStart.timeIntervalSince(now)
    let hoursUntil = secondsUntil / 3600

    return hoursUntil > 0 && hoursUntil <= 24
  }

  private var shiftStartDate: Date? {
    store.startDate(for: shift)
  }

  private var shiftEndDate: Date? {
    store.endDate(for: shift)
  }

  /// Dynamically computed status based on current time,
  /// so shifts transition from upcoming -> active -> past in real time.
  private var effectiveStatus: ShiftPreviewStatus {
    store.effectiveStatus(for: shift, now: currentTime)
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
        if effectiveStatus == .active {
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
    switch effectiveStatus {
    case .active:
      return String(localized: .watchActive)
    case .upcoming, .past:
      return relativeTimeText
    }
  }

  private var statusColor: Color {
    switch effectiveStatus {
    case .active:
      return .green
    case .upcoming:
      return .blue
    case .past:
      return .secondary
    }
  }

  private var statusBackgroundColor: Color {
    switch effectiveStatus {
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
    store.formattedDate(for: shift)
  }

  // MARK: - Progress for Active Shifts

  private var progress: Double {
    guard effectiveStatus == .active,
      let shiftStart = shiftStartDate,
      let shiftEnd = shiftEndDate
    else { return 0 }

    let now = Date()

    let totalDuration = shiftEnd.timeIntervalSince(shiftStart)
    let elapsed = now.timeIntervalSince(shiftStart)

    return min(1, max(0, elapsed / totalDuration))
  }

  // MARK: - Relative Time

  private var relativeTimeText: String {
    guard let shiftStart = shiftStartDate,
      let shiftEnd = shiftEndDate
    else { return "" }

    let now = currentTime
    let calendar = Calendar.current

    let referenceTime = effectiveStatus == .past ? shiftEnd : shiftStart
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
    if effectiveStatus == .upcoming && isFuture && hours < 24 {
      let hourLabel = String(localized: .commonHoursShort)
      let minLabel = String(localized: .commonMinutesShort)
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
      return String(localized: .watchTomorrow)
    } else if dayDiff == -1 {
      return String(localized: .watchYesterday)
    }

    // Past shifts - compact format without seconds
    let hourLabel = String(localized: .commonHoursShort)
    let minLabel = String(localized: .commonMinutesShort)

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
      let uiImage = UIImage(data: imageData)
    {
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
      isRefreshing: false
    )
  }
}
// swiftlint:enable file_length type_body_length
