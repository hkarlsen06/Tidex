import Charts
import SwiftUI

/// Chart showing cumulative monthly earnings progress
/// Displays current month vs previous month comparison
struct MonthlyProgressChart: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order
  let data: [DailyCumulativeData]  // swiftlint:disable:this explicit_acl

  @Environment(\.userCurrency) private var currency  // swiftlint:disable:this explicit_type_interface

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

  /// Generate Y-axis tick values
  private var yAxisTicks: [Double] {
    let max = maxYValue  // swiftlint:disable:this explicit_type_interface
    let step = calculateNiceStep(max: max, targetTicks: targetYAxisTickCount)  // swiftlint:disable:this explicit_type_interface line_length
    var ticks: [Double] = []
    var value: Double = 0
    while value <= max {
      ticks.append(value)
      value += step
    }
    return ticks
  }

  /// Dynamic Y-axis tick density to keep labels readable across ranges
  private var targetYAxisTickCount: Int {
    // Increase density for larger values so high earners still get useful granularity.
    min(6, max(4, Int(maxYValue / 30_000) + 4))  // swiftlint:disable:this no_magic_numbers
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

  // MARK: - Body

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(alignment: .leading, spacing: Spacing.md) {  // swiftlint:disable:this closure_body_length
      // Title
      Text(.statsChartsMonthlyProgressTitle)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

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
          .foregroundStyle(Color.tidexTextMuted.opacity(0.6))  // swiftlint:disable:this no_magic_numbers
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
                .foregroundColor(isToday ? .tidexBlue : .tidexTextPrimary)
            }
          }
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: yAxisTicks) { value in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))  // swiftlint:disable:this no_magic_numbers
            .foregroundStyle(Color.tidexSeparator)
          AxisValueLabel {
            if let amount = value.as(Double.self) {
              Text(formatAxisValue(amount))
                .font(.tidexCaptionRegular)
                .foregroundColor(.tidexTextPrimary)
            }
          }
        }
      }
      .chartLegend(.hidden)
      .frame(height: 220)  // swiftlint:disable:this no_magic_numbers
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .statsPanelSurface()
  }

  // MARK: - Helpers

  /// Calculate a "nice" step value for axis ticks
  private func calculateNiceStep(max: Double, targetTicks: Int) -> Double {
    guard max > 0, targetTicks > 0 else { return 1_000 }  // swiftlint:disable:this conditional_returns_on_newline line_length no_magic_numbers

    let roughStep = max / Double(targetTicks)  // swiftlint:disable:this explicit_type_interface
    let magnitude = pow(10, floor(log10(roughStep)))  // swiftlint:disable:this explicit_type_interface no_magic_numbers
    let normalized = roughStep / magnitude  // swiftlint:disable:this explicit_type_interface

    // Round up to avoid too-dense labels (e.g., prefer 4k over 2k when rough step is ~2.5k).
    let niceStep: Double
    if normalized <= 1 {
      niceStep = magnitude
    } else if normalized <= 2 {  // swiftlint:disable:this no_magic_numbers
      niceStep = 2 * magnitude  // swiftlint:disable:this no_magic_numbers
    } else if normalized <= 4 {  // swiftlint:disable:this no_magic_numbers
      niceStep = 4 * magnitude  // swiftlint:disable:this no_magic_numbers
    } else if normalized <= 5 {  // swiftlint:disable:this no_magic_numbers
      niceStep = 5 * magnitude  // swiftlint:disable:this no_magic_numbers
    } else {
      niceStep = 10 * magnitude  // swiftlint:disable:this no_magic_numbers
    }

    return niceStep
  }

  /// Format axis values as "Xk" (e.g., "5k", "10k")
  private func formatAxisValue(_ value: Double) -> String {
    if value == 0 {
      return "0k"
    }
    let kValue = value / 1_000  // swiftlint:disable:this explicit_type_interface no_magic_numbers
    if kValue == floor(kValue) {
      return "\(Int(kValue))k"
    }
    let sep = Locale.appLocale.decimalSeparator ?? ","  // swiftlint:disable:this explicit_type_interface
    return String(format: "%.1fk", kValue).replacingOccurrences(of: ".", with: sep)
  }
}

// MARK: - Empty State

/// Empty state when no cumulative data is available
struct MonthlyProgressChartEmpty: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.statsChartsMonthlyProgressTitle)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

      Text(.statsChartsMonthlyProgressNoData)
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextSecondary)
    }
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
