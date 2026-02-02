import WidgetKit

/// Layout state for the widget - determines which layout to render
enum WidgetLayoutState {
    /// State A: Today or tomorrow - shows start time prominently with end time and salute
    case todayOrTomorrow
    /// State B: More than 1 day away - shows countdown in days with time range
    case countdown
    /// State C: Past shift - shows "X days ago" when no future shifts
    case pastShift
    /// Empty/placeholder state - no shift available
    case empty
}

/// Timeline entry for the Shift Home Widget
struct ShiftWidgetEntry: TimelineEntry {
    /// The date for this timeline entry (used by WidgetKit for scheduling)
    let date: Date

    /// Formatted shift date: "I dag", "I morgen", "Man 12." etc.
    let shiftDate: String

    /// Start time in HH:MM format (always includes minutes for clarity)
    let startTime: String

    /// End time in HH:MM format
    let endTime: String

    /// Formatted net earnings after tax, e.g., "892 kr"
    let netEarnings: String

    /// Random motivational salute phrase
    let salute: String

    /// User's locale ("no" or "en")
    let locale: String

    /// Whether there's a shift to display (false shows placeholder)
    let hasShift: Bool

    /// Number of days until the shift (using midnight-crossing logic)
    let daysRemaining: Int

    /// The layout state determining which view to render
    let layoutState: WidgetLayoutState

    /// Whether the shift has already started (used to swap time emphasis)
    let shiftHasStarted: Bool

    /// Whether the shift has already ended (used to show "Ferdig" / "Done")
    let shiftHasEnded: Bool

    /// Deep link URL to open the shift in the app (e.g., "tidex://shifts?dates=2025-01-15")
    let deepLinkURL: URL?

    /// Placeholder entry for widget gallery and loading states
    static func placeholder(locale: String = "no") -> ShiftWidgetEntry {
        ShiftWidgetEntry(
            date: Date(),
            shiftDate: String(localized: .widgetToday),
            startTime: "07:00",
            endTime: "15:00",
            netEarnings: "892 kr",
            salute: MotivationalSalutes.random(locale: locale),
            locale: locale,
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
    ///   - locale: User's locale ("no" or "en")
    ///   - currency: User's currency symbol (e.g., "kr", "$"). If nil, shows "---" without currency
    static func empty(locale: String = "no", currency: String? = nil) -> ShiftWidgetEntry {
        // Format empty earnings based on currency
        // If no currency is known, just show "---"
        let emptyEarnings: String
        if let currency = currency {
            emptyEarnings = WidgetCurrencyFormatter.formatEmpty(currency: currency)
        } else {
            emptyEarnings = "---"
        }

        return ShiftWidgetEntry(
            date: Date(),
            shiftDate: "---",
            startTime: "--:--",
            endTime: "--:--",
            netEarnings: emptyEarnings,
            salute: "---",
            locale: locale,
            hasShift: false,
            daysRemaining: 0,
            layoutState: .empty,
            shiftHasStarted: false,
            shiftHasEnded: false,
            deepLinkURL: nil
        )
    }
}
