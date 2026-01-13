import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Tidex Brand Color

/// Tidex brand blue color - matches the app's brand gradient
private let tidexBlue = Color(red: 77/255, green: 137/255, blue: 249/255)

// MARK: - Localization Helper

private func localizedString(_ key: String, locale: String) -> String {
    let strings: [String: [String: String]] = [
        "remaining": ["no": "igjen", "en": "left"],
        "earned": ["no": "Tjent", "en": "Earned"],
        "of": ["no": "av", "en": "of"],
        "shift": ["no": "Vakt", "en": "Shift"],
        "hours_short": ["no": "t", "en": "h"],
        "minutes_short": ["no": "m", "en": "m"],
    ]
    return strings[key]?[locale] ?? strings[key]?["en"] ?? key
}

// MARK: - Currency Formatter

private func formatCurrency(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0
    formatter.groupingSeparator = " "
    return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
}

// MARK: - Time Formatter

private func formatTimeRemaining(_ minutes: Int, locale: String) -> String {
    let hours = minutes / 60
    let mins = minutes % 60
    let h = localizedString("hours_short", locale: locale)
    let m = localizedString("minutes_short", locale: locale)
    if hours > 0 {
        return "\(hours)\(h) \(mins)\(m)"
    }
    return "\(mins)\(m)"
}

// MARK: - Lock Screen View

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<ShiftActivityAttributes>

    private var currencySymbol: String {
        context.attributes.currencySymbol ?? "kr"
    }

    var body: some View {
        HStack(spacing: 16) {
            // Left side: Time info
            VStack(alignment: .leading, spacing: 4) {
                // Time remaining - all on same baseline
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 14))
                        .foregroundColor(tidexBlue)
                    Text(formatTimeRemaining(context.state.remainingMinutes, locale: context.attributes.locale))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(localizedString("remaining", locale: context.attributes.locale))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }

                // Shift time range
                Text("\(context.attributes.startTime) - \(context.attributes.endTime)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Right side: Earnings
            VStack(alignment: .trailing, spacing: 4) {
                // Current earnings
                Text("\(formatCurrency(context.state.currentEarnings)) \(currencySymbol)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(tidexBlue)

                // Of total
                Text("\(localizedString("of", locale: context.attributes.locale)) \(formatCurrency(context.attributes.totalGrossEstimate)) \(currencySymbol)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            // Progress bar at bottom
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(tidexBlue.opacity(0.3))
                        .frame(width: geometry.size.width * CGFloat(context.state.progressPercent / 100), height: 3)
                        .animation(.linear(duration: 0.5), value: context.state.progressPercent)
                }
            }
        )
    }
}

// MARK: - Dynamic Island Compact Views

struct CompactLeadingView: View {
    let context: ActivityViewContext<ShiftActivityAttributes>

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.system(size: 12))
                .foregroundColor(tidexBlue)
            Text(formatTimeRemaining(context.state.remainingMinutes, locale: context.attributes.locale))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

struct CompactTrailingView: View {
    let context: ActivityViewContext<ShiftActivityAttributes>

    private var currencySymbol: String {
        context.attributes.currencySymbol ?? "kr"
    }

    var body: some View {
        Text("\(formatCurrency(context.state.currentEarnings)) \(currencySymbol)")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(tidexBlue)
    }
}

// MARK: - Dynamic Island Expanded View

struct ExpandedView: View {
    let context: ActivityViewContext<ShiftActivityAttributes>

    private var currencySymbol: String {
        context.attributes.currencySymbol ?? "kr"
    }

    var body: some View {
        VStack(spacing: 8) {
            // Top row: Time range and remaining
            HStack {
                Text("\(context.attributes.startTime) - \(context.attributes.endTime)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(tidexBlue)
                    Text(formatTimeRemaining(context.state.remainingMinutes, locale: context.attributes.locale))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tidexBlue)
                        .frame(width: geometry.size.width * CGFloat(context.state.progressPercent / 100), height: 4)
                        .animation(.linear(duration: 0.5), value: context.state.progressPercent)
                }
            }
            .frame(height: 4)

            // Bottom row: Earnings
            HStack {
                Text(localizedString("earned", locale: context.attributes.locale))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(formatCurrency(context.state.currentEarnings)) / \(formatCurrency(context.attributes.totalGrossEstimate)) \(currencySymbol)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(tidexBlue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Minimal View

struct MinimalView: View {
    var body: some View {
        Image(systemName: "briefcase.fill")
            .font(.system(size: 14))
            .foregroundColor(tidexBlue)
    }
}

// MARK: - Live Activity Widget Configuration

struct ShiftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftActivityAttributes.self) { context in
            // Lock Screen presentation
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions - only use bottom for content
                // Leading and trailing are left empty to avoid clipping
                DynamicIslandExpandedRegion(.leading) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedView(context: context)
                }
            } compactLeading: {
                CompactLeadingView(context: context)
            } compactTrailing: {
                CompactTrailingView(context: context)
            } minimal: {
                MinimalView()
            }
        }
    }
}
