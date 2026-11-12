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
  var connection: Connection = .mutual
  var isSharingBack = false
  var onShareBack: (() -> Void)?

  private let ringWidth: CGFloat = 3
  private let ringGap: CGFloat = 3
  private let cardCornerRadius = CornerRadius.card

  private var shiftTiming: FriendShiftTiming? {
    preview?.shift.flatMap { FriendShiftTiming(shift: $0) }
  }

  private var shiftInterval: SharedShiftInterval? {
    preview?.shift.flatMap { shift in
      SharedShiftInterval(
        date: shift.shift_date, startTime: shift.start_time, endTime: shift.end_time,
        timeZoneIdentifier: shift.ownerTimeZone)
    }
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

  var body: some View {
    // Stack the shift tile under the conversation when large text leaves no room beside it.
    // Side by side, bottom alignment puts the shift status on the name's line and the times
    // beside the avatar, since both halves end in a row of avatar height.
    let isStacked = dynamicTypeSize.isAccessibilitySize
    let layout =
      isStacked
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
      : AnyLayout(HStackLayout(alignment: .bottom, spacing: Spacing.md))

    VStack(alignment: .leading, spacing: Spacing.sm) {
      // Tick every second only while a shift needs a live countdown.
      TimelineView(.periodic(from: .now, by: shiftTiming == nil ? 60 : 1)) { context in
        layout {
          conversation(at: context.date)

          shiftTile(at: context.date)
            // The line sits on the tile's edge rather than mid-gap. The tile centers its text, so
            // this leaves about as much room on the text's side as on the bubble's.
            .overlay(alignment: .leading) {
              if !isStacked {
                Rectangle()
                  .fill(Color.tidexSeparator)
                  .frame(width: 1 / displayScale)
              }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
      }

      if connection == .theyShareOnly, let onShareBack {
        shareBackRow(action: onShareBack)
      }
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
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityHint(Text(.friendsChatMessageAction))
    // The long press and the avatar tap open the profile, so assistive tech gets an action.
    .accessibilityAction(named: Text(.friendsAccessibilityViewProfile)) {
      onProfileRequested?()
    }
  }

  /// During a shift the photo shrinks inside the progress ring, so the avatar keeps its size.
  private func avatar(progress: Double?) -> some View {
    let inset = progress == nil ? 0 : ringWidth + ringGap
    let photoSize = avatarSize - inset * 2

    return AvatarView(
      url: sharer.avatarUrl,
      initials: sharer.initials,
      size: photoSize
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

  @ViewBuilder
  private func nameRow(at now: Date) -> some View {
    // Long names and the message time need their own lines at accessibility text sizes.
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: Spacing.micro) {
        nameAndBadge
        messageMeta(at: now)
      }
    } else {
      HStack(spacing: Spacing.xxxs) {
        nameAndBadge

        Spacer(minLength: Spacing.xxs)

        messageMeta(at: now)
      }
    }
  }

  private var nameAndBadge: some View {
    HStack(spacing: Spacing.xxxs) {
      Text(sharer.displayName)
        .font(.tidexHeadline)
        .foregroundStyle(Color.tidexTextPrimary)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

      if unreadMessageCount > 0 {
        Text(verbatim: unreadMessageCount > 9 ? "9+" : "\(unreadMessageCount)")
          .font(.tidexCaptionStrong)
          .monospacedDigit()
          .foregroundStyle(Color.tidexTextOnBrand)
          .padding(.horizontal, Spacing.xxxs)
          .frame(minWidth: 20, minHeight: 20)
          .background(Color.tidexBlue, in: Capsule())
          .accessibilityLabel(Text(.friendsAccessibilityUnreadCount(unreadMessageCount)))
      }
    }
  }

  @ViewBuilder
  private func messageMeta(at now: Date) -> some View {
    if !isTyping, let messagePreview {
      HStack(spacing: Spacing.micro) {
        Image(systemName: messagePreview.metaSymbol)
          .imageScale(.small)
          .accessibilityLabel(Text(messagePreview.metaLabel))

        Text(messagePreview.metaText(at: now))
          .monospacedDigit()
          .accessibilityLabel(Text(spokenTimestamp(of: messagePreview, at: now)))
      }
      .font(.tidexCaptionRegular)
      .foregroundStyle(messagePreview.metaColor)
      .lineLimit(1)
      .fixedSize()
    }
  }

  /// The compact "5m" text reads as "5 meters" aloud, so VoiceOver gets the spelled-out form.
  private func spokenTimestamp(of preview: FriendCardMessagePreview, at now: Date) -> String {
    guard now.timeIntervalSince(preview.timestamp) >= 60 else { return preview.metaText(at: now) }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale.appLocale
    formatter.unitsStyle = .full
    return formatter.localizedString(for: preview.timestamp, relativeTo: now)
  }

  private func statusColor(_ status: ShiftPreviewStatus) -> Color {
    switch status {
    case .active: .tidexSuccess
    case .upcoming: .tidexBlueText
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

extension FriendCard {
  /// Which way shifts are shared between the user and this friend.
  enum Connection: Equatable {
    case mutual
    /// They share with the user, who does not share back yet. The card offers Share back.
    case theyShareOnly
    /// The user shares with them, and they do not share back yet.
    case userSharesOnly
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
      .accessibilityLabel(shiftTileAccessibilityLabel(at: now))
      .accessibilityInputLabels(shiftTileInputLabels(at: now))
      .accessibilityHint(Text(.friendsAccessibilityOpensCalendar))
    } else {
      shiftTileLabel(at: now)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shiftTileAccessibilityLabel(at: now))
    }
  }

  /// Names the friend, since every card has a shift tile, then reads the status and times.
  private func shiftTileAccessibilityLabel(at now: Date) -> String {
    var parts = [String(localized: .friendsAccessibilityShiftsFor(sharer.firstNameOnly))]
    if let emptyTileText, !isRefreshing {
      parts.append(String(localized: emptyTileText))
    }
    if let timing = shiftTiming, let interval = shiftInterval, !isRefreshing {
      parts.append(timing.statusText(at: now, compact: false))
      // The globe beside the clocks marks times converted to the viewer's zone.
      if interval.differs() { parts.append(String(localized: .sharingTimeYourTime)) }
      parts.append(interval.datedTimeRange(locale: .appLocale))
      if !Calendar.gregorianCurrent.isDate(interval.start, inSameDayAs: interval.end) {
        parts.append(
          String(
            localized: .friendsCardEndsNextDay(interval.clock(interval.end, locale: .appLocale))))
      }
    }
    return parts.joined(separator: ", ")
  }

  /// Voice Control matches the visible text, which differs from the spoken label.
  private func shiftTileInputLabels(at now: Date) -> [String] {
    var labels = [String(localized: .tabsShifts)]
    if let timing = shiftTiming, !isRefreshing {
      labels.append(timing.statusText(at: now, compact: true))
    }
    return labels
  }

  /// At least 80 points, and wide enough for the widest clock row, the globe beside a next-day
  /// end time such as "06:00+1", so large text never truncates a clock. Clocks are always HH:mm.
  private var shiftTileWidth: CGFloat {
    let clockFont = UIFont.monospacedDigitSystemFont(
      ofSize: uiFont(.subheadline).pointSize, weight: .semibold)
    let clock = ("00:00+1" as NSString).size(withAttributes: [.font: clockFont]).width
    let globe =
      UIImage(
        systemName: "globe",
        withConfiguration: UIImage.SymbolConfiguration(font: uiFont(.caption1), scale: .small)
      )?.size.width ?? 0
    return max(80, (globe + Spacing.micro + clock).rounded(.up))
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
    .foregroundStyle(Color.tidexBlueText)
    .monospacedDigit()
    .lineLimit(isStacked ? nil : 1)
    // A shared width keeps the shift column aligned across cards. The full card height keeps the
    // hairline the same length on every card. A shift keeps to the bottom so its rows line up
    // with the conversation, and the calendar entry sits in the middle.
    .frame(width: isStacked ? nil : shiftTileWidth)
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
        .foregroundStyle(statusColor(timing.status(at: now)))
        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
        .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 0 : statusBaselineOffset)
    }
  }

  @ViewBuilder
  private func shiftTimes(at now: Date) -> some View {
    if isRefreshing {
      skeletonBars(count: 2)
    } else if let timing = shiftTiming, let interval = shiftInterval {
      if interval.differs() {
        // One globe centered beside both clocks, so it reads as marking the pair.
        HStack(spacing: Spacing.micro) {
          Image(systemName: "globe")
            .font(.tidexCaption)
            .imageScale(.small)
            .foregroundStyle(Color.tidexTextMuted)
            .accessibilityHidden(true)

          VStack(
            alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center,
            spacing: Spacing.micro
          ) {
            clocks(timing, interval, at: now)
          }
        }
      } else {
        clocks(timing, interval, at: now)
      }
    } else if let emptyTileText {
      // Wrapped text fills the tile, so it needs its own gap from the hairline on its leading edge.
      let isStacked = dynamicTypeSize.isAccessibilitySize
      Text(emptyTileText)
        .font(.tidexCaptionStrong)
        .foregroundStyle(Color.tidexTextMuted)
        .multilineTextAlignment(isStacked ? .leading : .center)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, isStacked ? 0 : Spacing.xs)
    } else if isCalendarAvailable {
      Image(systemName: "calendar")
        .font(.tidexHeadline)
        .accessibilityHidden(true)

      Text(.tabsShifts)
        .font(.tidexCaptionStrong)
    }
  }

  /// Says plainly why the tile has no shift: they share nothing yet, or have no shifts yet.
  private var emptyTileText: LocalizedStringResource? {
    guard shiftTiming == nil else { return nil }
    if connection == .userSharesOnly { return .sharingCardNotSharingYet }
    return isCalendarAvailable ? nil : .sharingCardNoShiftsYet
  }

  /// For a friend who shares with the user while the user shares nothing back.
  private func shareBackRow(action: @escaping () -> Void) -> some View {
    let title = String(localized: .sharingShareBack)
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
      : AnyLayout(HStackLayout(spacing: Spacing.sm))
    return layout {
      Text(.sharingCardCannotSeeYours(sharer.firstNameOnly))
        .font(.tidexFootnote)
        .foregroundStyle(Color.tidexTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: action) {
        Text(title)
          .font(.tidexLabelStrong)
          .opacity(isSharingBack ? 0 : 1)
          .overlay {
            if isSharingBack {
              ProgressView()
                .tint(.tidexTextOnBrand)
            }
          }
          .foregroundStyle(Color.tidexTextOnBrand)
          .padding(.horizontal, Spacing.md)
          .padding(.vertical, Spacing.xs)
          .background(Color.tidexBlue, in: Capsule())
      }
      .buttonStyle(.plain)
      .disabled(isSharingBack)
      .accessibilityLabel("\(title), \(sharer.displayName)")
      .accessibilityInputLabels([title])
    }
    .padding(.top, Spacing.sm)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(Color.tidexSeparator)
        .frame(height: 1 / displayScale)
    }
  }

  private func clocks(
    _ timing: FriendShiftTiming, _ interval: SharedShiftInterval, at now: Date
  ) -> some View {
    Group {
      Text(interval.clock(timing.start, locale: .appLocale))
      let endText = interval.clock(timing.end, locale: .appLocale)
      let crossesMidnight = !Calendar.gregorianCurrent.isDate(
        timing.start, inSameDayAs: timing.end)
      Text(verbatim: endText + (crossesMidnight ? "+1" : ""))
        .accessibilityLabel(
          crossesMidnight ? Text(.friendsCardEndsNextDay(endText)) : Text(verbatim: endText))
    }
    .font(.tidexSubheadline.weight(.semibold))
    .foregroundStyle(
      timing.status(at: now) == .past ? Color.tidexTextSecondary : Color.tidexTextPrimary)
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
/// Shown when nobody shares with the user. It leads with sending an invite link, since
/// opening one is how a friend starts sharing with the user.
struct FriendsListEmptyState: View {
  let onInvite: () -> Void
  let onAddByIdentifier: () -> Void

  @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 48

  var body: some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "person.2")
        .font(.system(size: iconSize))
        .foregroundStyle(Color.tidexBlueText)
        .accessibilityHidden(true)

      VStack(spacing: Spacing.xs) {
        Text(.sharingEmptyTitle)
          .font(.tidexTitle)
          .foregroundStyle(Color.tidexTextPrimary)
          .accessibilityAddTraits(.isHeader)

        Text(.sharingEmptyBody)
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexTextSecondary)
      }

      VStack(spacing: Spacing.xxs) {
        PrimaryButton(title: String(localized: .sharingInviteAction), action: onInvite)

        Button(action: onAddByIdentifier) {
          Text(.sharingAddByIdentifier)
            .font(.tidexButton)
            .foregroundStyle(Color.tidexBlueText)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Spacing.buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .frame(maxWidth: 360)
      .padding(.top, Spacing.xs)

      Text(.sharingEmptyGotLink)
        .font(.tidexFootnote)
        .foregroundStyle(Color.tidexTextMuted)
    }
    .multilineTextAlignment(.center)
    .padding(.horizontal, Spacing.xl)
    .frame(maxWidth: .infinity)
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
