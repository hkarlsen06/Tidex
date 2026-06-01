import SwiftUI
import WidgetKit

// MARK: - Tidex Brand Color

/// Tidex brand blue color - matches the app's brand gradient
private let tidexBlue = Color(red: 77 / 255, green: 137 / 255, blue: 249 / 255)

// MARK: - Currency Formatter

private func formatCurrency(_ value: Double) -> String {
  let formatter = NumberFormatter()
  formatter.numberStyle = .decimal
  formatter.minimumFractionDigits = 0
  formatter.maximumFractionDigits = 0
  formatter.groupingSeparator = " "
  return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
}

// MARK: - Before Tax Helper

private func beforeTaxText(
  context: ActivityViewContext<ShiftActivityAttributes>,
  currencySymbol: String
) -> String {
  let label = String(localized: .widgetBeforeTax)
  let amount = formatCurrency(context.attributes.totalGrossEstimate)
  return "\(label): \(amount) \(currencySymbol)"
}

private func isTemporaryClockActivity(_ attributes: ShiftActivityAttributes) -> Bool {
  if let explicitFlag = attributes.isTemporaryClock {
    return explicitFlag
  }

  // Legacy fallback for activities created before the explicit marker existed.
  return attributes.endTime == "00:00"
    && attributes.totalGrossEstimate == 0
    && attributes.hourlyWage == 0
    && attributes.supplementRatePerHour == 0
}

private func temporaryStartedLabel() -> String {
  let languageCode = Locale.current.language.languageCode?.identifier.lowercased()
  if languageCode == "nb" || languageCode == "nn" || languageCode == "no" {
    return "Startet"
  }
  return String(localized: .widgetStart)
}

// MARK: - Lock Screen View

struct LockScreenLiveActivityView: View {
  let context: ActivityViewContext<ShiftActivityAttributes>

  private var currencySymbol: String {
    context.attributes.currencySymbol ?? "kr"
  }

  /// The primary amount to display (net if available, otherwise gross)
  private var displayAmount: Double {
    context.attributes.totalNetEstimate ?? context.attributes.totalGrossEstimate
  }

  /// Whether to show "before tax" line (when net differs from gross)
  private var showBeforeTax: Bool {
    context.attributes.totalNetEstimate != nil
  }

  private var isTemporaryClock: Bool {
    isTemporaryClockActivity(context.attributes)
  }

  var body: some View {
    HStack(spacing: 16) {
      // Left side: Time info
      VStack(alignment: .leading, spacing: 4) {
        // Time remaining
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Image(systemName: "clock.fill")
            .font(.system(size: 14))
            .foregroundColor(tidexBlue)
          Text(context.attributes.endDate, style: .timer)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }

        // Shift time range
        if isTemporaryClock {
          Text("\(temporaryStartedLabel()) \(context.attributes.startTime)")
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.secondary)
        } else {
          Text("\(context.attributes.startTime) - \(context.attributes.endTime)")
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.secondary)
        }
      }

      Spacer()

      // Right side: Earnings
      VStack(alignment: .trailing, spacing: 2) {
        if isTemporaryClock {
          Text(.widgetActive)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundColor(tidexBlue)
        } else {
          // Primary amount (net or gross)
          Text("\(formatCurrency(displayAmount)) \(currencySymbol)")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(tidexBlue)

          // Before tax (only if tax is configured)
          if showBeforeTax {
            Text(beforeTaxText(context: context, currencySymbol: currencySymbol))
              .font(.system(size: 12))
              .foregroundColor(.secondary)
          }
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
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

  /// The primary amount to display (net if available, otherwise gross)
  private var displayAmount: Double {
    context.attributes.totalNetEstimate ?? context.attributes.totalGrossEstimate
  }

  private var isTemporaryClock: Bool {
    isTemporaryClockActivity(context.attributes)
  }

  var body: some View {
    if isTemporaryClock {
      Text(.widgetActive)
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundColor(tidexBlue)
    } else {
      Text("\(formatCurrency(displayAmount)) \(currencySymbol)")
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

  /// The primary amount to display (net if available, otherwise gross)
  private var displayAmount: Double {
    context.attributes.totalNetEstimate ?? context.attributes.totalGrossEstimate
  }

  /// Whether to show "before tax" line (when net differs from gross)
  private var showBeforeTax: Bool {
    context.attributes.totalNetEstimate != nil
  }

  private var isTemporaryClock: Bool {
    isTemporaryClockActivity(context.attributes)
  }

  var body: some View {
    HStack(spacing: 12) {
      // Left column: Countdown (top), Time range (bottom)
      VStack(alignment: .leading, spacing: 4) {
        // Countdown timer
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Image(systemName: "clock.fill")
            .font(.system(size: 12))
            .foregroundColor(tidexBlue)
          Text(context.attributes.endDate, style: .timer)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .monospacedDigit()
        }

        // Shift time range
        if isTemporaryClock {
          Text("\(temporaryStartedLabel()) \(context.attributes.startTime)")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)
        } else {
          Text("\(context.attributes.startTime) - \(context.attributes.endTime)")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)
        }
      }

      Spacer()

      // Right column: Net (top), Before tax (bottom)
      VStack(alignment: .trailing, spacing: 4) {
        if isTemporaryClock {
          Text(.widgetActive)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundColor(tidexBlue)
        } else {
          // Net amount
          Text("\(formatCurrency(displayAmount)) \(currencySymbol)")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(tidexBlue)

          // Before tax (only if tax configured)
          if showBeforeTax {
            Text(beforeTaxText(context: context, currencySymbol: currencySymbol))
              .font(.system(size: 11))
              .foregroundColor(.secondary)
          }
        }
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
