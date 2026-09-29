// swiftlint:disable file_length type_body_length function_body_length
// Widget files require multiple size-specific views that cannot be easily split
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Friend Entity (for Widget Configuration)

struct FriendEntity: AppEntity {
  // App Intents metadata needs literal keys, so these name catalog keys instead of symbols.
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.friend")
  static var defaultQuery = FriendEntityQuery()

  var id: String
  var displayName: String
  var initials: String
  var showEarnings: Bool

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(displayName)")
  }
}

// MARK: - Friend Entity Query

struct FriendEntityQuery: EntityQuery {
  internal func entities(for identifiers: [FriendEntity.ID]) async -> [FriendEntity] {
    let allFriends = await loadFriendsWithAPIFallback()
    return allFriends.filter { identifiers.contains($0.id) }
  }

  internal func suggestedEntities() async -> [FriendEntity] {
    await loadFriendsWithAPIFallback()
  }

  func defaultResult() async -> FriendEntity? {
    await loadFriendsWithAPIFallback().first
  }

  /// Load friends from App Group, falling back to API if empty
  private func loadFriendsWithAPIFallback() async -> [FriendEntity] {
    // First try App Group (fast, cached)
    let cachedFriends = loadFriendsFromAppGroup()
    if !cachedFriends.isEmpty {
      return cachedFriends
    }

    // No cached data - try to fetch from API directly
    do {
      let friends = try await FriendsAPIClient.fetchFriendsWithShifts()
      let entities = friends.map { friend in
        FriendEntity(
          id: friend.id,
          displayName: friend.displayName,
          initials: friend.initials,
          showEarnings: friend.showEarnings
        )
      }

      // Update App Group cache for future use
      updateAppGroupCache(friends: friends)

      return entities
    } catch {
      // API failed - return empty (user needs to open app)
      return []
    }
  }

  private func loadFriendsFromAppGroup() -> [FriendEntity] {
    guard let userDefaults = WidgetAppGroup.sharedUserDefaults(),
      let jsonString = userDefaults.string(forKey: WidgetAppGroup.friendSharersKey),
      let data = jsonString.data(using: .utf8),
      let sharers = try? JSONDecoder().decode([WidgetSharer].self, from: data)
    else {
      return []
    }

    return sharers.map { sharer in
      FriendEntity(
        id: sharer.id,
        displayName: sharer.displayName,
        initials: sharer.initials,
        showEarnings: sharer.showEarnings
      )
    }
  }

  /// Update App Group with fresh friends data for future widget loads
  private func updateAppGroupCache(friends: [FriendWithShift]) {
    guard let userDefaults = WidgetAppGroup.sharedUserDefaults() else { return }

    // Convert to WidgetSharer format
    let sharers = friends.map { friend in
      WidgetSharer(
        id: friend.id,
        displayName: friend.displayName,
        initials: friend.initials,
        showEarnings: friend.showEarnings
      )
    }

    // Encode and save
    if let data = try? JSONEncoder().encode(sharers),
      let jsonString = String(data: data, encoding: .utf8)
    {
      userDefaults.set(jsonString, forKey: WidgetAppGroup.friendSharersKey)
    }
  }
}

// MARK: - Widget Configuration Intent

struct FriendShiftIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "widget.name.friendsShift"
  static var description: IntentDescription = "widget.intent.friendShift.description"

  @Parameter(title: "widget.friend")
  var friend: FriendEntity?
}

// MARK: - Timeline Provider

struct FriendShiftTimelineProvider: AppIntentTimelineProvider {
  private let helper = ShiftWidgetProviderHelper()

  func placeholder(in _: Context) -> FriendShiftWidgetEntry {
    FriendShiftWidgetEntry.placeholder()
  }

  // Required by AppIntentTimelineProvider; this snapshot path intentionally uses cached sync data.
  // swiftlint:disable:next async_without_await
  func snapshot(for configuration: FriendShiftIntent, in _: Context) async -> FriendShiftWidgetEntry
  {
    if let friend = configuration.friend {
      // For snapshot, use cached data (fast)
      return createEntry(for: friend, fromAPI: nil)
    }
    return FriendShiftWidgetEntry.placeholder()
  }

  func timeline(for configuration: FriendShiftIntent, in _: Context) async -> Timeline<
    FriendShiftWidgetEntry
  > {
    guard let friend = configuration.friend else {
      let entry = FriendShiftWidgetEntry.noFriendSelected()
      return Timeline(entries: [entry], policy: .never)
    }

    // Try to fetch fresh data from API
    var apiFriend: FriendWithShift?
    do {
      let friends = try await FriendsAPIClient.fetchFriendsWithShifts()
      apiFriend = friends.first { $0.id == friend.id }

      // Update App Group cache with fresh data
      updateAppGroupCache(friends: friends)
    } catch {
      // API failed - will use cached data
    }

    // Create entry (will use API data if available, otherwise cached)
    let now = Date()
    let calendar = Calendar.gregorianCurrent
    let entry = createEntry(for: friend, fromAPI: apiFriend, at: now)

    var entries = [entry]

    // Add transition entries at shift start/end for today's shifts
    if entry.hasShift,
      entry.layoutState == .todayOrTomorrow,
      entry.daysRemaining == 0
    {
      for transition in [entry.shiftStart, entry.shiftEnd].compactMap(\.self)
      where transition > now {
        entries.append(createEntry(for: friend, fromAPI: apiFriend, at: transition))
      }
    }

    // Refresh at next midnight to pick up day transitions
    let tomorrow = calendar.startOfDay(
      for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
    return Timeline(entries: entries, policy: .after(tomorrow))
  }

  /// Update App Group cache with fresh data from API
  private func updateAppGroupCache(friends: [FriendWithShift]) {
    guard let userDefaults = WidgetAppGroup.sharedUserDefaults() else { return }

    // Convert to WidgetSharer format and save
    let sharers = friends.map { friend in
      WidgetSharer(
        id: friend.id,
        displayName: friend.displayName,
        initials: friend.initials,
        showEarnings: friend.showEarnings
      )
    }

    if let data = try? JSONEncoder().encode(sharers),
      let jsonString = String(data: data, encoding: .utf8)
    {
      userDefaults.set(jsonString, forKey: WidgetAppGroup.friendSharersKey)
    }

    // Convert to StoredFriendShift format and save
    let currency = userDefaults.string(forKey: WidgetAppGroup.currencyKey) ?? "kr"

    let shifts: [StoredFriendShift] = friends.compactMap { friend in
      guard let shiftId = friend.shiftId,
        let shiftDate = friend.shiftDate,
        let startTime = friend.startTime,
        let endTime = friend.endTime
      else {
        return nil
      }

      return StoredFriendShift(
        sharerId: friend.id,
        shiftId: shiftId,
        shiftDate: shiftDate,
        startTime: startTime,
        endTime: endTime,
        gross: friend.gross ?? 0,
        currencySymbol: currency,
        showEarnings: friend.showEarnings,
        status: friend.status?.rawValue ?? "upcoming"
      )
    }

    if let data = try? JSONEncoder().encode(shifts),
      let jsonString = String(data: data, encoding: .utf8)
    {
      userDefaults.set(jsonString, forKey: WidgetAppGroup.friendShiftsKey)
    }
  }

  // MARK: - Private Helpers

  private func getStoredCurrency() -> String? {
    WidgetAppGroup.sharedUserDefaults()?.string(forKey: WidgetAppGroup.currencyKey)
  }

  private func loadFriendShift(for friendId: String) -> StoredFriendShift? {
    guard let userDefaults = WidgetAppGroup.sharedUserDefaults(),
      let jsonString = userDefaults.string(forKey: WidgetAppGroup.friendShiftsKey),
      let data = jsonString.data(using: .utf8),
      let shifts = try? JSONDecoder().decode([StoredFriendShift].self, from: data)
    else {
      return nil
    }

    return shifts.first { $0.sharerId == friendId }
  }

  /// Create a widget entry for a friend
  /// - Parameters:
  ///   - friend: The friend entity from widget config
  ///   - fromAPI: Optional fresh data from API (if available)
  ///   - at: The date for this timeline entry
  private func createEntry(
    for friend: FriendEntity, fromAPI: FriendWithShift?, at now: Date = Date()
  )
    -> FriendShiftWidgetEntry
  {
    let storedCurrency = getStoredCurrency()

    // Use API data if available, otherwise fall back to App Group cache
    let shiftDate: String?
    let startTime: String?
    let endTime: String?
    let gross: Double?
    let showEarnings: Bool

    if let apiFriend = fromAPI, apiFriend.hasShift {
      shiftDate = apiFriend.shiftDate
      startTime = apiFriend.startTime
      endTime = apiFriend.endTime
      gross = apiFriend.gross
      showEarnings = apiFriend.showEarnings
    } else if let cachedShift = loadFriendShift(for: friend.id) {
      shiftDate = cachedShift.shiftDate
      startTime = cachedShift.startTime
      endTime = cachedShift.endTime
      gross = cachedShift.gross
      showEarnings = cachedShift.showEarnings
    } else {
      // No shift data available
      return FriendShiftWidgetEntry.empty(
        friendId: friend.id,
        friendName: friend.displayName,
        friendInitials: friend.initials,
        currency: storedCurrency
      )
    }

    // Unwrap required fields
    guard let shiftDate,
      let startTime,
      let endTime
    else {
      return FriendShiftWidgetEntry.empty(
        friendId: friend.id,
        friendName: friend.displayName,
        friendInitials: friend.initials,
        currency: storedCurrency
      )
    }

    // Determine layout state
    var (layoutState, daysRemaining) = helper.determineLayoutState(
      shiftDateString: shiftDate, at: now)

    // Check if shift has started/ended
    let shiftStarted = helper.hasShiftStarted(
      shiftDateString: shiftDate, startTime: startTime, at: now)
    let shiftEnded = helper.hasShiftEnded(
      shiftDateString: shiftDate,
      startTime: startTime,
      endTime: endTime,
      at: now
    )
    let shiftActive = helper.isShiftActive(
      shiftDateString: shiftDate,
      startTime: startTime,
      endTime: endTime,
      at: now
    )

    // Adjust layout state for active/ended shifts
    // Preserve pastShift layout for past shifts - they should show "X days ago"
    if shiftActive {
      layoutState = .todayOrTomorrow
      daysRemaining = 0
    } else if layoutState != .pastShift, shiftStarted || shiftEnded {
      layoutState = .todayOrTomorrow
    }

    // Format date
    let formattedDate = formatShiftDate(shiftDate, daysRemaining: daysRemaining)

    // Format earnings (or hide if not allowed)
    let netEarnings: String
    if showEarnings, let grossValue = gross, let currency = storedCurrency {
      netEarnings = WidgetCurrencyFormatter.format(grossValue, currency: currency)
    } else if showEarnings, let grossValue = gross {
      let formatter = NumberFormatter()
      formatter.numberStyle = .decimal
      formatter.minimumFractionDigits = 0
      formatter.maximumFractionDigits = 0
      formatter.groupingSeparator = " "
      netEarnings = formatter.string(from: NSNumber(value: grossValue)) ?? "\(Int(grossValue))"
    } else {
      netEarnings = "---"
    }

    // Build deep link (use "user" param to match AppCoordinator.handleDeepLink)
    let deepLinkURL = URL(string: "tidex://sharing?user=\(friend.id)&dates=\(shiftDate)")
    let interval = helper.shiftInterval(
      shiftDateString: shiftDate, startTime: startTime, endTime: endTime)

    return FriendShiftWidgetEntry(
      date: now,
      friendId: friend.id,
      friendName: friend.displayName,
      friendInitials: friend.initials,
      shiftDate: formattedDate,
      startTime: startTime,
      endTime: endTime,
      netEarnings: netEarnings,
      showEarnings: showEarnings,
      hasShift: true,
      daysRemaining: daysRemaining,
      layoutState: layoutState,
      shiftHasStarted: shiftStarted,
      shiftHasEnded: shiftEnded,
      deepLinkURL: deepLinkURL,
      shiftStart: interval?.start,
      shiftEnd: interval?.end
    )
  }

  // MARK: - Date Formatting (parsing & layout logic live in ShiftWidgetProviderHelper)

  private func formatShiftDate(_ dateString: String, daysRemaining: Int) -> String {
    guard let shiftDate = parseShiftDate(dateString) else { return dateString }

    let calendar = Calendar.gregorianCurrent
    let today = calendar.startOfDay(for: Date())
    let shiftDay = calendar.startOfDay(for: shiftDate)

    // Past shift
    if daysRemaining < 0 {
      let daysAgo = abs(daysRemaining)
      if daysAgo == 1 {
        return String(localized: .widgetYesterday)
      }
      return formattedWeekday(shiftDate, style: .abbreviatedDay)
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

    // Weekday + day
    return formattedWeekday(shiftDate, style: .abbreviatedDay)
  }
}

// MARK: - Initials Circle View

private struct InitialsCircle: View {
  private static let defaultBackgroundOpacity: Double = 0.15

  let initials: String
  let size: CGFloat

  var backgroundColor: Color = .white.opacity(Self.defaultBackgroundOpacity)
  var textColor: Color = .white

  var body: some View {
    ZStack {
      Circle()
        .fill(backgroundColor)

      Text(initials)
        .font(.system(size: size * 0.4, weight: .semibold))
        .foregroundColor(textColor)
    }
    .frame(width: size, height: size)
  }
}

// MARK: - Widget View

struct FriendShiftWidgetView: View {
  let entry: FriendShiftWidgetEntry
  @Environment(\.widgetRenderingMode) var renderingMode

  private var daysLabel: String {
    String(localized: .widgetDays)
  }

  private var leftLabel: String {
    String(localized: .widgetLeft)
  }

  /// Extract just the first name from the full display name
  private var firstName: String {
    entry.friendName.split(separator: " ").first.map(String.init) ?? entry.friendName
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

  private var accentColor: Color {
    switch renderingMode {
    case .accented:
      return .primary

    default:
      return WidgetPalette.blueText
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

  private var startTimeColor: Color {
    if entry.shiftHasStarted {
      return secondaryTextColor
    }
    return entry.hasShift ? primaryTextColor : mutedTextColor
  }

  private var endTimeColor: Color {
    if entry.shiftHasStarted {
      return entry.hasShift ? primaryTextColor : mutedTextColor
    }
    return secondaryTextColor
  }

  var body: some View {
    ZStack {
      backgroundColor

      if entry.friendId.isEmpty {
        noFriendSelectedLayout
      } else {
        switch entry.layoutState {
        case .countdown:
          countdownLayout

        case .pastShift, .todayOrTomorrow:
          todayTomorrowLayout

        case .empty:
          emptyStateLayout
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: accessibilitySummary))
  }

  /// One spoken summary: the friend's name, then the shift.
  private var accessibilitySummary: String {
    guard !entry.friendId.isEmpty else { return String(localized: .widgetSelectAFriend) }
    let shift = WidgetAccessibility.shiftSummary(
      entry, shiftDate: entry.shiftDate, startTime: entry.startTime, endTime: entry.endTime,
      earnings: entry.showEarnings ? entry.netEarnings : nil)
    return WidgetAccessibility.join([entry.friendName, shift])
  }

  // MARK: - No Friend Selected Layout

  private var noFriendSelectedLayout: some View {
    VStack(spacing: 12) {
      Image(systemName: "person.crop.circle.badge.plus")
        .font(.system(size: 36))
        .foregroundColor(mutedTextColor)

      Text(.widgetSelectAFriend)
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(mutedTextColor)
    }
  }

  // MARK: - Empty State Layout

  private var emptyStateLayout: some View {
    VStack(spacing: 8) {
      InitialsCircle(
        initials: entry.friendInitials,
        size: 48,
        backgroundColor: renderingMode == .fullColor
          ? WidgetPalette.textPrimary.opacity(0.15) : .secondary.opacity(0.2),
        textColor: renderingMode == .fullColor ? WidgetPalette.textPrimary : .primary
      )

      Text(.widgetNoShifts)
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(mutedTextColor)
    }
  }

  // MARK: - Today/Tomorrow/Past Layout

  private var todayTomorrowLayout: some View {
    VStack(spacing: 0) {
      topHeaderRow

      Spacer()

      timeBlockView

      Spacer()

      bottomTextView
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 14)
  }

  private var topHeaderRow: some View {
    Group {
      if let countdownTarget = entry.upcomingStartToday {
        // Timer countdown to shift start + earnings
        if entry.showEarnings {
          Text("\(countdownTarget, style: .timer)  \(entry.netEarnings)")
            .font(.system(size: 15, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(accentColor)
            .multilineTextAlignment(.center)
            .widgetAccentable()
            .lineLimit(1)
        } else {
          Text(countdownTarget, style: .timer)
            .font(.system(size: 15, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(accentColor)
            .widgetAccentable()
            .lineLimit(1)
        }
      } else if let shiftEnd = entry.activeShiftEnd {
        // Timer countdown to shift end + earnings
        if entry.showEarnings {
          Text("\(shiftEnd, style: .timer)  \(entry.netEarnings)")
            .font(.system(size: 15, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(accentColor)
            .multilineTextAlignment(.center)
            .widgetAccentable()
            .lineLimit(1)
        } else {
          Text(shiftEnd, style: .timer)
            .font(.system(size: 15, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(accentColor)
            .widgetAccentable()
            .lineLimit(1)
        }
      } else {
        HStack(spacing: 6) {
          Text(entry.shiftDate)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(entry.hasShift ? accentColor : mutedTextColor)
            .widgetAccentable(entry.hasShift)
            .lineLimit(1)

          if entry.showEarnings {
            Text(entry.netEarnings)
              .font(.system(size: 15, weight: .semibold))
              .foregroundColor(secondaryTextColor)
              .lineLimit(1)
          }
        }
      }
    }
  }

  private var bottomTextView: some View {
    // Always show friend's first name at bottom
    Text(firstName)
      .font(.system(size: 15, weight: .bold))
      .foregroundColor(entry.hasShift ? accentColor : mutedTextColor)
      .widgetAccentable(entry.hasShift)
      .lineLimit(1)
  }

  private var timeBlockView: some View {
    VStack(spacing: -6) {
      if entry.layoutState == .pastShift {
        pastShiftCountupView
      } else if entry.shiftHasEnded {
        Text(.widgetDoneCapitalized)
          .font(.system(size: 36, weight: .bold))
          .foregroundColor(entry.hasShift ? primaryTextColor : mutedTextColor)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      } else {
        Text(entry.startTime)
          .font(.system(size: 32, weight: entry.shiftHasStarted ? .medium : .bold))
          .monospacedDigit()
          .foregroundColor(startTimeColor)
          .lineLimit(1)

        Text(entry.endTime)
          .font(.system(size: 32, weight: entry.shiftHasStarted ? .bold : .medium))
          .monospacedDigit()
          .foregroundColor(endTimeColor)
          .lineLimit(1)
      }
    }
  }

  private var pastShiftCountupView: some View {
    let daysAgo = abs(entry.daysRemaining)
    let daysText = daysAgo == 1 ? String(localized: .widgetDay) : String(localized: .widgetDays)
    let agoText = String(localized: .widgetAgo)

    return HStack(alignment: .center, spacing: 4) {
      Text("\(daysAgo)")
        .font(.system(size: 72, weight: .bold))
        .monospacedDigit()
        .foregroundColor(entry.hasShift ? primaryTextColor : mutedTextColor)
        .lineLimit(1)
        .minimumScaleFactor(0.5)

      VStack(alignment: .leading, spacing: -4) {
        Text(daysText)
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(entry.hasShift ? primaryTextColor : mutedTextColor)
          .lineLimit(1)

        Text(agoText)
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(entry.hasShift ? primaryTextColor : mutedTextColor)
          .lineLimit(1)
      }
    }
  }

  // MARK: - Countdown Layout

  private var countdownLayout: some View {
    VStack(spacing: 0) {
      topHeaderRow

      Spacer()

      countdownHeroView

      Spacer()

      bottomTextView
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 14)
  }

  private var countdownHeroView: some View {
    HStack(alignment: .center, spacing: 4) {
      Text("\(entry.daysRemaining)")
        .font(.system(size: 72, weight: .bold))
        .monospacedDigit()
        .foregroundColor(primaryTextColor)
        .lineLimit(1)
        .minimumScaleFactor(0.5)

      VStack(alignment: .leading, spacing: -4) {
        Text(daysLabel)
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(primaryTextColor)
          .lineLimit(1)

        Text(leftLabel)
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(primaryTextColor)
          .lineLimit(1)
      }
    }
  }
}

// MARK: - Widget Configuration

struct FriendShiftWidget: Widget {
  let kind: String = "FriendShiftWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: kind,
      intent: FriendShiftIntent.self,
      provider: FriendShiftTimelineProvider()
    ) { entry in
      FriendShiftWidgetView(entry: entry)
        .widgetURL(entry.deepLinkURL)
        .containerBackground(for: .widget) {
          Color.clear
        }
    }
    .configurationDisplayName(String(localized: .widgetNameFriendsShift))
    .description(String(localized: .widgetDescFriendsShift))
    .supportedFamilies([.systemSmall])
    .contentMarginsDisabled()
  }
}

// MARK: - Preview

#if DEBUG
  #Preview(as: .systemSmall) {
    FriendShiftWidget()
  } timeline: {
    // Placeholder
    FriendShiftWidgetEntry.placeholder()
    FriendShiftWidgetEntry.placeholder()

    // Today's shift
    FriendShiftWidgetEntry(
      date: Date(),
      friendId: "friend-1",
      friendName: "Ola",
      friendInitials: "OL",
      shiftDate: "I dag",
      startTime: "07:00",
      endTime: "15:00",
      netEarnings: "892 kr",
      showEarnings: true,
      hasShift: true,
      daysRemaining: 0,
      layoutState: .todayOrTomorrow,
      shiftHasStarted: false,
      shiftHasEnded: false,
      deepLinkURL: URL(string: "tidex://sharing?user=friend-1")
    )

    // Countdown
    FriendShiftWidgetEntry(
      date: Date(),
      friendId: "friend-2",
      friendName: "Kari",
      friendInitials: "KA",
      shiftDate: "Man. 20.",
      startTime: "16:00",
      endTime: "23:15",
      netEarnings: "1 332 kr",
      showEarnings: true,
      hasShift: true,
      daysRemaining: 5,
      layoutState: .countdown,
      shiftHasStarted: false,
      shiftHasEnded: false,
      deepLinkURL: URL(string: "tidex://sharing?user=friend-2")
    )

    // Earnings hidden
    FriendShiftWidgetEntry(
      date: Date(),
      friendId: "friend-3",
      friendName: "Per",
      friendInitials: "PE",
      shiftDate: "I morgen",
      startTime: "08:00",
      endTime: "16:00",
      netEarnings: "---",
      showEarnings: false,
      hasShift: true,
      daysRemaining: 1,
      layoutState: .todayOrTomorrow,
      shiftHasStarted: false,
      shiftHasEnded: false,
      deepLinkURL: URL(string: "tidex://sharing?user=friend-3")
    )

    // Empty state
    FriendShiftWidgetEntry.empty(
      friendId: "friend-4",
      friendName: "Anna",
      friendInitials: "AN",
      currency: "kr"
    )

    // No friend selected
    FriendShiftWidgetEntry.noFriendSelected()
  }
#endif
// swiftlint:enable file_length type_body_length function_body_length
