import SwiftUI

/// Twelve rows, one per month, each with a bar for the year's pay and a tick for the same month a
/// year earlier. Every layer is always present, so a year change moves bars and ticks in place.
struct StatsMonthsSection: View {
  let months: StatsYearLattice.Months
  let onSelectMonth: (Int) -> Void

  @Environment(\.userCurrency) private var currency

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      StatsSectionHeader(title: .statsMonthsTitle, sentence: headline) { legend }
      VStack(spacing: 0) {
        ForEach(months.rows) { row in
          StatsMonthRow(
            row: row, year: months.year, yMax: months.yMax, onSelect: onSelectMonth)
        }
      }
      .padding(.top, StatsRhythm.headerToBody)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(Text(.statsMonthsTitle))
      .accessibilityChartDescriptor(chartDescriptor)
      .accessibilityIdentifier("stats.yearpage.months")
    }
  }

  private var legend: some View {
    HStack(spacing: Spacing.xxs) {
      RoundedRectangle(cornerRadius: 2, style: .continuous)
        .fill(Color.tidexBlue)
        .frame(width: 12, height: 8)
        .accessibilityHidden(true)
      Text(verbatim: String(months.year))
        .padding(.trailing, Spacing.xxs)
      Rectangle()
        .fill(Color.tidexTextMuted)
        .frame(width: 2, height: 12)
        .accessibilityHidden(true)
      Text(verbatim: String(months.year - 1))
    }
    .fontWeight(.regular)
    .monospacedDigit()
    .fixedSize()
  }

  private var headline: AttributedString {
    switch months.headline {
    case .noPay(let year):
      return StatsFormat.plain(
        String(localized: .statsNoPayIn(String(year))), color: .tidexTextMuted)
    case .best(let month, let amount):
      let name = StatsFormat.monthName(FocusMonth(year: months.year, month: month))
      return StatsFormat.plain(String(localized: .statsMonthsBest(name, money(amount))))
    case .tied(let perPaidMonth):
      return StatsFormat.plain(String(localized: .statsYearPerMonth(money(perPaidMonth))))
    }
  }

  private func money(_ amount: Double) -> String {
    StatsFormat.money(amount, currency: currency)
  }

  private var chartDescriptor: StatsCategoryChartDescriptor {
    StatsCategoryChartDescriptor(
      title: String(localized: .statsChartsYearlyIncomeTitle(String(months.year))),
      summary: String(headline.characters),
      categoryAxisTitle: String(localized: .commonMonth),
      valueAxisTitle: String(localized: .shiftsEarningsSection),
      points: months.rows.map { row in
        let name = StatsFormat.monthName(FocusMonth(year: months.year, month: row.id))
        return StatsCategoryChartDescriptor.Point(
          category: name, value: row.earnings, label: "\(name), \(money(row.earnings))")
      },
      formatValue: { [currency] in StatsFormat.money($0, currency: currency) }
    )
  }
}

private struct StatsMonthRow: View {
  static let monthColumnWidth: CGFloat = 52
  static let totalColumnWidth: CGFloat = 75
  private static let barHeight: CGFloat = 12
  private static let tickHeight: CGFloat = 22

  let row: StatsYearLattice.MonthRow
  let year: Int
  let yMax: Double
  let onSelect: (Int) -> Void

  @Environment(\.userCurrency) private var currency

  private var month: FocusMonth { FocusMonth(year: year, month: row.id) }

  /// Pay after the real current month is only scheduled, so its bar is an outline.
  private var isOutline: Bool { row.isAhead && row.earnings > 0 }

  var body: some View {
    Button {
      onSelect(row.id)
    } label: {
      HStack(spacing: Spacing.sm) {
        monthName
        GeometryReader { proxy in
          bar(width: proxy.size.width)
        }
        total
          .frame(width: Self.totalColumnWidth, alignment: .trailing)
      }
      .frame(height: StatsRhythm.row)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(StatsFormat.monthName(month)))
    .accessibilityValue(Text(accessibilityValue))
    .accessibilityIdentifier("stats.yearpage.month.\(row.id)")
  }

  private var monthName: some View {
    Text(StatsFormat.shortMonthName(month).sentenceCased())
      .font(row.isCurrent ? .tidexCaptionStrong : .tidexCaptionRegular)
      .foregroundStyle(row.isCurrent ? Color.tidexBlueText : Color.tidexTextSecondary)
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .padding(.leading, Spacing.sm)
      .frame(width: Self.monthColumnWidth, alignment: .leading)
      .background(alignment: .leading) {
        Capsule()
          .fill(Color.tidexBlue)
          .frame(width: 3, height: 18)
          .opacity(row.isCurrent ? 1 : 0)
      }
  }

  private func bar(width: CGFloat) -> some View {
    let barWidth = row.earnings > 0 ? max(length(row.earnings, in: width), 3) : 0
    let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
    return ZStack(alignment: .leading) {
      Circle()
        .fill(Color.tidexTextMuted)
        .frame(width: 4, height: 4)
        .opacity(row.earnings > 0 ? 0 : 0.82)
      shape
        .fill(Color.tidexBlue)
        .frame(width: barWidth, height: Self.barHeight)
        .opacity(isOutline ? 0 : 1)
      shape
        .stroke(Color.tidexBlueText, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
        .frame(width: barWidth, height: Self.barHeight)
        .opacity(isOutline ? 1 : 0)
      Capsule()
        .fill(Color.tidexTextMuted)
        .frame(width: 2, height: Self.tickHeight)
        .offset(x: length(row.previousEarnings, in: width) - 1)
        .opacity(row.previousEarnings > 0 ? 1 : 0)
    }
    .frame(width: width, height: StatsRhythm.row, alignment: .leading)
    .accessibilityHidden(true)
  }

  private func length(_ amount: Double, in width: CGFloat) -> CGFloat {
    yMax > 0 ? CGFloat(min(amount / yMax, 1)) * width : 0
  }

  private var total: some View {
    HStack(spacing: Spacing.micro) {
      Image(systemName: "star.fill")
        .font(.tidexMicro)
        .opacity(row.isBest ? 1 : 0)
        .accessibilityHidden(true)
      Text(row.earnings > 0 ? StatsFormat.money(row.earnings, currency: currency) : "–")
        .fontWeight(row.isBest ? .semibold : .regular)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
    .font(.tidexFootnote)
    .foregroundStyle(totalColor)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }

  private var totalColor: Color {
    if row.isBest { return .tidexTextPrimary }
    return row.earnings > 0 ? .tidexTextSecondary : .tidexTextMuted
  }

  private var accessibilityValue: String {
    var parts = [
      StatsFormat.money(row.earnings, currency: currency),
      String(localized: .statsWeeksHours(StatsFormat.hours(row.hours))),
      String(localized: .commonShiftCount(row.shifts)),
      String(
        localized: .statsYearTotal(
          StatsFormat.money(row.previousEarnings, currency: currency), String(year - 1))),
    ]
    if row.isBest {
      parts.append(String(localized: .statsAccessibilityBestMonth))
    }
    if row.isCurrent {
      parts.append(String(localized: .statsAccessibilityThisMonth))
    }
    return parts.joined(separator: ", ")
  }
}

/// The year's employment on its own, with no focus month.
struct StatsYearEmploymentSection: View {
  let employment: StatsLattice.EmploymentYear
  let currentMonth: Int?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      StatsSectionHeader(
        title: .statsEmploymentTitle,
        sentence: employment.average.text(sentenceCased: true)
      ) {
        StatsEmploymentInfoButton(fullTimeHoursPerWeek: employment.fullTimeHoursPerWeek)
      }
      VStack(spacing: Spacing.sm) {
        StatsMonthLetters(focus: nil, currentMonth: currentMonth)
        StatsEmploymentRow(employment: employment)
      }
      .padding(.leading, StatsScaleLabel.gutter)
      .padding(.top, StatsRhythm.headerToBody)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("stats.yearpage.employment")
  }
}
