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
        averageLegend
      }
      chart
        .padding(.top, StatsRhythm.headerToBody + Spacing.xs)
      employmentCaption
        .padding(.top, Spacing.lg + Spacing.xs)
    }
  }

  private var hasPay: Bool { year.total > 0 }

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

  private var chart: some View {
    VStack(spacing: Spacing.sm) {
      incomeRow
      StatsMonthLetters(focus: year.focus, currentMonth: year.currentMonth)
      StatsEmploymentRow(employment: year.employment)
    }
    .background { playhead }
    .overlay { monthButtons }
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
        Text(StatsFormat.compact(year.yMax))
          .font(.tidexMicro)
          .monospacedDigit()
          .foregroundStyle(Color.tidexTextMuted)
          .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
          .offset(y: Self.incomeTop - 15)
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
    case .best:
      return StatsFormat.plain(String(localized: .statsStandingBest))
    case .againstAverage(let difference):
      return difference >= 0
        ? StatsFormat.emphasized(.statsStandingAbove(money(difference)), color: .tidexSuccess)
        : StatsFormat.emphasized(.statsStandingBelow(money(-difference)), color: .tidexError)
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

  private var isOutline: Bool { month.isAhead && month.earnings > 0 }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: min(3, height / 2), style: .continuous)
    ZStack {
      shape
        .fill(isFocus ? Color.tidexBlue : Color.tidexBorder)
        .opacity(isOutline ? 0 : 1)
      shape
        .stroke(
          isFocus ? Color.tidexBlueText : Color.tidexBorder,
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

extension StatsLattice.EmploymentAverage {
  /// "avg 54,1% jan.–okt.", with the percent in the employment color.
  func text(sentenceCased: Bool = false) -> AttributedString {
    let resource: LocalizedStringResource
    switch self {
    case .noCompletedMonths:
      let text = String(localized: .statsYearNoCompletedMonths)
      return StatsFormat.plain(sentenceCased ? text.sentenceCased() : text)
    case .average(let average, let range?):
      resource = .statsYearAverage(StatsFormat.percent(average), range)
    case .average(let average, nil):
      resource = .statsYearAverageAll(StatsFormat.percent(average))
    }
    let text = String(localized: resource)
    return StatsFormat.emphasized(
      sentenceCased ? text.sentenceCased() : text, color: .tidexEmploymentAccent)
  }
}

struct StatsEmploymentRow: View {
  let employment: StatsLattice.EmploymentYear

  private var averageValue: Double? {
    if case .average(let value, _) = employment.average { value } else { nil }
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      StatsRule(lineY: StatsEmploymentScale.top)
        .stroke(Color.tidexSeparator, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
      StatsRule(lineY: StatsEmploymentScale.y(0))
        .stroke(Color.tidexSeparator, lineWidth: 1)
      Text(StatsFormat.percent(100))
        .font(.tidexMicro)
        .foregroundStyle(Color.tidexTextMuted)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .offset(y: StatsEmploymentScale.top - 14)
      StatsRule(lineY: StatsEmploymentScale.y(averageValue ?? 0))
        .stroke(
          Color.tidexEmploymentAccent,
          style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 4])
        )
        .opacity(averageValue == nil ? 0 : 1)
      StatsEmploymentLine(
        values: StatsVector(employment.months.map(\.value)),
        present: employment.months.map { $0 != .noShifts }
      )
      .stroke(Color.tidexTextMuted.opacity(0.8), lineWidth: 1.5)
      HStack(spacing: 0) {
        ForEach(employment.months.indices, id: \.self) { index in
          dot(employment.months[index])
        }
      }
    }
    .frame(height: StatsEmploymentScale.height)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(.statsChartsEmploymentTitle))
    .accessibilityChartDescriptor(descriptor)
    .accessibilityIdentifier("stats.year.employment")
  }

  private func dot(_ employment: StatsLattice.Employment) -> some View {
    let isCounted: Bool = if case .counted = employment { true } else { false }
    let hasShifts = employment != .noShifts
    let value = employment.value
    return ZStack(alignment: .top) {
      Circle()
        .fill(Color.tidexTextMuted)
        .frame(width: 3, height: 3)
        .offset(y: StatsEmploymentScale.y(0) - 1.5)
        .opacity(hasShifts ? 0 : 0.5)
      Circle()
        .fill(isCounted ? Color.tidexEmploymentAccent : Color.tidexBackground)
        .overlay(
          Circle().stroke(
            isCounted ? Color.tidexBackground : Color.tidexEmploymentAccent, lineWidth: 2)
        )
        .frame(width: 8, height: 8)
        .offset(y: StatsEmploymentScale.y(value) - 4)
        .opacity(hasShifts ? 1 : 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var descriptor: StatsCategoryChartDescriptor {
    StatsCategoryChartDescriptor(
      title: String(localized: .statsChartsEmploymentTitle),
      summary: averageValue.map {
        String(localized: .statsAccessibilityChartTotal(StatsFormat.percent($0)))
      },
      categoryAxisTitle: String(localized: .commonMonth),
      valueAxisTitle: String(localized: .statsChartsEmploymentTitle),
      points: employment.months.indices.map { index in
        let name = StatsFormat.monthName(FocusMonth(year: employment.year, month: index + 1))
        let value = employment.months[index].value
        return StatsCategoryChartDescriptor.Point(
          category: name, value: value, label: "\(name), \(StatsFormat.percent(value))")
      },
      formatValue: { StatsFormat.percent($0) }
    )
  }
}

private struct StatsEmploymentLine: Shape {
  var values: StatsVector
  let present: [Bool]

  nonisolated var animatableData: StatsVector {
    get { values }
    set { values = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let column = rect.width / CGFloat(StatsLattice.monthSlots)
    var path = Path()
    for index in present.indices.dropLast() where present[index] && present[index + 1] {
      path.move(
        to: CGPoint(x: (CGFloat(index) + 0.5) * column, y: StatsEmploymentScale.y(values[index])))
      path.addLine(
        to: CGPoint(
          x: (CGFloat(index) + 1.5) * column, y: StatsEmploymentScale.y(values[index + 1])))
    }
    return path
  }
}

private enum StatsEmploymentScale {
  static let height: CGFloat = 92
  /// Leaves room for the "100%" label under the month letters.
  static let top: CGFloat = 24

  static func y(_ percent: Double) -> CGFloat {
    top + (1 - CGFloat(min(max(percent, 0), 100) / 100)) * (height - top - 6)
  }
}

private struct StatsRule: Shape {
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
