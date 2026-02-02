// swiftlint:disable file_length
// Widget files require multiple size-specific views that cannot be easily split
import SwiftUI
import WidgetKit

// MARK: - Widget Entry

struct TotalCardWidgetEntry: TimelineEntry {
    let date: Date

    // Display values
    let gross: Double
    let net: Double?
    let completedGross: Double
    let completedNet: Double?
    let shiftCount: Int
    let plannedCount: Int
    let totalHours: Double
    let percentageChange: Double?
    let taxEnabled: Bool

    // Formatting
    let locale: String
    let currencySymbol: String
    let yearMonth: String

    // State
    let hasData: Bool

    /// Deep link URL to open dashboard
    var deepLinkURL: URL? {
        URL(string: "tidex://dashboard")
    }

    // MARK: - Computed Properties (matching TotalCard.swift exactly)

    /// Main display value (projected total)
    var mainDisplayValue: Double {
        taxEnabled ? (net ?? gross) : gross
    }

    /// Earned to date value (completed shifts only)
    var earnedToDateValue: Double {
        taxEnabled ? (completedNet ?? completedGross) : completedGross
    }

    /// Whether there are future shifts
    var hasFutureShifts: Bool {
        plannedCount > 0 && mainDisplayValue != earnedToDateValue
    }

    /// Whether to show dashes (no data)
    var showDashes: Bool {
        !hasData || mainDisplayValue == 0
    }

    /// Whether there's a meaningful percentage change
    var hasChange: Bool {
        percentageChange != nil && percentageChange != 0
    }

    /// Whether the change is positive
    var isPositive: Bool {
        (percentageChange ?? 0) >= 0
    }

    /// Absolute percentage value for display
    var displayPercentage: Double {
        abs(percentageChange ?? 0)
    }

    /// Whether to show a dash instead of percentage
    var showPercentageDash: Bool {
        percentageChange == nil || percentageChange == 0
    }

    // MARK: - Factory Methods

    static func placeholder() -> TotalCardWidgetEntry {
        TotalCardWidgetEntry(
            date: Date(),
            gross: 15000,
            net: 12500,
            completedGross: 9000,
            completedNet: 7500,
            shiftCount: 8,
            plannedCount: 3,
            totalHours: 64,
            percentageChange: 12,
            taxEnabled: true,
            locale: "no",
            currencySymbol: "kr",
            yearMonth: "2026-02",
            hasData: true
        )
    }

    static func empty(locale: String = "no", currency: String = "kr") -> TotalCardWidgetEntry {
        TotalCardWidgetEntry(
            date: Date(),
            gross: 0,
            net: nil,
            completedGross: 0,
            completedNet: nil,
            shiftCount: 0,
            plannedCount: 0,
            totalHours: 0,
            percentageChange: nil,
            taxEnabled: false,
            locale: locale,
            currencySymbol: currency,
            yearMonth: "",
            hasData: false
        )
    }
}

// MARK: - Timeline Provider

struct TotalCardWidgetProvider: TimelineProvider {
    private let appGroupId = "group.no.tidex.app"
    private let monthlyTotalsKey = "monthly_totals"
    private let currencyKey = "user_currency"

    private func sharedUserDefaults() -> UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) != nil else {
            return nil
        }
        return UserDefaults(suiteName: appGroupId)
    }

    func placeholder(in _: Context) -> TotalCardWidgetEntry {
        TotalCardWidgetEntry.placeholder()
    }

    func getSnapshot(in _: Context, completion: @escaping (TotalCardWidgetEntry) -> Void) {
        completion(TotalCardWidgetEntry.placeholder())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TotalCardWidgetEntry>) -> Void) {
        let entry = createEntry()

        // Refresh every 15 minutes
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }

    private func createEntry() -> TotalCardWidgetEntry {
        guard let userDefaults = sharedUserDefaults(),
              let totalsJson = userDefaults.string(forKey: monthlyTotalsKey),
              let data = totalsJson.data(using: .utf8)
        else {
            let currency = sharedUserDefaults()?.string(forKey: currencyKey) ?? "kr"
            return TotalCardWidgetEntry.empty(currency: currency)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let totals = try decoder.decode(StoredMonthlyTotals.self, from: data)

            // Check if data is stale (more than 1 hour old)
            let isStale = Date().timeIntervalSince(totals.updatedAt) > 3600

            if isStale {
                return TotalCardWidgetEntry.empty(
                    locale: totals.locale,
                    currency: totals.currencySymbol
                )
            }

            return TotalCardWidgetEntry(
                date: Date(),
                gross: totals.gross,
                net: totals.net,
                completedGross: totals.completedGross,
                completedNet: totals.completedNet,
                shiftCount: totals.shiftCount,
                plannedCount: totals.plannedCount,
                totalHours: totals.totalHours,
                percentageChange: totals.percentageChange,
                taxEnabled: totals.taxEnabled,
                locale: totals.locale,
                currencySymbol: totals.currencySymbol,
                yearMonth: totals.yearMonth,
                hasData: true
            )
        } catch {
            let currency = sharedUserDefaults()?.string(forKey: currencyKey) ?? "kr"
            return TotalCardWidgetEntry.empty(currency: currency)
        }
    }
}

// MARK: - Widget View (matches TotalCard.swift layout exactly)

struct TotalCardWidgetView: View {
    let entry: TotalCardWidgetEntry
    @Environment(\.widgetRenderingMode) var renderingMode
    @Environment(\.colorScheme) var colorScheme

    // MARK: - Colors (matching TotalCard.swift)

    private var isLightMode: Bool {
        colorScheme == .light
    }

    /// tidexBlue - matches Color.tidexBlue from Color+Tidex.swift
    private var tidexBlue: Color {
        isLightMode
            ? Color(hue: 221 / 360, saturation: 0.83, brightness: 0.53)
            : Color(red: 77 / 255, green: 137 / 255, blue: 249 / 255)
    }

    /// tidexTextSecondary - matches Color.tidexTextSecondary
    private var tidexTextSecondary: Color {
        isLightMode
            ? Color(hue: 214 / 360, saturation: 0.28, brightness: 0.35)
            : Color(hue: 214 / 360, saturation: 0.32, brightness: 0.85)
    }

    /// tidexTextMuted - matches Color.tidexTextMuted
    private var tidexTextMuted: Color {
        isLightMode
            ? Color(red: 0x59 / 255, green: 0x6B / 255, blue: 0x80 / 255)
            : Color(hue: 215 / 360, saturation: 0.20, brightness: 0.70)
    }

    /// tidexSurfacePrimary - matches Color.tidexSurfacePrimary
    private var tidexSurfacePrimary: Color {
        isLightMode
            ? .white
            : Color(red: 0x14 / 255, green: 0x21 / 255, blue: 0x33 / 255)
    }

    /// Adaptive colors for widget rendering modes
    private var accentColor: Color {
        switch renderingMode {
        case .accented:
            return .primary
        default:
            return tidexBlue
        }
    }

    private var secondaryTextColor: Color {
        switch renderingMode {
        case .accented, .vibrant:
            return .secondary
        default:
            return tidexTextSecondary
        }
    }

    private var mutedTextColor: Color {
        switch renderingMode {
        case .accented, .vibrant:
            return .secondary
        default:
            return tidexTextMuted
        }
    }

    private var backgroundColor: Color {
        switch renderingMode {
        case .accented:
            return .clear
        case .vibrant:
            return Color.black.opacity(0.4)
        default:
            return tidexSurfacePrimary
        }
    }

    // MARK: - Localization (matching TotalCard.swift)

    private var earnedToDateLabel: String {
        entry.locale == "no" ? "hittil" : "to date"
    }

    private var beforeTaxLabel: String {
        entry.locale == "no" ? "før skatt" : "before tax"
    }

    private var shiftsPlannedLabel: String {
        if entry.plannedCount == 1 {
            return entry.locale == "no" ? "vakt planlagt" : "shift planned"
        }
        return entry.locale == "no" ? "vakter planlagt" : "shifts planned"
    }

    private var shiftsLabel: String {
        if entry.shiftCount == 1 {
            return entry.locale == "no" ? "vakt" : "shift"
        }
        return entry.locale == "no" ? "vakter" : "shifts"
    }

    // MARK: - Subtitle Logic (matching TotalCard.swift exactly)

    private var subtitleText: String? {
        if entry.showDashes { return nil }

        // Has future shifts AND real earned amount
        let hasRealEarned = entry.hasFutureShifts && entry.earnedToDateValue > 0
        if hasRealEarned {
            return "\(formatCurrency(entry.earnedToDateValue)) \(earnedToDateLabel)"
        }

        // Show gross before tax when tax is enabled
        let hasGross = !entry.hasFutureShifts && entry.taxEnabled
            && entry.gross > 0 && entry.gross != entry.mainDisplayValue
        if hasGross {
            return "\(formatCurrency(entry.gross)) \(beforeTaxLabel)"
        }

        // Future shifts but no real earnings yet
        let showPlanned = entry.hasFutureShifts && !hasRealEarned && entry.plannedCount > 0
        if showPlanned {
            return "\(entry.plannedCount) \(shiftsPlannedLabel)"
        }

        // Fallback: shift count
        if entry.shiftCount > 0 {
            return "\(entry.shiftCount) \(shiftsLabel)"
        }

        return nil
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            backgroundColor

            // Two-column layout
            HStack(spacing: 0) {
                // Left column: Total amount (larger)
                leftColumn
                    .frame(maxWidth: .infinity)

                // Vertical separator
                Rectangle()
                    .fill(separatorColor)
                    .frame(width: 1)
                    .padding(.vertical, 20)

                // Right column: Stats (smaller)
                rightColumn
                    .frame(width: 100)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Left Column (Total)

    private var leftColumn: some View {
        VStack(spacing: 4) {
            Spacer()

            // Top: percentage indicator
            percentageIndicator

            // Center: Main amount
            mainAmountDisplay

            // Bottom: subtitle
            subtitleView

            Spacer()
        }
        .padding(.trailing, 16)
    }

    // MARK: - Right Column (Stats)

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()

            // Stat 1: Shifts this month
            statRow(
                icon: "calendar",
                value: "\(entry.shiftCount)",
                label: entry.locale == "no" ? "vakter" : "shifts"
            )

            // Stat 2: Completed shifts
            statRow(
                icon: "checkmark.circle",
                value: "\(entry.shiftCount - entry.plannedCount)",
                label: entry.locale == "no" ? "fullført" : "done"
            )

            // Stat 3: Hours worked
            statRow(
                icon: "clock",
                value: formattedHours,
                label: entry.locale == "no" ? "timer" : "hours"
            )

            Spacer()
        }
        .padding(.leading, 16)
    }

    /// Total hours formatted (e.g., "64.00" or "64.50")
    private var formattedHours: String {
        guard entry.totalHours > 0 else { return "—" }
        return String(format: "%.2f", entry.totalHours)
    }

    private func statRow(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: -2) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                Text(label)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(secondaryTextColor)
            }
        }
    }

    @ViewBuilder
    private var subtitleView: some View {
        if entry.showDashes {
            RoundedRectangle(cornerRadius: 6)
                .fill(mutedTextColor.opacity(0.3))
                .frame(width: 100, height: 14)
        } else if let subtitle = subtitleText {
            Text(subtitle)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(secondaryTextColor)
        } else {
            Color.clear
                .frame(height: 18)
        }
    }

    private var separatorColor: Color {
        switch renderingMode {
        case .accented, .vibrant:
            return .secondary.opacity(0.3)
        default:
            return mutedTextColor.opacity(0.3)
        }
    }

    private var primaryTextColor: Color {
        switch renderingMode {
        case .accented, .vibrant:
            return .primary
        default:
            return isLightMode ? .black : .white
        }
    }

    // MARK: - Subviews (matching TotalCard.swift)

    @ViewBuilder
    private var percentageIndicator: some View {
        HStack(spacing: 4) {
            if entry.hasChange {
                Image(systemName: entry.isPositive ? "arrow.up" : "arrow.down")
                    .font(.system(size: 16, weight: .semibold))
            }
            if entry.showPercentageDash {
                Text("—")
                    .font(.system(size: 18, weight: .semibold))
            } else {
                Text(String(format: "%.0f%%", entry.displayPercentage))
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .foregroundColor(entry.hasChange ? (entry.isPositive ? accentColor : secondaryTextColor) : mutedTextColor)
    }

    @ViewBuilder
    private var mainAmountDisplay: some View {
        if entry.showDashes {
            // Skeleton placeholder matching the height of the large text
            RoundedRectangle(cornerRadius: 10)
                .fill(accentColor.opacity(0.3))
                .frame(width: 140, height: 44)
        } else {
            // Large amount display - sized for two-column layout
            Text(formatCurrency(entry.mainDisplayValue))
                .font(.system(size: 56, weight: .bold))
                .foregroundColor(accentColor)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
        }
    }

    // MARK: - Formatting

    private func formatCurrency(_ amount: Double) -> String {
        WidgetCurrencyFormatter.format(amount, currency: entry.currencySymbol)
    }
}

// MARK: - Widget Configuration

struct TotalCardWidget: Widget {
    let kind: String = "TotalCardWidget"

    private var isNorwegian: Bool {
        let preferredLanguages = Locale.preferredLanguages
        return preferredLanguages.first?.hasPrefix("nb") == true ||
               preferredLanguages.first?.hasPrefix("no") == true ||
               preferredLanguages.first?.hasPrefix("nn") == true
    }

    private var displayName: String {
        isNorwegian ? "Månedens total" : "Monthly Total"
    }

    private var widgetDescription: String {
        isNorwegian ? "Se månedstotalen med ett blikk" : "See your monthly total at a glance"
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TotalCardWidgetProvider()) { entry in
            TotalCardWidgetView(entry: entry)
                .widgetURL(entry.deepLinkURL)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName(displayName)
        .description(widgetDescription)
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - StoredMonthlyTotals (must match main app)

private struct StoredMonthlyTotals: Codable {
    let gross: Double
    let net: Double?
    let completedGross: Double
    let completedNet: Double?
    let shiftCount: Int
    let plannedCount: Int
    let totalHours: Double
    let percentageChange: Double?
    let yearMonth: String
    let taxEnabled: Bool
    let locale: String
    let currencySymbol: String
    let updatedAt: Date
}

// MARK: - Preview

#if DEBUG
#Preview(as: .systemMedium) {
    TotalCardWidget()
} timeline: {
    // Case 1: Has future shifts AND real earned amount → "7 500 kr hittil"
    TotalCardWidgetEntry(
        date: Date(),
        gross: 15000,
        net: 12500,
        completedGross: 9000,
        completedNet: 7500,
        shiftCount: 8,
        plannedCount: 3,
        totalHours: 64,
        percentageChange: 15,
        taxEnabled: true,
        locale: "no",
        currencySymbol: "kr",
        yearMonth: "2026-02",
        hasData: true
    )
    // Case 2: No future shifts, tax enabled → "12 000 kr før skatt"
    TotalCardWidgetEntry(
        date: Date(),
        gross: 12000,
        net: 10000,
        completedGross: 12000,
        completedNet: 10000,
        shiftCount: 5,
        plannedCount: 0,
        totalHours: 40,
        percentageChange: -8,
        taxEnabled: true,
        locale: "no",
        currencySymbol: "kr",
        yearMonth: "2026-02",
        hasData: true
    )
    // Case 3: No future shifts, no tax → "5 vakter"
    TotalCardWidgetEntry(
        date: Date(),
        gross: 12000,
        net: nil,
        completedGross: 12000,
        completedNet: nil,
        shiftCount: 5,
        plannedCount: 0,
        totalHours: 40,
        percentageChange: -8,
        taxEnabled: false,
        locale: "no",
        currencySymbol: "kr",
        yearMonth: "2026-02",
        hasData: true
    )
    // Case 4: Future shifts, no earnings yet → "3 vakter planlagt"
    TotalCardWidgetEntry(
        date: Date(),
        gross: 5000,
        net: nil,
        completedGross: 0,
        completedNet: nil,
        shiftCount: 3,
        plannedCount: 3,
        totalHours: 24,
        percentageChange: nil,
        taxEnabled: false,
        locale: "no",
        currencySymbol: "kr",
        yearMonth: "2026-02",
        hasData: true
    )
    // Case 5: Zero earnings (shows dashes)
    TotalCardWidgetEntry.empty()
}
#endif
// swiftlint:enable file_length
