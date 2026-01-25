import SwiftUI
import Charts

/// Chart showing employment percentage across the year
/// Displays monthly average employment percentages with yearly average header
struct EmploymentPercentageChart: View {
    let data: EmploymentData

    @Environment(\.localization) private var localization

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
            return months // All zeros, return as-is
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

    /// Y-axis scale calculation
    private var yAxisScale: (domain: ClosedRange<Double>, ticks: [Double]) {
        let percentages = filteredData.map(\.averagePercentage)
        let positivePercentages = percentages.filter { $0 > 0 }

        guard !positivePercentages.isEmpty else {
            return (0...100, [0, 25, 50, 75, 100])
        }

        let maxPercentage = percentages.max() ?? 0

        // Add 15% padding above max, ensure at least 80% shown
        let upperBound = max(maxPercentage * 1.15, 80)

        // Build nice scale starting from 0
        let (niceDomain, ticks) = buildNiceScale(min: 0, max: upperBound, desiredTicks: 5)
        return (niceDomain, ticks)
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
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.tidexBorderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Header View

    @ViewBuilder
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(localization.string("stats.charts.employment.title"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            HStack(alignment: .firstTextBaseline) {
                // Yearly average percentage
                if let average = data.yearlyAverage {
                    Text(String(format: "%.1f%%", average))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.tidexTextPrimary)
                } else {
                    Text("---")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.tidexTextMuted)
                }

                Text(localization.string("stats.charts.employment.yearlyAverage"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextMuted)

                Spacer()

                // Info button
                InfoPopoverButton(
                    message: localization.string("stats.charts.employment.info")
                )
            }
        }
        .padding(20)
        .padding(.bottom, -4)
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
                .cornerRadius(6)
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
                        let isHighlighted = monthData?.monthNumber == currentMonth && monthData?.year == currentYear
                        let isSelected = selectedMonth == monthData?.monthNumber

                        Text(label)
                            .font(.system(size: 12, weight: (isHighlighted || isSelected) ? .semibold : .regular))
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
                            .font(.system(size: 14))
                            .foregroundColor(.tidexTextPrimary)
                    }
                }
            }
        }
        .chartYScale(domain: yAxisScale.domain)
        .chartLegend(.hidden)
        .frame(height: 200)
        .padding(20)
        .padding(.top, 4)
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

    /// Build a nice scale for the Y-axis
    private func buildNiceScale(min: Double, max: Double, desiredTicks: Int) -> (ClosedRange<Double>, [Double]) {
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
}

// MARK: - Chart Overlay Content

/// Separate struct to avoid compiler complexity issues with chartOverlay
private struct ChartOverlayContent: View {
    let proxy: ChartProxy
    let data: [EmploymentMonthlyData]
    @Binding var selectedMonth: Int?

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
                    TooltipView(monthData: tooltipData.monthData)
                        .position(x: tooltipData.xPosition, y: 30)
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

    private func tooltipData(plotFrame: CGRect) -> (monthData: EmploymentMonthlyData, xPosition: CGFloat)? {
        guard let selected = selectedMonth,
              let monthData = data.first(where: { $0.monthNumber == selected }),
              let index = data.firstIndex(where: { $0.monthNumber == selected }) else {
            return nil
        }

        let barWidth = plotFrame.width / CGFloat(data.count)
        let xPosition = plotFrame.origin.x + barWidth * (CGFloat(index) + 0.5)

        return (monthData: monthData, xPosition: xPosition)
    }
}

// MARK: - Tooltip View

/// Tooltip showing month name and employment percentage
private struct TooltipView: View {
    let monthData: EmploymentMonthlyData

    @Environment(\.localization) private var localization

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(monthData.fullMonth)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            HStack(spacing: 4) {
                Text(String(format: "%.1f%%", monthData.averagePercentage))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.tidexBlue)

                Text(localization.string("stats.charts.employment.employment"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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
                .font(.system(size: 18))
                .foregroundColor(.tidexTextMuted)
        }
        .popover(isPresented: $showPopover) {
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .padding()
                .frame(maxWidth: 280)
                .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Empty State

/// Empty state when no employment data is available
struct EmploymentPercentageChartEmpty: View {
    @Environment(\.localization) private var localization

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.string("stats.charts.employment.title"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            Text(localization.string("stats.charts.employment.noData"))
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.tidexTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.tidexBorderSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            EmploymentPercentageChart(data: EmploymentData.preview)
            EmploymentPercentageChartEmpty()
        }
        .padding()
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
