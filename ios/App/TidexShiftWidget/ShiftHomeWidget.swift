import SwiftUI
import WidgetKit

// MARK: - Tidex Adaptive Colors for Widgets
//
// These colors adapt to iOS system appearance (light/dark mode).
// The widget respects user's system appearance preference for a native feel.

/// Tidex brand blue color - adapts to light/dark mode for optimal contrast
/// Light: HSL(221, 83%, 53%) - vibrant blue
/// Dark: HSL(217, 91%, 65%) - bright blue
private struct TidexWidgetColors {
    /// Light mode brand blue
    static let lightBlue = Color(hue: 221 / 360, saturation: 0.83, brightness: 0.53)
    /// Dark mode brand blue
    static let darkBlue = Color(red: 77 / 255, green: 137 / 255, blue: 249 / 255)

    /// Light mode background
    static let lightBackground = Color(hue: 220 / 360, saturation: 0.40, brightness: 0.98)
    /// Dark mode background
    static let darkBackground = Color(red: 10 / 255, green: 15 / 255, blue: 26 / 255)
}

/// Logo gradient colors from short-logo-gradient.svg
/// These remain constant regardless of appearance mode
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
/// Supports both full color gradient and tinted monochrome modes
private struct LogoWatermark: View {
    var useTint: Bool = false

    var body: some View {
        if useTint {
            // Tinted mode: solid fill that will receive the widget's accent color
            TidexLogoShape()
                .fill(Color.primary.opacity(0.6))
        } else {
            // Full color mode: gradient fill
            TidexLogoShape()
                .fill(
                    LinearGradient(
                        colors: logoGradientColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

// MARK: - Widget View

struct ShiftHomeWidgetView: View {
    let entry: ShiftWidgetEntry
    @Environment(\.widgetRenderingMode) var renderingMode
    @Environment(\.colorScheme) var colorScheme

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

    /// Whether to use tinted monochrome logo (for accented/vibrant modes)
    private var useTintedLogo: Bool {
        renderingMode != .fullColor
    }

    var body: some View {
        ZStack {
            // Adaptive background
            backgroundColor

            // Content - switches based on layout state
            switch entry.layoutState {
            case .countdown:
                countdownLayout
            case .pastShift, .todayOrTomorrow, .empty:
                // Past shifts use the same layout as today/tomorrow
                todayTomorrowLayout
            }
        }
    }

    // MARK: - State A: Today/Tomorrow/Past Layout

    /// Layout for today, tomorrow, or past shifts with time block and salute
    private var todayTomorrowLayout: some View {
        VStack(spacing: 0) {
            // TOP ROW: Logo on left, Date + Earnings stacked on right
            HStack(alignment: .top) {
                // Logo - two lines high to match date + earnings
                LogoWatermark(useTint: useTintedLogo)
                    .frame(width: 28, height: 32)

                Spacer()

                // Date and earnings stacked on the right
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.shiftDate)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(entry.hasShift ? accentColor : mutedTextColor)
                        .widgetAccentable(entry.hasShift)
                        .lineLimit(1)

                    Text(entry.netEarnings)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)
                }
            }

            Spacer()

            // MIDDLE: Time block (vertically centered as a group)
            timeBlockView

            Spacer()

            // BOTTOM: Time range for past/ended shifts, salute for active shifts
            bottomTextView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
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
                Text(entry.salute)
                    .font(.system(size: 17, weight: .bold, design: .default))
                    .italic()
                    .foregroundColor(entry.hasShift ? accentColor : mutedTextColor)
                    .widgetAccentable(entry.hasShift)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 24)
    }

    /// Time block: primary time (large) + secondary time (small) stacked vertically
    /// Before shift: Start (large) over End (small)
    /// After shift starts: End (large) over Start (small)
    /// After shift ends today: "Ferdig" / "Done" (large)
    /// Past shift (previous day): "X dager siden" countdown
    private var timeBlockView: some View {
        VStack(spacing: 4) {
            if entry.layoutState == .pastShift {
                // Past shift from previous day - show days ago countdown
                pastShiftCountupView
            } else if entry.shiftHasEnded {
                // Shift ended today - show "Ferdig" / "Done"
                Text(entry.locale == "no" ? "Ferdig" : "Done")
                    .font(.system(size: 46, weight: .bold, design: .default))
                    .foregroundColor(entry.hasShift ? primaryTextColor : mutedTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
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
    }

    /// Past shift countup view - shows "X dager siden" / "X days ago"
    private var pastShiftCountupView: some View {
        let daysAgo = abs(entry.daysRemaining)
        let daysLabel = entry.locale == "no"
            ? (daysAgo == 1 ? "dag" : "dager")
            : (daysAgo == 1 ? "day" : "days")
        let agoLabel = entry.locale == "no" ? "siden" : "ago"

        return HStack(alignment: .center, spacing: 8) {
            Text("\(daysAgo)")
                .font(.system(size: 46, weight: .bold, design: .default))
                .monospacedDigit()
                .foregroundColor(entry.hasShift ? primaryTextColor : mutedTextColor)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 2) {
                Text(daysLabel)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(entry.hasShift ? primaryTextColor : mutedTextColor)
                    .lineLimit(1)

                Text(agoLabel)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(entry.hasShift ? primaryTextColor : mutedTextColor)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - State B: Countdown Layout

    /// Layout for shifts more than 1 day away
    private var countdownLayout: some View {
        VStack(spacing: 0) {
            // TOP ROW: Logo on left, Date + Earnings stacked on right
            HStack(alignment: .top) {
                // Logo - two lines high to match date + earnings
                LogoWatermark(useTint: useTintedLogo)
                    .frame(width: 28, height: 32)

                Spacer()

                // Date and earnings stacked on the right
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.shiftDate)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(entry.hasShift ? accentColor : mutedTextColor)
                        .widgetAccentable(entry.hasShift)
                        .lineLimit(1)

                    Text(entry.netEarnings)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)
                }
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

// MARK: - Widget Currency Formatter

/// Currency formatting for widgets - mirrors CurrencyConfig from the main app
/// Handles prefix vs suffix display based on currency symbol
enum WidgetCurrencyFormatter {
    /// Currency display position
    enum Display {
        case prefix  // Symbol before amount (e.g., "$100")
        case suffix  // Symbol after amount (e.g., "100 kr")
    }

    /// Get display position for a currency symbol
    static func display(for currency: String) -> Display {
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
    static func format(_ amount: Double, currency: String) -> String {
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
    static func formatEmpty(currency: String) -> String {
        switch display(for: currency) {
        case .prefix:
            return "\(currency)---"
        case .suffix:
            return "--- \(currency)"
        }
    }
}

// MARK: - Widget Provider

struct ShiftWidgetProvider: TimelineProvider {
    private let appGroupId = "group.no.tidex.app"
    private let shiftsKey = "upcoming_shifts"
    private let currencyKey = "user_currency"

    private func sharedUserDefaults() -> UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) != nil else {
            return nil
        }
        return UserDefaults(suiteName: appGroupId)
    }

    /// Get the user's stored currency symbol, or nil if not set
    private func getStoredCurrency() -> String? {
        sharedUserDefaults()?.string(forKey: currencyKey)
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

    /// Determine if the shift has already ended by comparing current time to shift end
    /// Returns true ONLY if the shift is TODAY and we're past the end time
    /// For past day shifts, returns false (those use pastShift layout with countdown instead)
    /// Note: For cross-midnight shifts (end <= start), adds 1 day to end time
    private func hasShiftEnded(shiftDateString: String, startTime: String, endTime: String) -> Bool {
        guard let shiftDate = parseShiftDate(shiftDateString) else {
            return false
        }

        let calendar = Calendar.current
        // Parse end time (HH:mm)
        let endComponents = endTime.split(separator: ":").compactMap { Int($0) }
        guard endComponents.count >= 2 else {
            return false
        }

        // Parse start time to check for cross-midnight
        let startComponents = startTime.split(separator: ":").compactMap { Int($0) }
        guard startComponents.count >= 2 else {
            return false
        }

        var components = calendar.dateComponents([.year, .month, .day], from: shiftDate)
        components.hour = endComponents[0]
        components.minute = endComponents[1]

        guard var shiftEndDateTime = calendar.date(from: components) else {
            return false
        }

        // Check for cross-midnight shift (end time <= start time means next day)
        let startMinutes = startComponents[0] * 60 + startComponents[1]
        let endMinutes = endComponents[0] * 60 + endComponents[1]
        if endMinutes <= startMinutes {
            // Cross-midnight: add 1 day to end time
            shiftEndDateTime = calendar.date(byAdding: .day, value: 1, to: shiftEndDateTime) ?? shiftEndDateTime
        }

        guard Date() >= shiftEndDateTime else {
            return false
        }

        // Only treat as "ended" if the end time is today
        return calendar.isDate(shiftEndDateTime, inSameDayAs: Date())
    }

    /// Determine the layout state based on midnight crossings
    /// - 0 crossings: today (State A)
    /// - 1 crossing: tomorrow (State A)
    /// - 2+ crossings: countdown (State B)
    /// - Negative crossings: past shift (State C)
    private func determineLayoutState(shiftDateString: String) -> (state: WidgetLayoutState, daysRemaining: Int) {
        guard let shiftDate = parseShiftDate(shiftDateString) else {
            return (.empty, 0)
        }

        let today = Date()
        let calendar = Calendar.current
        let todayMidnight = calendar.startOfDay(for: today)
        let shiftMidnight = calendar.startOfDay(for: shiftDate)

        // If shift is in the past, show it with pastShift layout
        if shiftMidnight < todayMidnight {
            let daysAgo = countMidnightCrossings(from: shiftDate, to: today)
            // Return negative daysRemaining to indicate past
            return (.pastShift, -daysAgo)
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
        guard let shift = findBestShift(from: shifts) else {
            return ShiftWidgetEntry.empty(locale: shifts.first?.locale ?? "no", currency: storedCurrency)
        }

        let locale = shift.locale
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
            formattedEarnings = formatter.string(from: NSNumber(value: netEarnings)) ?? "\(Int(netEarnings))"
        }

        // Determine layout state using midnight-crossing logic
        var (layoutState, daysRemaining) = determineLayoutState(shiftDateString: shift.shiftDate)

        // Check if shift has already started (for time emphasis swap)
        let shiftStarted = hasShiftStarted(shiftDateString: shift.shiftDate, startTime: shift.startTime)

        // Check if shift has already ended (for showing "Ferdig" / "Done")
        let shiftEnded = hasShiftEnded(shiftDateString: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime)

        // Ensure cross-midnight or recently ended shifts don't fall into pastShift layout
        if shiftStarted || shiftEnded {
            layoutState = .todayOrTomorrow
        }

        // Format date (pass daysRemaining for past shift formatting)
        let formattedDate = formatShiftDate(shift.shiftDate, locale: locale, daysRemaining: daysRemaining)

        // Get random salute
        let salute = MotivationalSalutes.random(locale: locale)

        // Build deep link URL to navigate to /shifts and highlight the shift date in calendar
        // Format: tidex://shifts?dates=2025-01-15&action=highlight
        // Using action=highlight so tapping the widget only highlights the shift in the calendar
        // (as opposed to action=open which opens the shift details sheet - used by notifications)
        let deepLinkURL = URL(string: "tidex://shifts?dates=\(shift.shiftDate)&action=highlight")

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
            shiftHasEnded: shiftEnded,
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

    private func formatShiftDate(_ dateString: String, locale: String, daysRemaining: Int) -> String {
        guard let shiftDate = parseShiftDate(dateString) else { return dateString }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let shiftDay = calendar.startOfDay(for: shiftDate)

        // Past shift - show "I går" / "Yesterday" or weekday+date for older shifts
        if daysRemaining < 0 {
            let daysAgo = abs(daysRemaining)
            if daysAgo == 1 {
                return locale == "no" ? "I går" : "Yesterday"
            } else {
                // 2+ days ago: show weekday + day format (e.g., "Man 12." / "Mon 12.")
                let weekdayFormatter = DateFormatter()
                weekdayFormatter.locale = Locale(identifier: locale == "no" ? "nb_NO" : "en_US")
                weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE d")
                return weekdayFormatter.string(from: shiftDate).capitalized
            }
        }

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
            ShiftHomeWidgetView(entry: entry)
                .widgetURL(entry.deepLinkURL)
                .containerBackground(for: .widget) {
                    // Background adapts to system appearance
                    // Uses Color.primary with dynamic scheme to get system-appropriate background
                    Color.clear // Let the view handle its own background based on colorScheme
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
        locale: "no",
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
        locale: "no",
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
        locale: "en",
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
        locale: "no",
        hasShift: true,
        daysRemaining: -3,
        layoutState: .pastShift,
        shiftHasStarted: true,
        shiftHasEnded: true,
        deepLinkURL: URL(string: "tidex://shifts?dates=2025-01-09&action=highlight")
    )
    // Empty state
    ShiftWidgetEntry.empty(locale: "no")
}
#endif
