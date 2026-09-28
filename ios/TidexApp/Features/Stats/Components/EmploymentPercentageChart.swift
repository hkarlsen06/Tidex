import Charts
import SwiftUI

/// Chart showing employment percentage across the year
/// Displays monthly average employment percentages with a completed-month average header
struct EmploymentPercentageChart: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order
  let data: EmploymentData  // swiftlint:disable:this explicit_acl

  /// Currently selected month label (for tooltip)
  @State private var selectedMonth: String?

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
      return String(localized: .statsChartsEmploymentCompletedAverageEmpty)
    }

    return String(localized: .statsChartsEmploymentCompletedAverageRange(rangeLabel))
  }

  /// Filter out leading and trailing months that are neither worked nor contextually relevant.
  private var filteredData: [EmploymentMonthlyData] {
    let months = data.monthlyData  // swiftlint:disable:this explicit_type_interface

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
    guard let selected = selectedMonth else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return data.monthlyData.first { $0.month == selected }
  }

  // MARK: - Body

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(spacing: 0) {
      // Header with completed-month average
      headerView

      // Chart
      chartView
    }
    .statsPanelSurface(padding: 0)
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
            .foregroundColor(.tidexEmploymentAccent)
        } else {
          Text("--")
            .font(.tidexMonoBody)
            .foregroundColor(.tidexEmploymentAccent)
        }

        Text(completedAverageSubtitle)
          .font(.tidexLabel)
          .foregroundColor(.tidexEmploymentAccent)

        Spacer()

        // Info button - show actual hours used (37.5 or 40)
        InfoPopoverButton(
          message: String(
            localized: .statsChartsEmploymentInfo(formatHours(data.fullTimeHoursPerWeek)))  // swiftlint:disable:this line_length multiline_arguments_brackets
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
        .foregroundStyle(barColor(for: month, isSelected: selectedMonth == month.month))
        .cornerRadius(CornerRadius.xs)
        .annotation(
          position: .top,
          overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
        ) {
          if selectedMonth == month.month {
            TooltipView(monthData: month)
          }
        }
      }
    }
    .chartOverlay { proxy in
      CompletedAverageOutlineOverlay(
        proxy: proxy,
        data: filteredData,
        outlinedMonths: Set(
          filteredData
            .filter { data.isIncludedInCompletedAverage($0) }
            .map(\.month)
        )
      )
    }
    .chartXSelection(value: $selectedMonth)
    .onChange(of: selectedMonth) { _, newValue in
      selectedMonth = ChartSelectionSnapping.nearestNonZero(
        to: newValue,
        in: filteredData.map { (key: $0.month, value: $0.averagePercentage) }
      )
    }
    .chartXAxis {
      AxisMarks(values: .automatic) { value in
        AxisValueLabel {
          if let label = value.as(String.self) {
            let monthData = filteredData.first(where: { $0.month == label })  // swiftlint:disable:this explicit_type_interface line_length
            let isIncluded =  // swiftlint:disable:this explicit_type_interface
              monthData.map { data.isIncludedInCompletedAverage($0) } ?? false
            let isCurrentMonth =  // swiftlint:disable:this explicit_type_interface
              monthData?.monthNumber == currentMonth && monthData?.year == currentYear
            let isSelected = selectedMonth == label  // swiftlint:disable:this explicit_type_interface
            let isEmphasized = isIncluded || isCurrentMonth || isSelected  // swiftlint:disable:this explicit_type_interface line_length

            Text(label)
              .font(isEmphasized ? .tidexCaptionStrong : .tidexCaptionRegular)
              .foregroundColor(
                axisLabelColor(
                  isIncluded: isIncluded,
                  isCurrentMonth: isCurrentMonth,
                  isSelected: isSelected
                ))  // swiftlint:disable:this multiline_arguments_brackets
          }
        }
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))  // swiftlint:disable:this no_magic_numbers
          .foregroundStyle(Color.tidexSeparator)
        AxisValueLabel {
          if let amount = value.as(Double.self) {
            Text("\(Int(amount))%")
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextPrimary)
          }
        }
      }
    }
    .chartYScale(domain: 0...100)
    .chartLegend(.hidden)
    .frame(height: 200)  // swiftlint:disable:this no_magic_numbers
    .padding(Spacing.mlg)
    .padding(.top, Spacing.xxs)
  }

  // MARK: - Helpers

  /// Get bar color based on completed-month average inclusion and selection state
  private func barColor(for month: EmploymentMonthlyData, isSelected: Bool) -> Color {  // swiftlint:disable:this line_length type_contents_order
    // Selected bars are always full color
    if isSelected {
      return .tidexBlue
    }

    // Months included in the average are highlighted.
    if data.isIncludedInCompletedAverage(month) {
      return .tidexBlue.opacity(0.16)  // swiftlint:disable:this no_magic_numbers
    }

    // Current month is highlighted, but not treated as part of the average.
    let isCurrentMonth = month.monthNumber == currentMonth && month.year == currentYear  // swiftlint:disable:this explicit_type_interface line_length
    return isCurrentMonth ? .tidexBlue : .tidexBlue.opacity(0.16)  // swiftlint:disable:this no_magic_numbers
  }

  private func axisLabelColor(  // swiftlint:disable:this type_contents_order
    isIncluded: Bool,
    isCurrentMonth: Bool,
    isSelected: Bool
  ) -> Color {
    if isIncluded {
      return .tidexEmploymentAccent
    }
    if isCurrentMonth || isSelected {
      return .tidexBlue
    }
    return .tidexTextPrimary
  }

  /// Format hours for display (e.g., "37,50" or "40,00")
  private func formatHours(_ hours: Double) -> String {  // swiftlint:disable:this type_contents_order
    hours.formatted(.number.precision(.fractionLength(2)).locale(Locale.appLocale))  // swiftlint:disable:this line_length no_magic_numbers
  }

  /// Format percentage for display (e.g., "85,5%")
  fileprivate static func formatPercent(_ value: Double) -> String {  // swiftlint:disable:this strict_fileprivate
    value.formatted(.number.precision(.fractionLength(1)).locale(Locale.appLocale)) + "%"
  }
}

// MARK: - Completed Average Outline Overlay

/// Draws an accent outline around bars for months included in the completed-months average.
/// Kept as a `chartOverlay` because Swift Charts marks have no native stroke/border modifier.
private struct CompletedAverageOutlineOverlay: View {
  let proxy: ChartProxy
  let data: [EmploymentMonthlyData]
  let outlinedMonths: Set<String>

  var body: some View {
    GeometryReader { geometry in
      let plotFrame: CGRect = proxy.plotFrame.map { geometry[$0] } ?? .zero

      ForEach(data.filter { outlinedMonths.contains($0.month) }) { month in
        if let outlineFrame = barOutlineFrame(for: month, plotFrame: plotFrame) {
          UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
              topLeading: CornerRadius.xs,
              bottomLeading: 0,
              bottomTrailing: 0,
              topTrailing: CornerRadius.xs
            )
          )
          .stroke(Color.tidexEmploymentAccent, lineWidth: 1.5)  // swiftlint:disable:this no_magic_numbers
          .frame(width: outlineFrame.width, height: outlineFrame.height)
          .position(x: outlineFrame.midX, y: outlineFrame.midY)
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

    let barSlotWidth = plotFrame.width / CGFloat(data.count)  // swiftlint:disable:this explicit_type_interface
    let barWidth = barSlotWidth * 0.62  // swiftlint:disable:this explicit_type_interface no_magic_numbers
    let topY = plotFrame.minY + yPosition  // swiftlint:disable:this explicit_type_interface
    let height = max(plotFrame.maxY - topY, 0)  // swiftlint:disable:this explicit_type_interface
    let centerX = plotFrame.minX + xPosition  // swiftlint:disable:this explicit_type_interface

    return CGRect(
      x: centerX - barWidth / 2,  // swiftlint:disable:this no_magic_numbers
      y: topY,
      width: barWidth,
      height: height
    )
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
    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)  // swiftlint:disable:this no_magic_numbers
  }
}

// MARK: - Info Popover Button

/// Info button that shows a popover with explanatory text
private struct InfoPopoverButton: View {
  let message: String

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass  // swiftlint:disable:this explicit_type_interface
  @State private var showPopover = false  // swiftlint:disable:this explicit_type_interface

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
      Image(systemName: "info.circle")  // swiftlint:disable:this accessibility_label_for_image
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
        .frame(maxWidth: 280)  // swiftlint:disable:this no_magic_numbers
    }
    .alert(Text(.statsChartsEmploymentTitle), isPresented: alertBinding) {
      Button(String(localized: .commonDone), role: .cancel) {}  // swiftlint:disable:this no_empty_block
    } message: {
      Text(message)
    }
  }
}

// MARK: - Empty State

/// Empty state when no employment data is available
struct EmploymentPercentageChartEmpty: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.statsChartsEmploymentTitle)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

      Text(.statsChartsEmploymentNoData)
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
      EmploymentPercentageChart(data: EmploymentData.preview)
      EmploymentPercentageChartEmpty()
    }
    .padding()
  }
  .background(Color.tidexBackground)
}
