import Foundation
import SwiftUI
import WidgetKit

// MARK: - Shift Calculator

/// Shared calculation logic for shift timing, progress, and display
struct ShiftCalculator {
  let shift: WatchShiftDTO
  let calendar: Calendar
  private let cachedDateRange: (start: Date, end: Date)?

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
    self.cachedDateRange = Self.makeDateRange(for: shift, calendar: calendar)
  }

  // MARK: - Date Range Calculation

  /// Calculates the start and end dates for the shift
  /// - Returns: Tuple of (start, end) dates, or nil if parsing fails
  func dateRange() -> (start: Date, end: Date)? {
    cachedDateRange
  }

  fileprivate static func parseShiftDate(_ dateString: String) -> Date? {
    dateFormatter.date(from: dateString)
  }

  private static func makeDateRange(
    for shift: WatchShiftDTO,
    calendar: Calendar
  ) -> (start: Date, end: Date)? {
    guard let shiftDate = parseShiftDate(shift.shiftDate) else {
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
    if date >= range.start, date < range.end {
      return shift.endTime
    }

    let todayMidnight = calendar.startOfDay(for: date)
    let shiftMidnight = calendar.startOfDay(for: range.start)
    let daysRemaining =
      calendar.dateComponents([.day], from: todayMidnight, to: shiftMidnight).day ?? 0

    // Show "X days" if more than 1 day away
    if daysRemaining > 1 {
      let dayLabel =
        daysRemaining == 1
        ? String(localized: .watchDay)
        : String(localized: .watchDays)
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

    // Before shift starts, refresh aggressively to reduce stale state at boundary.
    if date < range.start {
      let preStartInterval: TimeInterval = 5 * 60
      let preStartFallback =
        calendar.date(byAdding: .second, value: Int(preStartInterval), to: date)
        ?? date.addingTimeInterval(preStartInterval)
      return range.start < preStartFallback ? range.start : preStartFallback
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

  internal static var placeholder: Self {
    Self(
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

  internal func placeholder(in _: Context) -> ShiftComplicationEntry {
    .placeholder
  }

  internal func getSnapshot(in _: Context, completion: @escaping (ShiftComplicationEntry) -> Void) {
    Task { @MainActor in
      let entry = ShiftComplicationEntry(
        date: Date(),
        shift: currentUserShift()
      )
      completion(entry)
    }
  }

  func getTimeline(
    in _: Context, completion: @escaping (Timeline<ShiftComplicationEntry>) -> Void
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
    let calendar = Calendar.current

    // Seed extra entries around boundaries so we recover quickly if one boundary tick is delayed.
    let boundaryOffsetsInSeconds = [0, 5, 15, 30, 60]
    let boundaries = [range.start, range.end]
    for boundary in boundaries where boundary > now {
      for offset in boundaryOffsetsInSeconds {
        guard let checkpoint = calendar.date(byAdding: .second, value: offset, to: boundary),
          checkpoint > now
        else { continue }
        entries.append(ShiftComplicationEntry(date: checkpoint, shift: shift))
      }
    }

    // Seed minute checkpoints for active shifts and around upcoming shift start.
    // For far-future shifts, this places entries in a start window so transition logic
    // can still flip even if the provider isn't re-invoked exactly at the boundary.
    let checkpointWindowStart: Date
    if range.start > now {
      let preStartWindow =
        calendar.date(byAdding: .minute, value: -15, to: range.start) ?? range.start
      checkpointWindowStart = preStartWindow > now ? preStartWindow : now
    } else {
      checkpointWindowStart = now
    }

    let minuteHorizon: Date
    if range.start > now {
      minuteHorizon = calendar.date(byAdding: .minute, value: 120, to: range.start) ?? range.end
    } else {
      minuteHorizon = now.addingTimeInterval(120 * 60)
    }
    let checkpointEnd = range.end < minuteHorizon ? range.end : minuteHorizon

    if checkpointWindowStart < checkpointEnd {
      var cursor = nextMinuteBoundary(after: checkpointWindowStart, calendar: calendar)
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

  private func nextMinuteBoundary(after date: Date, calendar: Calendar) -> Date {
    let withSecondZero = calendar.date(bySetting: .second, value: 0, of: date) ?? date
    let aligned =
      calendar.date(bySetting: .nanosecond, value: 0, of: withSecondZero) ?? withSecondZero
    if aligned > date {
      return aligned
    }
    return calendar.date(byAdding: .minute, value: 1, to: aligned) ?? date.addingTimeInterval(60)
  }
}

// MARK: - Complication Views

struct ShiftComplicationView: View {
  @Environment(\.widgetFamily) var family
  let entry: ShiftComplicationEntry

  private enum ShiftDisplayState {
    case upcoming
    case active
    case ended
  }

  /// Use live wall-clock time during rendering to reduce stale UI when timeline refresh is delayed.
  private var renderDate: Date { Date() }

  private static let weekdayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.setLocalizedDateFormatFromTemplate("EEE")
    return formatter
  }()

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
    let now = renderDate
    let calculator = calculator
    if let shift = entry.shift,
      let calculator,
      let range = calculator.dateRange(),
      now < range.end
    {
      Text(cornerTopCurvedText(shift: shift, range: range, at: now))
        .widgetCurvesContent()  // <- this makes it follow the corner curve
        .font(.caption2)
        .monospacedDigit()
        .widgetLabel {
          relativeCountdownText(range: range, at: now)
        }
    } else {
      Text("--")
        .widgetCurvesContent()
    }
  }

  // MARK: - Circular

  @ViewBuilder
  private var accessoryCircularView: some View {
    let now = renderDate
    let calculator = calculator
    ZStack {
      AccessoryWidgetBackground()

      if let calculator,
        calculator.isActive(at: now),
        let progress = calculator.progress(at: now)
      {
        activeShiftRing(progress: progress)
      }

      if let shift = entry.shift, let calculator {
        VStack(spacing: 2) {
          Text(shortWeekdayText(for: shift))
            .font(.caption2)
            .foregroundStyle(.secondary)
          Text(calculator.highlightedText(at: now))
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
    let now = renderDate
    let calculator = calculator
    if let shift = entry.shift,
      let calculator,
      let range = calculator.dateRange()
    {
      let isActive = calculator.isActive(at: now)
      let progress = calculator.progress(at: now) ?? 0

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          let effectiveStatus = displayStatus(for: range, at: now)
          Label(
            effectiveStatus == .active ? activeTitle : nextShiftTitle,
            systemImage: statusIcon(for: effectiveStatus)
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)

          Spacer(minLength: 4)

          Text(rectangularDayLabel(for: shift, at: now))
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

          relativeCountdownText(range: range, at: now)
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
    let now = renderDate
    let calculator = calculator
    if let calculator {
      Text("\(shiftLabel) \(calculator.highlightedText(at: now))")
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
    guard let shiftDate = ShiftCalculator.parseShiftDate(shift.shiftDate) else {
      return "--"
    }

    return Self.weekdayFormatter.string(from: shiftDate).uppercased()
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

  private func rectangularDayLabel(for shift: WatchShiftDTO, at date: Date) -> String {
    guard let shiftDate = ShiftCalculator.parseShiftDate(shift.shiftDate) else {
      return shortWeekdayText(for: shift)
    }

    let calendar = Calendar.current
    let nowStart = calendar.startOfDay(for: date)
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

  @ViewBuilder
  private func relativeCountdownText(range: (start: Date, end: Date), at date: Date) -> some View {
    if let targetDate = countdownTargetDate(for: range, at: date) {
      // Match Live Activity timer rendering so the watch complication and mirrored
      // Live Activity advance on the same second boundary.
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

  private func cornerTopCurvedText(
    shift: WatchShiftDTO,
    range: (start: Date, end: Date),
    at date: Date
  ) -> String {
    switch displayState(for: range, at: date) {
    case .upcoming:
      return shift.startTime

    case .active, .ended:
      return shift.endTime
    }
  }

  private func displayState(
    for range: (start: Date, end: Date),
    at date: Date
  ) -> ShiftDisplayState {
    if date < range.start {
      return .upcoming
    }
    if date < range.end {
      return .active
    }
    return .ended
  }

  private func countdownTargetDate(for range: (start: Date, end: Date), at date: Date) -> Date? {
    switch displayState(for: range, at: date) {
    case .upcoming:
      return range.start

    case .active:
      return range.end

    case .ended:
      return nil
    }
  }

  private func displayStatus(
    for range: (start: Date, end: Date),
    at date: Date
  ) -> ShiftPreviewStatus {
    switch displayState(for: range, at: date) {
    case .upcoming:
      return .upcoming

    case .active:
      return .active

    case .ended:
      return .past
    }
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
