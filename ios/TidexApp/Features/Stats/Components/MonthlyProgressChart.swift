import Charts
import SwiftUI

/// Chart showing cumulative monthly earnings progress
/// Displays current month vs previous month comparison
struct MonthlyProgressChart: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order
  let data: [DailyCumulativeData]  // swiftlint:disable:this explicit_acl

  @Environment(\.userCurrency) private var currency  // swiftlint:disable:this explicit_type_interface
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface

  // MARK: - Computed Properties

  /// Find today's index in the data
  private var todayIndex: Int? {
    data.firstIndex(where: { $0.isToday })
  }

  /// Maximum Y value for the chart (for axis scaling)
  private var maxYValue: Double {
    let maxCurrent = data.map(\.currentMonth).max() ?? 0  // swiftlint:disable:this explicit_type_interface
    let maxLast = data.map(\.lastMonth).max() ?? 0  // swiftlint:disable:this explicit_type_interface
    return max(maxCurrent, maxLast, 1_000)  // Minimum of 1000 to avoid tiny charts // swiftlint:disable:this line_length no_magic_numbers
  }

  /// X-axis tick values (days to show: 1, 5, 10, 15, 20, 25, last day)
  private var xAxisTicks: [Int] {
    guard let lastDay = data.last?.day else { return [] }  // swiftlint:disable:this conditional_returns_on_newline
    var ticks = [1, 5, 10, 15, 20, 25]  // swiftlint:disable:this explicit_type_interface no_magic_numbers
    if lastDay > 25 {  // swiftlint:disable:this no_magic_numbers
      ticks.append(lastDay)
    }
    return ticks.filter { $0 <= lastDay }
  }

  // MARK: - Computed Data

  /// Actual earnings data (up to and including today)
  private var actualData: [DailyCumulativeData] {
    data.filter { !$0.isFuture }
  }

  /// Projected earnings data (from today onwards - includes today to connect)
  private var projectedData: [DailyCumulativeData] {
    guard let todayIdx = todayIndex else { return [] }  // swiftlint:disable:this conditional_returns_on_newline
    return Array(data[todayIdx...])
  }

  private var chartDescriptor: StatsLineChartDescriptor {
    let thisMonth = StatsLineChartDescriptor.Series(  // swiftlint:disable:this explicit_type_interface
      name: String(localized: .commonThisMonth),
      points: actualData.map { (x: Double($0.day), y: $0.currentMonth) }
    )
    let projected = StatsLineChartDescriptor.Series(  // swiftlint:disable:this explicit_type_interface
      name: String(localized: .statsAccessibilityProjected),
      points: projectedData.map { (x: Double($0.day), y: $0.currentMonth) }
    )
    let previous = StatsLineChartDescriptor.Series(  // swiftlint:disable:this explicit_type_interface
      name: String(localized: .commonPreviousMonth),
      points: data.map { (x: Double($0.day), y: $0.lastMonth) }
    )
    let latest = actualData.last?.currentMonth ?? 0  // swiftlint:disable:this explicit_type_interface
    return StatsLineChartDescriptor(
      title: String(localized: .statsChartsMonthlyProgressTitle),
      summary: String(localized: .statsAccessibilityChartTotal(CurrencyConfig.format(latest, currency: currency))),
      xAxisTitle: String(localized: .statsAccessibilityAxisDay),
      yAxisTitle: String(localized: .shiftsEarningsSection),
      xRange: 1...31,  // swiftlint:disable:this no_magic_numbers
      series: [thisMonth, projected, previous],
      formatValue: { CurrencyConfig.format($0, currency: currency) }
    )
  }

  // MARK: - Body

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(alignment: .leading, spacing: Spacing.md) {  // swiftlint:disable:this closure_body_length
      StatsChartHeader(title: String(localized: .statsChartsMonthlyProgressTitle))

      // Chart
      Chart {
        // Last month line (dashed, muted) - single series
        ForEach(data) { point in
          LineMark(
            x: .value("Day", point.day),
            y: .value("Last Month", point.lastMonth),
            series: .value("Series", "lastMonth")
          )
          .interpolationMethod(.monotone)
          .foregroundStyle(Color.tidexTextMuted)
          .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))  // swiftlint:disable:this no_magic_numbers
        }

        // Current month - actual (solid line up to today)
        ForEach(actualData) { point in
          LineMark(
            x: .value("Day", point.day),
            y: .value("Current", point.currentMonth),
            series: .value("Series", "actual")
          )
          .interpolationMethod(.monotone)
          .foregroundStyle(Color.tidexBlue)
          .lineStyle(StrokeStyle(lineWidth: 3))  // swiftlint:disable:this no_magic_numbers
        }

        // Current month - projected (dashed line from today)
        ForEach(projectedData) { point in
          LineMark(
            x: .value("Day", point.day),
            y: .value("Projected", point.currentMonth),
            series: .value("Series", "projected")
          )
          .interpolationMethod(.monotone)
          .foregroundStyle(Color.tidexBlue)
          .lineStyle(StrokeStyle(lineWidth: 3, dash: [8, 4]))  // swiftlint:disable:this no_magic_numbers
        }
      }
      .chartXScale(
        domain: 1...31,  // swiftlint:disable:this no_magic_numbers
        range: .plotDimension(padding: Spacing.xs)
      )
      .chartYScale(domain: 0...maxYValue)
      .chartXAxis {
        AxisMarks(values: xAxisTicks) { value in
          AxisValueLabel(centered: false, collisionResolution: .greedy) {
            if let day = value.as(Int.self) {
              let isToday = data.first(where: { $0.day == day })?.isToday ?? false  // swiftlint:disable:this explicit_type_interface line_length
              Text("\(day)")
                .font(isToday ? .tidexCaptionStrong : .tidexCaptionRegular)
                .foregroundColor(isToday ? .tidexBlueText : .tidexTextSecondary)
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
      .chartLegend(.hidden)
      .accessibilityChartDescriptor(chartDescriptor)
      .frame(height: 220)  // swiftlint:disable:this no_magic_numbers

      // Name the two lines so the dashed grey one doesn't need guessing.
      let legendLayout =  // swiftlint:disable:this explicit_type_interface
        dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
        : AnyLayout(HStackLayout(spacing: Spacing.md))
      legendLayout {
        ProgressLegendItem(label: .commonThisMonth, color: .tidexBlue, dash: [])
        ProgressLegendItem(
          label: .commonPreviousMonth,
          color: .tidexTextMuted,
          dash: [4, 3]  // swiftlint:disable:this no_magic_numbers
        )
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .statsPanelSurface()
  }
}

// MARK: - Legend

private struct ProgressLegendItem: View {
  let label: LocalizedStringResource
  let color: Color
  let dash: [CGFloat]

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      Path { path in
        path.move(to: CGPoint(x: 0, y: 1))
        path.addLine(to: CGPoint(x: 14, y: 1))  // swiftlint:disable:this no_magic_numbers
      }
      .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dash))  // swiftlint:disable:this no_magic_numbers
      .frame(width: 14, height: 2)  // swiftlint:disable:this no_magic_numbers
      .accessibilityHidden(true)

      Text(label)
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextSecondary)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    }
  }
}

// MARK: - Empty State

/// Empty state when no cumulative data is available
struct MonthlyProgressChartEmpty: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl

  var body: some View {  // swiftlint:disable:this explicit_acl
    StatsChartHeader(
      title: String(localized: .statsChartsMonthlyProgressTitle),
      caption: String(localized: .statsChartsMonthlyProgressNoData)
    )
    .frame(maxWidth: .infinity, alignment: .leading)
    .statsPanelSurface()
  }
}

// MARK: - Preview

#Preview {
  ScrollView {
    VStack(spacing: Spacing.md) {
      MonthlyProgressChart(data: DailyCumulativeData.previewData)
      MonthlyProgressChartEmpty()
    }
    .padding()
  }
  .background(Color.tidexBackground)
}
