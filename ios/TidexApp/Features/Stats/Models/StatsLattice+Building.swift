import Foundation

extension StatsLattice {
  init(stats: StatsData, now: Date, calendar: Calendar) {
    let today = Today(now, calendar: calendar)
    let month = stats.focusMonth
    let phase = Self.phase(of: month, today: today)
    let dayCount = Date.daysInMonth(year: month.year, month: month.month)
    let days = Self.paddedDays(stats.days, dayCount: dayCount)
    self.month = month
    self.phase = phase
    hero = Self.makeHero(stats: stats, today: today)
    metrics = Self.makeMetrics(stats: stats, days: days)
    pace = Self.makePace(stats: stats, phase: phase, dayCount: dayCount, today: today)
    weeks = Self.makeWeeks(
      stats: stats, days: days, phase: phase, calendar: calendar,
      showsYear: month.year != today.year)
    year = Self.makeYear(stats: stats, now: now, calendar: calendar, today: today)
  }

  /// The real date, read once so every part of a lattice agrees on it.
  struct Today {
    let year: Int
    let month: Int
    let day: Int

    var monthIndex: Int { year * 12 + month }

    init(_ date: Date, calendar: Calendar) {
      let parts = calendar.dateComponents([.year, .month, .day], from: date)
      year = parts.year ?? 0
      month = parts.month ?? 1
      day = parts.day ?? 1
    }
  }

  private static func phase(of month: FocusMonth, today: Today) -> Phase {
    if month.monthIndex < today.monthIndex { return .past }
    if month.monthIndex > today.monthIndex { return .future }
    return .current(today: today.day)
  }

  private static func paddedDays(_ days: [DayStats], dayCount: Int) -> [DayStats] {
    let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
    return (1...dayCount).map { day in
      byDay[day] ?? DayStats(day: day, earnings: 0, hours: 0, shifts: 0, otherCurrencyShifts: 0)
    }
  }

  private static func makeHero(stats: StatsData, today: Today) -> Hero {
    let gross = stats.currentMonth.totalEarnings
    let net = stats.currentMonth.totalEarningsNet
    let qualifier: Qualifier
    if stats.currentMonth.shiftCount == 0 {
      qualifier = .noShifts
    } else if stats.tax.enabled {
      // The month's own deduction, which also covers a half-tax month.
      let percent = gross > 0 ? (1 - net / gross) * 100 : stats.tax.percentage
      qualifier = .taxed(gross: gross, taxPercent: percent)
    } else {
      qualifier = .untaxed
    }
    let secondary = otherCurrencyEntries(stats.currentMonthCurrencyAggregate)
    return Hero(
      period: .month(stats.focusMonth, showsYear: stats.focusMonth.year != today.year),
      isAfterTax: stats.tax.enabled,
      amount: stats.tax.enabled ? net : gross,
      qualifier: qualifier,
      change: stats.percentageChange.map(Change.percent) ?? .noPreviousPay,
      otherCurrencies: otherCurrencies(secondary),
      breakdown: secondary
    )
  }

  static func otherCurrencyEntries(_ aggregate: JobCurrencyAggregateResolution?)
    -> [JobCurrencyAggregateEntry]
  {
    aggregate?.hasMixedCurrency == true ? aggregate?.secondary ?? [] : []
  }

  static func otherCurrencies(_ entries: [JobCurrencyAggregateEntry]) -> OtherCurrencies {
    let byCurrency = Dictionary(grouping: entries, by: \.currency)
    guard let only = byCurrency.first, byCurrency.count == 1 else {
      return byCurrency.isEmpty ? .absent : .several(count: byCurrency.count)
    }
    return .one(amount: only.value.reduce(0) { $0 + $1.displayAmount }, currency: only.key)
  }

  private static func makeMetrics(stats: StatsData, days: [DayStats]) -> Metrics {
    let pay = days.reduce(0) { $0 + $1.earnings }
    let paidHours = days.reduce(0) { $0 + $1.hours }
    return Metrics(
      hours: stats.currentMonth.totalHours,
      shifts: stats.currentMonth.shiftCount,
      perHour: pay > 0 && paidHours > 0 ? pay / paidHours : nil
    )
  }

  // MARK: Pace

  private static func makePace(stats: StatsData, phase: Phase, dayCount: Int, today: Today) -> Pace
  {
    let month = stats.focusMonth
    let focusValues = slotValues(stats.thisMonthCumulative.map(\.currentMonth), dayCount: dayCount)
    let previousValues = slotValues(stats.thisMonthCumulative.map(\.lastMonth), dayCount: dayCount)
    let reference: PaceReference
    switch phase {
    case .current(let day): reference = .today(min(day, dayCount))
    case .past, .future: reference = .monthEnd(dayCount)
    }
    let difference = focusValues[reference.day - 1] - previousValues[reference.day - 1]
    let peak = max(focusValues.max() ?? 0, previousValues.max() ?? 0)
    return Pace(
      month: month,
      previousMonth: month.previous,
      showsYear: month.year != today.year,
      focus: makeSeries(month, role: .focus, values: focusValues, dayCount: dayCount, today: today),
      previous: makeSeries(
        month.previous, role: .previous, values: previousValues, dayCount: dayCount, today: today),
      yMax: niceCeiling(max(peak, 1_000)),
      dayCount: dayCount,
      reference: reference,
      headline: paceHeadline(stats: stats, phase: phase, difference: difference)
    )
  }

  private static func slotValues(_ values: [Double], dayCount: Int) -> [Double] {
    let days = Array(values.prefix(dayCount))
    return days + Array(repeating: days.last ?? 0, count: daySlots - days.count)
  }

  /// Each line keeps the solid part its own month has, so it does not change shape when the
  /// month moves from focus to previous.
  private static func makeSeries(
    _ month: FocusMonth, role: PaceSeries.Role, values: [Double], dayCount: Int, today: Today
  ) -> PaceSeries {
    let solidThrough: Int
    switch phase(of: month, today: today) {
    case .past: solidThrough = dayCount
    case .current(let day): solidThrough = min(day, dayCount)
    case .future: solidThrough = 0
    }
    return PaceSeries(
      id: month.monthIndex, role: role, values: values, dayCount: dayCount,
      solidThrough: solidThrough)
  }

  private static func paceHeadline(stats: StatsData, phase: Phase, difference: Double)
    -> PaceHeadline
  {
    let month = stats.focusMonth
    let previousPay = stats.lastMonth.totalEarnings
    if stats.currentMonth.shiftCount == 0, previousPay <= 0 { return .nothing(month) }
    if phase == .future { return .scheduled(stats.currentMonth.totalEarnings) }
    if previousPay <= 0 { return .noPreviousPay(month.previous) }
    if phase == .past { return .ended(difference: difference, previous: month.previous) }
    return .running(difference: difference, previous: month.previous)
  }

  // MARK: Weeks

  private static func makeWeeks(
    stats: StatsData, days: [DayStats], phase: Phase, calendar: Calendar, showsYear: Bool
  ) -> Weeks {
    let month = stats.focusMonth
    let rows = makeWeekRows(month: month, days: days, phase: phase, calendar: calendar)
    return Weeks(
      month: month,
      showsYear: showsYear,
      rows: rows,
      headline: weeksHeadline(stats: stats, rows: rows, phase: phase),
      readout: readout(days: days, phase: phase)
    )
  }

  /// Six rows of Monday to Sunday, starting with the ISO week that holds day 1.
  private static func makeWeekRows(
    month: FocusMonth, days: [DayStats], phase: Phase, calendar: Calendar
  )
    -> [WeekRow]
  {
    let firstDay =
      calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)) ?? .now
    var isoCalendar = Calendar(identifier: .iso8601)
    isoCalendar.timeZone = calendar.timeZone
    // Calendar weekdays run from 1 for Sunday, so this counts the days back to Monday.
    let lead = (calendar.component(.weekday, from: firstDay) + 5) % 7
    let biggest = days.map(\.earnings).max() ?? 0
    let cellRows: [[DayCell]] = (0..<weekRows).map { row in
      (0..<7).map { column in
        cell(day: row * 7 + column - lead + 1, days: days, biggest: biggest, phase: phase)
      }
    }
    let totals = cellRows.map { cells in cells.reduce(0) { $0 + ($1.dayStats?.earnings ?? 0) } }
    let best = bestIndex(totals)
    return cellRows.indices.map { index in
      let monday = calendar.date(byAdding: .day, value: index * 7 - lead, to: firstDay) ?? firstDay
      let cells = cellRows[index]
      return WeekRow(
        id: index,
        isoWeek: isoCalendar.component(.weekOfYear, from: monday),
        cells: cells,
        total: totals[index],
        shiftCount: cells.reduce(0) { total, cell in
          total + (cell.dayStats.map { $0.shifts + $0.otherCurrencyShifts } ?? 0)
        },
        isCurrent: cells.contains(where: \.isToday),
        isBest: index == best
      )
    }
  }

  private static func cell(day: Int, days: [DayStats], biggest: Double, phase: Phase) -> DayCell {
    guard days.indices.contains(day - 1) else { return .outside }
    let stats = days[day - 1]
    return .day(
      stats,
      mark: mark(for: stats, biggest: biggest, phase: phase),
      isToday: phase == .current(today: day)
    )
  }

  private static func mark(for day: DayStats, biggest: Double, phase: Phase) -> DayMark {
    guard day.shifts > 0 || day.earnings > 0 else { return .empty }
    let share = biggest > 0 ? day.earnings / biggest : 0
    switch phase {
    case .past: return .worked(share)
    case .future: return .scheduled(share)
    case .current(let today): return day.day > today ? .scheduled(share) : .worked(share)
    }
  }

  /// The index of the highest total, or nil when every total is zero or two share the top.
  static func bestIndex(_ totals: [Double]) -> Int? {
    guard let top = totals.max(), top > 0 else { return nil }
    let leaders = totals.indices.filter { abs(totals[$0] - top) < 0.005 }
    return leaders.count == 1 ? leaders.first : nil
  }

  private static func weeksHeadline(stats: StatsData, rows: [WeekRow], phase: Phase)
    -> WeeksHeadline
  {
    let month = stats.focusMonth
    if stats.currentMonth.shiftCount == 0 { return .noShifts(month) }
    if case .current(let today) = phase, let row = rows.first(where: \.isCurrent) {
      let soFar = row.cells.reduce(0.0) { total, cell in
        guard let day = cell.dayStats, day.day <= today else { return total }
        return total + day.earnings
      }
      return .soFar(amount: soFar, week: row.isoWeek)
    }
    if let best = rows.first(where: \.isBest) {
      return phase == .future
        ? .busiestAhead(week: best.isoWeek) : .best(week: best.isoWeek, amount: best.total)
    }
    let top = rows.map(\.total).max() ?? 0
    return top > 0 ? .tied(amount: top) : .noPay(month)
  }

  private static func readout(days: [DayStats], phase: Phase) -> DayReadout {
    if case .current(let today) = phase, days.indices.contains(today - 1) {
      return .day(days[today - 1])
    }
    guard let biggest = days.max(by: { $0.earnings < $1.earnings }), biggest.earnings > 0 else {
      return .hint
    }
    return phase == .future ? .biggestDay(biggest) : .bestDay(biggest)
  }

  // MARK: Year

  private static func makeYear(stats: StatsData, now: Date, calendar: Calendar, today: Today)
    -> Year
  {
    let focus = stats.focusMonth
    let income = Dictionary(
      (stats.yearlyIncome ?? []).map { ($0.monthNumber, $0.earnings) }, uniquingKeysWith: +)
    let months = (1...monthSlots).map { number in
      MonthSlot(
        id: number,
        earnings: income[number] ?? 0,
        isAhead: FocusMonth(year: focus.year, month: number).monthIndex > today.monthIndex
      )
    }
    let total = months.reduce(0) { $0 + $1.earnings }
    let paidMonths = months.filter { $0.earnings > 0 }.count
    let peak = months.map(\.earnings).max() ?? 0
    return Year(
      year: focus.year,
      months: months,
      yMax: niceCeiling(max(peak, 1_000)),
      total: total,
      perPaidMonth: paidMonths > 0 ? total / Double(paidMonths) : nil,
      focus: focus.month,
      currentMonth: focus.year == today.year ? today.month : nil,
      employment: makeEmploymentYear(
        year: focus.year, data: stats.employment, now: now, calendar: calendar)
    )
  }

  static func makeEmploymentYear(year: Int, data: EmploymentData?, now: Date, calendar: Calendar)
    -> EmploymentYear
  {
    EmploymentYear(
      year: year,
      months: (1...monthSlots).map {
        monthEmployment(month: $0, data: data, now: now, calendar: calendar)
      },
      average: employmentAverage(data, now: now, calendar: calendar),
      fullTimeHoursPerWeek: data?.fullTimeHoursPerWeek ?? 37.5
    )
  }

  private static func monthEmployment(
    month: Int, data: EmploymentData?, now: Date, calendar: Calendar
  )
    -> Employment
  {
    guard let data, let entry = data.monthlyData.first(where: { $0.monthNumber == month }),
      entry.hasShifts
    else { return .noShifts }
    return data.isIncludedInCompletedAverage(entry, now: now, calendar: calendar)
      ? .counted(entry.averagePercentage) : .running(entry.averagePercentage)
  }

  private static func employmentAverage(_ data: EmploymentData?, now: Date, calendar: Calendar)
    -> EmploymentAverage
  {
    guard let data, let average = data.completedMonthsAverage(now: now, calendar: calendar) else {
      return .noCompletedMonths
    }
    return .average(average, range: data.completedAverageRangeLabel(now: now, calendar: calendar))
  }
}
