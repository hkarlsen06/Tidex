import Foundation
import SwiftUI
import WidgetKit

// MARK: - Shift Calculator

/// Shared calculation logic for shift timing, progress, and display
struct ShiftCalculator {
  let shift: WatchShiftDTO
  let calendar: Calendar

  /// Cached date formatter for parsing shift dates
  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current  // Use device timezone
    return formatter
  }()

  init(shift: WatchShiftDTO, calendar: Calendar = .current) {
    self.shift = shift
    self.calendar = calendar
  }

  // MARK: - Date Range Calculation

  /// Calculates the start and end dates for the shift
  /// - Returns: Tuple of (start, end) dates, or nil if parsing fails
  func dateRange() -> (start: Date, end: Date)? {
    guard let shiftDate = Self.dateFormatter.date(from: shift.shiftDate) else {
      return nil
    }

    // Parse start time
    let startParts = shift.startTime.split(separator: ":").compactMap { Int($0) }
    guard startParts.count >= 2 else { return nil }

    var startComponents = calendar.dateComponents([.year, .month, .day], from: shiftDate)
    startComponents.hour = startParts[0]
    startComponents.minute = startParts[1]
    startComponents.second = 0

    guard let shiftStart = calendar.date(from: startComponents) else {
      return nil
    }

    // Parse end time
    let endParts = shift.endTime.split(separator: ":").compactMap { Int($0) }
    guard endParts.count >= 2 else { return nil }

    var endComponents = calendar.dateComponents([.year, .month, .day], from: shiftDate)
    endComponents.hour = endParts[0]
    endComponents.minute = endParts[1]
    endComponents.second = 0

    guard let baseEndDate = calendar.date(from: endComponents) else {
      return nil
    }

    // Handle cross-midnight shifts
    var shiftEnd = baseEndDate
    if baseEndDate <= shiftStart {
      // Shift crosses midnight - add 1 day
      guard let nextDayEnd = calendar.date(byAdding: .day, value: 1, to: baseEndDate) else {
        return nil
      }
      shiftEnd = nextDayEnd
    }

    return (start: shiftStart, end: shiftEnd)
  }

  // MARK: - Progress Calculation

  /// Calculates shift progress at a given date
  /// - Parameter date: The reference date
  /// - Returns: Progress from 0.0 to 1.0, or nil if shift hasn't started or calculation fails
  func progress(at date: Date) -> Double? {
    guard let range = dateRange() else { return nil }

    // Not started yet
    guard date >= range.start else { return nil }

    let totalDuration = range.end.timeIntervalSince(range.start)
    guard totalDuration > 0 else { return nil }

    let elapsed = date.timeIntervalSince(range.start)
    let progress = elapsed / totalDuration

    return min(1.0, max(0.0, progress))
  }

  /// Checks if the shift is currently active at the given date
  func isActive(at date: Date) -> Bool {
    guard let range = dateRange() else { return false }
    return date >= range.start && date < range.end
  }

  // MARK: - Display Text Calculation

  /// Determines what text to highlight for the shift at a given date
  /// - Parameter date: The reference date
  /// - Returns: Time string or days remaining text
  func highlightedText(at date: Date) -> String {
    guard let range = dateRange() else {
      return shift.startTime
    }

    // Active shift - show end time
    if date >= range.start && date < range.end {
      return shift.endTime
    }

    // Future shift - calculate days remaining
    guard let shiftDate = Self.dateFormatter.date(from: shift.shiftDate) else {
      return shift.startTime
    }

    let todayMidnight = calendar.startOfDay(for: date)
    let shiftMidnight = calendar.startOfDay(for: shiftDate)
    let daysRemaining =
      calendar.dateComponents([.day], from: todayMidnight, to: shiftMidnight).day ?? 0

    // Show "X days" if more than 1 day away
    if daysRemaining > 1 {
      let dayLabel =
        daysRemaining == 1
        ? String(localized: "watch.day")
        : String(localized: "watch.days")
      return "\(daysRemaining) \(dayLabel)"
    }

    // Tomorrow or today - show start time
    return shift.startTime
  }

  // MARK: - Timeline Refresh Calculation

  /// Determines when the complication should next refresh
  /// - Parameter date: Current date
  /// - Returns: Next refresh date
  func nextRefreshDate(after date: Date) -> Date {
    // Default fallback - 15 minutes
    let defaultInterval: TimeInterval = 15 * 60
    guard let fallbackDate = calendar.date(byAdding: .second, value: Int(defaultInterval), to: date)
    else {
      return date.addingTimeInterval(defaultInterval)
    }

    guard let range = dateRange() else {
      return fallbackDate
    }

    // Before shift starts - refresh when shift starts (or default interval, whichever is sooner)
    if date < range.start {
      return range.start < fallbackDate ? range.start : fallbackDate
    }

    // During shift - refresh every minute for progress updates
    if date < range.end {
      guard let oneMinuteLater = calendar.date(byAdding: .minute, value: 1, to: date) else {
        return date.addingTimeInterval(60)
      }
      // Don't go past shift end
      return oneMinuteLater < range.end ? oneMinuteLater : range.end
    }

    // After shift ends - use default interval
    return fallbackDate
  }
}

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
  private let appGroupId = "group.no.tidex.app"
  private let payloadStorageKey = "watch_data_payload_v1"

  func placeholder(in context: Context) -> ShiftComplicationEntry {
    .placeholder
  }

  func getSnapshot(in context: Context, completion: @escaping (ShiftComplicationEntry) -> Void) {
    Task { @MainActor in
      let entry = ShiftComplicationEntry(
        date: Date(),
        shift: currentUserShift()
      )
      completion(entry)
    }
  }

  func getTimeline(
    in context: Context, completion: @escaping (Timeline<ShiftComplicationEntry>) -> Void
  ) {
    Task { @MainActor in
      let now = Date()
      let shift = currentUserShift()
      let entries = timelineEntries(now: now, shift: shift)

      let nextUpdate: Date
      if let shift {
        let calculator = ShiftCalculator(shift: shift)
        nextUpdate = calculator.nextRefreshDate(after: now)
      } else {
        // No shift - refresh in 15 minutes
        nextUpdate =
          Calendar.current.date(byAdding: .minute, value: 15, to: now)
          ?? now.addingTimeInterval(15 * 60)
      }

      let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
      completion(timeline)
    }
  }

  private func currentUserShift() -> WatchShiftDTO? {
    return persistedPayload()?.userShift
  }

  private func persistedPayload() -> WatchDataPayload? {
    guard let userDefaults = UserDefaults(suiteName: appGroupId),
      let data = userDefaults.data(forKey: payloadStorageKey),
      let payload = try? JSONDecoder().decode(WatchDataPayload.self, from: data)
    else {
      return nil
    }
    return payload
  }

  /// Build timeline entries at important boundaries to avoid stale countdown/state transitions.
  /// The system can still delay reloads, so we pre-seed start/end timestamps when possible.
  private func timelineEntries(now: Date, shift: WatchShiftDTO?) -> [ShiftComplicationEntry] {
    var entries: [ShiftComplicationEntry] = [
      ShiftComplicationEntry(date: now, shift: shift)
    ]

    guard let shift else { return entries }

    let calculator = ShiftCalculator(shift: shift)
    guard let range = calculator.dateRange() else { return entries }

    if range.start > now {
      entries.append(ShiftComplicationEntry(date: range.start, shift: shift))
    }

    if range.end > now {
      entries.append(ShiftComplicationEntry(date: range.end, shift: shift))
    }

    // Seed near-term minute checkpoints to keep active/soon-starting countdowns responsive.
    // This reduces visible "hangs" when the provider isn't invoked exactly on schedule.
    let secondsUntilStart = range.start.timeIntervalSince(now)
    let shouldSeedMinuteEntries = range.start <= now || secondsUntilStart <= 90 * 60

    if shouldSeedMinuteEntries {
      let calendar = Calendar.current
      let minuteHorizon = now.addingTimeInterval(120 * 60)
      let checkpointEnd = range.end < minuteHorizon ? range.end : minuteHorizon
      var cursor = calendar.date(byAdding: .minute, value: 1, to: now) ?? checkpointEnd

      while cursor < checkpointEnd {
        entries.append(ShiftComplicationEntry(date: cursor, shift: shift))
        guard let next = calendar.date(byAdding: .minute, value: 1, to: cursor) else { break }
        cursor = next
      }
    }

    // Keep strictly increasing dates; WidgetKit expects ordered entries.
    entries.sort { $0.date < $1.date }
    var deduped: [ShiftComplicationEntry] = []
    deduped.reserveCapacity(entries.count)
    var seenTimestamps = Set<TimeInterval>()

    for entry in entries {
      let secondTimestamp = floor(entry.date.timeIntervalSince1970)
      if seenTimestamps.insert(secondTimestamp).inserted {
        deduped.append(entry)
      }
    }

    return deduped
  }
}

// MARK: - Complication Views

struct ShiftComplicationView: View {
  @Environment(\.widgetFamily) var family
  let entry: ShiftComplicationEntry

  /// Use live wall-clock time during rendering to reduce stale UI when timeline refresh is delayed.
  private var renderDate: Date { Date() }

  /// Cached calculator for the current shift - computed once per render
  private var calculator: ShiftCalculator? {
    guard let shift = entry.shift else { return nil }
    return ShiftCalculator(shift: shift)
  }

  var body: some View {
    content
      .containerBackground(for: .widget) {
        Color.clear
      }
  }

  @ViewBuilder
  private var content: some View {
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

  @ViewBuilder
  private var accessoryCornerView: some View {
    if let shift = entry.shift,
      let calculator,
      let range = calculator.dateRange(),
      renderDate < range.end
    {
      Text(cornerTopCurvedText(shift: shift, range: range))
        .widgetCurvesContent()  // <- this makes it follow the corner curve
        .font(.caption2)
        .monospacedDigit()
        .widgetLabel {
          relativeCountdownText(range: range)
        }
    } else {
      Text("--")
        .widgetCurvesContent()
    }
  }

  // MARK: - Circular

  @ViewBuilder
  private var accessoryCircularView: some View {
    ZStack {
      AccessoryWidgetBackground()

      if let calculator = calculator,
        calculator.isActive(at: renderDate),
        let progress = calculator.progress(at: renderDate)
      {
        activeShiftRing(progress: progress)
      }

      if let shift = entry.shift, let calculator = calculator {
        VStack(spacing: 2) {
          Text(shortWeekdayText(for: shift))
            .font(.caption2)
            .foregroundStyle(.secondary)
          Text(calculator.highlightedText(at: renderDate))
            .font(.caption)
            .fontWeight(.semibold)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
        }
        .padding(4)
      } else {
        Image(systemName: "calendar.badge.clock")
      }
    }
  }

  // MARK: - Rectangular

  @ViewBuilder
  private var accessoryRectangularView: some View {
    if let shift = entry.shift,
      let calculator = calculator,
      let range = calculator.dateRange()
    {
      let isActive = calculator.isActive(at: renderDate)
      let progress = calculator.progress(at: renderDate) ?? 0

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Label(
            shift.status == .active ? activeTitle : nextShiftTitle,
            systemImage: statusIcon(for: shift.status)
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)

          Spacer(minLength: 4)

          Text(rectangularDayLabel(for: shift))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        HStack(spacing: 4) {
          Text("\(shift.startTime)-\(shift.endTime)")
            .font(.headline)
            .monospacedDigit()
            .widgetAccentable()
            .lineLimit(1)

          Spacer(minLength: 4)

          if isActive {
            Text("\(Int(progress * 100))%")
              .font(.caption2)
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
        }

        HStack(spacing: 6) {
          Image(systemName: isActive ? "hourglass.bottomhalf.filled" : "hourglass")
            .font(.caption2)
            .foregroundStyle(.secondary)

          relativeCountdownText(range: range)
            .font(.caption2)
            .lineLimit(1)

          if isActive {
            ProgressView(value: progress)
              .progressViewStyle(.linear)
              .frame(maxWidth: .infinity)
          }
        }
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
    if let calculator = calculator {
      Text("\(shiftLabel) \(calculator.highlightedText(at: renderDate))")
    } else {
      Text(noShiftsTitle)
    }
  }

  // MARK: - Helpers

  private func statusIcon(for status: ShiftPreviewStatus) -> String {
    switch status {
    case .active:
      return "play.fill"
    case .upcoming:
      return "calendar.badge.clock"
    case .past:
      return "checkmark.circle.fill"
    }
  }

  private func shortWeekdayText(for shift: WatchShiftDTO) -> String {
    let parser = DateFormatter()
    parser.dateFormat = "yyyy-MM-dd"
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = TimeZone.current

    guard let shiftDate = parser.date(from: shift.shiftDate) else {
      return "--"
    }

    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.setLocalizedDateFormatFromTemplate("EEE")
    return formatter.string(from: shiftDate).uppercased()
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

  private func rectangularDayLabel(for shift: WatchShiftDTO) -> String {
    let parser = DateFormatter()
    parser.dateFormat = "yyyy-MM-dd"
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = TimeZone.current

    guard let shiftDate = parser.date(from: shift.shiftDate) else {
      return shortWeekdayText(for: shift)
    }

    let calendar = Calendar.current
    let nowStart = calendar.startOfDay(for: renderDate)
    let shiftStart = calendar.startOfDay(for: shiftDate)
    let dayDiff = calendar.dateComponents([.day], from: nowStart, to: shiftStart).day ?? 0

    if dayDiff == 1 {
      return String(localized: .watchTomorrow)
    }
    if dayDiff == -1 {
      return String(localized: .watchYesterday)
    }
    return shortWeekdayText(for: shift)
  }

  private func countdownTargetDate(for range: (start: Date, end: Date)) -> Date? {
    if renderDate < range.start {
      return range.start
    }
    if renderDate < range.end {
      return range.end
    }
    return nil
  }

  @ViewBuilder
  private func relativeCountdownText(range: (start: Date, end: Date)) -> some View {
    if let targetDate = countdownTargetDate(for: range) {
      Text(targetDate, style: .timer)
        .monospacedDigit()
    } else {
      Text("--")
        .monospacedDigit()
    }
  }

  private func activeShiftRing(progress: Double) -> some View {
    GeometryReader { geometry in
      let size = min(geometry.size.width, geometry.size.height)
      let lineWidth: CGFloat = max(3, size * 0.08)  // Adaptive line width

      ZStack {
        Circle()
          .stroke(.secondary.opacity(0.2), lineWidth: lineWidth)

        Circle()
          .trim(from: 0.0, to: min(1.0, max(0.0, progress)))  // Clamp progress
          .stroke(
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
          )
          .rotationEffect(.degrees(-90))
          .foregroundStyle(Color.accentColor)
          .widgetAccentable()
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .offset(y: -1)
  }

  private func cornerTopCurvedText(shift: WatchShiftDTO, range: (start: Date, end: Date)) -> String
  {
    return renderDate < range.start ? shift.startTime : shift.endTime
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
      .accessoryInline,
    ])
  }

}

// MARK: - Preview

#Preview(as: .accessoryRectangular) {
  TidexShiftComplication()
} timeline: {
  ShiftComplicationEntry.placeholder
}
