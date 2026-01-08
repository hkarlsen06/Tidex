import WidgetKit

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

    /// Placeholder entry for widget gallery and loading states
    static func placeholder(locale: String = "no") -> ShiftWidgetEntry {
        ShiftWidgetEntry(
            date: Date(),
            shiftDate: locale == "no" ? "I dag" : "Today",
            startTime: "07:00",
            endTime: "15:00",
            netEarnings: locale == "no" ? "892 kr" : "$156",
            salute: locale == "no" ? "God vakt!" : "You got this!",
            locale: locale,
            hasShift: true
        )
    }

    /// Empty state entry when no shifts are available
    /// Shows placeholder values for each element instead of a single message
    static func empty(locale: String = "no") -> ShiftWidgetEntry {
        ShiftWidgetEntry(
            date: Date(),
            shiftDate: "---",
            startTime: "--:--",
            endTime: "--:--",
            netEarnings: "--- kr",
            salute: "---",
            locale: locale,
            hasShift: false
        )
    }
}
