import Charts
import SwiftUI

/// Chart showing cumulative monthly earnings progress
/// Displays current month vs previous month comparison
struct MonthlyProgressChart: View {
  let data: [DailyCumulativeData]

  @Environment(\.userCurrency) private var currency

  // MARK: - Computed Properties

  /// Find today's index in the data
  private var todayIndex: Int? {
    data.firstIndex(where: { $0.isToday })
  }

  /// Maximum Y value for the chart (for axis scaling)
  private var maxYValue: Double {
    let maxCurrent = data.map(\.currentMonth).max() ?? 0
    let maxLast = data.map(\.lastMonth).max() ?? 0
    return max(maxCurrent, maxLast, 1000)  // Minimum of 1000 to avoid tiny charts
  }

  /// Generate Y-axis tick values
  private var yAxisTicks: [Double] {
    let max = maxYValue
    let step = calculateNiceStep(max: max, targetTicks: targetYAxisTickCount)
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
    min(6, max(4, Int(maxYValue / 30_000) + 4))
  }

  /// X-axis tick values (days to show: 1, 5, 10, 15, 20, 25, last day)
  private var xAxisTicks: [Int] {
    guard let lastDay = data.last?.day else { return [] }
    var ticks = [1, 5, 10, 15, 20, 25]
    if lastDay > 25 {
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
    guard let todayIdx = todayIndex else { return [] }
    return Array(data[todayIdx...])
  }

  // MARK: - Body

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
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
          .foregroundStyle(Color.tidexTextMuted.opacity(0.6))
          .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
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
          .lineStyle(StrokeStyle(lineWidth: 3))
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
          .lineStyle(StrokeStyle(lineWidth: 3, dash: [8, 4]))
        }
      }
      .chartXScale(domain: 1...31)
      .chartYScale(domain: 0...maxYValue)
      .chartXAxis {
        AxisMarks(values: xAxisTicks) { value in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            .foregroundStyle(Color.tidexBorderSubtle)
          AxisValueLabel {
            if let day = value.as(Int.self) {
              let isToday = data.first(where: { $0.day == day })?.isToday ?? false
              Text("\(day)")
                .font(isToday ? .tidexLabelStrong : .tidexSubheadline)
                .foregroundColor(isToday ? .tidexBlue : .tidexTextPrimary)
            }
          }
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: yAxisTicks) { value in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            .foregroundStyle(Color.tidexBorderSubtle)
          AxisValueLabel(anchor: .trailing) {
            if let amount = value.as(Double.self) {
              Text(formatAxisValue(amount))
                .font(.tidexSubheadline)
                .foregroundColor(.tidexTextPrimary)
            }
          }
        }
      }
      .chartLegend(.hidden)
      .frame(height: 220)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.mlg)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.card)
    .tidexCardShadow()
  }

  // MARK: - Helpers

  /// Calculate a "nice" step value for axis ticks
  private func calculateNiceStep(max: Double, targetTicks: Int) -> Double {
    guard max > 0, targetTicks > 0 else { return 1_000 }

    let roughStep = max / Double(targetTicks)
    let magnitude = pow(10, floor(log10(roughStep)))
    let normalized = roughStep / magnitude

    // Round up to avoid too-dense labels (e.g., prefer 4k over 2k when rough step is ~2.5k).
    let niceStep: Double
    if normalized <= 1 {
      niceStep = magnitude
    } else if normalized <= 2 {
      niceStep = 2 * magnitude
    } else if normalized <= 4 {
      niceStep = 4 * magnitude
    } else if normalized <= 5 {
      niceStep = 5 * magnitude
    } else {
      niceStep = 10 * magnitude
    }

    return niceStep
  }

  /// Format axis values as "Xk" (e.g., "5k", "10k")
  private func formatAxisValue(_ value: Double) -> String {
    if value == 0 {
      return "0k"
    }
    let kValue = value / 1000
    if kValue == floor(kValue) {
      return "\(Int(kValue))k"
    }
    let sep = Locale.appLocale.decimalSeparator ?? ","
    return String(format: "%.1fk", kValue).replacingOccurrences(of: ".", with: sep)
  }
}

// MARK: - Empty State

/// Empty state when no cumulative data is available
struct MonthlyProgressChartEmpty: View {

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.statsChartsMonthlyProgressTitle)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

      Text(.statsChartsMonthlyProgressNoData)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.mlg)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.card)
    .tidexCardShadow()
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
