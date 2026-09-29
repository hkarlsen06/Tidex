import Charts
import SwiftUI

/// Bar chart showing daily earnings for a week
/// Used for both "This Week" (current month) and "Best Week" (past months)
struct WeeklyBarChart: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order
  let data: [DailyData]  // swiftlint:disable:this explicit_acl
  let title: String  // swiftlint:disable:this explicit_acl

  /// Whether to highlight today (true for "This Week", false for "Best Week")
  let highlightToday: Bool  // swiftlint:disable:this explicit_acl

  @Environment(\.userCurrency) private var currency  // swiftlint:disable:this explicit_type_interface

  /// Currently selected day (for tooltip)
  @State private var selectedDay: String?

  // MARK: - Computed Properties

  /// Today's ISO date string
  private var todayISO: String {
    Date().toISODateString()
  }

  /// Get the selected day's data
  private var selectedDayData: DailyData? {
    guard let selected = selectedDay else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return data.first { $0.date == selected }
  }

  // MARK: - Body

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(alignment: .leading, spacing: Spacing.md) {  // swiftlint:disable:this closure_body_length
      StatsChartHeader(
        title: title,
        value: CurrencyConfig.format(data.reduce(0) { $0 + $1.earnings }, currency: currency)
      )

      // Chart
      Chart {
        ForEach(data) { day in
          BarMark(
            x: .value("Day", day.date),
            y: .value("Earnings", day.earnings)
          )
          .foregroundStyle(barColor(for: day, isSelected: selectedDay == day.date))
          .cornerRadius(CornerRadius.xs)
          .annotation(
            position: .top,
            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
          ) {
            if selectedDay == day.date {
              TooltipView(dayData: day, currency: currency)
            }
          }
        }
      }
      .chartXSelection(value: $selectedDay)
      .onChange(of: selectedDay) { _, newValue in
        selectedDay = ChartSelectionSnapping.nearestNonZero(
          to: newValue,
          in: data.map { (key: $0.date, value: $0.earnings) }
        )
      }
      .chartXAxis {
        AxisMarks(values: .automatic) { value in
          AxisValueLabel {
            if let label = value.as(String.self) {
              let dayData = data.first(where: { $0.date == label })  // swiftlint:disable:this explicit_type_interface
              let isHighlighted = highlightToday && dayData?.fullDate == todayISO  // swiftlint:disable:this explicit_type_interface line_length
              let isSelected = selectedDay == label  // swiftlint:disable:this explicit_type_interface

              Text(label)
                .font((isHighlighted || isSelected) ? .tidexCaptionStrong : .tidexCaptionRegular)
                .foregroundColor((isHighlighted || isSelected) ? .tidexBlue : .tidexTextSecondary)
            }
          }
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))  // swiftlint:disable:this no_magic_numbers
            .foregroundStyle(Color.tidexSeparator)
          AxisValueLabel(
            format: FloatingPointFormatStyle<Double>.number
              .notation(.compactName)
              .precision(.fractionLength(0...1))
              .locale(.appLocale)
          )
          .font(.tidexCaptionRegular)
          .foregroundStyle(Color.tidexTextSecondary)
        }
      }
      .chartYScale(domain: .automatic(includesZero: true))
      .chartLegend(.hidden)
      .frame(height: 200)  // swiftlint:disable:this no_magic_numbers
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .statsPanelSurface()
  }

  // MARK: - Helpers

  /// Get bar color based on highlight and selection state
  private func barColor(for day: DailyData, isSelected: Bool) -> Color {
    // Selected bars are always full color
    if isSelected {
      return .tidexBlue
    }

    if highlightToday {
      // "This Week" mode: highlight today, fade others
      return day.fullDate == todayISO ? .tidexBlue : .tidexBorder
    }
    // "Best Week" mode: all bars full color
    return .tidexBlue
  }
}

// MARK: - Chart Selection

/// Shared selection-normalization logic for the Stats bar charts: taps/drags on a
/// zero-value bar snap to the nearest bar with a positive value instead of showing an
/// empty tooltip.
enum ChartSelectionSnapping {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  /// Returns the key nearest to `key` whose value is greater than zero, or `nil` if
  /// `key` is `nil` or no point in `points` has a positive value.
  static func nearestNonZero<Key: Equatable>(  // swiftlint:disable:this explicit_acl
    to key: Key?,
    in points: [(key: Key, value: Double)]
  ) -> Key? {
    guard let key, let index = points.firstIndex(where: { $0.key == key }) else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length
    if points[index].value > 0 { return key }  // swiftlint:disable:this conditional_returns_on_newline

    return points.enumerated()
      .filter { $0.element.value > 0 }
      .min { abs($0.offset - index) < abs($1.offset - index) }?
      .element.key
  }
}

// MARK: - Tooltip View

/// Tooltip showing day name and earnings amount
private struct TooltipView: View {
  let dayData: DailyData
  let currency: String

  var body: some View {
    VStack(alignment: .center, spacing: Spacing.xxs) {
      Text(dayData.fullDay)
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexTextPrimary)

      Text(CurrencyConfig.format(dayData.earnings, currency: currency))
        .font(.tidexMonoBody)
        .foregroundColor(.tidexBlue)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xs)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.sm)
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.sm)
        .stroke(Color.tidexBorderSubtle, lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)  // swiftlint:disable:this no_magic_numbers
  }
}

// MARK: - Empty State

/// Empty state when no weekly data is available
struct WeeklyBarChartEmpty: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let title: String  // swiftlint:disable:this explicit_acl

  var body: some View {  // swiftlint:disable:this explicit_acl
    StatsChartHeader(title: title, caption: String(localized: .statsChartsWeeklyChartNoData))
      .frame(maxWidth: .infinity, alignment: .leading)
    .statsPanelSurface()
  }
}

// MARK: - Preview

#Preview {
  ScrollView {
    VStack(spacing: Spacing.md) {
      // This Week preview
      WeeklyBarChart(
        data: DailyData.previewThisWeek,
        title: "Denne uken",
        highlightToday: true
      )

      // Best Week preview
      if let bestWeek = BestWeekData.preview.weekData as [DailyData]? {  // swiftlint:disable:this discouraged_optional_collection line_length
        WeeklyBarChart(
          data: bestWeek,
          title: "Beste uke (Uke 50)",
          highlightToday: false
        )
      }

      // Empty state
      WeeklyBarChartEmpty(title: "Denne uken")
    }
    .padding()
  }
  .background(Color.tidexBackground)
}
