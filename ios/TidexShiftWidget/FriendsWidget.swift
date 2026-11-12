// swiftlint:disable file_length function_body_length cyclomatic_complexity type_body_length
// Widget files require multiple size-specific views that cannot be easily split
import SwiftUI
import WidgetKit

// MARK: - Friend Preview Model

/// Represents a single friend's preview for the widget
struct FriendPreview: Equatable, Identifiable {
  let id: String
  let displayName: String
  let initials: String
  let shiftDate: String?  // Formatted date: "I dag", "I morgen", etc.
  let rawDate: String?  // Raw date for sorting: "2026-02-01"
  let timeRange: String?  // "09:00 – 17:00"
  let status: FriendShiftStatus
  let daysRemaining: Int?
  /// The schedule's zone differs from the viewer's, so the clocks shown are converted.
  var showsConvertedClock = false
  var interval: SharedShiftInterval?
  var avatar: UIImage?

  enum FriendShiftStatus: Equatable {
    case active
    case upcoming
    case past
    case none
  }
}

// MARK: - Widget Entry

struct FriendsWidgetEntry: TimelineEntry {
  let date: Date

  /// Up to 5 friends to display
  let friends: [FriendPreview]

  /// Whether there are any friends at all
  let hasAnyFriends: Bool

  /// Deep link URL to open sharing tab
  var deepLinkURL: URL? {
    URL(string: "tidex://sharing")
  }

  // MARK: - Factory Methods

  internal static func placeholder() -> Self {
    Self(
      date: Date(),
      friends: [
        FriendPreview(
          id: "1",
          displayName: "Ola Nordmann",
          initials: "ON",
          shiftDate: "I dag",
          rawDate: nil,
          timeRange: "07:00 – 15:00",
          status: .active,
          daysRemaining: 0
        ),
        FriendPreview(
          id: "2",
          displayName: "Kari Hansen",
          initials: "KH",
          shiftDate: "I morgen",
          rawDate: nil,
          timeRange: "09:00 – 17:00",
          status: .upcoming,
          daysRemaining: 1
        ),
        FriendPreview(
          id: "3",
          displayName: "Per Svendsen",
          initials: "PS",
          shiftDate: "Man 3. feb",
          rawDate: nil,
          timeRange: "08:00 – 16:00",
          status: .upcoming,
          daysRemaining: 3
        ),
      ],
      hasAnyFriends: true
    )
  }

  internal static func empty() -> Self {
    Self(
      date: Date(),
      friends: [],
      hasAnyFriends: false
    )
  }
}

// MARK: - Timeline Provider

struct FriendsWidgetProvider: TimelineProvider {
  internal func placeholder(in _: Context) -> FriendsWidgetEntry {
    FriendsWidgetEntry.placeholder()
  }

  internal func getSnapshot(in _: Context, completion: (FriendsWidgetEntry) -> Void) {
    completion(FriendsWidgetEntry.placeholder())
  }

  internal func getTimeline(in _: Context, completion: (Timeline<FriendsWidgetEntry>) -> Void) {
    let now = Date()
    let shifts = loadShifts()
    let sharers = loadSharers()
    let avatars = loadAvatars(for: sharers)
    let nextMidnight =
      Calendar.gregorianCurrent.nextDate(
        after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
        matchingPolicy: .nextTime) ?? now.addingTimeInterval(24 * 60 * 60)
    let boundaries = shifts.compactMap {
      SharedShiftInterval(
        date: $0.shiftDate, startTime: $0.startTime, endTime: $0.endTime,
        timeZoneIdentifier: $0.ownerTimeZone)
    }.flatMap { [$0.start, $0.end] }
    // The day bar's current-time line moves on every quarter hour.
    let quarter: TimeInterval = 15 * 60
    let firstQuarter = Date(
      timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / quarter).rounded(.down)
        * quarter + quarter)
    let quarterHours = sequence(first: firstQuarter) { $0.addingTimeInterval(quarter) }
      .prefix { $0 < nextMidnight }
    let dates =
      [now] + Set(boundaries.filter { $0 > now && $0 < nextMidnight } + quarterHours).sorted()
    let entries = dates.map {
      createEntry(at: $0, shifts: shifts, sharers: sharers, avatars: avatars)
    }
    completion(Timeline(entries: entries, policy: .after(nextMidnight)))
  }

  private func loadSharers() -> [WidgetSharer] {
    guard let defaults = WidgetAppGroup.sharedUserDefaults(),
      let json = defaults.string(forKey: WidgetAppGroup.friendSharersKey),
      let data = json.data(using: .utf8),
      let sharers = try? JSONDecoder().decode([WidgetSharer].self, from: data)
    else {
      return []
    }
    return sharers
  }

  /// Loaded once per timeline, so every entry shares the same images.
  private func loadAvatars(for sharers: [WidgetSharer]) -> [String: UIImage] {
    guard
      let directory = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: WidgetAppGroup.id)?
        .appendingPathComponent("friend-avatars", isDirectory: true)
    else { return [:] }
    var avatars: [String: UIImage] = [:]
    for sharer in sharers {
      avatars[sharer.id] = UIImage(
        contentsOfFile: directory.appendingPathComponent("\(sharer.id).jpg").path)
    }
    return avatars
  }

  private func loadShifts() -> [StoredFriendShift] {
    guard let defaults = WidgetAppGroup.sharedUserDefaults(),
      let json = defaults.string(forKey: WidgetAppGroup.friendShiftsKey),
      let data = json.data(using: .utf8),
      let shifts = try? JSONDecoder().decode([StoredFriendShift].self, from: data)
    else {
      return []
    }
    return shifts
  }

  private func createEntry(
    at now: Date, shifts: [StoredFriendShift], sharers: [WidgetSharer],
    avatars: [String: UIImage]
  ) -> FriendsWidgetEntry {
    guard !sharers.isEmpty else { return FriendsWidgetEntry.empty() }

    // Build friend previews
    var previews: [FriendPreview] = []

    for sharer in sharers {
      // Find shift for this sharer
      let shift = shifts.first { $0.sharerId == sharer.id }

      if let shift,
        let interval = SharedShiftInterval(
          date: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime,
          timeZoneIdentifier: shift.ownerTimeZone
        )
      {
        // Calculate layout state
        let (status, daysRemaining) = determineStatus(
          interval: interval,
          now: now
        )
        let formattedDate = formatShiftDate(
          interval.dateString(), daysRemaining: daysRemaining, now: now)

        previews.append(
          FriendPreview(
            id: sharer.id,
            displayName: sharer.displayName,
            initials: sharer.initials,
            shiftDate: formattedDate,
            rawDate: interval.dateString(),
            timeRange: interval.timeRange(),
            status: status,
            daysRemaining: daysRemaining,
            showsConvertedClock: interval.differs(),
            interval: interval
          ))
      } else {
        // No shift for this friend
        previews.append(
          FriendPreview(
            id: sharer.id,
            displayName: sharer.displayName,
            initials: sharer.initials,
            shiftDate: nil,
            rawDate: nil,
            timeRange: nil,
            status: .none,
            daysRemaining: nil
          ))
      }
    }

    // Sort by shift proximity:
    // 1. Active shifts (currently happening)
    // 2. Upcoming shifts (soonest first)
    // 3. Past shifts (most recent first)
    // 4. No shifts (alphabetical)
    previews.sort { lhs, rhs in
      // Active first
      if lhs.status == .active, rhs.status != .active {
        return true
      }
      if rhs.status == .active, lhs.status != .active {
        return false
      }

      // Upcoming by days remaining
      if lhs.status == .upcoming, rhs.status == .upcoming {
        return (lhs.daysRemaining ?? 999) < (rhs.daysRemaining ?? 999)
      }

      // Upcoming before past/none
      if lhs.status == .upcoming, rhs.status != .upcoming {
        return true
      }
      if rhs.status == .upcoming, lhs.status != .upcoming {
        return false
      }

      // Past by recency (closest to today first)
      if lhs.status == .past, rhs.status == .past {
        return abs(lhs.daysRemaining ?? 0) < abs(rhs.daysRemaining ?? 0)
      }

      // Past before none
      if lhs.status == .past, rhs.status == .none {
        return true
      }
      if rhs.status == .past, lhs.status == .none {
        return false
      }

      // Alphabetical for none
      return lhs.displayName < rhs.displayName
    }

    let friends = previews.map { preview in
      var preview = preview
      preview.avatar = avatars[preview.id]
      return preview
    }

    return FriendsWidgetEntry(
      date: now,
      friends: friends,
      hasAnyFriends: true
    )
  }

  // MARK: - Date Helpers

  private func determineStatus(
    interval: SharedShiftInterval,
    now: Date
  ) -> (FriendPreview.FriendShiftStatus, Int) {
    let calendar = Calendar.gregorianCurrent
    let days =
      calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: now),
        to: calendar.startOfDay(for: interval.start)
      ).day ?? 0
    if now < interval.start { return (.upcoming, days) }
    if now < interval.end { return (.active, 0) }
    return (.past, days)
  }

  private func formatShiftDate(_ dateString: String, daysRemaining: Int, now: Date) -> String {
    guard let shiftDate = parseShiftDate(dateString) else { return dateString }

    let calendar = Calendar.gregorianCurrent
    let today = calendar.startOfDay(for: now)
    let shiftDay = calendar.startOfDay(for: shiftDate)

    // Past shift
    if daysRemaining < 0 {
      let daysAgo = abs(daysRemaining)
      if daysAgo == 1 {
        return String(localized: .widgetYesterday)
      }
      return formattedWeekday(shiftDate, style: .abbreviatedDayMonth)
    }

    // Today
    if calendar.isDate(shiftDay, inSameDayAs: today) {
      return String(localized: .widgetToday)
    }

    // Tomorrow
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
      calendar.isDate(shiftDay, inSameDayAs: tomorrow)
    {
      return String(localized: .widgetTomorrow)
    }

    // Within a week: weekday only
    if daysRemaining <= 7 {
      return formattedWeekday(shiftDate, style: .fullWeekday)
    }

    // Weekday + date
    return formattedWeekday(shiftDate, style: .abbreviatedDayMonth)
  }
}

// MARK: - Widget View

struct FriendsWidgetView: View {
  let entry: FriendsWidgetEntry
  @Environment(\.widgetRenderingMode) var renderingMode

  // MARK: - Colors

  private var tidexBlue: Color {
    WidgetPalette.blue
  }

  private var tidexBlueText: Color {
    WidgetPalette.blueText
  }

  private var backgroundColor: Color {
    switch renderingMode {
    case .accented:
      return .clear

    case .vibrant:
      return Color.black.opacity(0.4)

    default:
      return WidgetPalette.background
    }
  }

  private var primaryTextColor: Color {
    switch renderingMode {
    case .accented, .vibrant:
      return .primary

    default:
      return WidgetPalette.textPrimary
    }
  }

  private var secondaryTextColor: Color {
    switch renderingMode {
    case .accented, .vibrant:
      return .secondary

    default:
      return WidgetPalette.textSecondary
    }
  }

  private var mutedTextColor: Color {
    switch renderingMode {
    case .accented, .vibrant:
      return .secondary

    default:
      return WidgetPalette.textMuted
    }
  }

  private var initialsBackground: Color {
    switch renderingMode {
    case .accented, .vibrant:
      return .secondary.opacity(0.2)

    default:
      return tidexBlue.opacity(0.2)
    }
  }

  private var initialsTextColor: Color {
    switch renderingMode {
    case .accented, .vibrant:
      return .primary

    default:
      return tidexBlueText
    }
  }

  private var activeColor: Color {
    WidgetPalette.success
  }

  // MARK: - Localization

  private var headerTitle: String {
    String(localized: .widgetNameFriendsShifts)
  }

  private var noFriendsText: String {
    String(localized: .widgetAddFriendsToSeeTheirShifts)
  }

  // MARK: - Body

  var body: some View {
    ZStack {
      backgroundColor

      if entry.hasAnyFriends, !entry.friends.isEmpty {
        contentView
      } else {
        emptyStateView
      }
    }
  }

  nonisolated static let maxRows = 4
  nonisolated static let maxFooterAvatars = 7

  /// Friends shown as the card and rows: the nearest shifts that fit.
  private var shiftFriends: [FriendPreview] {
    Array(entry.friends.filter { $0.status != .none }.prefix(Self.maxRows))
  }

  /// Everyone else: friends without a shift and shift friends that didn't fit.
  private var footerFriends: [FriendPreview] {
    let shown = Set(shiftFriends.map(\.id))
    return entry.friends.filter { !shown.contains($0.id) }
  }

  private var contentView: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        Image(systemName: "person.2.fill")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(initialsTextColor)
          .widgetAccentable()
          .accessibilityHidden(true)
        Text(headerTitle)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(secondaryTextColor)
      }

      if let first = shiftFriends.first {
        heroCard(first)
      }

      VStack(spacing: 10) {
        ForEach(shiftFriends.dropFirst()) { friend in
          compactRow(friend)
        }
      }
      .padding(.horizontal, 4)

      Spacer(minLength: 0)

      if !footerFriends.isEmpty {
        footer
      }
    }
    .padding(16)
  }

  /// The friend whose shift is closest in time gets the large card.
  private func heroCard(_ friend: FriendPreview) -> some View {
    let isActive = friend.status == .active
    return VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        avatar(friend, size: 44, fontSize: 16)

        VStack(alignment: .leading, spacing: 2) {
          Text(firstName(from: friend.displayName))
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(primaryTextColor)
            .lineLimit(1)
          if isActive {
            activeBadge
          } else if let shiftDate = friend.shiftDate {
            Text(shiftDate)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(secondaryTextColor)
              .lineLimit(1)
          }
        }
        // The name and badge keep their width. The time range shrinks to make room.
        .layoutPriority(1)

        Spacer(minLength: 8)

        if let timeRange = friend.timeRange {
          // The mark sits above the range. Beside it, it would take the name's width.
          VStack(alignment: .trailing, spacing: 0) {
            if friend.showsConvertedClock { convertedClockMark(size: 11) }
            Text(timeRange)
              .font(.system(size: 22, weight: .bold, design: .rounded))
              .monospacedDigit()
              .foregroundStyle(primaryTextColor)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
        }
      }

      if let interval = friend.interval {
        dayBar(interval.dayBar(in: .current, now: entry.date), isActive: isActive)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(isActive ? activeColor.opacity(0.14) : initialsBackground.opacity(0.5))
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: spokenSummary(for: friend)))
  }

  /// "Anna, Active, 09:00 to 17:00", read as one line per friend.
  private func spokenSummary(for friend: FriendPreview) -> String {
    WidgetAccessibility.join([
      firstName(from: friend.displayName),
      friend.status == .active ? String(localized: .widgetActive) : friend.shiftDate,
      friend.showsConvertedClock ? String(localized: .sharingTimeYourTime) : nil,
      friend.timeRange.map(WidgetAccessibility.spokenTimeRange),
    ])
  }

  /// Marks clocks converted from the schedule's zone to the viewer's.
  private func convertedClockMark(size: CGFloat) -> some View {
    Image(systemName: "globe")
      .font(.system(size: size, weight: .semibold))
      .foregroundStyle(mutedTextColor)
      .accessibilityHidden(true)
  }

  /// A 24-hour track with the shift as a filled segment and, on today's bar, a line at the
  /// current time.
  private func dayBar(_ bar: ShiftDayBar, isActive: Bool) -> some View {
    let accent = isActive ? activeColor : initialsTextColor
    return VStack(spacing: 6) {
      GeometryReader { geo in
        Capsule()
          .fill(mutedTextColor.opacity(0.18))
          .overlay(alignment: .leading) {
            Capsule()
              .fill(accent)
              .frame(width: max(6, geo.size.width * (bar.span.upperBound - bar.span.lowerBound)))
              .offset(x: geo.size.width * bar.span.lowerBound)
              .widgetAccentable()
          }
          .overlay(alignment: .leading) {
            if let now = bar.now {
              // The cut-out gap keeps the line readable on the segment in every rendering mode.
              ZStack {
                Capsule()
                  .frame(width: 6, height: 16)
                  .blendMode(.destinationOut)
                Capsule()
                  .fill(primaryTextColor)
                  .frame(width: 2, height: 12)
              }
              .offset(x: geo.size.width * now - 3)
            }
          }
          .compositingGroup()
      }
      .frame(height: 6)

      HStack {
        ForEach(["00", "06", "12", "18", "24"], id: \.self) { label in
          Text(label)
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(mutedTextColor)
          if label != "24" { Spacer(minLength: 0) }
        }
      }
    }
    .accessibilityHidden(true)
  }

  private func compactRow(_ friend: FriendPreview) -> some View {
    HStack(spacing: 12) {
      avatar(friend, size: 34, fontSize: 13)

      VStack(alignment: .leading, spacing: 1) {
        Text(firstName(from: friend.displayName))
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(primaryTextColor)
        if friend.status == .active {
          activeBadge
        } else if let shiftDate = friend.shiftDate {
          Text(shiftDate)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(secondaryTextColor)
        }
      }
      .lineLimit(1)

      Spacer(minLength: 8)

      if let timeRange = friend.timeRange {
        HStack(spacing: 4) {
          if friend.showsConvertedClock { convertedClockMark(size: 11) }
          Text(timeRange)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(primaryTextColor)
            .fixedSize()
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: spokenSummary(for: friend)))
  }

  /// Friends not shown above, as a centered row of overlapping avatars.
  private var footer: some View {
    let visible = footerFriends.prefix(Self.maxFooterAvatars)
    let overflow = footerFriends.count - visible.count
    return HStack(spacing: -8) {
      // Leftmost is the next friend in order, so it draws on top. The overflow badge keeps zIndex 0, under all of them.
      ForEach(Array(visible.enumerated()), id: \.element.id) { index, friend in
        avatar(friend, size: 28, fontSize: 11)
          .background(avatarCutout)
          .zIndex(Double(visible.count - index))
      }
      if overflow > 0 {
        Text("+\(overflow)")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(secondaryTextColor)
          .frame(width: 28, height: 28)
          .background(Circle().fill(mutedTextColor.opacity(0.25)))
          .background(avatarCutout)
      }
    }
    .compositingGroup()
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Text(
        verbatim: WidgetAccessibility.join(
          visible.map { firstName(from: $0.displayName) as String? }
            + [overflow > 0 ? String(localized: .widgetAccessibilityMoreFriends(overflow)) : nil])
      )
    )
  }

  private func avatar(_ friend: FriendPreview, size: CGFloat, fontSize: CGFloat) -> some View {
    Group {
      if let image = friend.avatar {
        Image(uiImage: image)
          .resizable()
          .widgetAccentedRenderingMode(.fullColor)
          .scaledToFill()
          .accessibilityHidden(true)
      } else {
        Text(friend.initials)
          .font(.system(size: fontSize, weight: .semibold))
          .foregroundStyle(initialsTextColor)
          .frame(width: size, height: size)
          .background(Circle().fill(initialsBackground))
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .overlay {
      if friend.status == .active {
        Circle().strokeBorder(activeColor, lineWidth: 2)
      }
    }
  }

  /// Erases the avatars beneath an overlapping one, plus a 2-point gap. An opaque backing would
  /// turn into a solid white disc in the tinted and clear home screen styles.
  private var avatarCutout: some View {
    Circle().padding(-2).blendMode(.destinationOut)
  }

  private var activeBadge: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(activeColor)
        .frame(width: 6, height: 6)
      Text(.widgetActive)
        .font(.system(size: 12, weight: .semibold))
    }
    .foregroundStyle(activeColor)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Capsule().fill(activeColor.opacity(0.15)))
    .widgetAccentable()
  }

  private var emptyStateView: some View {
    VStack(spacing: 12) {
      Image(systemName: "person.2.circle")
        .font(.system(size: 40))
        .foregroundStyle(mutedTextColor)
        .accessibilityHidden(true)

      Text(noFriendsText)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(mutedTextColor)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
  }

  // MARK: - Helpers

  private func firstName(from fullName: String) -> String {
    fullName.split(separator: " ").first.map(String.init) ?? fullName
  }
}

// MARK: - Widget Configuration

struct FriendsWidget: Widget {
  let kind: String = "FriendsWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FriendsWidgetProvider()) { entry in
      FriendsWidgetView(entry: entry)
        .widgetURL(entry.deepLinkURL)
        .containerBackground(for: .widget) {
          Color.clear
        }
    }
    .configurationDisplayName(String(localized: .widgetNameFriendsShifts))
    .description(String(localized: .widgetDescFriendsShifts))
    .supportedFamilies([.systemLarge])
    .contentMarginsDisabled()
  }
}

// MARK: - Preview

#if DEBUG
  #Preview(as: .systemLarge) {
    FriendsWidget()
  } timeline: {
    // With friends
    FriendsWidgetEntry(
      date: Date(),
      friends: [
        FriendPreview(
          id: "1",
          displayName: "Ola Nordmann",
          initials: "ON",
          shiftDate: "I dag",
          rawDate: "2026-02-01",
          timeRange: "07:00 – 15:00",
          status: .active,
          daysRemaining: 0
        ),
        FriendPreview(
          id: "2",
          displayName: "Kari Hansen",
          initials: "KH",
          shiftDate: "I morgen",
          rawDate: "2026-02-02",
          timeRange: "09:00 – 17:00",
          status: .upcoming,
          daysRemaining: 1
        ),
        FriendPreview(
          id: "3",
          displayName: "Per Svendsen",
          initials: "PS",
          shiftDate: "Mandag",
          rawDate: "2026-02-03",
          timeRange: "08:00 – 16:00",
          status: .upcoming,
          daysRemaining: 2
        ),
        FriendPreview(
          id: "4",
          displayName: "Lisa Johansen",
          initials: "LJ",
          shiftDate: "Tir 4. feb",
          rawDate: "2026-02-04",
          timeRange: "10:00 – 18:00",
          status: .upcoming,
          daysRemaining: 3
        ),
        FriendPreview(
          id: "5",
          displayName: "Anna Berg",
          initials: "AB",
          shiftDate: nil,
          rawDate: nil,
          timeRange: nil,
          status: .none,
          daysRemaining: nil
        ),
      ],
      hasAnyFriends: true
    )

    // Empty state
    FriendsWidgetEntry.empty()
  }
#endif
// swiftlint:enable file_length function_body_length cyclomatic_complexity type_body_length
