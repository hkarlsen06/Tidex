import SwiftUI

/// A card displaying a friend who shares their shifts with the current user
/// Shows their name, avatar, and a preview of their next/active/past shift
struct FriendCard: View {
  let sharer: SharedUser
  let preview: SharerShiftPreview?
  let isSelected: Bool
  let isRefreshing: Bool
  let onTap: () -> Void

  @Environment(\.layoutDirection) private var layoutDirection

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

          Image(systemName: layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.tidexTextMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, Spacing.sm)

        // Shift preview section - swap between skeleton and real card
        if let preview = preview, let shift = preview.shift, let status = preview.status {
          Group {
            if isRefreshing {
              shiftPreviewSkeleton
            } else {
              ShiftPreviewCard(shift: shift, status: status)
            }
          }
          .padding(.horizontal, 12)
          .padding(.bottom, 12)
        }
      }
      .background(
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .fill(isSelected ? Color.tidexBlue.opacity(0.1) : Color.tidexSurfacePrimary)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .strokeBorder(
            isSelected ? Color.tidexBlue : Color.clear,
            lineWidth: 2
          )
      )
      .tidexCardShadow()
    }
    .buttonStyle(PlainButtonStyle())
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
  }

  /// Skeleton placeholder for shift preview while refreshing
  private var shiftPreviewSkeleton: some View {
    HStack(spacing: 12) {
      // Date and time skeleton
      VStack(alignment: .leading, spacing: 4) {
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.tidexTextMuted.opacity(0.3))
          .frame(width: 140, height: 14)

        RoundedRectangle(cornerRadius: 4)
          .fill(Color.tidexTextMuted.opacity(0.2))
          .frame(width: 90, height: 13)
      }

      Spacer()

      // Status badge skeleton
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.tidexTextMuted.opacity(0.2))
        .frame(width: 70, height: 24)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.tidexSurfacePrimary)
    )
    .tidexCardShadow(.subtle, cornerRadius: 12)
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

      HStack(spacing: 12) {
        // Date and time info
        VStack(alignment: .leading, spacing: 2) {
          Text(formattedDate)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.tidexTextPrimary)

          Text(formattedTimeRange)
            .font(.system(size: 13))
            .foregroundColor(.tidexTextMuted)
            .environment(\.layoutDirection, .leftToRight)
        }

        Spacer()

        // Status badge
        statusBadge(computed: computed)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, Spacing.sm)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.tidexSurfacePrimary)
      )
      .overlay(
        // Progress bar for active shifts
        GeometryReader { geometry in
          if computed.status == .active {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(Color.green.opacity(0.1))
              .frame(width: geometry.size.width * computed.progress / 100)
              .animation(.linear(duration: 1), value: computed.progress)
          }
        }
      )
      .tidexCardShadow(.subtle, cornerRadius: 12)
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

  /// Format date: "Mandag · 15. januar" (Norwegian) or "Monday · 15 January" (English)
  /// Friends tab uses full month names for better readability
  private static func formatDate(shiftDate: String) -> String {
    guard let date = Date.fromISODateString(shiftDate) else { return "" }

    let locale = Locale.appLocale
    let dayName = FormatterCache.weekdayFormatter(locale: locale)
      .string(from: date)
      .capitalized

    let dayNumber = Calendar.current.component(.day, from: date)
    let daySuffix = String(localized: .commonDaySuffix)
    let dayString = "\(dayNumber)\(daySuffix)"

    let monthName = FormatterCache.monthNameFormatter(locale: locale)
      .string(from: date)
      .lowercased()

    return "\(dayName) · \(dayString) \(monthName)"
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
    if isCountingDown(computed) {
      // Show countdown number for final 60 seconds (matches Next.js behavior)
      Text("\(computed.secondsUntilEnd)")
        .font(.system(size: 16, weight: .medium))
        .monospacedDigit()
        .frame(minWidth: 40)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.green.opacity(0.2))
        )
        .foregroundColor(.green)
        .contentTransition(.numericText())
        .animation(.default, value: computed.secondsUntilEnd)
    } else {
      Text(statusText(computed: computed))
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(statusBackgroundColor(for: computed.status))
        )
        .foregroundColor(statusTextColor(for: computed.status))
        .contentTransition(.numericText())
        .animation(.default, value: computed.relativeText)
    }
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
    let referenceTime: Date
    if now > shiftEnd {
      referenceTime = shiftEnd
    } else {
      referenceTime = shiftStart
    }

    let diffSeconds = referenceTime.timeIntervalSince(now)
    let isFuture = diffSeconds > 0
    let absDiffSeconds = abs(diffSeconds)

    let totalSeconds = Int(absDiffSeconds)
    let totalMinutes = totalSeconds / 60
    let totalHours = totalMinutes / 60

    // Count midnight crossings for day-based formatting
    let midnightDays = countMidnightCrossings(from: min(now, shiftStart), to: max(now, shiftStart))

    // Abbreviations from String Catalog
    let hAbbrev = String(localized: .commonHoursShort)
    let minAbbrev = String(localized: .commonMinShort)
    let secAbbrev = String(localized: .commonSecondsShort)

    // Within the same day (0 midnight crossings)
    if midnightDays == 0 {
      let h = totalMinutes / 60
      let m = totalMinutes % 60
      let s = totalSeconds % 60

      // Under 12 hours: include seconds
      let includeSeconds = totalHours < 12

      var timeStr: String
      if totalMinutes == 0 {
        // Less than a minute - always show seconds
        timeStr = "\(s)\(secAbbrev)"
      } else if h == 0 {
        // Less than an hour
        if includeSeconds {
          timeStr = "\(m)\(minAbbrev) \(s)\(secAbbrev)"
        } else {
          timeStr = "\(m)\(minAbbrev)"
        }
      } else if includeSeconds {
        if m == 0 {
          timeStr = "\(h)\(hAbbrev) \(s)\(secAbbrev)"
        } else {
          timeStr = "\(h)\(hAbbrev) \(m)\(minAbbrev) \(s)\(secAbbrev)"
        }
      } else if m == 0 {
        timeStr = "\(h)\(hAbbrev)"
      } else {
        timeStr = "\(h)\(hAbbrev) \(m)\(minAbbrev)"
      }

      if isFuture {
        return String(localized: .commonInTime(timeStr))
      } else {
        return String(localized: .commonTimeAgo(timeStr))
      }
    }

    // 1 midnight crossing = tomorrow/yesterday
    if midnightDays == 1 {
      return isFuture
        ? String(localized: .commonTomorrow).capitalized
        : String(localized: .commonYesterday).capitalized
    }

    // Multiple days
    if isFuture {
      return String(localized: .commonInDaysPlural(Int(Int32(midnightDays))))
    } else {
      return String(localized: .commonDaysAgoPlural(Int(Int32(midnightDays))))
    }
  }

  /// Count midnight crossings between two dates (matches Next.js logic)
  private func countMidnightCrossings(from startDate: Date, to endDate: Date) -> Int {
    let calendar = Calendar.current
    let startOfStartDay = calendar.startOfDay(for: startDate)
    let startOfEndDay = calendar.startOfDay(for: endDate)
    let components = calendar.dateComponents([.day], from: startOfStartDay, to: startOfEndDay)
    return abs(components.day ?? 0)
  }

  private func statusBackgroundColor(for status: ShiftPreviewStatus) -> Color {
    switch status {
    case .active:
      return Color.green.opacity(0.15)
    case .upcoming:
      return Color.blue.opacity(0.15)
    case .past:
      return Color.tidexTextMuted.opacity(0.15)
    }
  }

  private func statusTextColor(for status: ShiftPreviewStatus) -> Color {
    switch status {
    case .active:
      return Color.green
    case .upcoming:
      return Color.blue
    case .past:
      return Color.tidexTextMuted
    }
  }
}

// MARK: - Empty State

/// Shown when no one has shared shifts with the user
struct FriendsListEmptyState: View {
  var onAddFriend: (() -> Void)?

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "person.2.slash")
        .font(.system(size: 48))
        .foregroundColor(.tidexTextMuted)

      Text(.sharingNoSharers)
        .font(.system(size: 17, weight: .medium))
        .foregroundColor(.tidexTextPrimary)

      Text(.sharingNoSharersDescription)
        .font(.system(size: 15))
        .foregroundColor(.tidexTextMuted)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)

      if let onAddFriend {
        Button(action: onAddFriend) {
          HStack(spacing: 6) {
            Image(systemName: "plus")
              .font(.system(size: 14, weight: .semibold))
            Text(.sharingAddFriend)
              .font(.system(size: 15, weight: .semibold))
          }
          .foregroundColor(.white)
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
          .background(Color.tidexBlue)
          .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.vertical, 80)
  }
}

#Preview {
  VStack(spacing: 16) {
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
        blocked: false
      ),
      preview: nil,
      isSelected: false,
      isRefreshing: false,
      onTap: {}
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
        blocked: false
      ),
      preview: nil,
      isSelected: true,
      isRefreshing: false,
      onTap: {}
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
