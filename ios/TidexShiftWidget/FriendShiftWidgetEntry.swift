import WidgetKit

/// Timeline entry for the Friend's Shift Widget
struct FriendShiftWidgetEntry: TimelineEntry {
    /// The date for this timeline entry (used by WidgetKit for scheduling)
    let date: Date

    // MARK: - Friend Info

    /// The friend's ID (empty string if no friend selected)
    let friendId: String

    /// The friend's display name
    let friendName: String

    /// The friend's initials for avatar placeholder
    let friendInitials: String

    // MARK: - Shift Info

    /// Formatted shift date: "I dag", "I morgen", "Man 12." etc.
    let shiftDate: String

    /// Start time in HH:MM format
    let startTime: String

    /// End time in HH:MM format
    let endTime: String

    /// Formatted net earnings, e.g., "892 kr" or "---" if hidden
    let netEarnings: String

    /// Whether earnings are visible for this friend
    let showEarnings: Bool

    /// User's locale ("no" or "en")
    let locale: String

    /// Whether there's a shift to display
    let hasShift: Bool

    /// Number of days until the shift (using midnight-crossing logic)
    let daysRemaining: Int

    /// The layout state determining which view to render
    let layoutState: WidgetLayoutState

    /// Whether the shift has already started
    let shiftHasStarted: Bool

    /// Whether the shift has already ended
    let shiftHasEnded: Bool

    /// Deep link URL to open the friend in the app
    let deepLinkURL: URL?

    // MARK: - Factory Methods

    /// Placeholder entry for widget gallery and loading states
    static func placeholder(locale: String = "no") -> FriendShiftWidgetEntry {
        FriendShiftWidgetEntry(
            date: Date(),
            friendId: "placeholder",
            friendName: String(localized: .widgetFriend),
            friendInitials: "VN",
            shiftDate: String(localized: .widgetToday),
            startTime: "07:00",
            endTime: "15:00",
            netEarnings: "892 kr",
            showEarnings: true,
            locale: locale,
            hasShift: true,
            daysRemaining: 0,
            layoutState: .todayOrTomorrow,
            shiftHasStarted: false,
            shiftHasEnded: false,
            deepLinkURL: nil
        )
    }

    /// Empty state entry when the selected friend has no shifts
    static func empty(
        friendId: String,
        friendName: String,
        friendInitials: String,
        locale: String = "no",
        currency: String? = nil
    ) -> FriendShiftWidgetEntry {
        let emptyEarnings: String
        if let currency = currency {
            emptyEarnings = WidgetCurrencyFormatter.formatEmpty(currency: currency)
        } else {
            emptyEarnings = "---"
        }

        return FriendShiftWidgetEntry(
            date: Date(),
            friendId: friendId,
            friendName: friendName,
            friendInitials: friendInitials,
            shiftDate: "---",
            startTime: "--:--",
            endTime: "--:--",
            netEarnings: emptyEarnings,
            showEarnings: true,
            locale: locale,
            hasShift: false,
            daysRemaining: 0,
            layoutState: .empty,
            shiftHasStarted: false,
            shiftHasEnded: false,
            deepLinkURL: URL(string: "tidex://sharing?user=\(friendId)")
        )
    }

    /// No friend selected - prompt to configure widget
    static func noFriendSelected(locale: String = "no") -> FriendShiftWidgetEntry {
        FriendShiftWidgetEntry(
            date: Date(),
            friendId: "",
            friendName: "",
            friendInitials: "",
            shiftDate: "---",
            startTime: "--:--",
            endTime: "--:--",
            netEarnings: "---",
            showEarnings: false,
            locale: locale,
            hasShift: false,
            daysRemaining: 0,
            layoutState: .empty,
            shiftHasStarted: false,
            shiftHasEnded: false,
            deepLinkURL: URL(string: "tidex://sharing")
        )
    }
}
