import SwiftUI
import WidgetKit

// MARK: - Tidex Brand Colors

/// Tidex brand blue color - matches the app's brand gradient
private let tidexBlue = Color(red: 77 / 255, green: 137 / 255, blue: 249 / 255)

/// Dark background color matching the app's dark theme (approx #0a0f1a)
private let tidexDarkBackground = Color(red: 10 / 255, green: 15 / 255, blue: 26 / 255)

/// Logo gradient colors from short-logo-gradient.svg
private let logoGradientColors = [
    Color(red: 0, green: 212 / 255, blue: 1),           // #00D4FF - cyan (top)
    Color(red: 123 / 255, green: 97 / 255, blue: 1),    // #7B61FF - purple (middle)
    Color(red: 155 / 255, green: 77 / 255, blue: 202 / 255) // #9B4DCA - magenta (bottom)
]

// MARK: - Logo Watermark View

/// Tidex "T" logo shape - exact path from short-logo-gradient.svg (converted via online tool)
private struct TidexLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Original path bounds
        let pathMinX: CGFloat = 0.63993
        let pathMaxX: CGFloat = 1.2635
        let pathMinY: CGFloat = 1.7177
        let pathMaxY: CGFloat = 2.311

        let pathWidth = pathMaxX - pathMinX   // ~0.624
        let pathHeight = pathMaxY - pathMinY  // ~0.593

        // Use uniform scaling to preserve aspect ratio
        let scale = min(rect.width / pathWidth, rect.height / pathHeight)

        // Center the path in the rect
        let scaledWidth = pathWidth * scale
        let scaledHeight = pathHeight * scale
        let offsetX = (rect.width - scaledWidth) / 2
        let offsetY = (rect.height - scaledHeight) / 2

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: offsetX + (x - pathMinX) * scale,
                y: offsetY + (y - pathMinY) * scale
            )
        }

        path.move(to: pt(1.23732, 1.7177))
        path.addCurve(to: pt(0.66612, 1.7177), control1: pt(1.13775, 1.7179), control2: pt(0.76566, 1.71337))
        path.addCurve(to: pt(0.63993, 1.74003), control1: pt(0.65617, 1.71814), control2: pt(0.6412, 1.72111))
        path.addCurve(to: pt(0.63993, 1.81659), control1: pt(0.6388, 1.75702), control2: pt(0.6372, 1.79978))
        path.addCurve(to: pt(0.66612, 1.83892), control1: pt(0.6412, 1.82434), control2: pt(0.64969, 1.83921))
        path.addCurve(to: pt(0.83797, 1.83892), control1: pt(0.69934, 1.83832), control2: pt(0.80156, 1.83786))
        path.addCurve(to: pt(0.88052, 1.88038), control1: pt(0.85928, 1.83953), control2: pt(0.88041, 1.85613))
        path.addCurve(to: pt(0.88052, 2.311), control1: pt(0.88091, 1.95937), control2: pt(0.88011, 2.24337))
        path.addCurve(to: pt(1.02782, 2.25997), control1: pt(0.88095, 2.38083), control2: pt(1.02782, 2.32572))
        path.addCurve(to: pt(1.02782, 1.87719), control1: pt(1.02783, 2.18381), control2: pt(1.02715, 1.94768))
        path.addCurve(to: pt(1.06874, 1.83892), control1: pt(1.02797, 1.86204), control2: pt(1.04362, 1.83915))
        path.addCurve(to: pt(1.23568, 1.83892), control1: pt(1.10399, 1.83859), control2: pt(1.20286, 1.83973))
        path.addCurve(to: pt(1.2635, 1.81021), control1: pt(1.25067, 1.83854), control2: pt(1.26304, 1.83083))
        path.addCurve(to: pt(1.2635, 1.74482), control1: pt(1.26387, 1.79389), control2: pt(1.26396, 1.76203))
        path.addCurve(to: pt(1.23732, 1.7177), control1: pt(1.26317, 1.73255), control2: pt(1.25496, 1.71767))
        path.closeSubpath()

        return path
    }
}

/// Gradient-filled logo watermark with brand colors from short-logo-gradient.svg
private struct LogoWatermark: View {
    var body: some View {
        TidexLogoShape()
            .fill(
                LinearGradient(
                    colors: logoGradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(0.15)
    }
}

// MARK: - Widget View

@available(iOS 17.0, *)
struct ShiftHomeWidgetView: View {
    let entry: ShiftWidgetEntry
    @Environment(\.widgetRenderingMode) var renderingMode

    /// Localized "days" label
    private var daysLabel: String {
        entry.locale == "no" ? "dager" : "days"
    }

    /// Localized "left" label
    private var leftLabel: String {
        entry.locale == "no" ? "igjen" : "left"
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

    /// Whether to show the watermark logo (hide in accented mode for cleaner look)
    private var showWatermark: Bool {
        renderingMode == .fullColor
    }

    var body: some View {
        ZStack {
            // Adaptive background
            backgroundColor

            // Watermark logo - only show in fullColor mode
            if showWatermark {
                LogoWatermark()
                    .frame(width: 75, height: 85)
            }

            // Content - switches based on layout state
            if entry.layoutState == .countdown {
                countdownLayout
            } else {
                todayTomorrowLayout
            }
        }
    }

    // MARK: - State A: Today/Tomorrow Layout

    /// Layout for today or tomorrow shifts with time block and salute
    private var todayTomorrowLayout: some View {
        VStack(spacing: 0) {
            // TOP ROW: Date + Earnings
            HStack(alignment: .top) {
                Text(entry.shiftDate)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(entry.hasShift ? accentColor : mutedTextColor)
                    .widgetAccentable(entry.hasShift)
                    .lineLimit(1)

                Spacer()

                Text(entry.netEarnings)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }

            Spacer()

            // MIDDLE: Time block (vertically centered as a group)
            timeBlockView

            Spacer()

            // BOTTOM: Salute - spans width with max height constraint
            Text(entry.salute)
                .font(.system(size: 17, weight: .bold, design: .default))
                .italic()
                .foregroundColor(entry.hasShift ? accentColor : mutedTextColor)
                .widgetAccentable(entry.hasShift)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }

    /// Time block: primary time (large) + secondary time (small) stacked vertically
    /// Before shift: Start (large) over End (small)
    /// After shift starts: End (large) over Start (small)
    private var timeBlockView: some View {
        VStack(spacing: 4) {
            // Secondary time (small) - shown on top after shift starts
            if entry.shiftHasStarted {
                Text(secondaryTime)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .monospacedDigit()
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }

            // Primary time (large)
            Text(primaryTime)
                .font(.system(size: 46, weight: .bold, design: .default))
                .monospacedDigit()
                .foregroundColor(entry.hasShift ? primaryTextColor : mutedTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Secondary time (small) - shown below before shift starts
            if !entry.shiftHasStarted {
                Text(secondaryTime)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .monospacedDigit()
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - State B: Countdown Layout

    /// Layout for shifts more than 1 day away
    private var countdownLayout: some View {
        VStack(spacing: 0) {
            // TOP ROW: Date + Earnings
            HStack(alignment: .top) {
                Text(entry.shiftDate)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(entry.hasShift ? accentColor : mutedTextColor)
                    .widgetAccentable(entry.hasShift)
                    .lineLimit(1)

                Spacer()

                Text(entry.netEarnings)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }

            Spacer()

            // MIDDLE: Countdown hero
            countdownHeroView

            Spacer()

            // BOTTOM: Centered time range
            Text("\(entry.startTime) – \(entry.endTime)")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }

    /// Countdown hero view: large number on left, two stacked lines on right
    /// The number and labels are horizontally centered as a group
    private var countdownHeroView: some View {
        HStack(alignment: .center, spacing: 8) {
            // Large countdown number
            Text("\(entry.daysRemaining)")
                .font(.system(size: 46, weight: .bold, design: .default))
                .monospacedDigit()
                .foregroundColor(primaryTextColor)
                .lineLimit(1)

            // Two stacked text lines: "days" / "dager" on top, "left" / "igjen" on bottom
            VStack(alignment: .leading, spacing: 2) {
                Text(daysLabel)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)

                Text(leftLabel)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Legacy Widget View (iOS 16)

/// Fallback view for iOS 16 that doesn't support widgetRenderingMode
/// Uses the original hardcoded dark theme
struct ShiftHomeWidgetViewLegacy: View {
    let entry: ShiftWidgetEntry

    /// Localized "days" label
    private var daysLabel: String {
        entry.locale == "no" ? "dager" : "days"
    }

    /// Localized "left" label
    private var leftLabel: String {
        entry.locale == "no" ? "igjen" : "left"
    }

    /// Primary time (large) - start time before shift, end time after shift starts
    private var primaryTime: String {
        entry.shiftHasStarted ? entry.endTime : entry.startTime
    }

    /// Secondary time (small) - end time before shift, start time after shift starts
    private var secondaryTime: String {
        entry.shiftHasStarted ? entry.startTime : entry.endTime
    }

    var body: some View {
        ZStack {
            // Dark background matching app theme
            tidexDarkBackground

            // Watermark logo - centered behind content
            LogoWatermark()
                .frame(width: 75, height: 85)

            // Content - switches based on layout state
            if entry.layoutState == .countdown {
                countdownLayout
            } else {
                todayTomorrowLayout
            }
        }
    }

    // MARK: - State A: Today/Tomorrow Layout

    private var todayTomorrowLayout: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(entry.shiftDate)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(entry.hasShift ? tidexBlue : .white.opacity(0.4))
                    .lineLimit(1)

                Spacer()

                Text(entry.netEarnings)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            timeBlockView

            Spacer()

            Text(entry.salute)
                .font(.system(size: 17, weight: .bold, design: .default))
                .italic()
                .foregroundColor(entry.hasShift ? tidexBlue : .white.opacity(0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }

    private var timeBlockView: some View {
        VStack(spacing: 4) {
            if entry.shiftHasStarted {
                Text(secondaryTime)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Text(primaryTime)
                .font(.system(size: 46, weight: .bold, design: .default))
                .monospacedDigit()
                .foregroundColor(entry.hasShift ? .white : .white.opacity(0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if !entry.shiftHasStarted {
                Text(secondaryTime)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - State B: Countdown Layout

    private var countdownLayout: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(entry.shiftDate)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(entry.hasShift ? tidexBlue : .white.opacity(0.4))
                    .lineLimit(1)

                Spacer()

                Text(entry.netEarnings)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            countdownHeroView

            Spacer()

            Text("\(entry.startTime) – \(entry.endTime)")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }

    private var countdownHeroView: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("\(entry.daysRemaining)")
                .font(.system(size: 46, weight: .bold, design: .default))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 2) {
                Text(daysLabel)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(leftLabel)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(.white)
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
    let shiftDate: String // YYYY-MM-DD
    let startTime: String // HH:mm
    let endTime: String // HH:mm
    let hourlyWage: Double
    let supplementRatePerHour: Double
    let totalGrossEstimate: Double
    let locale: String
    let currencySymbol: String?
    let taxRate: Double?
}

// MARK: - Widget Provider

struct ShiftWidgetProvider: TimelineProvider {
    private let appGroupId = "group.no.tidex.app"

    private func sharedUserDefaults() -> UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) != nil else {
            return nil
        }
        return UserDefaults(suiteName: appGroupId)
    }

    func placeholder(in _: Context) -> ShiftWidgetEntry {
        ShiftWidgetEntry.placeholder()
    }

    func getSnapshot(in _: Context, completion: @escaping (ShiftWidgetEntry) -> Void) {
        completion(ShiftWidgetEntry.placeholder())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<ShiftWidgetEntry>) -> Void) {
        let entry = createEntry()

        // Refresh every 15 minutes or at next midnight
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }

    // MARK: - Private Helpers

    /// Parse ISO date (YYYY-MM-DD) in a stable, locale-agnostic way.
    private func parseShiftDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    /// Count midnight boundaries crossed between two dates (matching the web app's pattern)
    /// Users perceive "1 day" as "tomorrow", not "24 hours from now"
    private func countMidnightCrossings(from: Date, to: Date) -> Int {
        let calendar = Calendar.current
        let fromMidnight = calendar.startOfDay(for: from)
        let toMidnight = calendar.startOfDay(for: to)

        let components = calendar.dateComponents([.day], from: fromMidnight, to: toMidnight)
        return abs(components.day ?? 0)
    }

    /// Determine if the shift has already started by comparing current time to shift start
    /// Returns true if we're past the shift's start time on the shift date
    private func hasShiftStarted(shiftDateString: String, startTime: String) -> Bool {
        guard let shiftDate = parseShiftDate(shiftDateString) else {
            return false
        }

        // Parse start time (HH:mm)
        let timeComponents = startTime.split(separator: ":").compactMap { Int($0) }
        guard timeComponents.count >= 2 else {
            return false
        }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: shiftDate)
        components.hour = timeComponents[0]
        components.minute = timeComponents[1]

        guard let shiftStartDateTime = calendar.date(from: components) else {
            return false
        }

        return Date() >= shiftStartDateTime
    }

    /// Determine the layout state based on midnight crossings
    /// - 0 crossings: today (State A)
    /// - 1 crossing: tomorrow (State A)
    /// - 2+ crossings: countdown (State B)
    private func determineLayoutState(shiftDateString: String) -> (state: WidgetLayoutState, daysRemaining: Int) {
        guard let shiftDate = parseShiftDate(shiftDateString) else {
            return (.empty, 0)
        }

        let today = Date()
        let calendar = Calendar.current
        let todayMidnight = calendar.startOfDay(for: today)
        let shiftMidnight = calendar.startOfDay(for: shiftDate)

        // If shift is in the past, still show it with today/tomorrow layout
        if shiftMidnight < todayMidnight {
            return (.todayOrTomorrow, 0)
        }

        let daysRemaining = countMidnightCrossings(from: today, to: shiftDate)

        // State A: today (0) or tomorrow (1)
        // State B: more than 1 day away (2+)
        if daysRemaining <= 1 {
            return (.todayOrTomorrow, daysRemaining)
        } else {
            return (.countdown, daysRemaining)
        }
    }

    private func createEntry() -> ShiftWidgetEntry {
        guard let userDefaults = sharedUserDefaults(),
              let shiftsJson = userDefaults.string(forKey: "upcoming_shifts"),
              let data = shiftsJson.data(using: .utf8),
              let shifts = try? JSONDecoder().decode([StoredShift].self, from: data),
              !shifts.isEmpty
        else {
            return ShiftWidgetEntry.empty()
        }

        // Find the best shift to display
        guard let shift = findBestShift(from: shifts) else {
            return ShiftWidgetEntry.empty(locale: shifts.first?.locale ?? "no")
        }

        let locale = shift.locale
        let currencySymbol = shift.currencySymbol ?? "kr"
        let taxRate = shift.taxRate ?? 0.0

        // Calculate net earnings
        let netEarnings = shift.totalGrossEstimate * (1 - taxRate)
        let formattedEarnings = formatCurrency(netEarnings, symbol: currencySymbol)

        // Determine layout state using midnight-crossing logic
        let (layoutState, daysRemaining) = determineLayoutState(shiftDateString: shift.shiftDate)

        // Check if shift has already started (for time emphasis swap)
        let shiftStarted = hasShiftStarted(shiftDateString: shift.shiftDate, startTime: shift.startTime)

        // Format date
        let formattedDate = formatShiftDate(shift.shiftDate, locale: locale)

        // Get random salute
        let salute = MotivationalSalutes.random(locale: locale)

        // Build deep link URL to open /shifts with the shift date highlighted
        // Format: tidex://shifts?dates=2025-01-15 (matches push notification pattern)
        let deepLinkURL = URL(string: "tidex://shifts?dates=\(shift.shiftDate)")

        return ShiftWidgetEntry(
            date: Date(),
            shiftDate: formattedDate,
            startTime: shift.startTime,
            endTime: shift.endTime,
            netEarnings: formattedEarnings,
            salute: salute,
            locale: locale,
            hasShift: true,
            daysRemaining: daysRemaining,
            layoutState: layoutState,
            shiftHasStarted: shiftStarted,
            deepLinkURL: deepLinkURL
        )
    }

    /// Find the best shift to display:
    /// 1. Next upcoming shift (today or future)
    /// 2. Most recent past shift if no future shifts
    private func findBestShift(from shifts: [StoredShift]) -> StoredShift? {
        let today = Calendar.current.startOfDay(for: Date())

        // Sort shifts by date
        let sortedShifts = shifts.sorted { a, b in
            guard let dateA = parseShiftDate(a.shiftDate),
                  let dateB = parseShiftDate(b.shiftDate)
            else { return false }
            return dateA < dateB
        }

        // Find first future shift (including today)
        for shift in sortedShifts {
            if let shiftDate = parseShiftDate(shift.shiftDate),
               shiftDate >= today
            {
                return shift
            }
        }

        // No future shifts - return most recent past shift
        return sortedShifts.last
    }

    private func formatShiftDate(_ dateString: String, locale: String) -> String {
        guard let shiftDate = parseShiftDate(dateString) else { return dateString }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let shiftDay = calendar.startOfDay(for: shiftDate)

        // Today
        if calendar.isDate(shiftDay, inSameDayAs: today) {
            return locale == "no" ? "I dag" : "Today"
        }

        // Tomorrow
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(shiftDay, inSameDayAs: tomorrow)
        {
            return locale == "no" ? "I morgen" : "Tomorrow"
        }

        // Weekday + day: "Man 12." or "Mon 12."
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: locale == "no" ? "nb_NO" : "en_US")
        weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE d")
        return weekdayFormatter.string(from: shiftDate).capitalized
    }

    private func formatCurrency(_ value: Double, symbol: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "

        let formatted = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(formatted) \(symbol)"
    }
}

// MARK: - Widget Configuration

struct ShiftHomeWidget: Widget {
    let kind: String = "ShiftHomeWidget"

    /// Check if the user's preferred language is Norwegian
    private var isNorwegian: Bool {
        let preferredLanguages = Locale.preferredLanguages
        // Check if Norwegian (any variant) is the preferred language
        return preferredLanguages.first?.hasPrefix("nb") == true ||
               preferredLanguages.first?.hasPrefix("no") == true ||
               preferredLanguages.first?.hasPrefix("nn") == true
    }

    /// Localized widget display name
    private var displayName: String {
        isNorwegian ? "Neste vakt" : "Next Shift"
    }

    /// Localized widget description
    private var widgetDescription: String {
        isNorwegian ? "Se neste vakt med ett blikk" : "See your next shift at a glance"
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShiftWidgetProvider()) { entry in
            if #available(iOS 17.0, *) {
                // iOS 17+: Use themed view with widgetRenderingMode support
                ShiftHomeWidgetView(entry: entry)
                    .widgetURL(entry.deepLinkURL)
                    .containerBackground(for: .widget) {
                        // Background is handled dynamically in the view based on renderingMode
                        // This serves as the fallback for fullColor mode
                        tidexDarkBackground
                    }
            } else {
                // iOS 16: Use legacy view with hardcoded dark theme
                ShiftHomeWidgetViewLegacy(entry: entry)
                    .widgetURL(entry.deepLinkURL)
                    .background(tidexDarkBackground)
            }
        }
        .configurationDisplayName(displayName)
        .description(widgetDescription)
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 17.0, *)
#Preview(as: .systemSmall) {
    ShiftHomeWidget()
} timeline: {
    // State A: Before shift starts (start time emphasized)
    ShiftWidgetEntry.placeholder(locale: "no")
    ShiftWidgetEntry.placeholder(locale: "en")
    // State A: After shift starts (end time emphasized)
    ShiftWidgetEntry(
        date: Date(),
        shiftDate: "I dag",
        startTime: "07:00",
        endTime: "15:00",
        netEarnings: "892 kr",
        salute: "Du klarer det!",
        locale: "no",
        hasShift: true,
        daysRemaining: 0,
        layoutState: .todayOrTomorrow,
        shiftHasStarted: true,
        deepLinkURL: URL(string: "tidex://shifts?dates=2025-01-15")
    )
    // State B: Countdown layouts
    ShiftWidgetEntry(
        date: Date(),
        shiftDate: "Man. 20.",
        startTime: "16:00",
        endTime: "23:15",
        netEarnings: "1 332 kr",
        salute: "Du klarer det!",
        locale: "no",
        hasShift: true,
        daysRemaining: 5,
        layoutState: .countdown,
        shiftHasStarted: false,
        deepLinkURL: URL(string: "tidex://shifts?dates=2025-01-20")
    )
    ShiftWidgetEntry(
        date: Date(),
        shiftDate: "Mon. 20.",
        startTime: "16:00",
        endTime: "23:15",
        netEarnings: "$234",
        salute: "You got this!",
        locale: "en",
        hasShift: true,
        daysRemaining: 12,
        layoutState: .countdown,
        shiftHasStarted: false,
        deepLinkURL: URL(string: "tidex://shifts?dates=2025-01-20")
    )
    // Empty state
    ShiftWidgetEntry.empty(locale: "no")
}
#endif
