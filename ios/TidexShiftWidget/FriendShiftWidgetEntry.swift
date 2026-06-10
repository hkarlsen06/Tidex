import WidgetKit

/// Timeline entry for the Friend's Shift Widget
internal struct FriendShiftWidgetEntry: TimelineEntry {
  /// The date for this timeline entry (used by WidgetKit for scheduling)
  internal let date: Date

  // MARK: - Friend Info

  /// The friend's ID (empty string if no friend selected)
  internal let friendId: String

  /// The friend's display name
  internal let friendName: String

  /// The friend's initials for avatar placeholder
  internal let friendInitials: String

  // MARK: - Shift Info

  /// Formatted shift date: "I dag", "I morgen", "Man 12." etc.
  internal let shiftDate: String

  /// Start time in HH:MM format
  internal let startTime: String

  /// End time in HH:MM format
  internal let endTime: String

  /// Formatted net earnings, e.g., "892 kr" or "---" if hidden
  internal let netEarnings: String

  /// Whether earnings are visible for this friend
  internal let showEarnings: Bool

  /// Whether there's a shift to display
  internal let hasShift: Bool

  /// Number of days until the shift (using midnight-crossing logic)
  internal let daysRemaining: Int

  /// The layout state determining which view to render
  internal let layoutState: WidgetLayoutState

  /// Whether the shift has already started
  internal let shiftHasStarted: Bool

  /// Whether the shift has already ended
  internal let shiftHasEnded: Bool

  /// Deep link URL to open the friend in the app
  internal let deepLinkURL: URL?

  // MARK: - Factory Methods

  /// Placeholder entry for widget gallery and loading states
  internal static func placeholder() -> Self {
    Self(
      date: Date(),
      friendId: "placeholder",
      friendName: String(localized: .widgetFriend),
      friendInitials: "VN",
      shiftDate: String(localized: .widgetToday),
      startTime: "07:00",
      endTime: "15:00",
      netEarnings: "892 kr",
      showEarnings: true,
      hasShift: true,
      daysRemaining: 0,
      layoutState: .todayOrTomorrow,
      shiftHasStarted: false,
      shiftHasEnded: false,
      deepLinkURL: nil
    )
  }

  /// Empty state entry when the selected friend has no shifts
  internal static func empty(
    friendId: String,
    friendName: String,
    friendInitials: String,
    currency: String? = nil
  ) -> Self {
    let emptyEarnings: String
    if let currency {
      emptyEarnings = WidgetCurrencyFormatter.formatEmpty(currency: currency)
    } else {
      emptyEarnings = "---"
    }

    return Self(
      date: Date(),
      friendId: friendId,
      friendName: friendName,
      friendInitials: friendInitials,
      shiftDate: "---",
      startTime: "--:--",
      endTime: "--:--",
      netEarnings: emptyEarnings,
      showEarnings: true,
      hasShift: false,
      daysRemaining: 0,
      layoutState: .empty,
      shiftHasStarted: false,
      shiftHasEnded: false,
      deepLinkURL: URL(string: "tidex://sharing?user=\(friendId)")
    )
  }

  /// No friend selected - prompt to configure widget
  internal static func noFriendSelected() -> Self {
    Self(
      date: Date(),
      friendId: "",
      friendName: "",
      friendInitials: "",
      shiftDate: "---",
      startTime: "--:--",
      endTime: "--:--",
      netEarnings: "---",
      showEarnings: false,
      hasShift: false,
      daysRemaining: 0,
      layoutState: .empty,
      shiftHasStarted: false,
      shiftHasEnded: false,
      deepLinkURL: URL(string: "tidex://sharing")
    )
  }
}
