import Charts
import SwiftUI

/// Bar chart showing monthly earnings for a full year
/// Displays all 12 months with the current month highlighted
struct YearlyIncomeChart: View {
  let data: [MonthlyIncomeData]
  let focusYear: Int

  @Environment(\.userCurrency) private var currency

  /// Currently selected month (for tooltip)
  @State private var selectedMonth: String?

  // MARK: - Computed Properties

  /// Current month number (1-12)
  private var currentMonthNumber: Int {
    Calendar.current.component(.month, from: Date())
  }

  /// Current year
  private var currentYear: Int {
    Calendar.current.component(.year, from: Date())
  }

  /// Whether the focus year is the current year
  private var isCurrentYear: Bool {
    focusYear == currentYear
  }

  /// Get the selected month's data
  private var selectedMonthData: MonthlyIncomeData? {
    guard let selected = selectedMonth else { return nil }
    return data.first { $0.month == selected }
  }

  /// Filter out leading and trailing zero months for display
  private var trimmedData: [MonthlyIncomeData] {
    let firstNonZeroIndex = data.firstIndex { $0.earnings > 0 }
    guard let firstIdx = firstNonZeroIndex else { return data }

    let lastNonZeroIndex = data.lastIndex { $0.earnings > 0 }
    guard let lastIdx = lastNonZeroIndex else { return data }

    return Array(data[firstIdx...lastIdx])
  }

  /// Y-axis scale calculation
  private var yAxisScale: (domain: ClosedRange<Double>, ticks: [Double]) {
    let earnings = trimmedData.map(\.earnings)
    let positiveEarnings = earnings.filter { $0 > 0 }

    guard !positiveEarnings.isEmpty else {
      return (0...100, [0, 25, 50, 75, 100])
    }

    let maxEarnings = earnings.max() ?? 0
    let upperBound = maxEarnings * 1.15

    let (niceDomain, ticks) = buildNiceScale(min: 0, max: upperBound, desiredTicks: 5)
    return (niceDomain, ticks)
  }

  // MARK: - Body

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      // Title
      Text(String(localized: .statsChartsYearlyIncomeTitle(String(focusYear))))
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

      // Chart
      Chart {
        ForEach(trimmedData) { month in
          BarMark(
            x: .value("Month", month.month),
            y: .value("Earnings", month.earnings)
          )
          .foregroundStyle(barColor(for: month, isSelected: selectedMonth == month.month))
          .cornerRadius(6)
        }
      }
      .chartOverlay { proxy in
        YearlyChartOverlay(
          proxy: proxy,
          data: trimmedData,
          selectedMonth: $selectedMonth,
          currency: currency
        )
      }
      .chartXAxis {
        AxisMarks(values: .automatic) { value in
          AxisValueLabel {
            if let label = value.as(String.self) {
              let monthData = trimmedData.first(where: { $0.month == label })
              let isCurrentMonthLabel =
                isCurrentYear && monthData?.monthNumber == currentMonthNumber
              let isSelected = selectedMonth == label

              // Show every other month label on smaller screens
              let index = trimmedData.firstIndex(where: { $0.month == label }) ?? 0
              let shouldShow = index == 0 || index.isMultiple(of: 2)

              if shouldShow {
                Text(label)
                  .font(
                    .system(
                      size: 12, weight: (isCurrentMonthLabel || isSelected) ? .semibold : .regular)
                  )
                  .foregroundColor(
                    (isCurrentMonthLabel || isSelected) ? .tidexBlue : .tidexTextPrimary)
              }
            }
          }
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: yAxisScale.ticks) { value in
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
      .chartYScale(domain: yAxisScale.domain)
      .chartLegend(.hidden)
      .frame(height: 200)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.mlg)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(24)
    .tidexCardShadow()
  }

  // MARK: - Helpers

  /// Get bar color based on highlight and selection state
  private func barColor(for month: MonthlyIncomeData, isSelected: Bool) -> Color {
    if isSelected {
      return .tidexBlue
    }

    if isCurrentYear && month.monthNumber == currentMonthNumber {
      return .tidexBlue
    }

    return .tidexBlue.opacity(0.2)
  }

  /// Build a nice scale for the Y-axis
  private func buildNiceScale(min: Double, max: Double, desiredTicks: Int) -> (
    ClosedRange<Double>, [Double]
  ) {
    let span = max - min

    guard span > 0 else {
      return (0...100, [0, 25, 50, 75, 100])
    }

    let tickInterval = niceNumber(span / Double(desiredTicks - 1))
    let niceMin = floor(min / tickInterval) * tickInterval
    let niceMax = ceil(max / tickInterval) * tickInterval

    var ticks: [Double] = []
    var tick = niceMin
    while tick <= niceMax + tickInterval / 2 {
      ticks.append(tick)
      tick += tickInterval
    }

    return (niceMin...niceMax, ticks)
  }

  /// Calculate a "nice" number for axis intervals
  private func niceNumber(_ value: Double) -> Double {
    guard value > 0 else { return 1 }

    let exponent = floor(log10(value))
    let fraction = value / pow(10, exponent)

    let niceFraction: Double
    if fraction <= 1 {
      niceFraction = 1
    } else if fraction <= 2 {
      niceFraction = 2
    } else if fraction <= 2.5 {
      niceFraction = 2.5
    } else if fraction <= 5 {
      niceFraction = 5
    } else {
      niceFraction = 10
    }

    return niceFraction * pow(10, exponent)
  }

  /// Format axis values as "Xk" (e.g., "1k", "5k", "10k")
  private func formatAxisValue(_ value: Double) -> String {
    if value == 0 {
      return "0"
    }

    if value >= 1000 {
      let kValue = value / 1000
      if kValue == floor(kValue) {
        return "\(Int(kValue))k"
      }
      return String(format: "%.1fk", kValue).replacingOccurrences(of: ".", with: ",")
    }

    return "\(Int(value))"
  }
}

// MARK: - Chart Overlay Content

private struct YearlyChartOverlay: View {
  let proxy: ChartProxy
  let data: [MonthlyIncomeData]
  @Binding var selectedMonth: String?
  let currency: String

  var body: some View {
    GeometryReader { geometry in
      let plotFrame: CGRect = proxy.plotFrame.map { geometry[$0] } ?? .zero

      ZStack {
        // Tap detection layer
        Rectangle()
          .fill(Color.clear)
          .contentShape(Rectangle())
          .onTapGesture { location in
            handleTap(at: location, plotFrame: plotFrame)
          }

        // Tooltip overlay
        if let tooltipData = tooltipData(plotFrame: plotFrame) {
          YearlyTooltipView(monthData: tooltipData.monthData, currency: currency)
            .position(x: tooltipData.xPosition, y: 30)
        }
      }
    }
  }

  private func handleTap(at location: CGPoint, plotFrame: CGRect) {
    let adjustedX = location.x - plotFrame.origin.x
    let barWidth = plotFrame.width / CGFloat(data.count)
    let tappedIndex = Int(adjustedX / barWidth)

    guard tappedIndex >= 0 && tappedIndex < data.count else { return }

    let tappedMonth = data[tappedIndex]
    guard tappedMonth.earnings > 0 else { return }

    withAnimation(.easeInOut(duration: 0.15)) {
      if selectedMonth == tappedMonth.month {
        selectedMonth = nil
      } else {
        selectedMonth = tappedMonth.month
      }
    }
  }

  private func tooltipData(plotFrame: CGRect) -> (monthData: MonthlyIncomeData, xPosition: CGFloat)?
  {
    guard let selected = selectedMonth,
      let monthData = data.first(where: { $0.month == selected }),
      let index = data.firstIndex(where: { $0.month == selected })
    else {
      return nil
    }

    let barWidth = plotFrame.width / CGFloat(data.count)
    let xPosition = plotFrame.origin.x + barWidth * (CGFloat(index) + 0.5)

    return (monthData: monthData, xPosition: xPosition)
  }
}

// MARK: - Tooltip View

private struct YearlyTooltipView: View {
  let monthData: MonthlyIncomeData
  let currency: String

  var body: some View {
    VStack(alignment: .center, spacing: Spacing.xxs) {
      Text(monthData.fullMonth)
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexTextPrimary)

      Text(CurrencyConfig.format(monthData.earnings, currency: currency))
        .font(.system(size: 16, weight: .bold, design: .monospaced))
        .foregroundColor(.tidexBlue)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xs)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(8)
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.tidexBorderSubtle, lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
  }
}

// MARK: - Empty State

struct YearlyIncomeChartEmpty: View {
  let focusYear: Int

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(String(localized: .statsChartsYearlyIncomeTitle(String(focusYear))))
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

      Text(.statsChartsYearlyIncomeNoData)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.mlg)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(24)
    .tidexCardShadow()
  }
}

// MARK: - Preview

#Preview {
  ScrollView {
    VStack(spacing: Spacing.md) {
      YearlyIncomeChart(
        data: MonthlyIncomeData.previewData,
        focusYear: 2026
      )

      YearlyIncomeChartEmpty(focusYear: 2026)
    }
    .padding()
  }
  .background(Color.tidexBackground)
}
