// swiftlint:disable file_length function_body_length
// Widget files require multiple size-specific views that cannot be easily split
import SwiftUI
import WidgetKit

// MARK: - Tidex Adaptive Colors for Widgets
//
// These colors adapt to iOS system appearance (light/dark mode).
// The widget respects user's system appearance preference for a native feel.

/// Tidex brand blue color - adapts to light/dark mode for optimal contrast
/// Light: HSL(221, 83%, 53%) - vibrant blue
/// Dark: HSL(217, 91%, 65%) - bright blue
private enum TidexWidgetColors {
  /// Light mode brand blue
  static let lightBlue = Color(hue: 221 / 360, saturation: 0.83, brightness: 0.53)
  /// Dark mode brand blue
  static let darkBlue = Color(red: 77 / 255, green: 137 / 255, blue: 249 / 255)

  /// Light mode background
  static let lightBackground = Color(hue: 220 / 360, saturation: 0.40, brightness: 0.98)
  /// Dark mode background
  static let darkBackground = Color(red: 10 / 255, green: 15 / 255, blue: 26 / 255)
}

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
  @Environment(\.colorScheme) internal var colorScheme: ColorScheme

  /// Whether we're in light mode
  private var isLightMode: Bool {
    colorScheme == .light
  }

  /// Adaptive brand blue color based on color scheme
  private var tidexBlue: Color {
    isLightMode ? TidexWidgetColors.lightBlue : TidexWidgetColors.darkBlue
  }

  /// Adaptive background color based on color scheme
  private var tidexDarkBackground: Color {
    isLightMode ? TidexWidgetColors.lightBackground : TidexWidgetColors.darkBackground
  }

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
      return tidexDarkBackground
    }
  }

  /// Primary text color (large time, countdown number)
  private var primaryTextColor: Color {
    switch renderingMode {
    case .accented, .vibrant:
      return .primary

    default:
      return .white
    }
  }

  /// Secondary text color (earnings, secondary time, time range)
  private var secondaryTextColor: Color {
    switch renderingMode {
    case .accented, .vibrant:
      return .secondary

    default:
      return .white.opacity(0.6)
    }
  }

  /// Accent color for branded elements (date, salute) - these get marked as accentable
  private var accentColor: Color {
    switch renderingMode {
    case .accented:
      return .primary  // Will receive user's tint via widgetAccentable

    default:
      return tidexBlue
    }
  }

  /// Muted text color for empty/placeholder states
  private var mutedTextColor: Color {
    switch renderingMode {
    case .accented, .vibrant:
      return .secondary

    default:
      return .white.opacity(0.4)
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

  /// Shift start timestamp for today's upcoming shifts (used for live countdown timer)
  private var todayShiftStartDateTime: Date? {
    guard entry.hasShift,
      entry.layoutState == .todayOrTomorrow,
      entry.daysRemaining == 0,
      !entry.shiftHasStarted,
      !entry.shiftHasEnded
    else {
      return nil
    }

    let timeComponents = entry.startTime.split(separator: ":").compactMap { Int($0) }
    guard timeComponents.count >= 2 else {
      return nil
    }

    let calendar = Calendar.current
    var components = calendar.dateComponents([.year, .month, .day], from: entry.date)
    components.hour = timeComponents[0]
    components.minute = timeComponents[1]
    components.second = 0

    return calendar.date(from: components)
  }

  /// Shift end timestamp for active shifts (used for live countdown to shift end)
  private var todayShiftEndDateTime: Date? {
    guard entry.hasShift,
      entry.layoutState == .todayOrTomorrow,
      entry.daysRemaining == 0,
      entry.shiftHasStarted,
      !entry.shiftHasEnded
    else {
      return nil
    }

    let calendar = Calendar.current
    let startComponents = entry.startTime.split(separator: ":").compactMap { Int($0) }
    let endComponents = entry.endTime.split(separator: ":").compactMap { Int($0) }
    guard startComponents.count >= 2, endComponents.count >= 2 else {
      return nil
    }

    var components = calendar.dateComponents([.year, .month, .day], from: entry.date)
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
      if let countdownTarget = todayShiftStartDateTime {
        // Timer countdown to shift start + earnings
        Text("\(countdownTarget, style: .timer)  \(entry.netEarnings)")
          .font(.system(size: 15, weight: .semibold))
          .monospacedDigit()
          .foregroundColor(accentColor)
          .multilineTextAlignment(.center)
          .widgetAccentable()
          .lineLimit(1)
      } else if let shiftEnd = todayShiftEndDateTime {
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

// MARK: - Stored Shift Model (matches App target)

/// Represents a shift stored in shared UserDefaults
/// Must match the structure from the main app
private struct StoredShift: Codable {
  let shiftId: String
  let shiftDate: String  // YYYY-MM-DD
  let startTime: String  // HH:mm
  let endTime: String  // HH:mm
  let hourlyWage: Double
  let supplementRatePerHour: Double
  let totalGrossEstimate: Double
  let currencySymbol: String?
  let taxRate: Double?
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

    var entries = [entry]

    // For today's shift, add transition entries at start/end times so the widget
    // updates exactly when the shift state changes (no stale countdown/timer).
    if entry.hasShift,
      entry.layoutState == .todayOrTomorrow,
      entry.daysRemaining == 0
    {
      let startComponents = entry.startTime.split(separator: ":").compactMap { Int($0) }
      let endComponents = entry.endTime.split(separator: ":").compactMap { Int($0) }

      // Transition entry at shift start
      if !entry.shiftHasStarted, startComponents.count >= 2 {
        var sc = calendar.dateComponents([.year, .month, .day], from: now)
        sc.hour = startComponents[0]
        sc.minute = startComponents[1]
        sc.second = 0
        if let shiftStart = calendar.date(from: sc), shiftStart > now {
          entries.append(helper.createEntry(at: shiftStart))
        }
      }

      // Transition entry at shift end
      if !entry.shiftHasEnded, endComponents.count >= 2, startComponents.count >= 2 {
        var ec = calendar.dateComponents([.year, .month, .day], from: now)
        ec.hour = endComponents[0]
        ec.minute = endComponents[1]
        ec.second = 0
        if var shiftEnd = calendar.date(from: ec) {
          // Handle cross-midnight shifts (end time <= start time)
          let startMinutes = startComponents[0] * 60 + startComponents[1]
          let endMinutes = endComponents[0] * 60 + endComponents[1]
          if endMinutes <= startMinutes {
            shiftEnd = calendar.date(byAdding: .day, value: 1, to: shiftEnd) ?? shiftEnd
          }
          if shiftEnd > now {
            entries.append(helper.createEntry(at: shiftEnd))
          }
        }
      }
    }

    // Refresh at next midnight to pick up day transitions and new shift data
    let tomorrow = calendar.startOfDay(
      for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
    let timeline = Timeline(entries: entries, policy: .after(tomorrow))
    completion(timeline)
  }

}

// MARK: - Provider Helpers

internal struct ShiftWidgetProviderHelper {
  private let appGroupId = "group.no.tidex.app"
  private let shiftsKey = "upcoming_shifts"
  private let currencyKey = "user_currency"

  private func sharedUserDefaults() -> UserDefaults? {
    guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) != nil
    else {
      return nil
    }
    return UserDefaults(suiteName: appGroupId)
  }

  /// Get the user's stored currency symbol, or nil if not set
  private func getStoredCurrency() -> String? {
    sharedUserDefaults()?.string(forKey: currencyKey)
  }

  /// Parse ISO date (YYYY-MM-DD) in a stable, locale-agnostic way.
  private func parseShiftDate(_ dateString: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: dateString)
  }

  /// Build a local Date from shift day + HH:mm, supporting 24:00 as next-day midnight.
  private func shiftDateTime(shiftDateString: String, time: String) -> Date? {
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

  private func shiftInterval(shiftDateString: String, startTime: String, endTime: String) -> (
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
  private func countMidnightCrossings(from startDate: Date, to endDate: Date) -> Int {
    let calendar = Calendar.current
    let fromMidnight = calendar.startOfDay(for: startDate)
    let toMidnight = calendar.startOfDay(for: endDate)

    let components = calendar.dateComponents([.day], from: fromMidnight, to: toMidnight)
    return abs(components.day ?? 0)
  }

  /// Determine if the shift has already started by comparing the given time to shift start
  /// Returns true if `now` is at or past the shift's start time on the shift date
  private func hasShiftStarted(shiftDateString: String, startTime: String, at now: Date) -> Bool {
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
  private func hasShiftEnded(
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
  private func isShiftActive(
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
  private func determineLayoutState(shiftDateString: String, at now: Date = Date()) -> (
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

  internal func createEntry(at now: Date) -> ShiftWidgetEntry {
    // Get stored currency (may be nil if never set)
    let storedCurrency = getStoredCurrency()

    guard let userDefaults = sharedUserDefaults(),
      let shiftsJson = userDefaults.string(forKey: shiftsKey),
      let data = shiftsJson.data(using: .utf8),
      let shifts = try? JSONDecoder().decode([StoredShift].self, from: data),
      !shifts.isEmpty
    else {
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
      deepLinkURL: deepLinkURL
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

    let weekdayFormatter: DateFormatter = .init()
    weekdayFormatter.locale = appLocale()
    weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE d")
    return sentenceCased(weekdayFormatter.string(from: shiftDate))
  }

  if calendar.isDate(shiftDay, inSameDayAs: today) {
    return String(localized: .widgetToday)
  }

  if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
    calendar.isDate(shiftDay, inSameDayAs: tomorrow)
  {
    return String(localized: .widgetTomorrow)
  }

  let weekdayFormatter: DateFormatter = .init()
  weekdayFormatter.locale = appLocale()
  weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE d")
  return sentenceCased(weekdayFormatter.string(from: shiftDate))
}

private func sentenceCased(_ text: String) -> String {
  guard !text.isEmpty else {
    return text
  }
  return text.prefix(1).uppercased(with: appLocale()) + text.dropFirst()
}

private func appLocale() -> Locale {
  let identifier = Bundle.main.preferredLocalizations.first ?? Locale.autoupdatingCurrent.identifier
  return Locale(identifier: identifier)
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
