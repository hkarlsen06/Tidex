import Charts
import SwiftUI

/// Bar chart showing monthly earnings for a full year
/// Displays all 12 months with the current month highlighted
struct YearlyIncomeChart: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order
  let data: [MonthlyIncomeData]  // swiftlint:disable:this explicit_acl
  let focusYear: Int  // swiftlint:disable:this explicit_acl

  @Environment(\.userCurrency) private var currency  // swiftlint:disable:this explicit_type_interface

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
    guard let selected = selectedMonth else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return data.first { $0.month == selected }
  }

  /// Filter out leading and trailing zero months for display
  private var trimmedData: [MonthlyIncomeData] {
    let firstNonZeroIndex = data.firstIndex { $0.earnings > 0 }  // swiftlint:disable:this explicit_type_interface
    guard let firstIdx = firstNonZeroIndex else {
      return data
    }

    let lastNonZeroIndex = data.lastIndex { $0.earnings > 0 }  // swiftlint:disable:this explicit_type_interface
    guard let lastIdx = lastNonZeroIndex else { return data }  // swiftlint:disable:this conditional_returns_on_newline

    return Array(data[firstIdx...lastIdx])
  }

  /// Y-axis scale calculation
  private var yAxisScale: (domain: ClosedRange<Double>, ticks: [Double]) {
    let earnings = trimmedData.map(\.earnings)  // swiftlint:disable:this explicit_type_interface
    let positiveEarnings = earnings.filter { $0 > 0 }  // swiftlint:disable:this explicit_type_interface

    guard !positiveEarnings.isEmpty else {
      return (0...100, [0, 25, 50, 75, 100])  // swiftlint:disable:this no_magic_numbers
    }

    let maxEarnings = earnings.max() ?? 0  // swiftlint:disable:this explicit_type_interface
    let upperBound = maxEarnings * 1.15  // swiftlint:disable:this explicit_type_interface no_magic_numbers

    let (niceDomain, ticks) = buildNiceScale(min: 0, max: upperBound, desiredTicks: 5)  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    return (niceDomain, ticks)
  }

  // MARK: - Body

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(alignment: .leading, spacing: Spacing.md) {  // swiftlint:disable:this closure_body_length
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
          .cornerRadius(CornerRadius.xs)
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
              let monthData = trimmedData.first(where: { $0.month == label })  // swiftlint:disable:this explicit_type_interface line_length
              let isCurrentMonthLabel =  // swiftlint:disable:this explicit_type_interface
                isCurrentYear && monthData?.monthNumber == currentMonthNumber
              let isSelected = selectedMonth == label  // swiftlint:disable:this explicit_type_interface

              // Show every other month label on smaller screens
              let index = trimmedData.firstIndex(where: { $0.month == label }) ?? 0  // swiftlint:disable:this explicit_type_interface line_length
              let shouldShow = index == 0 || index.isMultiple(of: 2)  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers

              if shouldShow {
                Text(label)
                  .font(
                    .system(
                      size: 12, weight: (isCurrentMonthLabel || isSelected) ? .semibold : .regular)  // swiftlint:disable:this line_length multiline_arguments_brackets no_magic_numbers
                  )
                  .foregroundColor(
                    (isCurrentMonthLabel || isSelected) ? .tidexBlue : .tidexTextPrimary)  // swiftlint:disable:this line_length multiline_arguments_brackets
              }
            }
          }
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: yAxisScale.ticks) { value in
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
      .chartYScale(domain: yAxisScale.domain)
      .chartLegend(.hidden)
      .frame(height: 200)  // swiftlint:disable:this no_magic_numbers
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .statsPanelSurface()
  }

  // MARK: - Helpers

  /// Get bar color based on highlight and selection state
  private func barColor(for month: MonthlyIncomeData, isSelected: Bool) -> Color {
    if isSelected {
      return .tidexBlue
    }

    if isCurrentYear, month.monthNumber == currentMonthNumber {
      return .tidexBlue
    }

    return .tidexBorder
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

  /// Format axis values as "Xk" (e.g., "1k", "5k", "10k")
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

private struct YearlyChartOverlay: View {
  let proxy: ChartProxy
  let data: [MonthlyIncomeData]
  @Binding var selectedMonth: String?
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
          YearlyTooltipView(monthData: tooltipData.monthData, currency: currency)
            .fixedSize()
            .position(x: tooltipData.xPosition, y: 30)  // swiftlint:disable:this no_magic_numbers
            .background(
              GeometryReader { tooltipGeometry in
                Color.clear.preference(
                  key: YearlyTooltipWidthPreferenceKey.self,
                  value: tooltipGeometry.size.width
                )
              }
            )
            .onPreferenceChange(YearlyTooltipWidthPreferenceKey.self) { width in
              tooltipWidth = width
            }
        }
      }
    }
  }

  private func handleTap(at location: CGPoint, plotFrame: CGRect) {
    let adjustedX = location.x - plotFrame.origin.x  // swiftlint:disable:this explicit_type_interface
    let barWidth = plotFrame.width / CGFloat(data.count)  // swiftlint:disable:this explicit_type_interface
    let tappedIndex = Int(adjustedX / barWidth)  // swiftlint:disable:this explicit_type_interface

    guard tappedIndex >= 0, tappedIndex < data.count else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length

    let tappedMonth = data[tappedIndex]  // swiftlint:disable:this explicit_type_interface
    guard tappedMonth.earnings > 0 else { return }  // swiftlint:disable:this conditional_returns_on_newline

    withAnimation(.easeInOut(duration: 0.15)) {  // swiftlint:disable:this no_magic_numbers
      if selectedMonth == tappedMonth.month {
        selectedMonth = nil
      } else {
        selectedMonth = tappedMonth.month
      }
    }
  }

  private func tooltipData(
    plotFrame: CGRect,
    containerWidth: CGFloat
  ) -> (monthData: MonthlyIncomeData, xPosition: CGFloat)? {
    guard let selected = selectedMonth,
      let monthData = data.first(where: { $0.month == selected }),
      let index = data.firstIndex(where: { $0.month == selected })
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

    return (monthData: monthData, xPosition: xPosition)
  }
}

private struct YearlyTooltipWidthPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
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

struct YearlyIncomeChartEmpty: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let focusYear: Int  // swiftlint:disable:this explicit_acl

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(String(localized: .statsChartsYearlyIncomeTitle(String(focusYear))))
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

      Text(.statsChartsYearlyIncomeNoData)
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
      YearlyIncomeChart(
        data: MonthlyIncomeData.previewData,
        focusYear: 2_026
      )

      YearlyIncomeChartEmpty(focusYear: 2_026)
    }
    .padding()
  }
  .background(Color.tidexBackground)
}
