import Foundation

/// Spoken summaries for widgets. A widget view ignores its children and reads one summary,
/// so VoiceOver says "07:00 to 15:00, 892 kr" and not four unrelated pieces of text.
internal enum WidgetAccessibility {
  /// "07:00 to 15:00".
  internal static func timeRange(_ start: String, _ end: String) -> String {
    String(localized: .widgetAccessibilityTimeRange(start, end))
  }

  /// Turns a "07:00 – 15:00" display string into a spoken range. Other strings pass through.
  internal static func spokenTimeRange(_ range: String) -> String {
    let parts = range.components(separatedBy: " – ")
    guard parts.count == 2 else { return range }
    return timeRange(parts[0], parts[1])
  }

  /// "5 days left".
  internal static func daysLeft(_ days: Int) -> String {
    let unit = String(localized: days == 1 ? .widgetDay : .widgetDays)
    return "\(days) \(unit) \(String(localized: .widgetLeft))"
  }

  /// "3 days ago".
  internal static func daysAgo(_ days: Int) -> String {
    let unit = String(localized: days == 1 ? .widgetDay : .widgetDays)
    return "\(days) \(unit) \(String(localized: .widgetAgo))"
  }

  /// Joins the non-empty parts with commas, so VoiceOver pauses between them.
  internal static func join(_ parts: [String?]) -> String {
    parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
  }

  /// The summary shared by the shift widget and the friend shift widget.
  internal static func shiftSummary(
    _ entry: some ShiftTimelineEntry,
    shiftDate: String,
    startTime: String,
    endTime: String,
    earnings: String?
  ) -> String {
    guard entry.hasShift, entry.layoutState != .empty else {
      return String(localized: .widgetNoShifts)
    }

    let times = timeRange(startTime, endTime)
    switch entry.layoutState {
    case .countdown:
      return join([daysLeft(abs(entry.daysRemaining)), shiftDate, times, earnings])

    case .pastShift:
      return join([daysAgo(abs(entry.daysRemaining)), times, earnings])

    default:
      let state: String? =
        entry.shiftHasEnded
        ? String(localized: .widgetDoneCapitalized)
        : (entry.shiftHasStarted ? String(localized: .widgetActive) : nil)
      return join([shiftDate, state, times, earnings])
    }
  }
}

extension ShiftWidgetEntry {
  internal var accessibilitySummary: String {
    WidgetAccessibility.shiftSummary(
      self, shiftDate: shiftDate, startTime: startTime, endTime: endTime, earnings: netEarnings)
  }

  /// The short summary for the circular lock screen widget, which shows a number and a small label.
  internal var circularAccessibilityLabel: String {
    guard hasShift else { return String(localized: .widgetNoShifts) }
    switch layoutState {
    case .countdown:
      return WidgetAccessibility.daysLeft(abs(daysRemaining))

    case .pastShift:
      return WidgetAccessibility.daysAgo(abs(daysRemaining))

    default:
      if shiftHasEnded { return String(localized: .widgetDoneCapitalized) }
      if activeShiftEnd != nil { return "\(String(localized: .widgetEnds)) \(endTime)" }
      return WidgetAccessibility.join([
        shiftDate, String(localized: .widgetAccessibilityStartsAt(startTime)),
      ])
    }
  }
}
