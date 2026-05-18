import Charts
import SwiftUI

/// Chart showing employment percentage across the year
/// Displays monthly average employment percentages with a completed-month average header
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

  private var completedAverageSubtitle: String {
    guard let rangeLabel = data.completedAverageRangeLabel() else {
      return String(localized: "stats.charts.employment.completedAverage.empty")
    }

    return String(
      format: String(localized: "stats.charts.employment.completedAverage.range"),
      rangeLabel
    )
  }

  /// Filter out leading and trailing months that are neither worked nor contextually relevant.
  private var filteredData: [EmploymentMonthlyData] {
    let months = data.monthlyData

    func shouldDisplay(_ month: EmploymentMonthlyData) -> Bool {
      month.averagePercentage > 0
        || data.isIncludedInCompletedAverage(month)
        || (month.monthNumber == currentMonth && month.year == currentYear)
    }

    guard let firstDisplayIndex = months.firstIndex(where: shouldDisplay) else {
      return months  // All zeros with no completed/current context, return as-is
    }
    guard let lastDisplayIndex = months.lastIndex(where: shouldDisplay) else {
      return months
    }
    return Array(months[firstDisplayIndex...lastDisplayIndex])
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
      // Header with completed-month average
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
        // Average percentage for completed months
        if let average = data.completedMonthsAverage() {
          Text(Self.formatPercent(average))
            .font(.tidexMonoDisplay)
            .foregroundColor(.tidexPurple)
        } else {
          Text("--")
            .font(.tidexMonoBody)
            .foregroundColor(.tidexPurple)
        }

        Text(completedAverageSubtitle)
          .font(.tidexLabel)
          .foregroundColor(.tidexPurple)

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
        outlinedMonthNumbers: Set(
          filteredData
            .filter { data.isIncludedInCompletedAverage($0) }
            .map(\.monthNumber)
        ),
        selectedMonth: $selectedMonth
      )
    }
    .chartXAxis {
      AxisMarks(values: .automatic) { value in
        AxisValueLabel {
          if let label = value.as(String.self) {
            let monthData = filteredData.first(where: { $0.month == label })
            let isIncluded =
              monthData.map { data.isIncludedInCompletedAverage($0) } ?? false
            let isCurrentMonth =
              monthData?.monthNumber == currentMonth && monthData?.year == currentYear
            let isSelected = selectedMonth == monthData?.monthNumber
            let isEmphasized = isIncluded || isCurrentMonth || isSelected

            Text(label)
              .font(isEmphasized ? .tidexCaptionStrong : .tidexCaptionRegular)
              .foregroundColor(
                axisLabelColor(
                  isIncluded: isIncluded,
                  isCurrentMonth: isCurrentMonth,
                  isSelected: isSelected
                ))
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

  /// Get bar color based on completed-month average inclusion and selection state
  private func barColor(for month: EmploymentMonthlyData, isSelected: Bool) -> Color {
    // Selected bars are always full color
    if isSelected {
      return .tidexBlue
    }

    // Months included in the average are highlighted.
    if data.isIncludedInCompletedAverage(month) {
      return .tidexBlue.opacity(0.16)
    }

    // Current month is highlighted, but not treated as part of the average.
    let isCurrentMonth = month.monthNumber == currentMonth && month.year == currentYear
    return isCurrentMonth ? .tidexBlue : .tidexBlue.opacity(0.16)
  }

  private func axisLabelColor(
    isIncluded: Bool,
    isCurrentMonth: Bool,
    isSelected: Bool
  ) -> Color {
    if isIncluded {
      return .tidexPurple
    }
    if isCurrentMonth || isSelected {
      return .tidexBlue
    }
    return .tidexTextPrimary
  }

  /// Format hours for display (e.g., "37,50" or "40,00")
  private func formatHours(_ hours: Double) -> String {
    hours.formatted(.number.precision(.fractionLength(2)).locale(Locale.appLocale))
  }

  /// Format percentage for display (e.g., "85,5%")
  fileprivate static func formatPercent(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(1)).locale(Locale.appLocale)) + "%"
  }
}

// MARK: - Chart Overlay Content

/// Separate struct to avoid compiler complexity issues with chartOverlay
private struct ChartOverlayContent: View {
  let proxy: ChartProxy
  let data: [EmploymentMonthlyData]
  let outlinedMonthNumbers: Set<Int>
  @Binding var selectedMonth: Int?
  @State private var tooltipWidth: CGFloat = 0

  var body: some View {
    GeometryReader { geometry in
      let plotFrame: CGRect = proxy.plotFrame.map { geometry[$0] } ?? .zero

      ZStack {
        ForEach(data.filter { outlinedMonthNumbers.contains($0.monthNumber) }) { month in
          if let outlineFrame = barOutlineFrame(for: month, plotFrame: plotFrame) {
            UnevenRoundedRectangle(
              cornerRadii: RectangleCornerRadii(
                topLeading: CornerRadius.xs,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: CornerRadius.xs
              )
            )
            .stroke(Color.tidexPurple, lineWidth: 1.5)
            .frame(width: outlineFrame.width, height: outlineFrame.height)
            .position(x: outlineFrame.midX, y: outlineFrame.midY)
          }
        }

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

  private func barOutlineFrame(for month: EmploymentMonthlyData, plotFrame: CGRect) -> CGRect? {
    guard !data.isEmpty,
      month.averagePercentage > 0,
      let xPosition = proxy.position(forX: month.month),
      let yPosition = proxy.position(forY: month.averagePercentage)
    else {
      return nil
    }

    let barSlotWidth = plotFrame.width / CGFloat(data.count)
    let barWidth = barSlotWidth * 0.62
    let topY = plotFrame.minY + yPosition
    let height = max(plotFrame.maxY - topY, 0)
    let centerX = plotFrame.minX + xPosition

    return CGRect(
      x: centerX - barWidth / 2,
      y: topY,
      width: barWidth,
      height: height
    )
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

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var showPopover = false

  private var usesCompactPresentation: Bool {
    horizontalSizeClass == .compact
  }

  private var popoverBinding: Binding<Bool> {
    Binding(
      get: { showPopover && !usesCompactPresentation },
      set: { if !$0 { showPopover = false } }
    )
  }

  private var alertBinding: Binding<Bool> {
    Binding(
      get: { showPopover && usesCompactPresentation },
      set: { if !$0 { showPopover = false } }
    )
  }

  var body: some View {
    Button {
      showPopover.toggle()
    } label: {
      Image(systemName: "info.circle")
        .font(.tidexBody)
        .foregroundColor(.tidexTextMuted)
    }
    .buttonStyle(.plain)
    .popover(isPresented: popoverBinding) {
      Text(message)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .frame(maxWidth: 280)
    }
    .alert(Text(.statsChartsEmploymentTitle), isPresented: alertBinding) {
      Button(String(localized: .commonDone), role: .cancel) {}
    } message: {
      Text(message)
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
