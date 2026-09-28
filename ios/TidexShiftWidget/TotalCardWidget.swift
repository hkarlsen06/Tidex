// swiftlint:disable file_length
// Widget files require multiple size-specific views that cannot be easily split
import SwiftUI
import WidgetKit

// MARK: - Widget Entry

struct TotalCardWidgetEntry: TimelineEntry {
  private static let placeholderGross: Double = 15_000
  private static let placeholderNet: Double = 12_500
  private static let placeholderCompletedGross: Double = 9_000
  private static let placeholderCompletedNet: Double = 7_500

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

  internal static func placeholder() -> Self {
    Self(
      date: Date(),
      gross: placeholderGross,
      net: placeholderNet,
      completedGross: placeholderCompletedGross,
      completedNet: placeholderCompletedNet,
      shiftCount: 8,
      plannedCount: 3,
      totalHours: 64,
      percentageChange: 12,
      taxEnabled: true,
      currencySymbol: "kr",
      yearMonth: "2026-02",
      hasData: true
    )
  }

  internal static func empty(currency: String = "kr") -> Self {
    Self(
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
      currencySymbol: currency,
      yearMonth: "",
      hasData: false
    )
  }
}

// MARK: - Timeline Provider

struct TotalCardWidgetProvider: TimelineProvider {
  internal func placeholder(in _: Context) -> TotalCardWidgetEntry {
    TotalCardWidgetEntry.placeholder()
  }

  internal func getSnapshot(in _: Context, completion: (TotalCardWidgetEntry) -> Void) {
    completion(TotalCardWidgetEntry.placeholder())
  }

  internal func getTimeline(in _: Context, completion: (Timeline<TotalCardWidgetEntry>) -> Void) {
    let entry = createEntry()

    // The card is month-scoped and only changes when the app calls WidgetCenter reloads,
    // so refreshing before the next month starts just re-renders the same data.
    let calendar = Calendar.gregorianCurrent
    let startOfMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
    let startOfNextMonth =
      calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? Date()
    let timeline = Timeline(entries: [entry], policy: .after(startOfNextMonth))
    completion(timeline)
  }

  private func createEntry() -> TotalCardWidgetEntry {
    guard let userDefaults = WidgetAppGroup.sharedUserDefaults(),
      let totalsJson = userDefaults.string(forKey: WidgetAppGroup.monthlyTotalsKey),
      let data = totalsJson.data(using: .utf8)
    else {
      let currency = WidgetAppGroup.sharedUserDefaults()?.string(forKey: WidgetAppGroup.currencyKey)
        ?? "kr"
      return TotalCardWidgetEntry.empty(currency: currency)
    }

    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let totals = try decoder.decode(StoredMonthlyTotals.self, from: data)

      // Totals saved last month would show the wrong month's earnings once the month changes.
      guard Calendar.gregorianCurrent.isDate(totals.updatedAt, equalTo: .now, toGranularity: .month) else {
        return TotalCardWidgetEntry.empty(currency: totals.currencySymbol)
      }

      // Show cached data for this month even if slightly stale, rather than a skeleton
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
        currencySymbol: totals.currencySymbol,
        yearMonth: totals.yearMonth,
        hasData: true
      )
    } catch {
      let currency = WidgetAppGroup.sharedUserDefaults()?.string(forKey: WidgetAppGroup.currencyKey)
        ?? "kr"
      return TotalCardWidgetEntry.empty(currency: currency)
    }
  }
}

// MARK: - Widget View (matches TotalCard.swift layout exactly)

struct TotalCardWidgetView: View {
  let entry: TotalCardWidgetEntry
  @Environment(\.widgetRenderingMode) var renderingMode

  // MARK: - Colors (matching TotalCard.swift)

  private var tidexBlue: Color { WidgetPalette.blue }
  private var tidexTextSecondary: Color { WidgetPalette.textSecondary }
  private var tidexTextMuted: Color { WidgetPalette.textMuted }
  private var tidexWidgetBackground: Color { WidgetPalette.background }

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
      return tidexWidgetBackground
    }
  }

  // MARK: - Localization (matching TotalCard.swift)

  private var earnedToDateLabel: String {
    String(localized: .widgetToDate)
  }

  private var beforeTaxLabel: String {
    String(localized: .widgetBeforeTax)
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
    let hasGross =
      !entry.hasFutureShifts && entry.taxEnabled
      && entry.gross > 0 && entry.gross != entry.mainDisplayValue
    if hasGross {
      return "\(formatCurrency(entry.gross)) \(beforeTaxLabel)"
    }

    // Future shifts but no real earnings yet
    let showPlanned = entry.hasFutureShifts && !hasRealEarned && entry.plannedCount > 0
    if showPlanned {
      return String(localized: .widgetShiftsPlannedCount(entry.plannedCount))
    }

    // Fallback: shift count
    if entry.shiftCount > 0 {
      return String(localized: .widgetShiftsCount(entry.shiftCount))
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
        label: String(localized: .widgetShifts)
      )

      // Stat 2: Completed shifts
      statRow(
        icon: "checkmark.circle",
        value: "\(entry.shiftCount - entry.plannedCount)",
        label: String(localized: .widgetDone)
      )

      // Stat 3: Hours worked
      statRow(
        icon: "clock",
        value: formattedHours,
        label: String(localized: .widgetHours)
      )

      Spacer()
    }
    .padding(.leading, 16)
  }

  /// Total hours in the user's locale with up to two decimals (e.g., "64" or "37,5")
  private var formattedHours: String {
    guard entry.totalHours > 0 else { return "—" }
    return entry.totalHours.formatted(.number.precision(.fractionLength(0...2)))
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
      return WidgetPalette.textPrimary
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
        Text((entry.displayPercentage / 100).formatted(.percent.precision(.fractionLength(0))))
          .font(.system(size: 18, weight: .semibold))
      }
    }
    .foregroundColor(
      entry.hasChange ? (entry.isPositive ? accentColor : secondaryTextColor) : mutedTextColor)
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

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: TotalCardWidgetProvider()) { entry in
      TotalCardWidgetView(entry: entry)
        .widgetURL(entry.deepLinkURL)
        .containerBackground(for: .widget) {
          Color.clear
        }
    }
    .configurationDisplayName(String(localized: .widgetNameMonthlyTotal))
    .description(String(localized: .widgetDescMonthlyTotal))
    .supportedFamilies([.systemMedium])
    .contentMarginsDisabled()
  }
}

// MARK: - Preview

#if DEBUG
  #Preview(as: .systemMedium) {
    TotalCardWidget()
  } timeline: {
    // Case 1: Has future shifts AND real earned amount → "7 500 kr hittil"
    TotalCardWidgetEntry(
      date: Date(),
      gross: 15_000,
      net: 12_500,
      completedGross: 9_000,
      completedNet: 7_500,
      shiftCount: 8,
      plannedCount: 3,
      totalHours: 64,
      percentageChange: 15,
      taxEnabled: true,
      currencySymbol: "kr",
      yearMonth: "2026-02",
      hasData: true
    )
    // Case 2: No future shifts, tax enabled → "12 000 kr før skatt"
    TotalCardWidgetEntry(
      date: Date(),
      gross: 12_000,
      net: 10_000,
      completedGross: 12_000,
      completedNet: 10_000,
      shiftCount: 5,
      plannedCount: 0,
      totalHours: 40,
      percentageChange: -8,
      taxEnabled: true,
      currencySymbol: "kr",
      yearMonth: "2026-02",
      hasData: true
    )
    // Case 3: No future shifts, no tax → "5 vakter"
    TotalCardWidgetEntry(
      date: Date(),
      gross: 12_000,
      net: nil,
      completedGross: 12_000,
      completedNet: nil,
      shiftCount: 5,
      plannedCount: 0,
      totalHours: 40,
      percentageChange: -8,
      taxEnabled: false,
      currencySymbol: "kr",
      yearMonth: "2026-02",
      hasData: true
    )
    // Case 4: Future shifts, no earnings yet → "3 vakter planlagt"
    TotalCardWidgetEntry(
      date: Date(),
      gross: 5_000,
      net: nil,
      completedGross: 0,
      completedNet: nil,
      shiftCount: 3,
      plannedCount: 3,
      totalHours: 24,
      percentageChange: nil,
      taxEnabled: false,
      currencySymbol: "kr",
      yearMonth: "2026-02",
      hasData: true
    )
    // Case 5: Zero earnings (shows dashes)
    TotalCardWidgetEntry.empty()
  }
#endif
// swiftlint:enable file_length
