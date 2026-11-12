import SwiftUI

/// Places the month on screen in its year: how its pay stands against the other months and the
/// year's average, with the year as the backdrop.
struct StatsYearSection: View {
  let year: StatsLattice.Year
  let onSelectMonth: (Int) -> Void

  @Environment(\.userCurrency) private var currency
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private static let incomeHeight: CGFloat = 148
  private static let incomeTop: CGFloat = 14

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      StatsSectionHeader(verbatimTitle: String(year.year), sentence: headline) {
        HStack(spacing: Spacing.sm) {
          payLegend
          averageLegend
        }
      }
      chart
        .padding(.top, StatsRhythm.headerToBody + Spacing.xs)
      employmentCaption
        .padding(.top, Spacing.lg + Spacing.xs)
    }
  }

  private var hasPay: Bool { year.total > 0 }

  /// Names the bars. The caption under the chart names the line the same way, so the legend
  /// needs no row of its own.
  private var payLegend: some View {
    HStack(spacing: Spacing.xxs) {
      HStack(alignment: .bottom, spacing: 2) {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
          .fill(StatsIncomeBar.restColor)
          .frame(width: 4, height: 7)
        RoundedRectangle(cornerRadius: 1, style: .continuous)
          .fill(Color.tidexBlue)
          .frame(width: 4, height: 11)
      }
      .accessibilityHidden(true)
      Text(.statsLegendPay)
        .fontWeight(.regular)
    }
    .fixedSize()
    .opacity(hasPay ? 1 : 0)
    .accessibilityHidden(!hasPay)
  }

  private var averageLegend: some View {
    HStack(spacing: Spacing.xxs) {
      StatsRule(lineY: 1)
        .stroke(Color.tidexTextSecondary, style: Self.averageStroke)
        .frame(width: 14, height: 2)
        .accessibilityHidden(true)
      Text(
        StatsFormat.emphasized(
          .statsYearAverageAll(money(year.perPaidMonth ?? 0)), color: .tidexTextSecondary)
      )
      .fontWeight(.regular)
      .monospacedDigit()
    }
    .fixedSize()
    .opacity(year.perPaidMonth == nil ? 0 : 1)
    .accessibilityHidden(year.perPaidMonth == nil)
  }

  private static let averageStroke: StrokeStyle = StrokeStyle(
    lineWidth: 1.5, lineCap: .round, dash: [1, 4])

  private func incomeY(_ amount: Double) -> CGFloat {
    let share = year.yMax > 0 ? min(amount / year.yMax, 1) : 0
    return Self.incomeHeight - CGFloat(share) * (Self.incomeHeight - Self.incomeTop)
  }

  /// Employment shares the pay plot on a scale of its own, from the baseline to the top line.
  private static let employmentScale: StatsEmploymentScale = StatsEmploymentScale(
    height: incomeHeight, top: incomeTop, bottom: incomeHeight - 0.5)

  private var chart: some View {
    VStack(spacing: Spacing.sm) {
      incomeRow
      StatsMonthLetters(focus: year.focus, currentMonth: year.currentMonth)
    }
    .background { playhead }
    .overlay { monthButtons }
    .padding(.horizontal, StatsScaleLabel.gutter)
    .overlay(alignment: .top) { scaleLabels }
  }

  /// Pay on the left and employment on the right, each in line with the top line and in the
  /// color of what it measures.
  private var scaleLabels: some View {
    HStack(spacing: 0) {
      StatsScaleLabel(
        text: StatsFormat.compact(year.yMax), lineY: Self.incomeTop, alignment: .trailing
      )
      .opacity(hasPay ? 1 : 0)
      Spacer(minLength: 0)
      StatsScaleLabel(
        text: StatsFormat.percent(100), color: .tidexEmploymentAccent, lineY: Self.incomeTop,
        alignment: .leading
      )
      .opacity(year.employment.hasShifts ? 1 : 0)
    }
  }

  /// Moves one column on a month change. On a year change it fades out and back in at the new
  /// column instead of sweeping across the year.
  private var playhead: some View {
    GeometryReader { proxy in
      let column = proxy.size.width / CGFloat(StatsLattice.monthSlots)
      let bandX = CGFloat(year.focus - 1) * column + 1
      RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
        .fill(Color.tidexSeparator)
        .frame(width: max(column - 2, 0), height: proxy.size.height + Spacing.md)
        .offset(x: bandX, y: -Spacing.xs)
        .motionProbe("stats-playhead", bandX)
        .id(year.year)
        .transition(.opacity)
    }
    .accessibilityHidden(true)
  }

  private var incomeRow: some View {
    ZStack(alignment: .topLeading) {
      // A year with no pay has no scale, so it keeps only the baseline and the month letters.
      Group {
        StatsRule(lineY: Self.incomeTop)
          .stroke(Color.tidexSeparator, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
        HStack(alignment: .bottom, spacing: 0) {
          ForEach(year.months) { month in
            StatsIncomeBar(month: month, height: barHeight(month), isFocus: month.id == year.focus)
              .frame(maxWidth: .infinity)
          }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        StatsRule(lineY: incomeY(year.perPaidMonth ?? 0))
          .stroke(Color.tidexTextSecondary, style: Self.averageStroke)
      }
      .opacity(hasPay ? 1 : 0)
      StatsRule(lineY: Self.incomeHeight - 0.5)
        .stroke(Color.tidexSeparator, lineWidth: 1)
      StatsEmploymentMarks(
        employment: year.employment, scale: Self.employmentScale,
        lineColor: .tidexEmploymentAccent, marksEmptyMonths: false)
    }
    .frame(height: Self.incomeHeight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(.statsChartsYearlyIncomeTitle(String(year.year))))
    .accessibilityChartDescriptor(incomeDescriptor)
    .accessibilityIdentifier("stats.year.income")
  }

  private func barHeight(_ month: StatsLattice.MonthSlot) -> CGFloat {
    let share = year.yMax > 0 ? month.earnings / year.yMax : 0
    return max(CGFloat(share) * (Self.incomeHeight - Self.incomeTop), 2)
  }

  private var monthButtons: some View {
    HStack(spacing: 0) {
      ForEach(year.months) { month in
        Button {
          guard month.id != year.focus else { return }
          Haptics.play(.selection)
          onSelectMonth(month.id)
        } label: {
          Color.clear
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          Text(StatsFormat.monthName(FocusMonth(year: year.year, month: month.id)))
        )
        .accessibilityValue(Text(accessibilityValue(month)))
        .accessibilityAddTraits(month.id == year.focus ? .isSelected : [])
      }
    }
  }

  private var employmentCaption: some View {
    HStack(spacing: Spacing.xs) {
      StatsEmploymentSwatch()
      Text(employmentText)
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
      StatsEmploymentInfoButton(fullTimeHoursPerWeek: year.employment.fullTimeHoursPerWeek)
    }
    .statsSlot(lines: dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    .font(.tidexFootnote)
    .foregroundStyle(Color.tidexTextSecondary)
  }

  // MARK: Copy

  private func money(_ amount: Double) -> String {
    StatsFormat.money(amount, currency: currency)
  }

  private var headline: AttributedString {
    switch year.standing {
    case .noPayInYear:
      return StatsFormat.plain(
        String(localized: .statsNoPayIn(String(year.year))), color: .tidexTextMuted)
    case .noPayInMonth:
      let month = StatsFormat.monthName(FocusMonth(year: year.year, month: year.focus))
      return StatsFormat.plain(String(localized: .statsNoPayIn(month)), color: .tidexTextMuted)
    case .nothingPlanned:
      return StatsFormat.plain(String(localized: .statsHeroNothingPlanned), color: .tidexTextMuted)
    case .best:
      return StatsFormat.plain(String(localized: .statsStandingBest))
    case .againstAverage(let difference):
      // A weak month is not drawn as a failure, so only the month above average gets a color.
      return difference >= 0
        ? StatsFormat.emphasized(.statsStandingAbove(money(difference)), color: .tidexSuccess)
        : StatsFormat.emphasized(.statsStandingBelow(money(-difference)), color: .tidexTextPrimary)
    }
  }

  private var employmentText: AttributedString {
    let value = employment(month: year.focus)?.percent.map { StatsFormat.percent($0.rounded()) }
    let month = StatsFormat.shortMonthName(FocusMonth(year: year.year, month: year.focus))
    let focusPart = StatsFormat.emphasized(
      .statsYearEmployment(value ?? "–", month), color: .tidexTextPrimary)
    return focusPart + AttributedString(" · ") + year.employment.average.text()
  }

  private func employment(month: Int) -> StatsLattice.Employment? {
    let months = year.employment.months
    return months.indices.contains(month - 1) ? months[month - 1] : nil
  }

  private func accessibilityValue(_ month: StatsLattice.MonthSlot) -> String {
    let pay = money(month.earnings)
    guard let percent = employment(month: month.id)?.percent else { return pay }
    let share = StatsFormat.percent(percent)
    return "\(pay), \(share) \(String(localized: .statsChartsEmploymentEmployment))"
  }

  private var incomeDescriptor: StatsCategoryChartDescriptor {
    StatsCategoryChartDescriptor(
      title: String(localized: .statsChartsYearlyIncomeTitle(String(year.year))),
      summary: String(headline.characters),
      categoryAxisTitle: String(localized: .commonMonth),
      valueAxisTitle: String(localized: .shiftsEarningsSection),
      points: year.months.map { month in
        let name = StatsFormat.monthName(FocusMonth(year: year.year, month: month.id))
        return StatsCategoryChartDescriptor.Point(
          category: name, value: month.earnings, label: "\(name), \(money(month.earnings))")
      },
      formatValue: { [currency] in StatsFormat.money($0, currency: currency) }
    )
  }
}

private struct StatsIncomeBar: View {
  let month: StatsLattice.MonthSlot
  let height: CGFloat
  let isFocus: Bool

  /// Pay is blue on this screen, so the months around the shown one are a quieter blue. Grey
  /// read as the dull series beside the coloured employment line.
  static let restColor: Color = Color.tidexBlue.opacity(0.5)

  private var isOutline: Bool { month.isAhead && month.earnings > 0 }

  /// A month with no pay keeps a grey stub.
  private var restColor: Color { month.earnings > 0 ? Self.restColor : .tidexBorder }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: min(3, height / 2), style: .continuous)
    ZStack {
      shape
        .fill(isFocus ? Color.tidexBlue : restColor)
        .opacity(isOutline ? 0 : 1)
      shape
        .stroke(
          isFocus ? Color.tidexBlueText : restColor,
          style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])
        )
        .opacity(isOutline ? 1 : 0)
    }
    .frame(width: 16, height: height)
  }
}

/// The month letters under a year's columns. The focus month is bold and the real current
/// month has a blue mark.
struct StatsMonthLetters: View {
  let focus: Int?
  let currentMonth: Int?

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(StatsFormat.monthLetters.enumerated()), id: \.offset) { index, letter in
        Text(letter)
          .fontWeight(index + 1 == focus ? .bold : .medium)
          .foregroundStyle(index + 1 == focus ? Color.tidexTextPrimary : Color.tidexTextMuted)
          .frame(maxWidth: .infinity)
          .overlay(alignment: .bottom) {
            Capsule()
              .fill(Color.tidexBlueText)
              .frame(width: 10, height: 2)
              .offset(y: 2)
              .opacity(index + 1 == currentMonth ? 1 : 0)
          }
      }
    }
    .statsSlot()
    .font(.tidexMicro)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .accessibilityHidden(true)
  }
}

struct StatsRule: Shape {
  var lineY: CGFloat

  nonisolated var animatableData: CGFloat {
    get { lineY }
    set { lineY = newValue }
  }

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: lineY))
    path.addLine(to: CGPoint(x: rect.maxX, y: lineY))
    return path
  }
}
