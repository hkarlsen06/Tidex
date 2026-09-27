import SwiftUI

enum FriendCardMessageState: Equatable {
  case outgoingSending
  case outgoingSent
  case outgoingOpened
  case outgoingFailed
  case incomingUnread
  case incomingOpened
}

struct FriendCardMessagePreview: Equatable {
  let text: String
  let timestamp: Date
  let state: FriendCardMessageState

  var metaColor: Color {
    switch state {
    case .incomingUnread: .tidexBlue
    case .outgoingFailed: .tidexError
    default: .tidexTextMuted
    }
  }

  /// Relative time, prefixed with the delivery state for the user's own messages.
  func metaText(at now: Date) -> String {
    let timestamp = FriendCardMessagePreviewTimestampFormatter.relativeTimestamp(
      messageDate: timestamp,
      referenceDate: now
    )
    let label: LocalizedStringResource? =
      switch state {
      case .outgoingSending: .friendsChatStatusSending
      case .outgoingSent: .friendsChatPreviewLabelSent
      case .outgoingOpened: .friendsChatPreviewLabelOpened
      case .outgoingFailed: .friendsChatStatusFailed
      case .incomingUnread, .incomingOpened: nil
      }
    return label.map { "\(String(localized: $0)) \(timestamp)" } ?? timestamp
  }
}

/// A friend who shares their shifts with the current user. The left side is the conversation:
/// name on top and the last message as a chat bubble, gray from them and blue from the user.
/// The right side is a shift tile that opens their calendar. A progress ring around the avatar
/// shows how far into a shift they are.
struct FriendCard: View {
  enum SurfaceStyle {
    case standard
    case example
  }

  let sharer: SharedUser
  let preview: SharerShiftPreview?
  let messagePreview: FriendCardMessagePreview?
  let isTyping: Bool
  let isSelected: Bool
  let isRefreshing: Bool
  let onChatTap: () -> Void
  let onCalendarTap: () -> Void
  var onProfileRequested: (() -> Void)?
  var isCalendarAvailable = true
  var isOpeningMessage = false
  var unreadMessageCount = 0
  var surfaceStyle: SurfaceStyle = .standard

  private let avatarSize = AvatarView.Size.large
  private let ringWidth: CGFloat = 3
  private let ringGap: CGFloat = 3
  private let cardCornerRadius = CornerRadius.xxxl

  private var shiftTiming: FriendShiftTiming? {
    preview?.shift.flatMap { FriendShiftTiming(shift: $0) }
  }

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var showsMessage: Bool {
    isTyping || messagePreview != nil
  }

  private var showsShiftTile: Bool {
    isCalendarAvailable || shiftTiming != nil
  }

  var body: some View {
    // Stack the shift tile under the conversation when large text leaves no room beside it.
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
      : AnyLayout(HStackLayout(spacing: Spacing.sm))

    // Tick every second only while a shift needs a live countdown.
    TimelineView(.periodic(from: .now, by: shiftTiming == nil ? 60 : 1)) { context in
      layout {
        conversation(at: context.date)

        if showsShiftTile {
          shiftTile(at: context.date)
        }
      }
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(Spacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .onTapGesture(perform: onChatTap)
    .accessibilityAddTraits(.isButton)
    .onLongPressGesture {
      onProfileRequested?()
    }
    .allowsHitTesting(!isOpeningMessage)
    .background(
      RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
        .fill(backgroundFillColor)
    )
    .overlay(
      RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
        .strokeBorder(borderColor, style: borderStyle)
    )
    .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
    .modifier(
      FriendCardShadowModifier(
        isEnabled: surfaceStyle == .standard,
        cornerRadius: cardCornerRadius
      )
    )
  }

  private func conversation(at now: Date) -> some View {
    HStack(spacing: Spacing.xs) {
      avatar(
        progress: shiftTiming.flatMap { timing in
          timing.status(at: now) == .active ? timing.progress(at: now) : nil
        }
      )
      .contentShape(Circle())
      .onTapGesture {
        onProfileRequested?()
      }
      // The avatar is a shortcut for sighted users; VoiceOver reads the card as one chat button.
      .accessibilityAddTraits(.isButton)
      .accessibilityHidden(true)

      FriendCardMessageColumn(spacing: Spacing.xxxs) {
        nameRow(at: now)

        if showsMessage {
          FriendCardMessageBubble(preview: messagePreview, isTyping: isTyping)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isButton)
      .accessibilityHint(Text(.friendsChatMessageAction))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func avatar(progress: Double?) -> some View {
    AvatarView(
      url: sharer.avatarUrl,
      initials: sharer.initials,
      size: avatarSize,
      cornerRadius: avatarSize / 2
    )
    .padding(ringWidth + ringGap)
    .overlay {
      if let progress {
        Circle()
          .stroke(Color.tidexSuccess.opacity(0.2), lineWidth: ringWidth)
          .padding(ringWidth / 2)

        Circle()
          .trim(from: 0, to: progress)
          .stroke(Color.tidexSuccess, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .padding(ringWidth / 2)
          .animation(.linear(duration: 1), value: progress)
      }
    }
  }

  private func nameRow(at now: Date) -> some View {
    HStack(spacing: Spacing.xxxs) {
      Text(sharer.displayName)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)
        .lineLimit(1)

      if unreadMessageCount > 0 {
        Text(verbatim: unreadMessageCount > 9 ? "9+" : "\(unreadMessageCount)")
          .font(.tidexCaptionStrong)
          .monospacedDigit()
          .foregroundColor(.tidexTextOnBrand)
          .padding(.horizontal, Spacing.xxxs)
          .frame(minWidth: 20, minHeight: 20)
          .background(Color.tidexBlue, in: Capsule())
      }

      Spacer(minLength: Spacing.xxs)

      if !isTyping, let messagePreview {
        Text(messagePreview.metaText(at: now))
          .font(.tidexCaptionRegular)
          .foregroundColor(messagePreview.metaColor)
          .monospacedDigit()
          .lineLimit(1)
          .fixedSize()
      }
    }
  }

  /// Shift status and time range. Tapping it opens the friend's calendar; without a shift it
  /// is only the calendar entry.
  @ViewBuilder
  private func shiftTile(at now: Date) -> some View {
    if isCalendarAvailable && !isRefreshing {
      Button(action: onCalendarTap) {
        shiftTileLabel(at: now)
      }
      .buttonStyle(.plain)
    } else {
      shiftTileLabel(at: now)
    }
  }

  /// Status over stacked start and end times, like the calendar day cell. "+1" marks an end time
  /// on the next day.
  private func shiftTileLabel(at now: Date) -> some View {
    let isStacked = dynamicTypeSize.isAccessibilitySize

    return VStack(alignment: isStacked ? .leading : .center, spacing: Spacing.micro) {
      if isRefreshing {
        ForEach(0..<3, id: \.self) { _ in
          RoundedRectangle(cornerRadius: CornerRadius.xxs)
            .fill(Color.tidexTextMuted.opacity(0.25))
            .frame(width: 44, height: 12)
        }
        .shimmer(duration: 1.2)
      } else if let timing = shiftTiming, let shift = preview?.shift {
        let status = timing.status(at: now)
        let crossesMidnight = !Calendar.current.isDate(timing.end, inSameDayAs: timing.start)

        Text(timing.statusText(at: now))
          .font(.tidexCaptionStrong)
          .foregroundColor(statusColor(status))
          .minimumScaleFactor(0.7)

        let endTime = ShiftCardFormatter.localizedTime(shift.end_time, locale: Locale.appLocale)

        Group {
          Text(ShiftCardFormatter.localizedTime(shift.start_time, locale: Locale.appLocale))
          Text(verbatim: endTime + (crossesMidnight ? "+1" : ""))
            .accessibilityLabel(
              crossesMidnight ? Text(.friendsCardEndsNextDay(endTime)) : Text(verbatim: endTime))
        }
        .font(.tidexSubheadline.weight(.semibold))
        .foregroundColor(status == .past ? .tidexTextSecondary : .tidexTextPrimary)
      } else {
        Image(systemName: "calendar")
          .font(.tidexHeadline)
          .accessibilityHidden(true)

        Text(.tabsShifts)
          .font(.tidexCaptionStrong)
      }
    }
    .foregroundColor(.tidexBlue)
    .monospacedDigit()
    .lineLimit(1)
    // A fixed width keeps the shift column aligned across cards.
    .frame(width: isStacked ? nil : 80)
    .frame(maxHeight: .infinity)
    .contentShape(Rectangle())
  }

  private func statusColor(_ status: ShiftPreviewStatus) -> Color {
    switch status {
    case .active: .tidexSuccess
    case .upcoming: .tidexBlue
    case .past: .tidexTextMuted
    }
  }

  private var backgroundFillColor: Color {
    switch surfaceStyle {
    case .standard:
      isSelected ? Color.tidexBlue.opacity(0.1) : Color.tidexSurfacePrimary

    case .example:
      .clear
    }
  }

  private var borderColor: Color {
    switch surfaceStyle {
    case .standard:
      isSelected ? .tidexBlue : .clear

    case .example:
      .tidexBorder
    }
  }

  private var borderStyle: StrokeStyle {
    switch surfaceStyle {
    case .standard:
      StrokeStyle(lineWidth: 2)

    case .example:
      StrokeStyle(lineWidth: 1.5, dash: [7, 5])
    }
  }
}

private struct FriendCardShadowModifier: ViewModifier {
  let isEnabled: Bool
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    if isEnabled {
      content.tidexCardShadow(cornerRadius: cornerRadius)
    } else {
      content
    }
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
      messagePreview: FriendCardMessagePreview(
        text: "Can you cover Friday?",
        timestamp: Date().addingTimeInterval(-900),
        state: .incomingUnread
      ),
      isTyping: false,
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
      messagePreview: FriendCardMessagePreview(
        text: "I opened the shift snapshot",
        timestamp: Date().addingTimeInterval(-7_200),
        state: .outgoingOpened
      ),
      isTyping: false,
      isSelected: true,
      isRefreshing: false,
      onChatTap: {},
      onCalendarTap: {}
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
