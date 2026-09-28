import SwiftUI

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

  private let ringWidth: CGFloat = 3
  private let ringGap: CGFloat = 3
  private let cardCornerRadius = CornerRadius.xxxl

  private var shiftTiming: FriendShiftTiming? {
    preview?.shift.flatMap { FriendShiftTiming(shift: $0) }
  }

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.displayScale) private var displayScale

  /// As tall as a two-line message bubble, so the avatar lines up with the bubble beside it.
  /// Capped at the largest non-accessibility text size.
  private var avatarSize: CGFloat {
    (uiFont(.subheadline).lineHeight * 2 + Spacing.xxxs * 2).rounded()
  }

  /// Lifts the shift status onto the name's baseline. Both rows end at the same height, and
  /// the name's font reaches further below its baseline.
  private var statusBaselineOffset: CGFloat {
    uiFont(.caption1).descender - uiFont(.headline).descender
  }

  /// Empty space as tall as a two-line message bubble. The avatar row and the shift times both
  /// take this height, so the two columns line up exactly.
  private var twoLineBubbleSpace: some View {
    Text(verbatim: "A\nA")
      .font(.tidexSubheadline)
      .lineLimit(2)
      .padding(.vertical, Spacing.xxxs)
      .hidden()
      .accessibilityHidden(true)
  }

  private func uiFont(_ style: UIFont.TextStyle) -> UIFont {
    UIFont.preferredFont(
      forTextStyle: style,
      compatibleWith: UITraitCollection(
        preferredContentSizeCategory: UIContentSizeCategory(min(dynamicTypeSize, .xxxLarge))
      )
    )
  }

  private var showsMessage: Bool {
    isTyping || messagePreview != nil
  }

  private var showsShiftTile: Bool {
    isCalendarAvailable || shiftTiming != nil
  }

  var body: some View {
    // Stack the shift tile under the conversation when large text leaves no room beside it.
    // Side by side, bottom alignment puts the shift status on the name's line and the times
    // beside the avatar, since both halves end in a row of avatar height.
    let isStacked = dynamicTypeSize.isAccessibilitySize
    let layout =
      isStacked
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
      : AnyLayout(HStackLayout(alignment: .bottom, spacing: Spacing.md))

    // Tick every second only while a shift needs a live countdown.
    TimelineView(.periodic(from: .now, by: shiftTiming == nil ? 60 : 1)) { context in
      layout {
        conversation(at: context.date)

        // Without a tile the empty column still holds its width, so the message times line up
        // with the other cards.
        if showsShiftTile || !isStacked {
          shiftTile(at: context.date)
            // The line sits on the tile's edge rather than mid-gap. The tile centers its text, so
            // this leaves about as much room on the text's side as on the bubble's.
            .overlay(alignment: .leading) {
              if showsShiftTile && !isStacked {
                Rectangle()
                  .fill(Color.tidexSeparator)
                  .frame(width: 1 / displayScale)
              }
            }
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
  }

  /// The name row on top, with the avatar and the message bubble under it.
  private func conversation(at now: Date) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      nameRow(at: now)

      ZStack(alignment: .leading) {
        twoLineBubbleSpace

        HStack(spacing: Spacing.sm) {
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

          if showsMessage {
            FriendCardMessageBubble(preview: messagePreview, isTyping: isTyping)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityHint(Text(.friendsChatMessageAction))
  }

  /// During a shift the photo shrinks inside the progress ring, so the avatar keeps its size.
  private func avatar(progress: Double?) -> some View {
    let inset = progress == nil ? 0 : ringWidth + ringGap
    let photoSize = avatarSize - inset * 2

    return AvatarView(
      url: sharer.avatarUrl,
      initials: sharer.initials,
      size: photoSize,
      cornerRadius: photoSize / 2
    )
    .padding(inset)
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
        HStack(spacing: Spacing.micro) {
          Image(systemName: messagePreview.metaSymbol)
            .imageScale(.small)
            .accessibilityLabel(Text(messagePreview.metaLabel))

          Text(messagePreview.metaText(at: now))
            .monospacedDigit()
        }
        .font(.tidexCaptionRegular)
        .foregroundColor(messagePreview.metaColor)
        .lineLimit(1)
        .fixedSize()
      }
    }
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

// MARK: - Shift tile

extension FriendCard {
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

  /// Status over stacked start and end times, like the calendar day cell. The times fill a row
  /// as tall as the avatar, which lines them up with it. "+1" marks an end time on the next day.
  private func shiftTileLabel(at now: Date) -> some View {
    let isStacked = dynamicTypeSize.isAccessibilitySize
    let alignment: HorizontalAlignment = isStacked ? .leading : .center

    return VStack(alignment: alignment, spacing: Spacing.xs) {
      shiftStatus(at: now)

      ZStack {
        if !isStacked {
          twoLineBubbleSpace
        }

        VStack(alignment: alignment, spacing: Spacing.micro) {
          shiftTimes(at: now)
        }
      }
    }
    .foregroundColor(.tidexBlue)
    .monospacedDigit()
    .lineLimit(1)
    // A fixed width keeps the shift column aligned across cards. The full card height keeps the
    // hairline the same length on every card. A shift keeps to the bottom so its rows line up
    // with the conversation, and the calendar entry sits in the middle.
    .frame(width: isStacked ? nil : 80)
    .frame(
      maxHeight: isStacked ? nil : .infinity,
      alignment: shiftTiming == nil && !isRefreshing ? .center : .bottom
    )
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func shiftStatus(at now: Date) -> some View {
    if isRefreshing {
      skeletonBars(count: 1)
    } else if let timing = shiftTiming {
      Text(timing.statusText(at: now, compact: true))
        .font(.tidexCaptionStrong)
        .foregroundColor(statusColor(timing.status(at: now)))
        .minimumScaleFactor(0.7)
        .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 0 : statusBaselineOffset)
    }
  }

  @ViewBuilder
  private func shiftTimes(at now: Date) -> some View {
    if isRefreshing {
      skeletonBars(count: 2)
    } else if let timing = shiftTiming, let shift = preview?.shift {
      let crossesMidnight = !Calendar.current.isDate(timing.end, inSameDayAs: timing.start)
      let endTime = ShiftCardFormatter.localizedTime(shift.end_time, locale: Locale.appLocale)

      Group {
        Text(ShiftCardFormatter.localizedTime(shift.start_time, locale: Locale.appLocale))
        Text(verbatim: endTime + (crossesMidnight ? "+1" : ""))
          .accessibilityLabel(
            crossesMidnight ? Text(.friendsCardEndsNextDay(endTime)) : Text(verbatim: endTime))
      }
      .font(.tidexSubheadline.weight(.semibold))
      .foregroundColor(timing.status(at: now) == .past ? .tidexTextSecondary : .tidexTextPrimary)
    } else if isCalendarAvailable {
      Image(systemName: "calendar")
        .font(.tidexHeadline)
        .accessibilityHidden(true)

      Text(.tabsShifts)
        .font(.tidexCaptionStrong)
    }
  }

  private func skeletonBars(count: Int) -> some View {
    ForEach(0..<count, id: \.self) { _ in
      RoundedRectangle(cornerRadius: CornerRadius.xxs)
        .fill(Color.tidexTextMuted.opacity(0.25))
        .frame(width: 44, height: 12)
    }
    .shimmer(duration: 1.2)
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
