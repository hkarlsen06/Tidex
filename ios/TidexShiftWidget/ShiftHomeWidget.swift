// swiftlint:disable file_length function_body_length
// Widget files require multiple size-specific views that cannot be easily split
import SwiftUI
import WidgetKit

// MARK: - Logo Watermark View

/// Uses the same generated artwork as the app, with a template for tinted widgets.
private struct LogoWatermark: View {
  var useTint: Bool = false

  var body: some View {
    Image("TidexLogo")
      .renderingMode(useTint ? .template : .original)
      .resizable()
      .scaledToFit()
      .foregroundStyle(Color.primary.opacity(0.6))
      .accessibilityHidden(true)
  }
}

// MARK: - Widget View

internal struct ShiftHomeWidgetView: View {
  internal let entry: ShiftWidgetEntry
  @Environment(\.widgetRenderingMode) internal var renderingMode: WidgetRenderingMode

  /// Localized "days" label
  private var daysLabel: String {
    String(localized: .widgetDays)
  }

  /// Localized "left" label
  private var leftLabel: String {
    String(localized: .widgetLeft)
  }

  /// Primary time (large) - start time before shift, end time after shift starts
  private var primaryTime: String {
    entry.shiftHasStarted ? entry.endTime : entry.startTime
  }

  /// Secondary time (small) - end time before shift, start time after shift starts
  private var secondaryTime: String {
    entry.shiftHasStarted ? entry.startTime : entry.endTime
  }

  // MARK: - Adaptive Colors for iOS 18 Themes

  /// Background color adapts to rendering mode
  /// - fullColor: Dark theme background
  /// - accented: Clear to show wallpaper with tint
  /// - vibrant: Semi-transparent for lock screen
  private var backgroundColor: Color {
    switch renderingMode {
    case .accented:
      return .clear

    case .vibrant:
      return Color.black.opacity(0.4)

    default:
      return WidgetPalette.background
    }
  }

  /// Primary text color (large time, countdown number)
  private var primaryTextColor: Color {
    switch renderingMode {
    case .accented, .vibrant:
      return .primary

    default:
      return WidgetPalette.textPrimary
    }
  }

  /// Secondary text color (earnings, secondary time, time range)
  private var secondaryTextColor: Color {
    switch renderingMode {
    case .accented, .vibrant:
      return .secondary

    default:
      return WidgetPalette.textSecondary
    }
  }

  /// Accent color for branded elements (date, salute) - these get marked as accentable
  private var accentColor: Color {
    switch renderingMode {
    case .accented:
      return .primary  // Will receive user's tint via widgetAccentable

    default:
      return WidgetPalette.blue
    }
  }

  /// Muted text color for empty/placeholder states
  private var mutedTextColor: Color {
    switch renderingMode {
    case .accented, .vibrant:
      return .secondary

    default:
      return WidgetPalette.textMuted
    }
  }

  /// Color for start time based on shift state
  private var startTimeColor: Color {
    if entry.shiftHasStarted {
      return secondaryTextColor
    }
    return entry.hasShift ? primaryTextColor : mutedTextColor
  }

  /// Color for end time based on shift state
  private var endTimeColor: Color {
    if entry.shiftHasStarted {
      return entry.hasShift ? primaryTextColor : mutedTextColor
    }
    return secondaryTextColor
  }

  /// Whether to use tinted monochrome logo (for accented/vibrant modes)
  private var useTintedLogo: Bool {
    renderingMode != .fullColor
  }

  internal var body: some View {
    ZStack {
      // Adaptive background
      backgroundColor

      // Content - switches based on layout state
      switch entry.layoutState {
      case .countdown:
        countdownLayout

      case .pastShift, .todayOrTomorrow:
        // Past shifts use the same layout as today/tomorrow
        todayTomorrowLayout

      case .empty:
        emptyStateLayout
      }
    }
  }

  // MARK: - Empty State Layout

  /// Minimal empty state with just logo and simple message
  private var emptyStateLayout: some View {
    VStack(spacing: 12) {
      // Logo watermark - larger and centered
      LogoWatermark(useTint: useTintedLogo)
        .frame(width: 48, height: 48)

      // Simple "No shifts" message
      Text(.widgetNoShifts)
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(mutedTextColor)
    }
  }

  // MARK: - State A: Today/Tomorrow/Past Layout

  /// Layout for today, tomorrow, or past shifts with time block and salute
  private var todayTomorrowLayout: some View {
    // All content in one width-matched centered group
    VStack(spacing: 0) {
      // TOP: Header row
      topHeaderRow

      Spacer()

      // MIDDLE: Times
      timeBlockView

      Spacer()

      // BOTTOM: Salute or time range
      bottomTextView
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 14)
  }

  /// Top header row: Date and Earnings centered
  private var topHeaderRow: some View {
    Group {
      if let countdownTarget = entry.upcomingStartToday {
        // Timer countdown to shift start + earnings
        Text("\(countdownTarget, style: .timer)  \(entry.netEarnings)")
          .font(.system(size: 15, weight: .semibold))
          .monospacedDigit()
          .foregroundColor(accentColor)
          .multilineTextAlignment(.center)
          .widgetAccentable()
          .lineLimit(1)
      } else if let shiftEnd = entry.activeShiftEnd {
        // Timer countdown to shift end + earnings
        Text("\(shiftEnd, style: .timer)  \(entry.netEarnings)")
          .font(.system(size: 15, weight: .semibold))
          .monospacedDigit()
          .foregroundColor(accentColor)
          .multilineTextAlignment(.center)
          .widgetAccentable()
          .lineLimit(1)
      } else {
        HStack(spacing: 6) {
          Text(entry.shiftDate)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(entry.hasShift ? accentColor : mutedTextColor)
            .widgetAccentable(entry.hasShift)
            .lineLimit(1)

          Text(entry.netEarnings)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(secondaryTextColor)
            .lineLimit(1)
        }
      }
    }
  }

  /// Bottom text: shows time range for past/ended shifts, salute for active shifts
  private var bottomTextView: some View {
    Group {
      if entry.layoutState == .pastShift || entry.shiftHasEnded {
        // Show time range instead of salute for past/ended shifts
        Text("\(entry.startTime) – \(entry.endTime)")
          .font(.system(size: 14, weight: .medium, design: .default))
          .foregroundColor(secondaryTextColor)
          .lineLimit(1)
      } else {
        // Show motivational salute for active/upcoming shifts
        // Allow wrapping to 2 lines for long salutes
        Text(entry.salute)
          .font(.system(size: 15, weight: .bold, design: .default))
          .italic()
          .foregroundColor(entry.hasShift ? accentColor : mutedTextColor)
          .widgetAccentable(entry.hasShift)
          .lineLimit(2)
          .multilineTextAlignment(.center)
          .minimumScaleFactor(0.8)
      }
    }
  }

  /// Time block: start and end times in equal sizes
  /// Primary time (start before shift, end after shift starts) is emphasized via weight/color
  /// After shift ends today: "Ferdig" / "Done"
  /// Past shift (previous day): "X dager siden" countdown
  private var timeBlockView: some View {
    VStack(spacing: -6) {
      if entry.layoutState == .pastShift {
        // Past shift from previous day - show days ago countdown
        pastShiftCountupView
      } else if entry.shiftHasEnded {
        // Shift ended today - show "Done"
        Text(.widgetDoneCapitalized)
          .font(.system(size: 36, weight: .bold, design: .default))
          .foregroundColor(entry.hasShift ? primaryTextColor : mutedTextColor)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      } else {
        // Start time - emphasized when shift hasn't started
        Text(entry.startTime)
          .font(
            .system(size: 32, weight: entry.shiftHasStarted ? .medium : .bold, design: .default)
          )
          .monospacedDigit()
          .foregroundColor(startTimeColor)
          .lineLimit(1)

        // End time - emphasized after shift starts
        Text(entry.endTime)
          .font(
            .system(size: 32, weight: entry.shiftHasStarted ? .bold : .medium, design: .default)
          )
          .monospacedDigit()
          .foregroundColor(endTimeColor)
          .lineLimit(1)
      }
    }
  }

  /// Past shift countup view - shows "X days ago"
  private var pastShiftCountupView: some View {
    let daysAgo = abs(entry.daysRemaining)
    let daysText = daysAgo == 1 ? String(localized: .widgetDay) : String(localized: .widgetDays)
    let agoText = String(localized: .widgetAgo)

    return HStack(alignment: .center, spacing: 4) {
      Text("\(daysAgo)")
        .font(.system(size: 72, weight: .bold, design: .default))
        .monospacedDigit()
        .foregroundColor(entry.hasShift ? primaryTextColor : mutedTextColor)
        .lineLimit(1)
        .minimumScaleFactor(0.5)

      VStack(alignment: .leading, spacing: -4) {
        Text(daysText)
          .font(.system(size: 24, weight: .semibold, design: .default))
          .foregroundColor(entry.hasShift ? primaryTextColor : mutedTextColor)
          .lineLimit(1)

        Text(agoText)
          .font(.system(size: 24, weight: .semibold, design: .default))
          .foregroundColor(entry.hasShift ? primaryTextColor : mutedTextColor)
          .lineLimit(1)
      }
    }
  }

  // MARK: - State B: Countdown Layout

  /// Layout for shifts more than 1 day away
  private var countdownLayout: some View {
    // All content in one width-matched centered group
    VStack(spacing: 0) {
      // TOP: Header row
      topHeaderRow

      Spacer()

      // MIDDLE: Countdown hero
      countdownHeroView

      Spacer()

      // BOTTOM: Time range
      Text("\(entry.startTime) – \(entry.endTime)")
        .font(.system(size: 14, weight: .medium, design: .default))
        .foregroundColor(secondaryTextColor)
        .lineLimit(1)
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 14)
  }

  /// Countdown hero view: large number on left, two stacked lines on right
  /// The number and labels are horizontally centered as a group
  private var countdownHeroView: some View {
    HStack(alignment: .center, spacing: 4) {
      // Large countdown number
      Text("\(entry.daysRemaining)")
        .font(.system(size: 72, weight: .bold, design: .default))
        .monospacedDigit()
        .foregroundColor(primaryTextColor)
        .lineLimit(1)
        .minimumScaleFactor(0.5)

      // Two stacked text lines: "days" / "dager" on top, "left" / "igjen" on bottom
      VStack(alignment: .leading, spacing: -4) {
        Text(daysLabel)
          .font(.system(size: 24, weight: .semibold, design: .default))
          .foregroundColor(primaryTextColor)
          .lineLimit(1)

        Text(leftLabel)
          .font(.system(size: 24, weight: .semibold, design: .default))
          .foregroundColor(primaryTextColor)
          .lineLimit(1)
      }
    }
  }
}

// MARK: - Widget Currency Formatter

/// Currency formatting for widgets - mirrors CurrencyConfig from the main app
/// Handles prefix vs suffix display based on currency symbol
internal enum WidgetCurrencyFormatter {
  /// Currency display position
  internal enum Display {
    case prefix  // Symbol before amount (e.g., "$100")
    case suffix  // Symbol after amount (e.g., "100 kr")
  }

  /// Get display position for a currency symbol
  internal static func display(for currency: String) -> Display {
    switch currency {
    // Suffix currencies
    case "kr", "zł", "Kč", "₽":
      return .suffix

    // Prefix currencies (default)
    default:
      return .prefix
    }
  }

  /// Format an amount with currency symbol
  internal static func format(_ amount: Double, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0
    formatter.groupingSeparator = " "

    let formatted = formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"

    switch display(for: currency) {
    case .prefix:
      return "\(currency)\(formatted)"

    case .suffix:
      return "\(formatted) \(currency)"
    }
  }

  /// Format empty/placeholder with currency symbol (e.g., "--- kr" or "$---")
  internal static func formatEmpty(currency: String) -> String {
    switch display(for: currency) {
    case .prefix:
      return "\(currency)---"

    case .suffix:
      return "--- \(currency)"
    }
  }

  /// Format an amount in compact form for stats (e.g., "1.5k", "15k")
  internal static func formatCompact(_ amount: Double, currency: String) -> String {
    let absAmount = abs(amount)
    let formatted: String

    let compactThreshold: Double = 1_000.0
    if absAmount >= compactThreshold {
      // Format as "Xk" or "X.Xk"
      let thousands: Double = amount / compactThreshold
      if thousands.truncatingRemainder(dividingBy: 1) == 0 {
        formatted = "\(Int(thousands))k"
      } else {
        formatted = String(format: "%.1fk", thousands)
      }
    } else {
      // Format as whole number
      formatted = "\(Int(amount))"
    }

    switch display(for: currency) {
    case .prefix:
      return "\(currency)\(formatted)"

    case .suffix:
      return "\(formatted) \(currency)"
    }
  }
}

// MARK: - Widget Provider

internal struct ShiftWidgetProvider: TimelineProvider {
  private let helper: ShiftWidgetProviderHelper = .init()

  internal func placeholder(in _: Context) -> ShiftWidgetEntry {
    ShiftWidgetEntry.placeholder()
  }

  internal func getSnapshot(in _: Context, completion: (ShiftWidgetEntry) -> Void) {
    completion(ShiftWidgetEntry.placeholder())
  }

  internal func getTimeline(in _: Context, completion: (Timeline<ShiftWidgetEntry>) -> Void) {
    let now = Date()
    let calendar = Calendar.current
    let entry: ShiftWidgetEntry = helper.createEntry(at: now)

    // Refresh at next midnight to pick up day transitions and new shift data
    let tomorrow = calendar.startOfDay(
      for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)

    // Add an entry at every shift start and end before the refresh, including a second
    // shift on the same day, so the widget never shows a stale countdown.
    let entries =
      [entry]
      + helper.transitionDates(after: now, before: tomorrow).map { helper.createEntry(at: $0) }
    let timeline = Timeline(entries: entries, policy: .after(tomorrow))
    completion(timeline)
  }

}

// MARK: - Provider Helpers

internal struct ShiftWidgetProviderHelper {
  /// Get the user's stored currency symbol, or nil if not set
  private func getStoredCurrency() -> String? {
    WidgetAppGroup.sharedUserDefaults()?.string(forKey: WidgetAppGroup.currencyKey)
  }

  /// Build a local Date from shift day + HH:mm, supporting 24:00 as next-day midnight.
  internal func shiftDateTime(shiftDateString: String, time: String) -> Date? {
    guard let shiftDate = parseShiftDate(shiftDateString) else {
      return nil
    }

    let timeComponents = time.split(separator: ":").compactMap { Int($0) }
    guard timeComponents.count >= 2 else {
      return nil
    }

    let rawHour = timeComponents[0]
    let minute = timeComponents[1]
    let hour = rawHour == 24 ? 0 : rawHour

    let calendar = Calendar.current
    var components = calendar.dateComponents([.year, .month, .day], from: shiftDate)
    components.hour = hour
    components.minute = minute
    components.second = 0

    guard var date = calendar.date(from: components) else {
      return nil
    }
    if rawHour == 24 {
      date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
    }

    return date
  }

  internal func shiftInterval(shiftDateString: String, startTime: String, endTime: String) -> (
    start: Date, end: Date
  )? {
    guard let start = shiftDateTime(shiftDateString: shiftDateString, time: startTime),
      var end = shiftDateTime(shiftDateString: shiftDateString, time: endTime)
    else {
      return nil
    }

    if end <= start {
      end = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
    }

    return (start, end)
  }

  /// Count midnight boundaries crossed between two dates (matching the web app's pattern)
  /// Users perceive "1 day" as "tomorrow", not "24 hours from now"
  internal func countMidnightCrossings(from startDate: Date, to endDate: Date) -> Int {
    let calendar = Calendar.current
    let fromMidnight = calendar.startOfDay(for: startDate)
    let toMidnight = calendar.startOfDay(for: endDate)

    let components = calendar.dateComponents([.day], from: fromMidnight, to: toMidnight)
    return abs(components.day ?? 0)
  }

  /// Determine if the shift has already started by comparing the given time to shift start
  /// Returns true if `now` is at or past the shift's start time on the shift date
  internal func hasShiftStarted(shiftDateString: String, startTime: String, at now: Date) -> Bool {
    guard let shiftStartDateTime = shiftDateTime(shiftDateString: shiftDateString, time: startTime)
    else {
      return false
    }

    return now >= shiftStartDateTime
  }

  /// Determine if the shift has already ended by comparing the given time to shift end
  /// Returns true ONLY if the shift end time is today (relative to `now`) and we're past it
  /// For past day shifts, returns false (those use pastShift layout with countdown instead)
  /// Note: For cross-midnight shifts (end <= start), adds 1 day to end time
  internal func hasShiftEnded(
    shiftDateString: String, startTime: String, endTime: String, at now: Date
  ) -> Bool {
    guard
      let (_, shiftEndDateTime) = shiftInterval(
        shiftDateString: shiftDateString,
        startTime: startTime,
        endTime: endTime
      )
    else {
      return false
    }

    let calendar = Calendar.current
    guard now >= shiftEndDateTime else {
      return false
    }

    // Only treat as "ended" if the end time is today
    return calendar.isDate(shiftEndDateTime, inSameDayAs: now)
  }

  /// True while "now" is between start and end (supports cross-midnight).
  internal func isShiftActive(
    shiftDateString: String, startTime: String, endTime: String, at now: Date
  ) -> Bool {
    guard
      let interval = shiftInterval(
        shiftDateString: shiftDateString,
        startTime: startTime,
        endTime: endTime
      )
    else {
      return false
    }

    return now >= interval.start && now < interval.end
  }

  /// Determine the layout state based on midnight crossings
  /// - 0 crossings: today (State A)
  /// - 1 crossing: tomorrow (State A)
  /// - 2+ crossings: countdown (State B)
  /// - Negative crossings: past shift (State C)
  internal func determineLayoutState(shiftDateString: String, at now: Date = Date()) -> (
    state: WidgetLayoutState, daysRemaining: Int
  ) {
    guard let shiftDate = parseShiftDate(shiftDateString) else {
      return (.empty, 0)
    }

    let calendar = Calendar.current
    let todayMidnight = calendar.startOfDay(for: now)
    let shiftMidnight = calendar.startOfDay(for: shiftDate)

    // If shift is in the past, show it with pastShift layout
    if shiftMidnight < todayMidnight {
      let daysAgo = countMidnightCrossings(from: shiftDate, to: now)
      // Return negative daysRemaining to indicate past
      return (.pastShift, -daysAgo)
    }

    let daysRemaining = countMidnightCrossings(from: now, to: shiftDate)

    // State A: today (0) or tomorrow (1)
    // State B: more than 1 day away (2+)
    if daysRemaining <= 1 {
      return (.todayOrTomorrow, daysRemaining)
    }
    return (.countdown, daysRemaining)
  }

  private func loadShifts() -> [StoredShift] {
    guard let json = WidgetAppGroup.sharedUserDefaults()?.string(forKey: WidgetAppGroup.shiftsKey),
      let data = json.data(using: .utf8),
      let shifts = try? JSONDecoder().decode([StoredShift].self, from: data)
    else {
      return []
    }
    return shifts
  }

  /// Start and end instants of stored shifts inside (now, limit), sorted and unique.
  internal func transitionDates(after now: Date, before limit: Date) -> [Date] {
    let dates = loadShifts().compactMap { shift in
      shiftInterval(
        shiftDateString: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime)
    }.flatMap { [$0.start, $0.end] }
    return Set(dates.filter { $0 > now && $0 < limit }).sorted()
  }

  internal func createEntry(at now: Date) -> ShiftWidgetEntry {
    // Get stored currency (may be nil if never set)
    let storedCurrency = getStoredCurrency()

    let shifts = loadShifts()
    guard !shifts.isEmpty else {
      // No shifts - use stored currency if available
      return ShiftWidgetEntry.empty(currency: storedCurrency)
    }

    // Find the best shift to display
    guard let shift = findBestShift(from: shifts, at: now) else {
      return ShiftWidgetEntry.empty(currency: storedCurrency)
    }

    // Prefer shift's currency, then stored currency, then nil (no currency shown)
    let currencySymbol = shift.currencySymbol ?? storedCurrency
    let taxRate = shift.taxRate ?? 0.0

    // Calculate net earnings
    let netEarnings = shift.totalGrossEstimate * (1 - taxRate)
    // Format with currency if available, otherwise show just the number
    let formattedEarnings: String
    if let currency = currencySymbol {
      formattedEarnings = WidgetCurrencyFormatter.format(netEarnings, currency: currency)
    } else {
      // No currency known - just show the number
      let formatter = NumberFormatter()
      formatter.numberStyle = .decimal
      formatter.minimumFractionDigits = 0
      formatter.maximumFractionDigits = 0
      formatter.groupingSeparator = " "
      formattedEarnings =
        formatter.string(from: NSNumber(value: netEarnings)) ?? "\(Int(netEarnings))"
    }

    // Determine layout state using midnight-crossing logic
    var (layoutState, daysRemaining) = determineLayoutState(
      shiftDateString: shift.shiftDate,
      at: now
    )

    // Check if shift has already started (for time emphasis swap)
    let shiftStarted = hasShiftStarted(
      shiftDateString: shift.shiftDate, startTime: shift.startTime, at: now)

    // Check if shift has already ended (for showing "Ferdig" / "Done")
    let shiftEnded = hasShiftEnded(
      shiftDateString: shift.shiftDate,
      startTime: shift.startTime,
      endTime: shift.endTime,
      at: now
    )
    let shiftActive = isShiftActive(
      shiftDateString: shift.shiftDate,
      startTime: shift.startTime,
      endTime: shift.endTime,
      at: now
    )

    // Adjust layout state for active/ended shifts
    // Preserve pastShift layout for past shifts - they should show "X days ago"
    if shiftActive {
      layoutState = .todayOrTomorrow
      daysRemaining = 0
    } else if layoutState != .pastShift, shiftStarted || shiftEnded {
      layoutState = .todayOrTomorrow
    }

    // Format date (pass daysRemaining for past shift formatting)
    let formattedDate: String = formatShiftDate(
      shift.shiftDate,
      daysRemaining: daysRemaining,
      parseDate: parseShiftDate
    )

    // Get random salute
    let salute = MotivationalSalutes.random()

    // Build deep link URL to navigate to /shifts and highlight the shift date in calendar
    // Format: tidex://shifts?dates=2025-01-15&action=highlight
    // Using action=highlight so tapping the widget only highlights the shift in the calendar
    // (as opposed to action=open which opens the shift details sheet - used by notifications)
    let deepLinkURL = URL(string: "tidex://shifts?dates=\(shift.shiftDate)&action=highlight")
    let interval = shiftInterval(
      shiftDateString: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime)

    return ShiftWidgetEntry(
      date: now,
      shiftDate: formattedDate,
      startTime: shift.startTime,
      endTime: shift.endTime,
      netEarnings: formattedEarnings,
      salute: salute,
      hasShift: true,
      daysRemaining: daysRemaining,
      layoutState: layoutState,
      shiftHasStarted: shiftStarted,
      shiftHasEnded: shiftEnded,
      deepLinkURL: deepLinkURL,
      shiftStart: interval?.start,
      shiftEnd: interval?.end
    )
  }

  /// Find the best shift to display:
  /// 1. Next upcoming shift (today or future)
  /// 2. Most recent past shift if no future shifts
  private func findBestShift(from shifts: [StoredShift], at now: Date) -> StoredShift? {
    let intervals = shifts.compactMap { shift -> (shift: StoredShift, start: Date, end: Date)? in
      guard
        let interval = shiftInterval(
          shiftDateString: shift.shiftDate,
          startTime: shift.startTime,
          endTime: shift.endTime
        )
      else {
        return nil
      }

      return (shift, interval.start, interval.end)
    }

    if let active =
      intervals
      .filter({ now >= $0.start && now < $0.end })
      .min(by: { $0.end < $1.end })
    {
      return active.shift
    }

    if let upcoming =
      intervals
      .filter({ $0.start > now })
      .min(by: { $0.start < $1.start })
    {
      return upcoming.shift
    }

    if let past =
      intervals
      .filter({ $0.end <= now })
      .max(by: { $0.end < $1.end })
    {
      return past.shift
    }

    // Fallback for unparseable rows: preserve previous date-based behavior.
    let sortedShifts = shifts.sorted { lhs, rhs in
      guard let dateA = parseShiftDate(lhs.shiftDate),
        let dateB = parseShiftDate(rhs.shiftDate)
      else { return false }
      return dateA < dateB
    }
    return sortedShifts.last
  }

}

// MARK: - App Locale Helper

private func formatShiftDate(
  _ dateString: String,
  daysRemaining: Int,
  parseDate: (String) -> Date?
) -> String {
  guard let shiftDate = parseDate(dateString) else {
    return dateString
  }

  let calendar: Calendar = .current
  let today: Date = calendar.startOfDay(for: Date())
  let shiftDay: Date = calendar.startOfDay(for: shiftDate)

  if daysRemaining < 0 {
    let daysAgo: Int = abs(daysRemaining)
    if daysAgo == 1 {
      return String(localized: .widgetYesterday)
    }
    return formattedWeekday(shiftDate, style: .abbreviatedDay)
  }

  if calendar.isDate(shiftDay, inSameDayAs: today) {
    return String(localized: .widgetToday)
  }

  if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
    calendar.isDate(shiftDay, inSameDayAs: tomorrow)
  {
    return String(localized: .widgetTomorrow)
  }

  return formattedWeekday(shiftDate, style: .abbreviatedDay)
}

// MARK: - Widget Date Formatting Helpers
//
// Shared by ShiftHomeWidget, FriendShiftWidget and FriendsWidget so shift dates parse and
// display the same way across all three.

/// Locale Tidex actually ships strings in, so widget dates match the app's language even
/// when the system locale isn't one Tidex supports.
internal func appLocale() -> Locale {
  let identifier = Bundle.main.preferredLocalizations.first ?? Locale.autoupdatingCurrent.identifier
  return Locale(identifier: identifier)
}

/// Parses a "yyyy-MM-dd" shift date in the device's local time zone.
internal func parseShiftDate(_ dateString: String) -> Date? {
  let strategy = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
  return try? Date(dateString, strategy: strategy)
}

/// Weekday label shapes used across the widget extension's shift date displays.
internal enum WidgetWeekdayStyle {
  /// e.g. "Mon 5"
  case abbreviatedDay
  /// e.g. "Monday"
  case fullWeekday
  /// e.g. "Mon 5 Oct"
  case abbreviatedDayMonth
}

/// Formats a weekday label for the app's locale, sentence-cased.
internal func formattedWeekday(_ date: Date, style: WidgetWeekdayStyle) -> String {
  var format: Date.FormatStyle
  switch style {
  case .abbreviatedDay:
    format = .dateTime.weekday(.abbreviated).day()
  case .fullWeekday:
    format = .dateTime.weekday(.wide)
  case .abbreviatedDayMonth:
    format = .dateTime.weekday(.abbreviated).day().month(.abbreviated)
  }
  format.locale = appLocale()
  format.capitalizationContext = .beginningOfSentence
  return date.formatted(format)
}

// MARK: - Widget Configuration

internal struct ShiftHomeWidget: Widget {
  internal let kind: String = "ShiftHomeWidget"

  internal var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ShiftWidgetProvider()) { entry in
      ShiftHomeWidgetView(entry: entry)
        .widgetURL(entry.deepLinkURL)
        .containerBackground(for: .widget) {
          // Background adapts to system appearance
          // Uses Color.primary with dynamic scheme to get system-appropriate background
          Color.clear  // Let the view handle its own background based on colorScheme
        }
    }
    .configurationDisplayName(String(localized: .widgetNameNextShift))
    .description(String(localized: .widgetDescNextShift))
    .supportedFamilies([.systemSmall])
    .contentMarginsDisabled()
  }
}

// MARK: - Preview

#if DEBUG
  #Preview(as: .systemSmall) {
    ShiftHomeWidget()
  } timeline: {
    // State A: Before shift starts (start time emphasized)
    ShiftWidgetEntry.placeholder()
    ShiftWidgetEntry.placeholder()
    // State A: After shift starts (end time emphasized)
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
      deepLinkURL: URL(string: "tidex://shifts?dates=2025-01-15&action=highlight")
    )
    // State A: After shift ends (shows "Ferdig")
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
      deepLinkURL: URL(string: "tidex://shifts?dates=2025-01-15&action=highlight")
    )
    // State B: Countdown layouts
    ShiftWidgetEntry(
      date: Date(),
      shiftDate: "Man. 20.",
      startTime: "16:00",
      endTime: "23:15",
      netEarnings: "1 332 kr",
      salute: "Du klarer det!",
      hasShift: true,
      daysRemaining: 5,
      layoutState: .countdown,
      shiftHasStarted: false,
      shiftHasEnded: false,
      deepLinkURL: URL(string: "tidex://shifts?dates=2025-01-20&action=highlight")
    )
    ShiftWidgetEntry(
      date: Date(),
      shiftDate: "Mon. 20.",
      startTime: "16:00",
      endTime: "23:15",
      netEarnings: "$234",
      salute: "You got this!",
      hasShift: true,
      daysRemaining: 12,
      layoutState: .countdown,
      shiftHasStarted: false,
      shiftHasEnded: false,
      deepLinkURL: URL(string: "tidex://shifts?dates=2025-01-20&action=highlight")
    )
    // State C: Past shift (days ago countup)
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
      deepLinkURL: URL(string: "tidex://shifts?dates=2025-01-09&action=highlight")
    )
    // Empty state
    ShiftWidgetEntry.empty()
  }
#endif
// swiftlint:enable file_length function_body_length
