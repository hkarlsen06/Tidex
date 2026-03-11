import SwiftUI

struct CompactFriendIdentityRow: View {
  let sharer: SharedUser
  var unreadMessageCount = 0
  var showsContactInfo = true
  var avatarSize: CGFloat = AvatarView.Size.large

  var body: some View {
    HStack(spacing: Spacing.sm) {
      avatarView

      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(sharer.displayName)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)

        if showsContactInfo, let contactInfo = sharer.contactInfo {
          Text(contactInfo)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
            .lineLimit(1)
        }
      }

      Spacer()
    }
  }

  private var avatarView: some View {
    AvatarView(
      url: sharer.avatarUrl,
      initials: sharer.initials,
      size: avatarSize,
      cornerRadius: max(12, avatarSize - 32)
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
}

struct FriendShiftPreviewStatusCard: View {
  let shift: SharedShiftData
  let status: ShiftPreviewStatus
  private let schedule: ShiftSchedule?

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

  private func computeStatus(at now: Date) -> ComputedStatus {
    var currentStatus = status
    var progress: Double = 0
    var secondsUntilEnd: Int = 0
    guard let schedule else {
      return ComputedStatus(status: status, progress: 0, secondsUntilEnd: 0, relativeText: "")
    }

    let start = schedule.start
    let end = schedule.end

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
    }

    let relativeText = computeRelativeTimeText(at: now, shiftStart: start, shiftEnd: end)

    return ComputedStatus(
      status: currentStatus,
      progress: progress,
      secondsUntilEnd: secondsUntilEnd,
      relativeText: relativeText
    )
  }

  @ViewBuilder
  private func statusBadge(computed: ComputedStatus) -> some View {
    ShiftCountdownBadge(
      text: statusText(computed: computed),
      status: computed.status,
      finalCountdownSeconds: isCountingDown(computed) ? computed.secondsUntilEnd : nil
    )
  }

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

  private func isCountingDown(_ computed: ComputedStatus) -> Bool {
    computed.status == .active && computed.secondsUntilEnd <= 60 && computed.secondsUntilEnd > 0
  }

  private func statusText(computed: ComputedStatus) -> String {
    switch computed.status {
    case .active:
      return String(localized: .sharingStatusActive)
    case .upcoming, .past:
      return computed.relativeText
    }
  }

  private func computeRelativeTimeText(at now: Date, shiftStart: Date, shiftEnd: Date) -> String {
    let referenceTime = now > shiftEnd ? shiftEnd : shiftStart

    return CountdownFormatter.formatRelativeCountdown(
      referenceDate: referenceTime,
      dayBoundaryReferenceDate: shiftStart,
      now: now
    )
  }
}

struct CompactFriendShiftPreviewHeader: View {
  let sharer: SharedUser
  let preview: SharerShiftPreview
  let label: LocalizedStringResource

  var body: some View {
    if let shift = preview.shift, let status = preview.status {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        Text(label)
          .font(.tidexMicro)
          .foregroundColor(.tidexTextMuted)
          .textCase(.uppercase)

        CompactFriendIdentityRow(
          sharer: sharer,
          showsContactInfo: false,
          avatarSize: AvatarView.Size.medium
        )

        FriendShiftPreviewStatusCard(shift: shift, status: status)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
          .fill(Color.tidexSurfacePrimary)
      )
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
          .strokeBorder(Color.tidexBorderSubtle, lineWidth: 1)
      )
      .tidexCardShadow(.subtle, cornerRadius: CornerRadius.card)
    }
  }
}
