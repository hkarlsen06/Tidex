import WidgetKit

/// Layout state for the widget - determines which layout to render
internal enum WidgetLayoutState {
  /// State B: More than 1 day away - shows countdown in days with time range
  case countdown
  /// Empty/placeholder state - no shift available
  case empty
  /// State C: Past shift - shows "X days ago" when no future shifts
  case pastShift
  /// State A: Today or tomorrow - shows start time prominently with end time and salute
  case todayOrTomorrow
}

/// A timeline entry that shows one shift with its real start and end instants.
internal protocol ShiftTimelineEntry: TimelineEntry {
  var hasShift: Bool { get }
  var layoutState: WidgetLayoutState { get }
  var daysRemaining: Int { get }
  var shiftHasStarted: Bool { get }
  var shiftHasEnded: Bool { get }
  var shiftStart: Date? { get }
  var shiftEnd: Date? { get }
}

extension ShiftTimelineEntry {
  /// Start of today's shift while it is still upcoming, for a live countdown.
  internal var upcomingStartToday: Date? {
    guard hasShift,
      layoutState == .todayOrTomorrow,
      daysRemaining == 0,
      !shiftHasStarted,
      !shiftHasEnded
    else {
      return nil
    }
    return shiftStart
  }

  /// End of the shift in progress, for a live countdown. Nil once the shift is over.
  internal var activeShiftEnd: Date? {
    guard hasShift, shiftHasStarted, !shiftHasEnded, let shiftEnd, shiftEnd > date else {
      return nil
    }
    return shiftEnd
  }
}

/// Timeline entry for the Shift Home Widget
internal struct ShiftWidgetEntry: ShiftTimelineEntry {
  /// The date for this timeline entry (used by WidgetKit for scheduling)
  internal let date: Date

  /// Formatted shift date: "I dag", "I morgen", "Man 12." etc.
  internal let shiftDate: String

  /// Start time in HH:MM format (always includes minutes for clarity)
  internal let startTime: String

  /// End time in HH:MM format
  internal let endTime: String

  /// Formatted net earnings after tax, e.g., "892 kr"
  internal let netEarnings: String

  /// Random motivational salute phrase
  internal let salute: String

  /// Whether there's a shift to display (false shows placeholder)
  internal let hasShift: Bool

  /// Number of days until the shift (using midnight-crossing logic)
  internal let daysRemaining: Int

  /// The layout state determining which view to render
  internal let layoutState: WidgetLayoutState

  /// Whether the shift has already started (used to swap time emphasis)
  internal let shiftHasStarted: Bool

  /// Whether the shift has already ended (used to show "Ferdig" / "Done")
  internal let shiftHasEnded: Bool

  /// Deep link URL to open the shift in the app (e.g., "tidex://shifts?dates=2025-01-15")
  internal let deepLinkURL: URL?

  /// Real start instant of the shift
  internal var shiftStart: Date?

  /// Real end instant of the shift (next day for night shifts)
  internal var shiftEnd: Date?

  /// Placeholder entry for widget gallery and loading states
  internal static func placeholder() -> Self {
    Self(
      date: Date(),
      shiftDate: String(localized: .widgetToday),
      startTime: "07:00",
      endTime: "15:00",
      netEarnings: "892 kr",
      salute: MotivationalSalutes.random(),
      hasShift: true,
      daysRemaining: 0,
      layoutState: .todayOrTomorrow,
      shiftHasStarted: false,
      shiftHasEnded: false,
      deepLinkURL: nil
    )
  }

  /// Empty state entry when no shifts are available
  /// Shows placeholder values for each element instead of a single message
  /// - Parameters:
  ///   - currency: User's currency symbol (e.g., "kr", "$"). If nil, shows "---" without currency
  internal static func empty(currency: String? = nil) -> Self {
    // Format empty earnings based on currency
    // If no currency is known, just show "---"
    let emptyEarnings: String
    if let currency {
      emptyEarnings = WidgetCurrencyFormatter.formatEmpty(currency: currency)
    } else {
      emptyEarnings = "---"
    }

    return Self(
      date: Date(),
      shiftDate: "---",
      startTime: "--:--",
      endTime: "--:--",
      netEarnings: emptyEarnings,
      salute: "---",
      hasShift: false,
      daysRemaining: 0,
      layoutState: .empty,
      shiftHasStarted: false,
      shiftHasEnded: false,
      deepLinkURL: nil
    )
  }
}
