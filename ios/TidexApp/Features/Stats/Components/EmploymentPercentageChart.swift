import Charts
import SwiftUI

/// Chart showing employment percentage across the year
/// Displays monthly average employment percentages with yearly average header
struct EmploymentPercentageChart: View {
  let data: EmploymentData

  /// Currently selected month (for tooltip)
  @State private var selectedMonth: Int?

  // MARK: - Computed Properties

  /// Current month and year
  private var currentMonth: Int {
    Calendar.current.component(.month, from: Date())
  }

  private var currentYear: Int {
    Calendar.current.component(.year, from: Date())
  }

  /// Filter out leading and trailing zero months for display
  private var filteredData: [EmploymentMonthlyData] {
    let months = data.monthlyData
    guard let firstNonZeroIndex = months.firstIndex(where: { $0.averagePercentage > 0 }) else {
      return months  // All zeros, return as-is
    }
    guard let lastNonZeroIndex = months.lastIndex(where: { $0.averagePercentage > 0 }) else {
      return months
    }
    return Array(months[firstNonZeroIndex...lastNonZeroIndex])
  }

  /// Get selected month data
  private var selectedMonthData: EmploymentMonthlyData? {
    guard let selected = selectedMonth else { return nil }
    return data.monthlyData.first { $0.monthNumber == selected }
  }

  /// Y-axis scale calculation - rounds up to nearest 10
  private var yAxisScale: (domain: ClosedRange<Double>, ticks: [Double]) {
    let percentages = filteredData.map(\.averagePercentage)
    let maxPercentage = percentages.max() ?? 0

    // Round up to nearest 10, minimum 20%
    let upperBound = max(ceil(maxPercentage / 10) * 10, 20)

    // Create ticks at 20% intervals, or 10% if upper bound is small
    let tickInterval = upperBound <= 40 ? 10.0 : 20.0
    var ticks: [Double] = []
    var tick = 0.0
    while tick <= upperBound {
      ticks.append(tick)
      tick += tickInterval
    }

    return (0...upperBound, ticks)
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: 0) {
      // Header with yearly average
      headerView

      // Chart
      chartView
    }
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.card)
    .tidexCardShadow()
  }

  // MARK: - Header View

  @ViewBuilder
  private var headerView: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      // Title
      Text(.statsChartsEmploymentTitle)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

      HStack(alignment: .firstTextBaseline) {
        // Yearly average percentage
        if let average = data.yearlyAverage {
          Text(Self.formatPercent(average))
            .font(.tidexMonoDisplay)
            .foregroundColor(.tidexTextPrimary)
        } else {
          Text("---")
            .font(.tidexMonoDisplay)
            .foregroundColor(.tidexTextMuted)
        }

        Text(.statsChartsEmploymentYearlyAverage)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextMuted)

        Spacer()

        // Info button - show actual hours used (37.5 or 40)
        InfoPopoverButton(
          message: String(
            localized: .statsChartsEmploymentInfo(formatHours(data.fullTimeHoursPerWeek)))
        )
      }
    }
    .padding(Spacing.mlg)
    .padding(.bottom, -Spacing.xxs)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.tidexSurfaceSecondary)
  }

  // MARK: - Chart View

  @ViewBuilder
  private var chartView: some View {
    Chart {
      ForEach(filteredData) { month in
        BarMark(
          x: .value("Month", month.month),
          y: .value("Percentage", month.averagePercentage)
        )
        .foregroundStyle(barColor(for: month, isSelected: selectedMonth == month.monthNumber))
        .cornerRadius(CornerRadius.xs)
      }
    }
    .chartOverlay { proxy in
      ChartOverlayContent(
        proxy: proxy,
        data: filteredData,
        selectedMonth: $selectedMonth
      )
    }
    .chartXAxis {
      AxisMarks(values: .automatic) { value in
        AxisValueLabel {
          if let label = value.as(String.self) {
            let monthData = filteredData.first(where: { $0.month == label })
            let isHighlighted =
              monthData?.monthNumber == currentMonth && monthData?.year == currentYear
            let isSelected = selectedMonth == monthData?.monthNumber

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
            Text("\(Int(amount))%")
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextPrimary)
          }
        }
      }
    }
    .chartYScale(domain: yAxisScale.domain)
    .chartLegend(.hidden)
    .frame(height: 200)
    .padding(Spacing.mlg)
    .padding(.top, Spacing.xxs)
  }

  // MARK: - Helpers

  /// Get bar color based on current month and selection state
  private func barColor(for month: EmploymentMonthlyData, isSelected: Bool) -> Color {
    // Selected bars are always full color
    if isSelected {
      return .tidexBlue
    }

    // Current month is highlighted
    let isCurrentMonth = month.monthNumber == currentMonth && month.year == currentYear
    return isCurrentMonth ? .tidexBlue : .tidexBlue.opacity(0.2)
  }

  /// Format hours for display (e.g., "37,50" or "40,00")
  private func formatHours(_ hours: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    formatter.locale = Locale.appLocale
    return formatter.string(from: NSNumber(value: hours)) ?? String(format: "%.2f", hours)
  }

  /// Format percentage for display (e.g., "85,5%")
  fileprivate static func formatPercent(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 1
    formatter.maximumFractionDigits = 1
    formatter.locale = Locale.appLocale
    return (formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)) + "%"
  }
}

// MARK: - Chart Overlay Content

/// Separate struct to avoid compiler complexity issues with chartOverlay
private struct ChartOverlayContent: View {
  let proxy: ChartProxy
  let data: [EmploymentMonthlyData]
  @Binding var selectedMonth: Int?
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
          TooltipView(monthData: tooltipData.monthData)
            .fixedSize()
            .position(x: tooltipData.xPosition, y: 30)
            .background(
              GeometryReader { tooltipGeometry in
                Color.clear.preference(
                  key: EmploymentTooltipWidthPreferenceKey.self,
                  value: tooltipGeometry.size.width
                )
              }
            )
            .onPreferenceChange(EmploymentTooltipWidthPreferenceKey.self) { width in
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

    let tappedMonth = data[tappedIndex]
    guard tappedMonth.averagePercentage > 0 else { return }

    withAnimation(.easeInOut(duration: 0.15)) {
      if selectedMonth == tappedMonth.monthNumber {
        selectedMonth = nil
      } else {
        selectedMonth = tappedMonth.monthNumber
      }
    }
  }

  private func tooltipData(
    plotFrame: CGRect,
    containerWidth: CGFloat
  ) -> (
    monthData: EmploymentMonthlyData, xPosition: CGFloat
  )? {
    guard let selected = selectedMonth,
      let monthData = data.first(where: { $0.monthNumber == selected }),
      let index = data.firstIndex(where: { $0.monthNumber == selected })
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

    return (monthData: monthData, xPosition: xPosition)
  }
}

private struct EmploymentTooltipWidthPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

// MARK: - Tooltip View

/// Tooltip showing month name and employment percentage
private struct TooltipView: View {
  let monthData: EmploymentMonthlyData

  var body: some View {
    VStack(alignment: .center, spacing: Spacing.xxs) {
      Text(monthData.fullMonth)
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexTextPrimary)

      HStack(spacing: Spacing.xxs) {
        Text(EmploymentPercentageChart.formatPercent(monthData.averagePercentage))
          .font(.tidexMonoBody)
          .foregroundColor(.tidexBlue)

        Text(.statsChartsEmploymentEmployment)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextMuted)
      }
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

// MARK: - Info Popover Button

/// Info button that shows a popover with explanatory text
private struct InfoPopoverButton: View {
  let message: String

  @State private var showPopover = false

  var body: some View {
    Button {
      showPopover.toggle()
    } label: {
      Image(systemName: "info.circle")
        .font(.tidexBody)
        .foregroundColor(.tidexTextMuted)
    }
    .popover(isPresented: $showPopover) {
      Text(message)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .frame(maxWidth: 280)
        .presentationCompactAdaptation(.popover)
    }
  }
}

// MARK: - Empty State

/// Empty state when no employment data is available
struct EmploymentPercentageChartEmpty: View {

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.statsChartsEmploymentTitle)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

      Text(.statsChartsEmploymentNoData)
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
      EmploymentPercentageChart(data: EmploymentData.preview)
      EmploymentPercentageChartEmpty()
    }
    .padding()
  }
  .background(Color.tidexBackground)
}
