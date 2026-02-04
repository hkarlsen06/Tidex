// swiftlint:disable file_length type_body_length function_body_length
// Widget files require multiple size-specific views that cannot be easily split
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Widget Sharer Model (Local copy for widget extension)

/// Lightweight sharer model for widget consumption
/// Must match the structure written by NativeWidgetStorage in the main app
private struct WidgetSharer: Codable, Identifiable, Equatable {
    let id: String
    let displayName: String
    let initials: String
    let showEarnings: Bool
}

// MARK: - Stored Friend Shift Model (Local copy for widget extension)

/// Friend's shift data stored in App Group
/// Must match the structure written by NativeWidgetStorage in the main app
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

// MARK: - Friend Entity (for Widget Configuration)

struct FriendEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Friend")
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
    private let appGroupId = "group.no.tidex.app"
    private let friendSharersKey = "friend_sharers"

    func entities(for identifiers: [FriendEntity.ID]) async throws -> [FriendEntity] {
        let allFriends = await loadFriendsWithAPIFallback()
        return allFriends.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FriendEntity] {
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
        guard let userDefaults = UserDefaults(suiteName: appGroupId),
              let jsonString = userDefaults.string(forKey: friendSharersKey),
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
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else { return }

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
           let jsonString = String(data: data, encoding: .utf8) {
            userDefaults.set(jsonString, forKey: friendSharersKey)
        }
    }
}

// MARK: - Widget Configuration Intent

struct FriendShiftIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Friend's Shift"
    static var description: IntentDescription = "Select a friend to display their shift"

    @Parameter(title: "Friend")
    var friend: FriendEntity?
}

// MARK: - Timeline Provider

struct FriendShiftTimelineProvider: AppIntentTimelineProvider {
    private let appGroupId = "group.no.tidex.app"
    private let friendSharersKey = "friend_sharers"
    private let friendShiftsKey = "friend_shifts"
    private let currencyKey = "user_currency"

    func placeholder(in _: Context) -> FriendShiftWidgetEntry {
        FriendShiftWidgetEntry.placeholder()
    }

    func snapshot(for configuration: FriendShiftIntent, in _: Context) async -> FriendShiftWidgetEntry {
        if let friend = configuration.friend {
            // For snapshot, use cached data (fast)
            return createEntry(for: friend, fromAPI: nil)
        }
        return FriendShiftWidgetEntry.placeholder()
    }

    func timeline(for configuration: FriendShiftIntent, in _: Context) async -> Timeline<FriendShiftWidgetEntry> {
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
        let entry = createEntry(for: friend, fromAPI: apiFriend)

        // Refresh every 15 minutes
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(refreshDate))
    }

    /// Update App Group cache with fresh data from API
    private func updateAppGroupCache(friends: [FriendWithShift]) {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else { return }

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
           let jsonString = String(data: data, encoding: .utf8) {
            userDefaults.set(jsonString, forKey: friendSharersKey)
        }

        // Convert to StoredFriendShift format and save
        let currency = userDefaults.string(forKey: currencyKey) ?? "kr"

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
           let jsonString = String(data: data, encoding: .utf8) {
            userDefaults.set(jsonString, forKey: friendShiftsKey)
        }
    }

    // MARK: - Private Helpers

    private func sharedUserDefaults() -> UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) != nil else {
            return nil
        }
        return UserDefaults(suiteName: appGroupId)
    }

    private func getStoredCurrency() -> String? {
        sharedUserDefaults()?.string(forKey: currencyKey)
    }

    private func loadFriendShift(for friendId: String) -> StoredFriendShift? {
        guard let userDefaults = sharedUserDefaults(),
              let jsonString = userDefaults.string(forKey: friendShiftsKey),
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
    private func createEntry(for friend: FriendEntity, fromAPI: FriendWithShift?) -> FriendShiftWidgetEntry {
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
        guard let shiftDate = shiftDate,
              let startTime = startTime,
              let endTime = endTime
        else {
            return FriendShiftWidgetEntry.empty(
                friendId: friend.id,
                friendName: friend.displayName,
                friendInitials: friend.initials,
                currency: storedCurrency
            )
        }

        // Determine layout state
        var (layoutState, daysRemaining) = determineLayoutState(shiftDateString: shiftDate)

        // Check if shift has started/ended
        let shiftStarted = hasShiftStarted(shiftDateString: shiftDate, startTime: startTime)
        let shiftEnded = hasShiftEnded(
            shiftDateString: shiftDate,
            startTime: startTime,
            endTime: endTime
        )

        // Adjust layout state for active/ended shifts
        // Preserve pastShift layout for past shifts - they should show "X days ago"
        if layoutState != .pastShift && (shiftStarted || shiftEnded) {
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

        return FriendShiftWidgetEntry(
            date: Date(),
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
            deepLinkURL: deepLinkURL
        )
    }

    // MARK: - Date Parsing & Layout Logic (same as ShiftWidgetProvider)

    private func parseShiftDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    private func countMidnightCrossings(from startDate: Date, to endDate: Date) -> Int {
        let calendar = Calendar.current
        let fromMidnight = calendar.startOfDay(for: startDate)
        let toMidnight = calendar.startOfDay(for: endDate)
        let components = calendar.dateComponents([.day], from: fromMidnight, to: toMidnight)
        return abs(components.day ?? 0)
    }

    private func hasShiftStarted(shiftDateString: String, startTime: String) -> Bool {
        guard let shiftDate = parseShiftDate(shiftDateString) else { return false }

        let timeComponents = startTime.split(separator: ":").compactMap { Int($0) }
        guard timeComponents.count >= 2 else { return false }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: shiftDate)
        components.hour = timeComponents[0]
        components.minute = timeComponents[1]

        guard let shiftStartDateTime = calendar.date(from: components) else { return false }
        return Date() >= shiftStartDateTime
    }

    private func hasShiftEnded(shiftDateString: String, startTime: String, endTime: String) -> Bool {
        guard let shiftDate = parseShiftDate(shiftDateString) else { return false }

        let calendar = Calendar.current
        let endComponents = endTime.split(separator: ":").compactMap { Int($0) }
        guard endComponents.count >= 2 else { return false }

        let startComponents = startTime.split(separator: ":").compactMap { Int($0) }
        guard startComponents.count >= 2 else { return false }

        var components = calendar.dateComponents([.year, .month, .day], from: shiftDate)
        components.hour = endComponents[0]
        components.minute = endComponents[1]

        guard var shiftEndDateTime = calendar.date(from: components) else { return false }

        // Cross-midnight shift handling
        let startMinutes = startComponents[0] * 60 + startComponents[1]
        let endMinutes = endComponents[0] * 60 + endComponents[1]
        if endMinutes <= startMinutes {
            shiftEndDateTime = calendar.date(byAdding: .day, value: 1, to: shiftEndDateTime) ?? shiftEndDateTime
        }

        guard Date() >= shiftEndDateTime else { return false }
        return calendar.isDate(shiftEndDateTime, inSameDayAs: Date())
    }

    private func determineLayoutState(shiftDateString: String) -> (state: WidgetLayoutState, daysRemaining: Int) {
        guard let shiftDate = parseShiftDate(shiftDateString) else {
            return (.empty, 0)
        }

        let today = Date()
        let calendar = Calendar.current
        let todayMidnight = calendar.startOfDay(for: today)
        let shiftMidnight = calendar.startOfDay(for: shiftDate)

        if shiftMidnight < todayMidnight {
            let daysAgo = countMidnightCrossings(from: shiftDate, to: today)
            return (.pastShift, -daysAgo)
        }

        let daysRemaining = countMidnightCrossings(from: today, to: shiftDate)

        if daysRemaining <= 1 {
            return (.todayOrTomorrow, daysRemaining)
        } else {
            return (.countdown, daysRemaining)
        }
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
                weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE d")
                return weekdayFormatter.string(from: shiftDate).capitalized
            }
        }

        // Today
        if calendar.isDate(shiftDay, inSameDayAs: today) {
            return String(localized: .widgetToday)
        }

        // Tomorrow
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(shiftDay, inSameDayAs: tomorrow) {
            return String(localized: .widgetTomorrow)
        }

        // Weekday + day
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = appLocale()
        weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE d")
        return weekdayFormatter.string(from: shiftDate).capitalized
    }
}

// MARK: - App Locale Helper

private func appLocale() -> Locale {
    let identifier = Bundle.main.preferredLocalizations.first ?? Locale.autoupdatingCurrent.identifier
    return Locale(identifier: identifier)
}

// MARK: - Initials Circle View

private struct InitialsCircle: View {
    let initials: String
    let size: CGFloat
    var backgroundColor: Color = Color.white.opacity(0.15)
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
    @Environment(\.colorScheme) var colorScheme

    private var isLightMode: Bool {
        colorScheme == .light
    }

    // Reuse color definitions from ShiftHomeWidget
    private var tidexBlue: Color {
        isLightMode
            ? Color(hue: 221 / 360, saturation: 0.83, brightness: 0.53)
            : Color(red: 77 / 255, green: 137 / 255, blue: 249 / 255)
    }

    private var tidexDarkBackground: Color {
        isLightMode
            ? Color(hue: 220 / 360, saturation: 0.40, brightness: 0.98)
            : Color(red: 10 / 255, green: 15 / 255, blue: 26 / 255)
    }

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
            return tidexDarkBackground
        }
    }

    private var primaryTextColor: Color {
        switch renderingMode {
        case .accented, .vibrant:
            return .primary
        default:
            return .white
        }
    }

    private var secondaryTextColor: Color {
        switch renderingMode {
        case .accented, .vibrant:
            return .secondary
        default:
            return .white.opacity(0.6)
        }
    }

    private var accentColor: Color {
        switch renderingMode {
        case .accented:
            return .primary
        default:
            return tidexBlue
        }
    }

    private var mutedTextColor: Color {
        switch renderingMode {
        case .accented, .vibrant:
            return .secondary
        default:
            return .white.opacity(0.4)
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
                backgroundColor: renderingMode == .fullColor ? .white.opacity(0.15) : .secondary.opacity(0.2),
                textColor: renderingMode == .fullColor ? .white : .primary
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
        HStack(spacing: 6) {
            // Date (matching standard widget layout)
            Text(entry.shiftDate)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(entry.hasShift ? accentColor : mutedTextColor)
                .widgetAccentable(entry.hasShift)
                .lineLimit(1)

            // Earnings (if visible)
            if entry.showEarnings {
                Text(entry.netEarnings)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
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

            Text("\(entry.startTime) – \(entry.endTime)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
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
