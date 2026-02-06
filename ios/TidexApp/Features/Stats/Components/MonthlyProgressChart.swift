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
    // Aim for ~5 ticks
    let step = calculateNiceStep(max: max, targetTicks: 5)
    var ticks: [Double] = []
    var value: Double = 0
    while value <= max {
      ticks.append(value)
      value += step
    }
    return ticks
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
    VStack(alignment: .leading, spacing: 16) {
      // Title
      Text(.statsChartsMonthlyProgressTitle)
        .font(.system(size: 18, weight: .semibold))
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
                .font(.system(size: 14, weight: isToday ? .semibold : .regular))
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
                .font(.system(size: 14))
                .foregroundColor(.tidexTextPrimary)
            }
          }
        }
      }
      .chartLegend(.hidden)
      .frame(height: 220)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(24)
    .tidexCardShadow()
  }

  // MARK: - Helpers

  /// Calculate a "nice" step value for axis ticks
  private func calculateNiceStep(max: Double, targetTicks: Int) -> Double {
    let roughStep = max / Double(targetTicks)
    let magnitude = pow(10, floor(log10(roughStep)))
    let normalized = roughStep / magnitude

    let niceStep: Double
    if normalized < 1.5 {
      niceStep = magnitude
    } else if normalized < 3 {
      niceStep = 2 * magnitude
    } else if normalized < 7 {
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
    return String(format: "%.1fk", kValue)
  }
}

// MARK: - Empty State

/// Empty state when no cumulative data is available
struct MonthlyProgressChartEmpty: View {

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(.statsChartsMonthlyProgressTitle)
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(.tidexTextPrimary)

      Text(.statsChartsMonthlyProgressNoData)
        .font(.system(size: 14, weight: .regular))
        .foregroundColor(.tidexTextSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(24)
    .tidexCardShadow()
  }
}

// MARK: - Preview

#Preview {
  ScrollView {
    VStack(spacing: 16) {
      MonthlyProgressChart(data: DailyCumulativeData.previewData)
      MonthlyProgressChartEmpty()
    }
    .padding()
  }
  .background(Color.tidexBackground)
}
