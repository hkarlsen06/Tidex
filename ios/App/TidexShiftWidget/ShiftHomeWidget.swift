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

struct ShiftHomeWidgetView: View {
    let entry: ShiftWidgetEntry

    var body: some View {
        ZStack {
            // Dark background matching app theme
            tidexDarkBackground

            // Watermark logo - centered behind content
            LogoWatermark()
                .frame(width: 75, height: 85)

            // Content
            VStack(spacing: 0) {
                // TOP ROW
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

                // MIDDLE - HERO (large start time)
                Text(entry.startTime)
                    .font(.system(size: 46, weight: .bold, design: .default))
                    .monospacedDigit()
                    .foregroundColor(entry.hasShift ? .white : .white.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer()

                // BOTTOM ROW
                HStack(alignment: .bottom) {
                    Text(entry.endTime)
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)

                    Spacer()

                    Text(entry.salute)
                        .font(.system(size: 17, weight: .bold, design: .default))
                        .italic()
                        .foregroundColor(entry.hasShift ? tidexBlue : .white.opacity(0.4))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
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

    private func createEntry() -> ShiftWidgetEntry {
        guard let userDefaults = UserDefaults(suiteName: appGroupId),
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

        // Format date
        let formattedDate = formatShiftDate(shift.shiftDate, locale: locale)

        // Get random salute
        let salute = MotivationalSalutes.random(locale: locale)

        return ShiftWidgetEntry(
            date: Date(),
            shiftDate: formattedDate,
            startTime: shift.startTime,
            endTime: shift.endTime,
            netEarnings: formattedEarnings,
            salute: salute,
            locale: locale,
            hasShift: true
        )
    }

    /// Find the best shift to display:
    /// 1. Next upcoming shift (today or future)
    /// 2. Most recent past shift if no future shifts
    private func findBestShift(from shifts: [StoredShift]) -> StoredShift? {
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        // Sort shifts by date
        let sortedShifts = shifts.sorted { a, b in
            guard let dateA = formatter.date(from: a.shiftDate),
                  let dateB = formatter.date(from: b.shiftDate)
            else { return false }
            return dateA < dateB
        }

        // Find first future shift (including today)
        for shift in sortedShifts {
            if let shiftDate = formatter.date(from: shift.shiftDate),
               shiftDate >= today
            {
                return shift
            }
        }

        // No future shifts - return most recent past shift
        return sortedShifts.last
    }

    private func formatShiftDate(_ dateString: String, locale: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let shiftDate = formatter.date(from: dateString) else { return dateString }

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
        weekdayFormatter.dateFormat = "EEE d."
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

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShiftWidgetProvider()) { entry in
            if #available(iOS 17.0, *) {
                ShiftHomeWidgetView(entry: entry)
                    .containerBackground(for: .widget) {
                        tidexDarkBackground
                    }
            } else {
                ShiftHomeWidgetView(entry: entry)
                    .background(tidexDarkBackground)
            }
        }
        .configurationDisplayName("Next Shift")
        .description("See your next shift at a glance")
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
    ShiftWidgetEntry.placeholder(locale: "no")
    ShiftWidgetEntry.placeholder(locale: "en")
    ShiftWidgetEntry.empty(locale: "no")
}
#endif
