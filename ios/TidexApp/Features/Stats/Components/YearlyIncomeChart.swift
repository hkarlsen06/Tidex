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
          .annotation(
            position: .top,
            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
          ) {
            if selectedMonth == month.month {
              YearlyTooltipView(monthData: month, currency: currency)
            }
          }
        }
      }
      .chartXSelection(value: $selectedMonth)
      .onChange(of: selectedMonth) { _, newValue in
        selectedMonth = ChartSelectionSnapping.nearestNonZero(
          to: newValue,
          in: trimmedData.map { (key: $0.month, value: $0.earnings) }
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
        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))  // swiftlint:disable:this no_magic_numbers
            .foregroundStyle(Color.tidexSeparator)
          AxisValueLabel(
            format: FloatingPointFormatStyle<Double>.number
              .notation(.compactName)
              .precision(.fractionLength(0...1))
              .locale(.appLocale)
          )
          .font(.tidexCaptionRegular)
          .foregroundStyle(Color.tidexTextPrimary)
        }
      }
      .chartYScale(domain: .automatic(includesZero: true))
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
