import Charts
import SwiftUI

/// Bar chart showing daily earnings for a week
/// Used for both "This Week" (current month) and "Best Week" (past months)
struct WeeklyBarChart: View {
  let data: [DailyData]
  let title: String

  /// Whether to highlight today (true for "This Week", false for "Best Week")
  let highlightToday: Bool

  @Environment(\.userCurrency) private var currency

  /// Currently selected day (for tooltip)
  @State private var selectedDay: String?

  // MARK: - Computed Properties

  /// Today's ISO date string
  private var todayISO: String {
    Date().toISODateString()
  }

  /// Get the selected day's data
  private var selectedDayData: DailyData? {
    guard let selected = selectedDay else { return nil }
    return data.first { $0.date == selected }
  }

  /// Y-axis scale calculation
  /// Note: Bar charts must always start at 0 - bars draw from 0 by default in Swift Charts
  private var yAxisScale: (domain: ClosedRange<Double>, ticks: [Double]) {
    let earnings = data.map(\.earnings)
    let positiveEarnings = earnings.filter { $0 > 0 }

    guard !positiveEarnings.isEmpty else {
      // No data - show default range
      return (0...100, [0, 25, 50, 75, 100])
    }

    let maxEarnings = earnings.max() ?? 0

    // Add 15% padding above max
    let upperBound = maxEarnings * 1.15

    // Build nice scale starting from 0
    let (niceDomain, ticks) = buildNiceScale(min: 0, max: upperBound, desiredTicks: 5)
    return (niceDomain, ticks)
  }

  // MARK: - Body

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      // Title
      Text(title)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

      // Chart
      Chart {
        ForEach(data) { day in
          BarMark(
            x: .value("Day", day.date),
            y: .value("Earnings", day.earnings)
          )
          .foregroundStyle(barColor(for: day, isSelected: selectedDay == day.date))
          .cornerRadius(CornerRadius.xs)
        }
      }
      .chartOverlay { proxy in
        ChartOverlayContent(
          proxy: proxy,
          data: data,
          selectedDay: $selectedDay,
          currency: currency
        )
      }
      .chartXAxis {
        AxisMarks(values: .automatic) { value in
          AxisValueLabel {
            if let label = value.as(String.self) {
              let dayData = data.first(where: { $0.date == label })
              let isHighlighted = highlightToday && dayData?.fullDate == todayISO
              let isSelected = selectedDay == label

              Text(label)
                .font((isHighlighted || isSelected) ? .tidexCaptionStrong : .tidexCaptionRegular)
                .foregroundColor((isHighlighted || isSelected) ? .tidexBlue : .tidexTextPrimary)
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
                .font(.tidexCaptionRegular)
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
    .cornerRadius(CornerRadius.card)
    .tidexCardShadow()
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
      return day.fullDate == todayISO ? .tidexBlue : .tidexBlue.opacity(0.2)
    } else {
      // "Best Week" mode: all bars full color
      return .tidexBlue
    }
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

  /// Format axis values as "Xk" (e.g., "1,2k", "1,4k")
  private func formatAxisValue(_ value: Double) -> String {
    if value == 0 {
      return "0"
    }

    if value >= 1000 {
      let kValue = value / 1000
      if kValue == floor(kValue) {
        return "\(Int(kValue))k"
      }
      let sep = Locale.appLocale.decimalSeparator ?? ","
      return String(format: "%.1fk", kValue).replacingOccurrences(of: ".", with: sep)
    }

    return "\(Int(value))"
  }
}

// MARK: - Chart Overlay Content

/// Separate struct to avoid compiler complexity issues with chartOverlay
private struct ChartOverlayContent: View {
  let proxy: ChartProxy
  let data: [DailyData]
  @Binding var selectedDay: String?
  let currency: String
  @State private var tooltipWidth: CGFloat = 0

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
        if let tooltipData = tooltipData(
          plotFrame: plotFrame,
          containerWidth: geometry.size.width
        ) {
          TooltipView(dayData: tooltipData.dayData, currency: currency)
            .fixedSize()
            .position(x: tooltipData.xPosition, y: 30)
            .background(
              GeometryReader { tooltipGeometry in
                Color.clear.preference(
                  key: TooltipWidthPreferenceKey.self,
                  value: tooltipGeometry.size.width
                )
              }
            )
            .onPreferenceChange(TooltipWidthPreferenceKey.self) { width in
              tooltipWidth = width
            }
        }
      }
    }
  }

  private func handleTap(at location: CGPoint, plotFrame: CGRect) {
    // Adjust tap location relative to plot area
    let adjustedX = location.x - plotFrame.origin.x
    let barWidth = plotFrame.width / CGFloat(data.count)
    let tappedIndex = Int(adjustedX / barWidth)

    guard tappedIndex >= 0 && tappedIndex < data.count else { return }

    let tappedDay = data[tappedIndex]
    guard tappedDay.earnings > 0 else { return }

    withAnimation(.easeInOut(duration: 0.15)) {
      if selectedDay == tappedDay.date {
        selectedDay = nil
      } else {
        selectedDay = tappedDay.date
      }
    }
  }

  private func tooltipData(
    plotFrame: CGRect,
    containerWidth: CGFloat
  ) -> (dayData: DailyData, xPosition: CGFloat)? {
    guard let selected = selectedDay,
      let dayData = data.first(where: { $0.date == selected }),
      let index = data.firstIndex(where: { $0.date == selected })
    else {
      return nil
    }

    let barWidth = plotFrame.width / CGFloat(data.count)
    let desiredX = plotFrame.origin.x + barWidth * (CGFloat(index) + 0.5)
    let horizontalInset = Spacing.xs
    let fallbackTooltipWidth: CGFloat = 120
    let effectiveTooltipWidth =
      tooltipWidth > 0 && tooltipWidth < (containerWidth - (horizontalInset * 2))
      ? tooltipWidth : fallbackTooltipWidth
    let halfTooltipWidth = effectiveTooltipWidth / 2
    let minX = halfTooltipWidth + horizontalInset
    let maxX = containerWidth - halfTooltipWidth - horizontalInset
    let xPosition = maxX > minX ? min(max(desiredX, minX), maxX) : containerWidth / 2

    return (dayData: dayData, xPosition: xPosition)
  }
}

private struct TooltipWidthPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
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
    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
  }
}

// MARK: - Empty State

/// Empty state when no weekly data is available
struct WeeklyBarChartEmpty: View {
  let title: String

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(title)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

      Text(.statsChartsWeeklyChartNoData)
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
      // This Week preview
      WeeklyBarChart(
        data: DailyData.previewThisWeek,
        title: "Denne uken",
        highlightToday: true
      )

      // Best Week preview
      if let bestWeek = BestWeekData.preview.weekData as [DailyData]? {
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
