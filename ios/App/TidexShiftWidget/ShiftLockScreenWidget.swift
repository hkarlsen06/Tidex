import SwiftUI
import WidgetKit

// MARK: - Lock Screen Widget Views (iOS 16+)

/// Circular lock screen widget - shows time until shift or current shift indicator
struct ShiftAccessoryCircularView: View {
    let entry: ShiftWidgetEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            if entry.hasShift {
                if entry.layoutState == .countdown {
                    // Countdown: show days remaining
                    VStack(spacing: 0) {
                        Text("\(entry.daysRemaining)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.8)

                        Text(entry.locale == "no" ? "dager" : "days")
                            .font(.system(size: 9, weight: .medium))
                            .textCase(.uppercase)
                    }
                } else if entry.layoutState == .pastShift {
                    // Past shift from previous day: show days ago countup
                    let daysAgo = abs(entry.daysRemaining)
                    VStack(spacing: 0) {
                        Text("\(daysAgo)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.8)

                        Text(entry.locale == "no" ? "siden" : "ago")
                            .font(.system(size: 9, weight: .medium))
                            .textCase(.uppercase)
                    }
                } else if entry.shiftHasEnded {
                    // Shift ended today: show "Done" indicator with checkmark
                    VStack(spacing: 0) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))

                        Text(entry.locale == "no" ? "ferdig" : "done")
                            .font(.system(size: 9, weight: .medium))
                            .textCase(.uppercase)
                    }
                } else if entry.shiftHasStarted {
                    // Shift in progress: show end time
                    VStack(spacing: 0) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))

                        Text(entry.endTime)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                } else {
                    // Today/tomorrow: show start time
                    VStack(spacing: 0) {
                        Text(entry.startTime)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        Text("start")
                            .font(.system(size: 9, weight: .medium))
                            .textCase(.uppercase)
                    }
                }
            } else {
                // No shift: show briefcase icon
                Image(systemName: "briefcase")
                    .font(.system(size: 20))
            }
        }
    }
}

/// Rectangular lock screen widget - shows shift date, time range, and earnings
struct ShiftAccessoryRectangularView: View {
    let entry: ShiftWidgetEntry

    var body: some View {
        if entry.hasShift {
            VStack(alignment: .leading, spacing: 2) {
                // Top row: Date label with icon
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .medium))

                    Text(entry.shiftDate)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .widgetAccentableIfAvailable()

                // Middle row: Time range (large)
                Text("\(entry.startTime) – \(entry.endTime)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)

                // Bottom row: Earnings
                HStack(spacing: 4) {
                    Image(systemName: "banknote")
                        .font(.system(size: 10, weight: .medium))

                    Text(entry.netEarnings)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // No shift state
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "briefcase")
                        .font(.system(size: 11, weight: .medium))

                    Text(entry.locale == "no" ? "Ingen vakt" : "No shift")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .widgetAccentableIfAvailable()

                Text("--:-- – --:--")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("---")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Inline lock screen widget - single line with essential info
struct ShiftAccessoryInlineView: View {
    let entry: ShiftWidgetEntry

    var body: some View {
        if entry.hasShift {
            if entry.layoutState == .countdown {
                // Countdown mode: "5d 16:00-23:15"
                let daysText = entry.locale == "no" ? "d" : "d"
                Label("\(entry.daysRemaining)\(daysText) \(entry.startTime)-\(entry.endTime)", systemImage: "calendar")
            } else if entry.layoutState == .pastShift {
                // Past shift from previous day: "3d siden" / "3d ago"
                let daysAgo = abs(entry.daysRemaining)
                let agoText = entry.locale == "no" ? "siden" : "ago"
                Label("\(daysAgo)d \(agoText)", systemImage: "clock.arrow.circlepath")
            } else if entry.shiftHasEnded {
                // Shift ended today: "Ferdig" / "Done"
                let doneText = entry.locale == "no" ? "Ferdig" : "Done"
                Label(doneText, systemImage: "checkmark.circle")
            } else if entry.shiftHasStarted {
                // In progress: "Ends 15:00" / "Slutt 15:00"
                let endsText = entry.locale == "no" ? "Slutt" : "Ends"
                Label("\(endsText) \(entry.endTime)", systemImage: "clock.fill")
            } else {
                // Today/tomorrow: "I dag 07:00"
                Label("\(entry.shiftDate) \(entry.startTime)", systemImage: "briefcase.fill")
            }
        } else {
            Label(entry.locale == "no" ? "Ingen vakt" : "No shift", systemImage: "briefcase")
        }
    }
}

// MARK: - Lock Screen Widget Configuration

/// Dedicated lock screen widget for iOS 16+
/// Shows shift information in lock screen accessory sizes
struct ShiftLockScreenWidget: Widget {
    let kind: String = "ShiftLockScreenWidget"

    /// Check if the user's preferred language is Norwegian
    private var isNorwegian: Bool {
        let preferredLanguages = Locale.preferredLanguages
        return preferredLanguages.first?.hasPrefix("nb") == true ||
            preferredLanguages.first?.hasPrefix("no") == true ||
            preferredLanguages.first?.hasPrefix("nn") == true
    }

    /// Localized widget display name
    private var displayName: String {
        isNorwegian ? "Vakt" : "Shift"
    }

    /// Localized widget description
    private var widgetDescription: String {
        isNorwegian ? "Se neste vakt på låseskjermen" : "See your next shift on the lock screen"
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShiftWidgetProvider()) { entry in
            ShiftLockScreenWidgetEntryView(entry: entry)
                .widgetURL(entry.deepLinkURL)
                .containerBackground(for: .widget) {
                    // Accessory widgets don't have backgrounds
                    Color.clear
                }
        }
        .configurationDisplayName(displayName)
        .description(widgetDescription)
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

/// Entry view that switches based on widget family
struct ShiftLockScreenWidgetEntryView: View {
    let entry: ShiftWidgetEntry
    @Environment(\.widgetFamily) var widgetFamily

    var body: some View {
        switch widgetFamily {
        case .accessoryCircular:
            ShiftAccessoryCircularView(entry: entry)
        case .accessoryRectangular:
            ShiftAccessoryRectangularView(entry: entry)
        case .accessoryInline:
            ShiftAccessoryInlineView(entry: entry)
        default:
            // Fallback for unsupported families
            Text("---")
        }
    }
}

// MARK: - Previews

private extension View {
    @ViewBuilder
    func widgetAccentableIfAvailable(_ enabled: Bool = true) -> some View {
        widgetAccentable(enabled)
    }
}

#if DEBUG
#Preview("Circular", as: .accessoryCircular) {
    ShiftLockScreenWidget()
} timeline: {
    ShiftWidgetEntry.placeholder(locale: "no")
    ShiftWidgetEntry(
        date: Date(),
        shiftDate: "I dag",
        startTime: "07:00",
        endTime: "15:00",
        netEarnings: "892 kr",
        salute: "Du klarer det!",
        locale: "no",
        hasShift: true,
        daysRemaining: 0,
        layoutState: .todayOrTomorrow,
        shiftHasStarted: true,
        shiftHasEnded: false,
        deepLinkURL: nil
    )
    // Shift ended today
    ShiftWidgetEntry(
        date: Date(),
        shiftDate: "I dag",
        startTime: "07:00",
        endTime: "15:00",
        netEarnings: "892 kr",
        salute: "Godt jobbet!",
        locale: "no",
        hasShift: true,
        daysRemaining: 0,
        layoutState: .todayOrTomorrow,
        shiftHasStarted: true,
        shiftHasEnded: true,
        deepLinkURL: nil
    )
    ShiftWidgetEntry(
        date: Date(),
        shiftDate: "Man. 20.",
        startTime: "16:00",
        endTime: "23:15",
        netEarnings: "1 332 kr",
        salute: "Stå på!",
        locale: "no",
        hasShift: true,
        daysRemaining: 5,
        layoutState: .countdown,
        shiftHasStarted: false,
        shiftHasEnded: false,
        deepLinkURL: nil
    )
    // Past shift (days ago countup)
    ShiftWidgetEntry(
        date: Date(),
        shiftDate: "Fre. 9.",
        startTime: "12:00",
        endTime: "16:00",
        netEarnings: "230 kr",
        salute: "Godt jobbet!",
        locale: "no",
        hasShift: true,
        daysRemaining: -3,
        layoutState: .pastShift,
        shiftHasStarted: true,
        shiftHasEnded: true,
        deepLinkURL: nil
    )
    ShiftWidgetEntry.empty(locale: "no")
}

#Preview("Rectangular", as: .accessoryRectangular) {
    ShiftLockScreenWidget()
} timeline: {
    ShiftWidgetEntry.placeholder(locale: "no")
    ShiftWidgetEntry.placeholder(locale: "en")
    ShiftWidgetEntry(
        date: Date(),
        shiftDate: "I dag",
        startTime: "07:00",
        endTime: "15:00",
        netEarnings: "892 kr",
        salute: "Du klarer det!",
        locale: "no",
        hasShift: true,
        daysRemaining: 0,
        layoutState: .todayOrTomorrow,
        shiftHasStarted: true,
        shiftHasEnded: false,
        deepLinkURL: nil
    )
    ShiftWidgetEntry.empty(locale: "no")
}

#Preview("Inline", as: .accessoryInline) {
    ShiftLockScreenWidget()
} timeline: {
    ShiftWidgetEntry.placeholder(locale: "no")
    ShiftWidgetEntry(
        date: Date(),
        shiftDate: "I dag",
        startTime: "07:00",
        endTime: "15:00",
        netEarnings: "892 kr",
        salute: "Du klarer det!",
        locale: "no",
        hasShift: true,
        daysRemaining: 0,
        layoutState: .todayOrTomorrow,
        shiftHasStarted: true,
        shiftHasEnded: false,
        deepLinkURL: nil
    )
    ShiftWidgetEntry(
        date: Date(),
        shiftDate: "Mon. 20.",
        startTime: "16:00",
        endTime: "23:15",
        netEarnings: "$234",
        salute: "You got this!",
        locale: "en",
        hasShift: true,
        daysRemaining: 5,
        layoutState: .countdown,
        shiftHasStarted: false,
        shiftHasEnded: false,
        deepLinkURL: nil
    )
    ShiftWidgetEntry.empty(locale: "en")
}
#endif
