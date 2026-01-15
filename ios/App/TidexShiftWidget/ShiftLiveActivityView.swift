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

// MARK: - Time Formatter (for fallback static display)

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

// MARK: - Real-Time Calculation Helpers

/// Calculate current earnings based on elapsed time (linear interpolation)
private func calculateCurrentEarnings(startDate: Date, endDate: Date, totalGross: Double, at now: Date) -> Double {
    let total = endDate.timeIntervalSince(startDate)
    guard total > 0 else { return 0 }
    let elapsed = now.timeIntervalSince(startDate)
    let progress = min(1.0, max(0.0, elapsed / total))
    return progress * totalGross
}

/// Calculate progress percentage based on elapsed time
private func calculateProgress(startDate: Date, endDate: Date, at now: Date) -> Double {
    let total = endDate.timeIntervalSince(startDate)
    guard total > 0 else { return 0 }
    let elapsed = now.timeIntervalSince(startDate)
    return min(100.0, max(0.0, (elapsed / total) * 100.0))
}

// MARK: - Lock Screen View

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<ShiftActivityAttributes>

    private var currencySymbol: String {
        context.attributes.currencySymbol ?? "kr"
    }

    var body: some View {
        // TimelineView updates the view every minute for earnings calculation
        TimelineView(.periodic(from: context.attributes.startDate, by: 60)) { timelineContext in
            let now = timelineContext.date
            let currentEarnings = calculateCurrentEarnings(
                startDate: context.attributes.startDate,
                endDate: context.attributes.endDate,
                totalGross: context.attributes.totalGrossEstimate,
                at: now
            )
            let progress = calculateProgress(
                startDate: context.attributes.startDate,
                endDate: context.attributes.endDate,
                at: now
            )

            HStack(spacing: 16) {
                // Left side: Time info
                VStack(alignment: .leading, spacing: 4) {
                    // Time remaining - uses SwiftUI's auto-updating timer
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14))
                            .foregroundColor(tidexBlue)
                        // SwiftUI timer automatically counts down every second
                        Text(context.attributes.endDate, style: .timer)
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

                // Right side: Earnings (updates every minute)
                VStack(alignment: .trailing, spacing: 4) {
                    // Current earnings - calculated from elapsed time
                    Text("\(formatCurrency(currentEarnings)) \(currencySymbol)")
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
                // Progress bar at bottom - updates every minute
                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(tidexBlue.opacity(0.3))
                            .frame(width: geometry.size.width * CGFloat(progress / 100), height: 3)
                            .animation(.linear(duration: 1.0), value: progress)
                    }
                }
            )
        }
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
            // SwiftUI timer automatically counts down
            Text(context.attributes.endDate, style: .timer)
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
        // TimelineView updates earnings every minute
        TimelineView(.periodic(from: context.attributes.startDate, by: 60)) { timelineContext in
            let currentEarnings = calculateCurrentEarnings(
                startDate: context.attributes.startDate,
                endDate: context.attributes.endDate,
                totalGross: context.attributes.totalGrossEstimate,
                at: timelineContext.date
            )
            Text("\(formatCurrency(currentEarnings)) \(currencySymbol)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(tidexBlue)
        }
    }
}

// MARK: - Dynamic Island Expanded View

struct ExpandedView: View {
    let context: ActivityViewContext<ShiftActivityAttributes>

    private var currencySymbol: String {
        context.attributes.currencySymbol ?? "kr"
    }

    var body: some View {
        // TimelineView updates earnings and progress every minute
        TimelineView(.periodic(from: context.attributes.startDate, by: 60)) { timelineContext in
            let now = timelineContext.date
            let currentEarnings = calculateCurrentEarnings(
                startDate: context.attributes.startDate,
                endDate: context.attributes.endDate,
                totalGross: context.attributes.totalGrossEstimate,
                at: now
            )
            let progress = calculateProgress(
                startDate: context.attributes.startDate,
                endDate: context.attributes.endDate,
                at: now
            )

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
                        // SwiftUI timer automatically counts down
                        Text(context.attributes.endDate, style: .timer)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                }

                // Progress bar - updates every minute
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tidexBlue)
                            .frame(width: geometry.size.width * CGFloat(progress / 100), height: 4)
                            .animation(.linear(duration: 1.0), value: progress)
                    }
                }
                .frame(height: 4)

                // Bottom row: Earnings - updates every minute
                HStack {
                    Text(localizedString("earned", locale: context.attributes.locale))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(formatCurrency(currentEarnings)) / \(formatCurrency(context.attributes.totalGrossEstimate)) \(currencySymbol)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(tidexBlue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
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
