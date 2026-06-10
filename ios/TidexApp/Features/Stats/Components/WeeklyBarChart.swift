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

  /// Y-axis scale calculation
  /// Note: Bar charts must always start at 0 - bars draw from 0 by default in Swift Charts
  private var yAxisScale: (domain: ClosedRange<Double>, ticks: [Double]) {
    let earnings = data.map(\.earnings)  // swiftlint:disable:this explicit_type_interface
    let positiveEarnings = earnings.filter { $0 > 0 }  // swiftlint:disable:this explicit_type_interface

    guard !positiveEarnings.isEmpty else {
      // No data - show default range
      return (0...100, [0, 25, 50, 75, 100])  // swiftlint:disable:this no_magic_numbers
    }

    let maxEarnings = earnings.max() ?? 0  // swiftlint:disable:this explicit_type_interface

    // Add 15% padding above max
    let upperBound = maxEarnings * 1.15  // swiftlint:disable:this explicit_type_interface no_magic_numbers

    // Build nice scale starting from 0
    let (niceDomain, ticks) = buildNiceScale(min: 0, max: upperBound, desiredTicks: 5)  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    return (niceDomain, ticks)
  }

  // MARK: - Body

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(alignment: .leading, spacing: Spacing.md) {  // swiftlint:disable:this closure_body_length
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
              let dayData = data.first(where: { $0.date == label })  // swiftlint:disable:this explicit_type_interface
              let isHighlighted = highlightToday && dayData?.fullDate == todayISO  // swiftlint:disable:this explicit_type_interface line_length
              let isSelected = selectedDay == label  // swiftlint:disable:this explicit_type_interface

              Text(label)
                .font((isHighlighted || isSelected) ? .tidexCaptionStrong : .tidexCaptionRegular)
                .foregroundColor((isHighlighted || isSelected) ? .tidexBlue : .tidexTextPrimary)
            }
          }
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: yAxisScale.ticks) { value in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))  // swiftlint:disable:this no_magic_numbers
            .foregroundStyle(Color.tidexBorderSubtle)
          AxisValueLabel {
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
      return day.fullDate == todayISO ? .tidexBlue : .tidexBlue.opacity(0.2)  // swiftlint:disable:this no_magic_numbers
    }
    // "Best Week" mode: all bars full color
    return .tidexBlue
  }

  /// Build a nice scale for the Y-axis
  private func buildNiceScale(min: Double, max: Double, desiredTicks: Int) -> (
    ClosedRange<Double>, [Double]
  ) {
    let span = max - min  // swiftlint:disable:this explicit_type_interface

    guard span > 0 else {
      return (0...100, [0, 25, 50, 75, 100])  // swiftlint:disable:this no_magic_numbers
    }

    let tickInterval = niceNumber(span / Double(desiredTicks - 1))  // swiftlint:disable:this explicit_type_interface
    let niceMin = floor(min / tickInterval) * tickInterval  // swiftlint:disable:this explicit_type_interface
    let niceMax = ceil(max / tickInterval) * tickInterval  // swiftlint:disable:this explicit_type_interface

    var ticks: [Double] = []
    var tick = niceMin  // swiftlint:disable:this explicit_type_interface
    while tick <= niceMax + tickInterval / 2 {  // swiftlint:disable:this no_magic_numbers
      ticks.append(tick)
      tick += tickInterval
    }

    return (niceMin...niceMax, ticks)
  }

  /// Calculate a "nice" number for axis intervals
  private func niceNumber(_ value: Double) -> Double {
    guard value > 0 else { return 1 }  // swiftlint:disable:this conditional_returns_on_newline

    let exponent = floor(log10(value))  // swiftlint:disable:this explicit_type_interface
    let fraction = value / pow(10, exponent)  // swiftlint:disable:this explicit_type_interface no_magic_numbers

    let niceFraction: Double
    if fraction <= 1 {
      niceFraction = 1
    } else if fraction <= 2 {  // swiftlint:disable:this no_magic_numbers
      niceFraction = 2  // swiftlint:disable:this no_magic_numbers
    } else if fraction <= 2.5 {  // swiftlint:disable:this no_magic_numbers
      niceFraction = 2.5  // swiftlint:disable:this no_magic_numbers
    } else if fraction <= 5 {  // swiftlint:disable:this no_magic_numbers
      niceFraction = 5  // swiftlint:disable:this no_magic_numbers
    } else {
      niceFraction = 10  // swiftlint:disable:this no_magic_numbers
    }

    return niceFraction * pow(10, exponent)  // swiftlint:disable:this no_magic_numbers
  }

  /// Format axis values as "Xk" (e.g., "1,2k", "1,4k")
  private func formatAxisValue(_ value: Double) -> String {
    if value == 0 {
      return "0"
    }

    if value >= 1_000 {  // swiftlint:disable:this no_magic_numbers
      let kValue = value / 1_000  // swiftlint:disable:this explicit_type_interface no_magic_numbers
      if kValue == floor(kValue) {
        return "\(Int(kValue))k"
      }
      let sep = Locale.appLocale.decimalSeparator ?? ","  // swiftlint:disable:this explicit_type_interface
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
        Rectangle()  // swiftlint:disable:this accessibility_trait_for_button
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
            .position(x: tooltipData.xPosition, y: 30)  // swiftlint:disable:this no_magic_numbers
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
    let adjustedX = location.x - plotFrame.origin.x  // swiftlint:disable:this explicit_type_interface
    let barWidth = plotFrame.width / CGFloat(data.count)  // swiftlint:disable:this explicit_type_interface
    let tappedIndex = Int(adjustedX / barWidth)  // swiftlint:disable:this explicit_type_interface

    guard tappedIndex >= 0, tappedIndex < data.count else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length

    let tappedDay = data[tappedIndex]  // swiftlint:disable:this explicit_type_interface
    guard tappedDay.earnings > 0 else { return }  // swiftlint:disable:this conditional_returns_on_newline

    withAnimation(.easeInOut(duration: 0.15)) {  // swiftlint:disable:this no_magic_numbers
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

    let barWidth = plotFrame.width / CGFloat(data.count)  // swiftlint:disable:this explicit_type_interface
    let desiredX = plotFrame.origin.x + barWidth * (CGFloat(index) + 0.5)  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    let horizontalInset = Spacing.xs  // swiftlint:disable:this explicit_type_interface
    let fallbackTooltipWidth: CGFloat = 120
    let effectiveTooltipWidth =  // swiftlint:disable:this explicit_type_interface
      tooltipWidth > 0 && tooltipWidth < (containerWidth - (horizontalInset * 2))  // swiftlint:disable:this line_length no_magic_numbers
      ? tooltipWidth : fallbackTooltipWidth
    let halfTooltipWidth = effectiveTooltipWidth / 2  // swiftlint:disable:this explicit_type_interface no_magic_numbers
    let minX = halfTooltipWidth + horizontalInset  // swiftlint:disable:this explicit_type_interface
    let maxX = containerWidth - halfTooltipWidth - horizontalInset  // swiftlint:disable:this explicit_type_interface
    let xPosition = maxX > minX ? min(max(desiredX, minX), maxX) : containerWidth / 2  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers

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
    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)  // swiftlint:disable:this no_magic_numbers
  }
}

// MARK: - Empty State

/// Empty state when no weekly data is available
struct WeeklyBarChartEmpty: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let title: String  // swiftlint:disable:this explicit_acl

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(title)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

      Text(.statsChartsWeeklyChartNoData)
        .font(.tidexSubheadline)
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
