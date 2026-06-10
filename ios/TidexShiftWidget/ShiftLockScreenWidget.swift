import SwiftUI
import WidgetKit

extension ShiftWidgetEntry {
  /// Shift start timestamp for today's upcoming shifts (used for lock screen countdown timer)
  fileprivate var lockScreenCountdownTargetDate: Date? {
    guard hasShift,
      layoutState == .todayOrTomorrow,
      daysRemaining == 0,
      !shiftHasStarted,
      !shiftHasEnded
    else {
      return nil
    }

    let timeComponents = startTime.split(separator: ":").compactMap { Int($0) }
    guard timeComponents.count >= 2 else {
      return nil
    }

    let calendar = Calendar.current
    var components = calendar.dateComponents([.year, .month, .day], from: date)
    components.hour = timeComponents[0]
    components.minute = timeComponents[1]
    components.second = 0

    return calendar.date(from: components)
  }

  /// Shift end timestamp for active shifts (used for countdown to shift end)
  fileprivate var shiftEndDateTime: Date? {
    guard hasShift,
      shiftHasStarted,
      !shiftHasEnded
    else {
      return nil
    }

    let calendar = Calendar.current
    let startComponents = startTime.split(separator: ":").compactMap { Int($0) }
    let endComponents = endTime.split(separator: ":").compactMap { Int($0) }
    guard startComponents.count >= 2, endComponents.count >= 2 else {
      return nil
    }

    var components = calendar.dateComponents([.year, .month, .day], from: date)
    components.hour = endComponents[0]
    components.minute = endComponents[1]
    components.second = 0

    guard var endDate = calendar.date(from: components) else {
      return nil
    }

    // Handle cross-midnight shifts (end time <= start time)
    let startMinutes = startComponents[0] * 60 + startComponents[1]
    let endMinutes = endComponents[0] * 60 + endComponents[1]
    if endMinutes <= startMinutes {
      endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
    }

    return endDate
  }
}

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

            Text(.widgetDays)
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

            Text(.widgetAgo)
              .font(.system(size: 9, weight: .medium))
              .textCase(.uppercase)
          }
        } else if entry.shiftHasEnded {
          // Shift ended today: show "Done" indicator with checkmark
          VStack(spacing: 0) {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 20))

            Text(.widgetDone)
              .font(.system(size: 9, weight: .medium))
              .textCase(.uppercase)
          }
        } else if let countdownTarget = entry.lockScreenCountdownTargetDate {
          // Today's upcoming shift: show live countdown to shift start
          VStack(spacing: 0) {
            Text(countdownTarget, style: .timer)
              .font(.system(size: 13, weight: .bold, design: .rounded))
              .monospacedDigit()
              .lineLimit(1)

            Text(.widgetStart)
              .font(.system(size: 9, weight: .medium))
              .textCase(.uppercase)
          }
        } else if let shiftEnd = entry.shiftEndDateTime {
          // Shift in progress: show live countdown to end
          VStack(spacing: 0) {
            Text(shiftEnd, style: .timer)
              .font(.system(size: 13, weight: .bold, design: .rounded))
              .monospacedDigit()
              .lineLimit(1)

            Text(.widgetEnd)
              .font(.system(size: 9, weight: .medium))
              .textCase(.uppercase)
          }
        } else {
          // Today/tomorrow: show start time
          VStack(spacing: 0) {
            Text(entry.startTime)
              .font(.system(size: 18, weight: .bold, design: .rounded))
              .monospacedDigit()

            Text(.widgetStart)
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

          Spacer(minLength: 4)

          if let countdownTarget = entry.lockScreenCountdownTargetDate {
            Text(countdownTarget, style: .timer)
              .font(.system(size: 11, weight: .semibold, design: .rounded))
              .monospacedDigit()
              .lineLimit(1)
          } else if let shiftEnd = entry.shiftEndDateTime {
            Text(shiftEnd, style: .timer)
              .font(.system(size: 11, weight: .semibold, design: .rounded))
              .monospacedDigit()
              .lineLimit(1)
          }
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
      // Simplified empty state
      HStack(spacing: 6) {
        Image(systemName: "briefcase")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.secondary)

        Text(.widgetNoShifts)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        Label(
          "\(entry.daysRemaining)d \(entry.startTime)-\(entry.endTime)", systemImage: "calendar")
      } else if entry.layoutState == .pastShift {
        // Past shift from previous day: "3d ago"
        let daysAgo = abs(entry.daysRemaining)
        let agoText = String(localized: .widgetAgo)
        Label("\(daysAgo)d \(agoText)", systemImage: "clock.arrow.circlepath")
      } else if entry.shiftHasEnded {
        // Shift ended today: "Done"
        Label(String(localized: .widgetDoneCapitalized), systemImage: "checkmark.circle")
      } else if let countdownTarget = entry.lockScreenCountdownTargetDate {
        // Today's upcoming shift: live countdown to shift start
        Label {
          Text(countdownTarget, style: .timer)
            .monospacedDigit()
        } icon: {
          Image(systemName: "hourglass")
        }
      } else if let shiftEnd = entry.shiftEndDateTime {
        // In progress: live countdown to end
        Label {
          Text(shiftEnd, style: .timer)
            .monospacedDigit()
        } icon: {
          Image(systemName: "hourglass.bottomhalf.filled")
        }
      } else {
        // Today/tomorrow: "I dag 07:00"
        Label("\(entry.shiftDate) \(entry.startTime)", systemImage: "briefcase.fill")
      }
    } else {
      Label(String(localized: .widgetNoShift), systemImage: "briefcase")
    }
  }
}

// MARK: - Lock Screen Widget Configuration

/// Dedicated lock screen widget for iOS 16+
/// Shows shift information in lock screen accessory sizes
struct ShiftLockScreenWidget: Widget {
  let kind: String = "ShiftLockScreenWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ShiftWidgetProvider()) { entry in
      ShiftLockScreenWidgetEntryView(entry: entry)
        .widgetURL(entry.deepLinkURL)
        .containerBackground(for: .widget) {
          // Accessory widgets don't have backgrounds
          Color.clear
        }
    }
    .configurationDisplayName(String(localized: .widgetNameShift))
    .description(String(localized: .widgetDescLockScreen))
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

extension View {
  @ViewBuilder
  fileprivate func widgetAccentableIfAvailable(_ enabled: Bool = true) -> some View {
    widgetAccentable(enabled)
  }
}

#if DEBUG
  #Preview("Circular", as: .accessoryCircular) {
    ShiftLockScreenWidget()
  } timeline: {
    ShiftWidgetEntry.placeholder()
    ShiftWidgetEntry(
      date: Date(),
      shiftDate: "I dag",
      startTime: "07:00",
      endTime: "15:00",
      netEarnings: "892 kr",
      salute: "Du klarer det!",
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
      hasShift: true,
      daysRemaining: -3,
      layoutState: .pastShift,
      shiftHasStarted: true,
      shiftHasEnded: true,
      deepLinkURL: nil
    )
    ShiftWidgetEntry.empty()
  }

  #Preview("Rectangular", as: .accessoryRectangular) {
    ShiftLockScreenWidget()
  } timeline: {
    ShiftWidgetEntry.placeholder()
    ShiftWidgetEntry.placeholder()
    ShiftWidgetEntry(
      date: Date(),
      shiftDate: "I dag",
      startTime: "07:00",
      endTime: "15:00",
      netEarnings: "892 kr",
      salute: "Du klarer det!",
      hasShift: true,
      daysRemaining: 0,
      layoutState: .todayOrTomorrow,
      shiftHasStarted: true,
      shiftHasEnded: false,
      deepLinkURL: nil
    )
    ShiftWidgetEntry.empty()
  }

  #Preview("Inline", as: .accessoryInline) {
    ShiftLockScreenWidget()
  } timeline: {
    ShiftWidgetEntry.placeholder()
    ShiftWidgetEntry(
      date: Date(),
      shiftDate: "I dag",
      startTime: "07:00",
      endTime: "15:00",
      netEarnings: "892 kr",
      salute: "Du klarer det!",
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
      hasShift: true,
      daysRemaining: 5,
      layoutState: .countdown,
      shiftHasStarted: false,
      shiftHasEnded: false,
      deepLinkURL: nil
    )
    ShiftWidgetEntry.empty()
  }
#endif
