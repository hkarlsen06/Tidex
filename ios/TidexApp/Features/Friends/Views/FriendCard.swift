import SwiftUI

/// A card displaying a friend who shares their shifts with the current user
/// Shows their name, avatar, and a preview of their next/active/past shift
struct FriendCard: View {
  let sharer: SharedUser
  let preview: SharerShiftPreview?
  let isSelected: Bool
  let isRefreshing: Bool
  let onChatTap: () -> Void
  let onCalendarTap: () -> Void
  var isCalendarAvailable = true
  var isOpeningMessage = false
  var unreadMessageCount = 0

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: Spacing.sm) {
        Button(action: primaryCardTapAction) {
          HStack(spacing: Spacing.sm) {
            avatarView

            VStack(alignment: .leading, spacing: Spacing.micro) {
              Text(sharer.displayName)
                .font(.tidexBodyMedium)
                .foregroundColor(.tidexTextPrimary)

              if let contactInfo = sharer.contactInfo {
                Text(contactInfo)
                  .font(.tidexFootnote)
                  .foregroundColor(.tidexTextMuted)
                  .lineLimit(1)
              }
            }
            Spacer()
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOpeningMessage)

        Button(action: onChatTap) {
          Group {
            if isOpeningMessage {
              ProgressView()
                .progressViewStyle(.circular)
                .tint(.tidexTextOnBrand)
            } else {
              Image(systemName: "message")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.tidexTextOnBrand)
            }
          }
          .frame(width: 44, height: 44)
          .tidexGlass(
            shape: .circle,
            tint: .tidexBlue.opacity(0.26),
            interactive: true
          )
        }
        .buttonStyle(.plain)
        .disabled(isOpeningMessage)
        .accessibilityLabel(Text(verbatim: "\(sharer.displayName) chat"))
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)

      if let preview = preview, let shift = preview.shift, let status = preview.status {
        Button(action: onCalendarTap) {
          Group {
            if isRefreshing {
              shiftPreviewSkeleton
            } else {
              ShiftPreviewCard(shift: shift, status: status)
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(!isCalendarAvailable)
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
        .fill(isSelected ? Color.tidexBlue.opacity(0.1) : Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
        .strokeBorder(
          isSelected ? Color.tidexBlue : Color.clear,
          lineWidth: 2
        )
    )
    .tidexCardShadow()
  }

  private var primaryCardTapAction: () -> Void {
    isCalendarAvailable ? onCalendarTap : onChatTap
  }

  /// Corner radius for concentric design: outer (24) - padding (12) = 12
  private static let concentricCornerRadius: CGFloat = 12

  private var avatarView: some View {
    AvatarView(
      url: sharer.avatarUrl,
      initials: sharer.initials,
      size: AvatarView.Size.large,
      cornerRadius: Self.concentricCornerRadius
    )
    .overlay(alignment: .topTrailing) {
      if unreadMessageCount > 0 {
        Text(unreadMessageCount > 9 ? "9+" : "\(unreadMessageCount)")
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundColor(.white)
          .frame(minWidth: 22, minHeight: 22)
          .background(
            Capsule(style: .continuous)
              .fill(Color.tidexError)
          )
          .overlay(
            Capsule(style: .continuous)
              .stroke(Color.tidexSurfacePrimary, lineWidth: 2)
          )
          .offset(x: 8, y: -8)
      }
    }
  }

  /// Skeleton placeholder for shift preview while refreshing
  private var shiftPreviewSkeleton: some View {
    HStack(spacing: Spacing.sm) {
      // Date and time skeleton
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        RoundedRectangle(cornerRadius: CornerRadius.xxs)
          .fill(Color.tidexTextMuted.opacity(0.3))
          .frame(width: 140, height: 14)

        RoundedRectangle(cornerRadius: CornerRadius.xxs)
          .fill(Color.tidexTextMuted.opacity(0.2))
          .frame(width: 90, height: 13)
      }

      Spacer()

      // Status badge skeleton
      RoundedRectangle(cornerRadius: CornerRadius.sm)
        .fill(Color.tidexTextMuted.opacity(0.2))
        .frame(width: 70, height: 24)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .fill(Color.tidexSurfacePrimary)
    )
    .tidexCardShadow(.subtle, cornerRadius: CornerRadius.lg)
    .shimmer(duration: 1.2)
  }
}

// MARK: - Shift Preview Card

/// Compact preview of a shift (shown under sharer info)
/// Matches the Next.js SharedUserShiftPreview component behavior
/// Uses TimelineView for efficient per-second updates only when visible
private struct ShiftPreviewCard: View {
  let shift: SharedShiftData
  let status: ShiftPreviewStatus
  private let schedule: ShiftSchedule?
  @Environment(\.layoutDirection) private var layoutDirection

  init(shift: SharedShiftData, status: ShiftPreviewStatus) {
    self.shift = shift
    self.status = status
    self.schedule = Self.makeSchedule(for: shift)
  }

  private var formattedDate: String {
    Self.formatDate(shiftDate: shift.shift_date)
  }

  private var formattedTimeRange: String {
    ShiftCardFormatter.localizedTimeRange(
      start: shift.start_time,
      end: shift.end_time,
      locale: Locale.appLocale,
      separator: " – "
    )
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let computed = computeStatus(at: context.date)

      HStack(spacing: Spacing.sm) {
        // Date and time info
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(formattedDate)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextPrimary)
            .lineLimit(1)

          Text(formattedTimeRange)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
            .lineLimit(1)
            .environment(\.layoutDirection, .leftToRight)
        }

        Spacer(minLength: Spacing.xs)

        // Status badge
        statusBadge(computed: computed)
          .fixedSize(horizontal: true, vertical: false)
          .layoutPriority(1)
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.sm)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(Color.tidexSurfacePrimary)
      )
      .overlay(
        // Progress bar for active shifts
        GeometryReader { geometry in
          if computed.status == .active {
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
              .fill(Color.green.opacity(0.1))
              .frame(width: geometry.size.width * computed.progress / 100)
              .animation(.linear(duration: 1), value: computed.progress)
          }
        }
      )
      .tidexCardShadow(.subtle, cornerRadius: CornerRadius.lg)
    }
  }

  /// Computed status values for a given point in time
  private struct ComputedStatus {
    let status: ShiftPreviewStatus
    let progress: Double
    let secondsUntilEnd: Int
    let relativeText: String
  }

  private struct ShiftSchedule {
    let start: Date
    let end: Date
  }

  /// Compute current status, progress, and relative time for a given date
  private func computeStatus(at now: Date) -> ComputedStatus {
    var currentStatus = status
    var progress: Double = 0
    var secondsUntilEnd: Int = 0
    guard let schedule else {
      return ComputedStatus(status: status, progress: 0, secondsUntilEnd: 0, relativeText: "")
    }

    let start = schedule.start
    let end = schedule.end

    // Compute status
    if now >= start && now <= end {
      currentStatus = .active
      let totalDuration = end.timeIntervalSince(start)
      let elapsed = now.timeIntervalSince(start)
      progress = min(100, max(0, (elapsed / totalDuration) * 100))
      secondsUntilEnd = Int(ceil(end.timeIntervalSince(now)))
    } else if now < start {
      currentStatus = .upcoming
      progress = 0
      secondsUntilEnd = 0
    } else {
      currentStatus = .past
      progress = 100
      secondsUntilEnd = 0
    }

    let relativeText = computeRelativeTimeText(at: now, shiftStart: start, shiftEnd: end)

    return ComputedStatus(
      status: currentStatus,
      progress: progress,
      secondsUntilEnd: secondsUntilEnd,
      relativeText: relativeText
    )
  }

  /// Format date using system locale: "Monday, January 15" (English) or "Mandag 15. januar" (Norwegian)
  /// Friends tab uses full month names for better readability
  private static func formatDate(shiftDate: String) -> String {
    guard let date = Date.fromISODateString(shiftDate) else { return "" }
    return date.formatted(.dateTime.weekday(.wide).day().month(.wide)).sentenceCased()
  }

  private static func makeSchedule(for shift: SharedShiftData) -> ShiftSchedule? {
    guard let shiftDate = Date.fromISODateString(shift.shift_date) else {
      return nil
    }

    let startComponents = shift.start_time.split(separator: ":").compactMap { Int($0) }
    let endComponents = shift.end_time.split(separator: ":").compactMap { Int($0) }

    guard startComponents.count >= 2, endComponents.count >= 2 else {
      return nil
    }

    let calendar = Calendar.current
    let start =
      calendar.date(
        bySettingHour: startComponents[0],
        minute: startComponents[1],
        second: 0,
        of: shiftDate
      ) ?? shiftDate

    var end =
      calendar.date(
        bySettingHour: endComponents[0],
        minute: endComponents[1],
        second: 0,
        of: shiftDate
      ) ?? shiftDate

    if end <= start {
      end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
    }

    return ShiftSchedule(start: start, end: end)
  }

  /// Check if we're in the final countdown (last 60 seconds of active shift)
  private func isCountingDown(_ computed: ComputedStatus) -> Bool {
    computed.status == .active && computed.secondsUntilEnd <= 60 && computed.secondsUntilEnd > 0
  }

  @ViewBuilder
  private func statusBadge(computed: ComputedStatus) -> some View {
    ShiftCountdownBadge(
      text: statusText(computed: computed),
      status: computed.status,
      finalCountdownSeconds: isCountingDown(computed) ? computed.secondsUntilEnd : nil
    )
  }

  private func statusText(computed: ComputedStatus) -> String {
    switch computed.status {
    case .active:
      return String(localized: .sharingStatusActive)
    case .upcoming, .past:
      return computed.relativeText
    }
  }

  /// Custom relative time formatting to match Next.js useCountdown hook
  /// Format: "Om 2t 30min 45sek", "I morgen", "2t siden", etc.
  /// Includes seconds for countdowns under 12 hours
  private func computeRelativeTimeText(at now: Date, shiftStart: Date, shiftEnd: Date) -> String {
    // For past shifts, calculate from end time (matches Next.js behavior)
    // "3min siden" means "ended 3 minutes ago", not "started X hours ago"
    let referenceTime = now > shiftEnd ? shiftEnd : shiftStart

    return CountdownFormatter.formatRelativeCountdown(
      referenceDate: referenceTime,
      dayBoundaryReferenceDate: shiftStart,
      now: now
    )
  }

}

// MARK: - Empty State

/// Shown when no one has shared shifts with the user
struct FriendsListEmptyState: View {
  var onAddFriend: (() -> Void)?

  var body: some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "person.2.slash")
        .font(.system(size: 48))
        .foregroundColor(.tidexTextMuted)

      Text(.sharingNoSharers)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)

      Text(.sharingNoSharersDescription)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.xl)

      if let onAddFriend {
        Button(action: onAddFriend) {
          HStack(spacing: Spacing.xxxs) {
            Image(systemName: "plus")
              .font(.tidexLabelStrong)
            Text(.sharingAddFriend)
              .font(.tidexLabelStrong)
          }
          .foregroundColor(.tidexTextOnBrand)
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, Spacing.xsm)
          .background(Color.tidexBlue)
          .cornerRadius(CornerRadius.md)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, Spacing.xxs)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.vertical, 80)
  }
}

#Preview {
  VStack(spacing: Spacing.md) {
    FriendCard(
      sharer: SharedUser(
        id: "1",
        email: "john@example.com",
        phone: nil,
        firstName: "John Doe",
        profilePictureUrl: nil,
        oauthAvatarUrl: nil,
        sharedAt: "2025-01-01",
        showEarnings: true,
        hidden: false
      ),
      preview: nil,
      isSelected: false,
      isRefreshing: false,
      onChatTap: {},
      onCalendarTap: {}
    )

    FriendCard(
      sharer: SharedUser(
        id: "2",
        email: "jane@example.com",
        phone: nil,
        firstName: "Jane",
        profilePictureUrl: nil,
        oauthAvatarUrl: nil,
        sharedAt: "2025-01-01",
        showEarnings: false,
        hidden: false
      ),
      preview: nil,
      isSelected: true,
      isRefreshing: false,
      onChatTap: {},
      onCalendarTap: {}
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
