import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

/// Timeline entry for shift complications
struct ShiftComplicationEntry: TimelineEntry {
  let date: Date
  let shift: WatchShiftDTO?

  static var placeholder: ShiftComplicationEntry {
    ShiftComplicationEntry(
      date: Date(),
      shift: WatchShiftDTO(
        id: "placeholder",
        personId: "user",
        personName: "You",
        personProfilePictureUrl: nil,
        personOauthAvatarUrl: nil,
        shiftDate: "2025-01-21",
        startTime: "07:00",
        endTime: "15:00",
        status: .upcoming,
        avatarImageData: nil
      )
    )
  }
}

// MARK: - Timeline Provider

struct ShiftComplicationProvider: TimelineProvider {
  func placeholder(in context: Context) -> ShiftComplicationEntry {
    .placeholder
  }

  func getSnapshot(in context: Context, completion: @escaping (ShiftComplicationEntry) -> Void) {
    let entry = ShiftComplicationEntry(
      date: Date(),
      shift: WatchDataStore.shared.userShift
    )
    completion(entry)
  }

  func getTimeline(
    in context: Context, completion: @escaping (Timeline<ShiftComplicationEntry>) -> Void
  ) {
    let entry = ShiftComplicationEntry(
      date: Date(),
      shift: WatchDataStore.shared.userShift
    )

    // Refresh every 15 minutes
    let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
    let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
    completion(timeline)
  }
}

// MARK: - Complication Views

struct ShiftComplicationView: View {
  @Environment(\.widgetFamily) var family
  let entry: ShiftComplicationEntry

  var body: some View {
    switch family {
    case .accessoryCorner:
      accessoryCornerView
    case .accessoryCircular:
      accessoryCircularView
    case .accessoryRectangular:
      accessoryRectangularView
    case .accessoryInline:
      accessoryInlineView
    default:
      Text("--")
    }
  }

  // MARK: - Corner

  @ViewBuilder
  private var accessoryCornerView: some View {
    if let shift = entry.shift {
      // Show just the start hour for minimal space
      Text(String(shift.startTime.prefix(2)))
        .font(.title2)
        .widgetAccentable()
    } else {
      Text("--")
    }
  }

  // MARK: - Circular

  @ViewBuilder
  private var accessoryCircularView: some View {
    ZStack {
      AccessoryWidgetBackground()
      if let shift = entry.shift {
        VStack(spacing: 0) {
          Image(systemName: statusIcon(for: shift.status))
            .font(.caption2)
          Text(shift.startTime)
            .font(.caption)
            .fontWeight(.semibold)
        }
      } else {
        Image(systemName: "calendar.badge.clock")
      }
    }
  }

  // MARK: - Rectangular

  @ViewBuilder
  private var accessoryRectangularView: some View {
    if let shift = entry.shift {
      VStack(alignment: .leading, spacing: 2) {
        Text(shift.status == .active ? activeTitle : nextShiftTitle)
          .font(.caption2)
          .foregroundStyle(.secondary)
        Text("\(shift.startTime)–\(shift.endTime)")
          .font(.headline)
          .widgetAccentable()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      Text(noShiftsTitle)
        .font(.caption)
    }
  }

  // MARK: - Inline

  @ViewBuilder
  private var accessoryInlineView: some View {
    if let shift = entry.shift {
      Text("\(shiftLabel) \(shift.startTime)")
    } else {
      Text(noShiftsTitle)
    }
  }

  // MARK: - Helpers

  private func statusIcon(for status: ShiftPreviewStatus) -> String {
    switch status {
    case .active: return "clock.fill"
    case .upcoming: return "clock"
    case .past: return "clock.badge.checkmark"
    }
  }

  private var nextShiftTitle: String {
    String(localized: .watchNextShift)
  }

  private var activeTitle: String {
    String(localized: .watchActiveShift)
  }

  private var noShiftsTitle: String {
    String(localized: .watchNoShifts)
  }

  private var shiftLabel: String {
    String(localized: .watchShift)
  }
}

// MARK: - Widget Configuration

struct TidexShiftComplication: Widget {
  let kind = "TidexShiftComplication"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ShiftComplicationProvider()) { entry in
      ShiftComplicationView(entry: entry)
    }
    .configurationDisplayName("Next Shift")
    .description("Shows your next upcoming shift")
    .supportedFamilies([
      .accessoryCorner,
      .accessoryCircular,
      .accessoryRectangular,
      .accessoryInline
    ])
  }
}

// MARK: - Preview

#Preview(as: .accessoryRectangular) {
  TidexShiftComplication()
} timeline: {
  ShiftComplicationEntry.placeholder
}
