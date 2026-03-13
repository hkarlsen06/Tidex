import SwiftUI

private enum FriendShiftPreviewStatusCardStyle {
  case card
  case embedded
  case toolbarExtension
}

struct CompactFriendIdentityRow: View {
  let sharer: SharedUser
  var unreadMessageCount = 0
  var messagePreview: FriendCardMessagePreview? = nil
  var showsContactInfo = true
  var avatarSize: CGFloat = AvatarView.Size.large

  var body: some View {
    HStack(spacing: Spacing.sm) {
      avatarView

      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(sharer.displayName)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(1)
          .truncationMode(.tail)

        if let messagePreview {
          FriendCardMessagePreviewRow(messagePreview: messagePreview)
        } else if showsContactInfo, let contactInfo = sharer.contactInfo {
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

private struct FriendCardMessagePreviewRow: View {
  let messagePreview: FriendCardMessagePreview

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(stateLabel)
            .font(.tidexFootnote.weight(.semibold))
            .foregroundColor(statusColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

          Text(relativeTimestamp(referenceDate: context.date))
            .font(.tidexCaptionRegular)
            .foregroundColor(statusColor)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
        }

        Text(messagePreview.text)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted.opacity(0.75))
          .lineLimit(1)
          .truncationMode(.tail)

        Spacer(minLength: 0)
      }
    }
  }

  private var statusColor: Color {
    switch messagePreview.state {
    case .incomingUnread:
      .tidexBlue
    case .outgoingSending, .outgoingSent, .outgoingOpened, .incomingOpened:
      .tidexTextMuted
    case .outgoingFailed:
      .tidexError
    }
  }

  private var stateLabel: LocalizedStringResource {
    switch messagePreview.state {
    case .outgoingSending:
      .friendsChatStatusSending
    case .outgoingSent:
      LocalizedStringResource("friends.chat.preview_label.sent", table: "Localizable")
    case .outgoingOpened, .incomingOpened:
      LocalizedStringResource("friends.chat.preview_label.opened", table: "Localizable")
    case .outgoingFailed:
      .friendsChatStatusFailed
    case .incomingUnread:
      LocalizedStringResource("friends.chat.preview_label.received", table: "Localizable")
    }
  }

  private func relativeTimestamp(referenceDate: Date) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 1
    formatter.zeroFormattingBehavior = .dropAll

    let elapsed = max(referenceDate.timeIntervalSince(messagePreview.timestamp), 60)
    return formatter.string(from: elapsed)?
      .replacingOccurrences(of: " ", with: "")
      ?? "1m"
  }
}

struct FriendShiftPreviewStatusCard: View {
  let shift: SharedShiftData
  let status: ShiftPreviewStatus
  private let style: FriendShiftPreviewStatusCardStyle
  private let schedule: ShiftSchedule?

  init(shift: SharedShiftData, status: ShiftPreviewStatus) {
    self.shift = shift
    self.status = status
    style = .card
    schedule = Self.makeSchedule(for: shift)
  }

  init(shift: SharedShiftData, status: ShiftPreviewStatus, embedded: Bool) {
    self.shift = shift
    self.status = status
    style = embedded ? .embedded : .card
    schedule = Self.makeSchedule(for: shift)
  }

  fileprivate init(
    shift: SharedShiftData,
    status: ShiftPreviewStatus,
    style: FriendShiftPreviewStatusCardStyle
  ) {
    self.shift = shift
    self.status = status
    self.style = style
    schedule = Self.makeSchedule(for: shift)
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
      .padding(.horizontal, style == .toolbarExtension ? Spacing.md : Spacing.sm)
      .padding(.top, style == .embedded ? Spacing.xxs : Spacing.sm)
      .padding(.bottom, style == .embedded ? Spacing.xs : Spacing.sm)
      .background(backgroundShape)
      .overlay(alignment: .leading) {
        if computed.status == .active {
          activeProgressOverlay(progress: computed.progress)
        }
      }
      .overlay(borderShape)
      .modifier(FriendShiftPreviewShadowModifier(style: style))
    }
  }

  @ViewBuilder
  private var backgroundShape: some View {
    switch style {
    case .card:
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .fill(Color.tidexSurfacePrimary)
    case .embedded:
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .fill(Color.clear)
    case .toolbarExtension:
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(Color.tidexSurfacePrimary.opacity(0.94))
        .overlay(
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.tidexBlue.opacity(0.04))
        )
    }
  }

  @ViewBuilder
  private var borderShape: some View {
    switch style {
    case .card:
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .stroke(Color.clear, lineWidth: 0)
    case .embedded:
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .stroke(Color.clear, lineWidth: 0)
    case .toolbarExtension:
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(Color.tidexBorderSubtle, lineWidth: 1)
    }
  }

  private var progressShape: RoundedRectangle {
    RoundedRectangle(
      cornerRadius: style == .toolbarExtension ? 22 : CornerRadius.lg,
      style: .continuous
    )
  }

  @ViewBuilder
  private func activeProgressOverlay(progress: Double) -> some View {
    GeometryReader { geometry in
      progressShape
        .fill(Color.green.opacity(0.1))
        .frame(width: geometry.size.width * progress / 100)
        .animation(.linear(duration: 1), value: progress)
    }
    .clipShape(progressShape)
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
  let preview: SharerShiftPreview

  var body: some View {
    if let shift = preview.shift, let status = preview.status {
      CompactFriendShiftPreviewTextRow(
        shift: shift,
        status: status,
        showEarnings: preview.showEarnings,
        currency: preview.currency
      )
    }
  }
}

private struct CompactFriendShiftPreviewTextRow: View {
  let shift: SharedShiftData
  let status: ShiftPreviewStatus
  let showEarnings: Bool
  let currency: String?

  private struct ShiftSchedule {
    let start: Date
    let end: Date
  }

  private struct ComputedStatus {
    let status: ShiftPreviewStatus
    let secondsUntilEnd: Int
    let relativeText: String
  }

  private var formattedDate: String {
    guard let date = Date.fromISODateString(shift.shift_date) else { return "" }
    return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).sentenceCased()
  }

  private var formattedTimeRange: String {
    ShiftCardFormatter.localizedTimeRange(
      start: shift.start_time,
      end: shift.end_time,
      locale: Locale.appLocale,
      separator: " – "
    )
  }

  private var formattedEarnings: String {
    CurrencyConfig.format(shift.computed.gross, currency: currency ?? "kr")
  }

  private var schedule: ShiftSchedule? {
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

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let computed = computeStatus(at: context.date)

      HStack(alignment: .top, spacing: Spacing.md) {
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(formattedDate)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
            .lineLimit(1)

          Text(formattedTimeRange)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
            .lineLimit(1)
            .environment(\.layoutDirection, .leftToRight)
        }

        Spacer(minLength: Spacing.xs)

        VStack(alignment: .trailing, spacing: Spacing.micro) {
          Text(statusText(computed: computed))
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

          if previewShowsEarnings {
            Text(formattedEarnings)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)
              .lineLimit(1)
              .fixedSize(horizontal: true, vertical: false)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, Spacing.xxs)
    }
  }

  private var previewShowsEarnings: Bool {
    showEarnings
  }

  private func computeStatus(at now: Date) -> ComputedStatus {
    guard let schedule else {
      return ComputedStatus(status: status, secondsUntilEnd: 0, relativeText: "")
    }

    let start = schedule.start
    let end = schedule.end
    let currentStatus: ShiftPreviewStatus
    let secondsUntilEnd: Int

    if now >= start && now <= end {
      currentStatus = .active
      secondsUntilEnd = Int(ceil(end.timeIntervalSince(now)))
    } else if now < start {
      currentStatus = .upcoming
      secondsUntilEnd = 0
    } else {
      currentStatus = .past
      secondsUntilEnd = 0
    }

    let referenceTime = now > end ? end : start
    let relativeText = CountdownFormatter.formatRelativeCountdown(
      referenceDate: referenceTime,
      dayBoundaryReferenceDate: start,
      now: now
    )

    return ComputedStatus(
      status: currentStatus,
      secondsUntilEnd: secondsUntilEnd,
      relativeText: relativeText
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
}

private struct FriendShiftPreviewShadowModifier: ViewModifier {
  let style: FriendShiftPreviewStatusCardStyle

  func body(content: Content) -> some View {
    switch style {
    case .card:
      content.tidexCardShadow(.subtle, cornerRadius: CornerRadius.lg)
    case .embedded:
      content
    case .toolbarExtension:
      content
    }
  }
}
