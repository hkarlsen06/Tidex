import SwiftUI

struct StatsWeeksSection: View {
  let weeks: StatsLattice.Weeks

  @Environment(\.userCurrency) private var currency
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var pinnedDay: Int?

  private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

  /// A month with no shifts shows the bare calendar, with no legend, sums or hint.
  private var isEmpty: Bool {
    if case .noShifts = weeks.headline { true } else { false }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      StatsSectionHeader(title: .statsWeeksTitle, sentence: headline) {
        legend
          .opacity(isEmpty ? 0 : 1)
          .accessibilityHidden(isEmpty)
      }
      weekdayHeader
        .padding(.top, StatsRhythm.headerToBody)
        .padding(.bottom, Spacing.xs)
      grid
      Text(readout)
        .monospacedDigit()
        .statsSlot(lines: isStacked ? 2 : 1)
        .font(.tidexFootnote)
        .foregroundStyle(Color.tidexTextSecondary)
        .padding(.top, Spacing.mlg)
    }
    .onChange(of: weeks.month) {
      pinnedDay = nil
    }
  }

  private var legend: some View {
    HStack(spacing: Spacing.xxs) {
      Circle()
        .fill(Color.tidexBlue)
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
      Text(.statsWeeksWorked)
        .padding(.trailing, Spacing.xxs)
      Circle()
        .strokeBorder(Color.tidexBlueText, lineWidth: 1.5)
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
      Text(.statsWeeksScheduled)
    }
    .fontWeight(.regular)
    .fixedSize()
  }

  private var weekdayHeader: some View {
    HStack(spacing: 0) {
      Text(.statsWeeksWeekColumn)
        .frame(width: StatsWeekRow.weekColumnWidth - Spacing.xs, alignment: .trailing)
        .padding(.trailing, Spacing.xs)
      ForEach(Array(StatsFormat.weekdayLetters.enumerated()), id: \.offset) { _, letter in
        Text(letter)
          .frame(maxWidth: .infinity)
      }
      Text(.statsWeeksTotalColumn)
        .frame(width: isStacked ? 0 : StatsWeekRow.totalColumnWidth, alignment: .trailing)
        .opacity(isStacked || isEmpty ? 0 : 1)
    }
    .statsSlot()
    .font(.tidexMicro.weight(.medium))
    .foregroundStyle(Color.tidexTextMuted)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .accessibilityHidden(true)
  }

  private var grid: some View {
    VStack(spacing: 0) {
      ForEach(weeks.rows) { row in
        StatsWeekRow(
          row: row, pinnedDay: pinnedDay, isStacked: isStacked, showsEmptyTotal: !isEmpty,
          onTapDay: togglePin)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(.statsWeeksTitle))
    .accessibilityChartDescriptor(chartDescriptor)
    .accessibilityIdentifier("stats.weeks.grid")
  }

  private func togglePin(_ day: Int) {
    Haptics.play(.selection)
    pinnedDay = pinnedDay == day ? nil : day
  }

  // MARK: Copy

  private var days: [DayStats] {
    weeks.rows.flatMap(\.cells).compactMap(\.dayStats)
  }

  private var headline: AttributedString {
    let month = StatsFormat.monthName(weeks.month, withYear: weeks.showsYear)
    switch weeks.headline {
    case .noShifts:
      return StatsFormat.plain(
        String(localized: .shiftsEmptyNoShiftsInMonth(month)), color: .tidexTextMuted)
    case .noPay:
      return StatsFormat.plain(String(localized: .statsNoPayIn(month)), color: .tidexTextMuted)
    case .soFar(let amount, let week):
      return StatsFormat.plain(String(localized: .statsWeeksSoFar(money(amount), week)))
    case .best(let week, let amount):
      return StatsFormat.plain(String(localized: .statsWeeksBest(week, money(amount))))
    case .busiestAhead(let week):
      return StatsFormat.plain(String(localized: .statsWeeksBusiestAhead(week)))
    case .tied(let amount):
      return StatsFormat.plain(String(localized: .statsWeeksTied(money(amount))))
    }
  }

  private var readout: String {
    if let pinnedDay, let day = days.first(where: { $0.day == pinnedDay }) {
      return dayLine(day)
    }
    switch weeks.readout {
    case .day(let day): return dayLine(day)
    case .bestDay(let day): return String(localized: .statsWeeksBestDay(payLine(day)))
    case .biggestDay(let day): return String(localized: .statsWeeksBiggestDay(payLine(day)))
    case .hint: return isEmpty ? "" : String(localized: .statsWeeksHint)
    }
  }

  private func dayLine(_ day: DayStats) -> String {
    dayParts(day).joined(separator: " · ")
  }

  private func dayParts(_ day: DayStats) -> [String] {
    let date = StatsFormat.weekdayAndDate(weeks.month, day: day.day)
    if day.shifts > 0 {
      return [
        date,
        String(localized: .commonShiftCount(day.shifts + day.otherCurrencyShifts)),
        String(localized: .statsWeeksHours(StatsFormat.hours(day.hours))),
        money(day.earnings),
      ]
    }
    if day.otherCurrencyShifts > 0 {
      return [date, String(localized: .statsWeeksOtherCurrencyShift)]
    }
    return [date, String(localized: .statsWeeksNoShift)]
  }

  private func payLine(_ day: DayStats) -> String {
    [StatsFormat.weekdayAndDate(weeks.month, day: day.day), money(day.earnings)]
      .joined(separator: " · ")
  }

  private func money(_ amount: Double) -> String {
    StatsFormat.money(amount, currency: currency)
  }

  private var chartDescriptor: StatsCategoryChartDescriptor {
    StatsCategoryChartDescriptor(
      title: String(localized: .statsWeeksTitle),
      summary: String(headline.characters),
      categoryAxisTitle: String(localized: .statsAccessibilityAxisDay),
      valueAxisTitle: String(localized: .shiftsEarningsSection),
      // A row is one VoiceOver element, so the chart carries what a tap on a day shows.
      points: days.map { day in
        StatsCategoryChartDescriptor.Point(
          category: StatsFormat.weekdayAndDate(weeks.month, day: day.day),
          value: day.earnings,
          label: dayParts(day).joined(separator: ", "))
      },
      formatValue: { [currency] in StatsFormat.money($0, currency: currency) }
    )
  }
}

private struct StatsWeekRow: View {
  static let weekColumnWidth: CGFloat = 34
  static let totalColumnWidth: CGFloat = 75

  let row: StatsLattice.WeekRow
  let pinnedDay: Int?
  let isStacked: Bool
  /// Whether a week without pay shows a dash. An empty month leaves the column blank.
  let showsEmptyTotal: Bool
  let onTapDay: (Int) -> Void

  @Environment(\.userCurrency) private var currency

  private var hasDays: Bool { row.cells.contains { $0.dayStats != nil } }

  var body: some View {
    VStack(alignment: .trailing, spacing: 0) {
      HStack(spacing: 0) {
        weekNumber
        ForEach(0..<row.cells.count, id: \.self) { column in
          StatsDayMark(
            cell: row.cells[column],
            isPinned: pinnedDay != nil && row.cells[column].dayStats?.day == pinnedDay,
            onTap: onTapDay
          )
        }
        total
          .frame(width: isStacked ? 0 : Self.totalColumnWidth, alignment: .trailing)
          .opacity(isStacked ? 0 : 1)
      }
      .frame(height: StatsRhythm.row)
      if isStacked {
        total.statsSlot(alignment: .trailing)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(.statsAccessibilityWeek(row.isoWeek)))
    .accessibilityValue(Text(accessibilityValue))
  }

  private var weekNumber: some View {
    Text(row.isoWeek, format: .number.grouping(.never))
      .font(row.isCurrent ? .tidexCaptionStrong : .tidexCaptionRegular)
      .foregroundStyle(row.isCurrent ? Color.tidexBlueText : Color.tidexTextMuted)
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .frame(width: Self.weekColumnWidth - Spacing.xs, alignment: .trailing)
      .padding(.trailing, Spacing.xs)
      .background(alignment: .leading) {
        Capsule()
          .fill(Color.tidexBlue)
          .frame(width: 3, height: 18)
          .opacity(row.isCurrent ? 1 : 0)
      }
  }

  private var total: some View {
    HStack(spacing: Spacing.micro) {
      Image(systemName: "star.fill")
        .font(.tidexMicro)
        .opacity(row.isBest ? 1 : 0)
        .accessibilityHidden(true)
      Text(totalText)
        .fontWeight(row.isBest ? .semibold : .regular)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
    .font(.tidexFootnote)
    .foregroundStyle(totalColor)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }

  private var totalText: String {
    guard hasDays else { return "" }
    if row.total > 0 { return StatsFormat.money(row.total, currency: currency) }
    return showsEmptyTotal ? "–" : ""
  }

  private var totalColor: Color {
    if row.isBest { return .tidexTextPrimary }
    return row.total > 0 ? .tidexTextSecondary : .tidexTextMuted
  }

  private var accessibilityValue: String {
    var parts = [
      row.total > 0 ? StatsFormat.money(row.total, currency: currency) : "–",
      String(localized: .commonShiftCount(row.shiftCount)),
    ]
    if row.isCurrent {
      parts.append(String(localized: .statsChartsWeeklyChartThisWeek))
    }
    if row.isBest {
      parts.append(String(localized: .statsAccessibilityBestWeek))
    }
    return parts.joined(separator: ", ")
  }
}

/// A day's mark. Every layer is always present and only changes size or opacity, so a month
/// change animates the marks in place.
private struct StatsDayMark: View {
  let cell: StatsLattice.DayCell
  let isPinned: Bool
  let onTap: (Int) -> Void

  var body: some View {
    ZStack {
      Circle()
        .fill(Color.tidexTextMuted)
        .frame(width: 4, height: 4)
        .opacity(dotOpacity)
      Circle()
        .fill(Color.tidexBlue)
        .frame(width: fillDiameter, height: fillDiameter)
      Circle()
        .strokeBorder(Color.tidexBlueText, lineWidth: 2)
        .frame(width: ringDiameter, height: ringDiameter)
        .opacity(ringDiameter > 0 ? 1 : 0)
      StatsDiamond()
        .stroke(Color.tidexTextSecondary, lineWidth: 1.6)
        .frame(width: diamondSize, height: diamondSize)
        .offset(x: hasMark ? 11 : 0, y: hasMark ? -11 : 0)
        .opacity(hasOtherCurrency ? 1 : 0)
      Circle()
        .stroke(Color.tidexTextPrimary.opacity(0.7), lineWidth: 1.5)
        .frame(width: 33, height: 33)
        .opacity(cell.isToday ? 1 : 0)
      Circle()
        .stroke(Color.tidexBlueText, lineWidth: 1.5)
        .frame(width: 33, height: 33)
        .opacity(isPinned && !cell.isToday ? 1 : 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .onTapGesture {
      if let day = cell.dayStats?.day {
        onTap(day)
      }
    }
    .accessibilityAddTraits(.isButton)
  }

  private var mark: StatsLattice.DayMark {
    if case .day(_, let mark, _) = cell { mark } else { .empty }
  }

  /// Area grows with pay, from a 10-point circle for an unpaid shift to 26 points.
  private func diameter(_ share: Double) -> CGFloat {
    2 * (5 + 8 * CGFloat(share.squareRoot()))
  }

  private var fillDiameter: CGFloat {
    if case .worked(let share) = mark { diameter(share) } else { 0 }
  }

  private var ringDiameter: CGFloat {
    if case .scheduled(let share) = mark { diameter(share) } else { 0 }
  }

  private var hasMark: Bool { mark != .empty }

  private var hasOtherCurrency: Bool { (cell.dayStats?.otherCurrencyShifts ?? 0) > 0 }

  private var diamondSize: CGFloat { hasMark ? 7 : 12 }

  private var dotOpacity: Double {
    switch cell {
    case .outside: 0.22
    case .day: hasMark || hasOtherCurrency ? 0 : 0.82
    }
  }
}

private struct StatsDiamond: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
    path.closeSubpath()
    return path
  }
}
