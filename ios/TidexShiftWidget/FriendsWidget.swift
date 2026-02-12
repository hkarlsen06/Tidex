// swiftlint:disable file_length function_body_length cyclomatic_complexity
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

  static func placeholder() -> FriendsWidgetEntry {
    FriendsWidgetEntry(
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

  static func empty() -> FriendsWidgetEntry {
    FriendsWidgetEntry(
      date: Date(),
      friends: [],
      hasAnyFriends: false
    )
  }
}

// MARK: - Timeline Provider

struct FriendsWidgetProvider: TimelineProvider {
  private let appGroupId = "group.no.tidex.app"
  private let friendSharersKey = "friend_sharers"
  private let friendShiftsKey = "friend_shifts"

  private func sharedUserDefaults() -> UserDefaults? {
    guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) != nil
    else {
      return nil
    }
    return UserDefaults(suiteName: appGroupId)
  }

  func placeholder(in _: Context) -> FriendsWidgetEntry {
    FriendsWidgetEntry.placeholder()
  }

  func getSnapshot(in _: Context, completion: @escaping (FriendsWidgetEntry) -> Void) {
    completion(FriendsWidgetEntry.placeholder())
  }

  func getTimeline(in _: Context, completion: @escaping (Timeline<FriendsWidgetEntry>) -> Void) {
    let entry = createEntry()

    // Refresh every 15 minutes
    let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
    let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
    completion(timeline)
  }

  private func createEntry() -> FriendsWidgetEntry {
    // Load sharers
    guard let userDefaults = sharedUserDefaults(),
      let sharersJson = userDefaults.string(forKey: friendSharersKey),
      let sharersData = sharersJson.data(using: .utf8),
      let sharers = try? JSONDecoder().decode([WidgetSharer].self, from: sharersData),
      !sharers.isEmpty
    else {
      return FriendsWidgetEntry.empty()
    }

    // Load shifts
    var shifts: [StoredFriendShift] = []
    if let shiftsJson = userDefaults.string(forKey: friendShiftsKey),
      let shiftsData = shiftsJson.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([StoredFriendShift].self, from: shiftsData)
    {
      shifts = decoded
    }

    // Build friend previews
    var previews: [FriendPreview] = []

    for sharer in sharers {
      // Find shift for this sharer
      let shift = shifts.first { $0.sharerId == sharer.id }

      if let shift = shift {
        // Calculate layout state
        let (status, daysRemaining) = determineStatus(
          shiftDateString: shift.shiftDate,
          startTime: shift.startTime,
          endTime: shift.endTime
        )
        let formattedDate = formatShiftDate(shift.shiftDate, daysRemaining: daysRemaining)

        previews.append(
          FriendPreview(
            id: sharer.id,
            displayName: sharer.displayName,
            initials: sharer.initials,
            shiftDate: formattedDate,
            rawDate: shift.shiftDate,
            timeRange: "\(shift.startTime) – \(shift.endTime)",
            status: status,
            daysRemaining: daysRemaining
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
      if lhs.status == .active && rhs.status != .active { return true }
      if rhs.status == .active && lhs.status != .active { return false }

      // Upcoming by days remaining
      if lhs.status == .upcoming && rhs.status == .upcoming {
        return (lhs.daysRemaining ?? 999) < (rhs.daysRemaining ?? 999)
      }

      // Upcoming before past/none
      if lhs.status == .upcoming && rhs.status != .upcoming { return true }
      if rhs.status == .upcoming && lhs.status != .upcoming { return false }

      // Past by recency (closest to today first)
      if lhs.status == .past && rhs.status == .past {
        return abs(lhs.daysRemaining ?? 0) < abs(rhs.daysRemaining ?? 0)
      }

      // Past before none
      if lhs.status == .past && rhs.status == .none { return true }
      if rhs.status == .past && lhs.status == .none { return false }

      // Alphabetical for none
      return lhs.displayName < rhs.displayName
    }

    // Take top 5
    let topFriends = Array(previews.prefix(5))

    return FriendsWidgetEntry(
      date: Date(),
      friends: topFriends,
      hasAnyFriends: true
    )
  }

  // MARK: - Date Helpers

  private func parseShiftDate(_ dateString: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: dateString)
  }

  private func determineStatus(
    shiftDateString: String,
    startTime: String,
    endTime: String
  ) -> (FriendPreview.FriendShiftStatus, Int) {
    guard let shiftDate = parseShiftDate(shiftDateString) else {
      return (.none, 0)
    }

    let now = Date()
    let calendar = Calendar.current
    let todayMidnight = calendar.startOfDay(for: now)
    let shiftMidnight = calendar.startOfDay(for: shiftDate)

    // Check if shift is active (currently happening)
    if isShiftActive(shiftDateString: shiftDateString, startTime: startTime, endTime: endTime) {
      return (.active, 0)
    }

    // Past shift
    if shiftMidnight < todayMidnight {
      let components = calendar.dateComponents([.day], from: shiftMidnight, to: todayMidnight)
      let daysAgo = -(components.day ?? 0)
      return (.past, daysAgo)
    }

    // Upcoming shift
    let components = calendar.dateComponents([.day], from: todayMidnight, to: shiftMidnight)
    let daysRemaining = components.day ?? 0
    return (.upcoming, daysRemaining)
  }

  private func isShiftActive(shiftDateString: String, startTime: String, endTime: String) -> Bool {
    guard let shiftDate = parseShiftDate(shiftDateString) else { return false }

    let now = Date()
    let calendar = Calendar.current

    // Parse start time
    let startComponents = startTime.split(separator: ":").compactMap { Int($0) }
    guard startComponents.count >= 2 else { return false }

    var startDateComponents = calendar.dateComponents([.year, .month, .day], from: shiftDate)
    startDateComponents.hour = startComponents[0]
    startDateComponents.minute = startComponents[1]
    guard let shiftStartDateTime = calendar.date(from: startDateComponents) else { return false }

    // Parse end time
    let endComponents = endTime.split(separator: ":").compactMap { Int($0) }
    guard endComponents.count >= 2 else { return false }

    var endDateComponents = calendar.dateComponents([.year, .month, .day], from: shiftDate)
    endDateComponents.hour = endComponents[0]
    endDateComponents.minute = endComponents[1]
    guard var shiftEndDateTime = calendar.date(from: endDateComponents) else { return false }

    // Handle cross-midnight shifts
    let startMinutes = startComponents[0] * 60 + startComponents[1]
    let endMinutes = endComponents[0] * 60 + endComponents[1]
    if endMinutes <= startMinutes {
      shiftEndDateTime =
        calendar.date(byAdding: .day, value: 1, to: shiftEndDateTime) ?? shiftEndDateTime
    }

    // Check if now is within the shift
    return now >= shiftStartDateTime && now < shiftEndDateTime
  }

  private func formatShiftDate(_ dateString: String, daysRemaining: Int) -> String {
    guard let shiftDate = parseShiftDate(dateString) else { return dateString }

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let shiftDay = calendar.startOfDay(for: shiftDate)

    // Past shift
    if daysRemaining < 0 {
      let daysAgo = abs(daysRemaining)
      if daysAgo == 1 {
        return String(localized: .widgetYesterday)
      } else {
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = appLocale()
        weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE d. MMM")
        return sentenceCased(weekdayFormatter.string(from: shiftDate))
      }
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
      let weekdayFormatter = DateFormatter()
      weekdayFormatter.locale = appLocale()
      weekdayFormatter.setLocalizedDateFormatFromTemplate("EEEE")
      return sentenceCased(weekdayFormatter.string(from: shiftDate))
    }

    // Weekday + date
    let weekdayFormatter = DateFormatter()
    weekdayFormatter.locale = appLocale()
    weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE d. MMM")
    return sentenceCased(weekdayFormatter.string(from: shiftDate))
  }
}

// MARK: - Widget Sharer (Local copy)

private struct WidgetSharer: Codable, Identifiable, Equatable {
  let id: String
  let displayName: String
  let initials: String
  let showEarnings: Bool
}

// MARK: - Stored Friend Shift (Local copy)

private struct StoredFriendShift: Codable {
  let sharerId: String
  let shiftId: String
  let shiftDate: String
  let startTime: String
  let endTime: String
  let gross: Double
  let currencySymbol: String?
  let showEarnings: Bool
  let status: String
}

// MARK: - App Locale Helper

private func sentenceCased(_ text: String) -> String {
  guard !text.isEmpty else { return text }
  return text.prefix(1).uppercased(with: appLocale()) + text.dropFirst()
}

private func appLocale() -> Locale {
  let identifier = Bundle.main.preferredLocalizations.first ?? Locale.autoupdatingCurrent.identifier
  return Locale(identifier: identifier)
}

// MARK: - Widget View

struct FriendsWidgetView: View {
  let entry: FriendsWidgetEntry
  @Environment(\.widgetRenderingMode) var renderingMode
  @Environment(\.colorScheme) var colorScheme

  // MARK: - Colors

  private var isLightMode: Bool {
    colorScheme == .light
  }

  private var tidexBlue: Color {
    isLightMode
      ? Color(hue: 221 / 360, saturation: 0.83, brightness: 0.53)
      : Color(red: 77 / 255, green: 137 / 255, blue: 249 / 255)
  }

  private var backgroundColor: Color {
    switch renderingMode {
    case .accented:
      return .clear
    case .vibrant:
      return Color.black.opacity(0.4)
    default:
      return isLightMode
        ? Color(hue: 220 / 360, saturation: 0.40, brightness: 0.98)
        : Color(red: 10 / 255, green: 15 / 255, blue: 26 / 255)
    }
  }

  private var primaryTextColor: Color {
    switch renderingMode {
    case .accented, .vibrant:
      return .primary
    default:
      return isLightMode ? .black : .white
    }
  }

  private var secondaryTextColor: Color {
    switch renderingMode {
    case .accented, .vibrant:
      return .secondary
    default:
      return isLightMode ? .black.opacity(0.6) : .white.opacity(0.6)
    }
  }

  private var mutedTextColor: Color {
    switch renderingMode {
    case .accented, .vibrant:
      return .secondary
    default:
      return isLightMode ? .black.opacity(0.4) : .white.opacity(0.4)
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
      return tidexBlue
    }
  }

  private var activeColor: Color {
    .green
  }

  // MARK: - Localization

  private var headerTitle: String {
    String(localized: .widgetNameFriendsShifts)
  }

  private var noFriendsText: String {
    String(localized: .widgetAddFriendsToSeeTheirShifts)
  }

  private var noShiftText: String {
    String(localized: .widgetNoShift)
  }

  // MARK: - Body

  var body: some View {
    ZStack {
      backgroundColor

      if entry.hasAnyFriends && !entry.friends.isEmpty {
        contentView
      } else {
        emptyStateView
      }
    }
  }

  private var contentView: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      Text(headerTitle)
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(secondaryTextColor)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)

      // Friend rows
      VStack(spacing: 0) {
        ForEach(entry.friends) { friend in
          friendRow(friend)

          if friend.id != entry.friends.last?.id {
            Divider()
              .background(mutedTextColor.opacity(0.3))
              .padding(.horizontal, 16)
          }
        }
      }

      Spacer(minLength: 0)
    }
  }

  private func friendRow(_ friend: FriendPreview) -> some View {
    HStack(spacing: 12) {
      // Initials circle
      ZStack {
        Circle()
          .fill(initialsBackground)

        Text(friend.initials)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(initialsTextColor)
      }
      .frame(width: 36, height: 36)

      // Name and shift info
      VStack(alignment: .leading, spacing: 2) {
        // Name
        Text(firstName(from: friend.displayName))
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(primaryTextColor)
          .lineLimit(1)

        // Shift date and time
        if let shiftDate = friend.shiftDate, let timeRange = friend.timeRange {
          HStack(spacing: 4) {
            Text("\(shiftDate) · \(timeRange)")
              .font(.system(size: 13, weight: .regular))
              .foregroundColor(secondaryTextColor)
              .lineLimit(1)
          }
        } else {
          Text(noShiftText)
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(mutedTextColor)
        }
      }

      Spacer()

      // Status indicator for active shifts
      if friend.status == .active {
        HStack(spacing: 4) {
          Circle()
            .fill(activeColor)
            .frame(width: 8, height: 8)

          Text(.widgetActive)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(activeColor)
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private var emptyStateView: some View {
    VStack(spacing: 12) {
      Image(systemName: "person.2.circle")
        .font(.system(size: 40))
        .foregroundColor(mutedTextColor)

      Text(noFriendsText)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(mutedTextColor)
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
// swiftlint:enable file_length function_body_length cyclomatic_complexity
