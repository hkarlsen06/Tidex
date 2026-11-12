#if DEBUG
  import SwiftUI

  /// Stats from fixtures with a fixed today, 12 November 2026, so the screens look the same on
  /// any day. TIDEX_DESIGN_SCREEN=stats shows a busy current month, stats-empty a past month
  /// without shifts, and stats-february a short month with pay in a second currency.
  /// stats-year shows the running year with tax and scheduled December pay, stats-year-empty a
  /// year without shifts for the same taxed user, and stats-year-past a finished year with a
  /// second currency. Amounts follow the service: after tax wherever tax is on.
  internal struct DesignReviewStats: View {
    let screen: String

    private static let now: Date =
      Calendar.gregorianCurrent.date(
        from: DateComponents(year: 2_026, month: 11, day: 12, hour: 12)) ?? .now

    internal var body: some View {
      NavigationStack {
        ScrollView {
          StatsContent(
            page: page,
            onSelectMonth: { _ in },
            onExport: {},
            onAddShift: {}
          )
          .statsContentFrame()
        }
        .background(Color.tidexBackground)
        .navigationTitle(Text(.tabsStats))
        .navigationBarTitleDisplayMode(.inline)
      }
      .userCurrency("kr")
    }

    private var page: StatsContent.Page {
      switch screen {
      case "stats-year": year(Self.runningYear)
      case "stats-year-empty": year(Self.emptyYear)
      case "stats-year-past": year(Self.pastYear)
      case "stats-empty": month(Self.emptyMarch)
      case "stats-february": month(Self.february)
      default: month(Self.busyNovember)
      }
    }

    private func month(_ stats: StatsData) -> StatsContent.Page {
      .month(StatsLattice(stats: stats, now: Self.now, calendar: .gregorianCurrent))
    }

    private func year(_ stats: YearStatsData) -> StatsContent.Page {
      .year(StatsYearLattice(stats: stats, now: Self.now, calendar: .gregorianCurrent))
    }

    // MARK: Fixtures

    /// Pay and employment for each month of a year. The focus month's pay comes from its days.
    private struct YearFixture {
      let pay: [Double]
      let employment: [Double?]
    }

    private static let year2026 = YearFixture(
      pay: [
        16_200, 2_240, 17_100, 15_900, 18_800, 23_400, 31_200, 27_100, 17_300, 19_640, 0, 6_900,
      ],
      employment: [48, 6, 50, 46, 55, 68, 90, 79, 51, 57, 74, 20]
    )

    private static var busyNovember: StatsData {
      let november = days(
        year: 2_026, month: 11,
        worked: [1, 3, 4, 6, 7, 9, 11, 12, 14, 19, 21, 22, 26, 28, 30], bonus: [11])
      let october = days(
        year: 2_026, month: 10, worked: [2, 3, 4, 6, 8, 10, 13, 16, 17, 20, 24, 27])
      return stats(
        FocusMonth(year: 2_026, month: 11), days: november, previous: october,
        taxPercent: 15, year: year2026, earnedBefore: 12)
    }

    private static var emptyMarch: StatsData {
      stats(
        FocusMonth(year: 2_025, month: 3),
        days: days(year: 2_025, month: 3, worked: []),
        previous: days(year: 2_025, month: 2, worked: []),
        taxPercent: nil,
        year: YearFixture(
          pay: [0, 0, 0, 0, 0, 9_400, 20_100, 17_300, 12_600, 12_200, 14_100, 18_700],
          employment: [nil, nil, nil, nil, nil, 34, 75, 65, 46, 45, 53, 70]
        )
      )
    }

    /// One shift paid in kroner and one in euros, so the currency chip and the diamond show.
    private static var february: StatsData {
      let worked = days(year: 2_026, month: 2, worked: [7])
      let february = worked.map { day in
        day.day == 20
          ? DayStats(day: 20, earnings: 0, hours: 0, shifts: 0, otherCurrencyShifts: 1) : day
      }
      let euros = aggregateEntry(currency: "€", amount: 1_950)
      return stats(
        FocusMonth(year: 2_026, month: 2), days: february,
        previous: days(year: 2_026, month: 1, worked: [3, 5, 9, 10, 16, 17, 24, 30, 31]),
        taxPercent: 15, year: year2026,
        aggregate: JobCurrencyAggregateResolution(
          primary: aggregateEntry(currency: "kr", amount: 1_904),
          secondary: [euros],
          hasMixedCurrency: true
        )
      )
    }

    // MARK: Building

    /// Pay and hours per weekday, Monday first, so the fixtures read like a shift pattern.
    private static let weekdayPay: [Double] = [1_480, 1_480, 1_480, 1_480, 1_760, 2_240, 2_310]
    private static let weekdayHours: [Double] = [7.5, 7.5, 7.5, 7.5, 8, 8, 8]

    private static func days(year: Int, month: Int, worked: Set<Int>, bonus: Set<Int> = [])
      -> [DayStats]
    {
      (1...Date.daysInMonth(year: year, month: month)).map { day in
        guard worked.contains(day) else {
          return DayStats(day: day, earnings: 0, hours: 0, shifts: 0, otherCurrencyShifts: 0)
        }
        let date = StatsFormat.date(FocusMonth(year: year, month: month), day: day)
        let weekday = (Calendar.gregorianCurrent.component(.weekday, from: date) + 5) % 7
        let extra: Double = bonus.contains(day) ? 140 : 0
        return DayStats(
          day: day, earnings: weekdayPay[weekday] + extra, hours: weekdayHours[weekday],
          shifts: 1, otherCurrencyShifts: 0)
      }
    }

    /// `days` and `previous` hold pay before tax. `earnedBefore` makes the shifts before that
    /// day the ones already worked, with later shifts still scheduled.
    private static func stats(
      _ month: FocusMonth,
      days grossDays: [DayStats],
      previous grossPrevious: [DayStats],
      taxPercent: Double?,
      year: YearFixture,
      aggregate: JobCurrencyAggregateResolution? = nil,
      earnedBefore: Int? = nil
    ) -> StatsData {
      let share = 1 - (taxPercent ?? 0) / 100
      let days = grossDays.map { $0.scaled(by: share) }
      let previous = grossPrevious.map { $0.scaled(by: share) }
      let gross = grossDays.reduce(0) { $0 + $1.earnings }
      let previousGross = grossPrevious.reduce(0) { $0 + $1.earnings }
      var pay = year.pay
      pay[month.month - 1] = gross
      let earned = earnedBefore.map { day in
        days.filter { $0.day < day }.reduce(0) { $0 + $1.earnings }
      }
      return StatsData(
        focusMonth: month,
        tax: TaxSettings(enabled: taxPercent != nil, percentage: taxPercent ?? 0),
        currentMonth: MonthStats(
          totalEarnings: gross, totalEarningsNet: gross * share,
          totalHours: days.reduce(0) { $0 + $1.hours },
          shiftCount: days.reduce(0) { $0 + $1.shifts + $1.otherCurrencyShifts }),
        earnedSoFar: earned,
        currentMonthCurrencyAggregate: aggregate,
        lastMonth: MonthStats(
          totalEarnings: previousGross, totalEarningsNet: previousGross * share,
          totalHours: previous.reduce(0) { $0 + $1.hours },
          shiftCount: previous.reduce(0) { $0 + $1.shifts }),
        percentageChange: previousGross > 0 ? (gross - previousGross) / previousGross * 100 : nil,
        thisMonthCumulative: cumulative(month, days: days, previous: previous),
        days: days,
        employment: employmentData(year: month.year, percentages: year.employment),
        yearlyIncome: yearlyIncome(year: month.year, pay: pay.map { $0 * share })
      )
    }

    /// The previous month's days after this month's last day fold into the last point, as the
    /// service does.
    private static func cumulative(_ month: FocusMonth, days: [DayStats], previous: [DayStats])
      -> [DailyCumulativeData]
    {
      var running: Double = 0
      var previousRunning: Double = 0
      return days.map { day in
        running += day.earnings
        previousRunning += previous.first { $0.day == day.day }?.earnings ?? 0
        if day.day == days.count {
          previousRunning += previous.filter { $0.day > days.count }.reduce(0) { $0 + $1.earnings }
        }
        return DailyCumulativeData(
          day: day.day, currentMonth: running, lastMonth: previousRunning, isToday: false,
          isFuture: false)
      }
    }

    private static func employmentData(year: Int, percentages: [Double?]) -> EmploymentData {
      let names = StatsService.monthNames()
      return EmploymentData(
        monthlyData: percentages.enumerated().map { index, percentage in
          EmploymentMonthlyData(
            month: names.short[index], fullMonth: names.full[index], year: year,
            monthNumber: index + 1, averagePercentage: percentage ?? 0,
            hasShifts: percentage != nil)
        },
        yearlyAverage: nil,
        fullTimeHoursPerWeek: 37.5
      )
    }

    private static func yearlyIncome(year: Int, pay: [Double]) -> [MonthlyIncomeData] {
      let names = StatsService.monthNames()
      return pay.enumerated().map { index, earnings in
        MonthlyIncomeData(
          month: names.short[index], fullMonth: names.full[index], year: year,
          monthNumber: index + 1, earnings: earnings, hours: 0, shifts: 0)
      }
    }

    // MARK: Year fixtures

    /// 2026 up to 12 November with 15% tax, scheduled pay in December and pay in 2025 to compare.
    private static var runningYear: YearStatsData {
      var pay = year2026.pay
      pay[10] = busyNovember.currentMonth.totalEarnings
      let previous: [Double] = [
        12_400, 9_800, 14_100, 13_300, 15_600, 19_900, 26_400, 22_800, 15_100, 16_900, 18_200,
        21_300,
      ]
      let net = { (gross: Double) in gross * 0.85 }
      let november = days(year: 2_025, month: 11, worked: [3, 4, 6, 7, 10, 11])
      return YearStatsData(
        year: 2_026,
        tax: TaxSettings(enabled: true, percentage: 15),
        months: yearMonths(pay, net: net),
        previousMonths: yearMonths(previous, net: net),
        currencyAggregate: nil,
        toDate: YearToDate(
          focus: pay.prefix(10).reduce(0, +) + 7_380,
          previous: previous.prefix(10).reduce(0, +) + november.reduce(0) { $0 + $1.earnings }
        ),
        employment: employmentData(year: 2_026, percentages: year2026.employment)
      )
    }

    private static var emptyYear: YearStatsData {
      YearStatsData(
        year: 2_024,
        tax: TaxSettings(enabled: true, percentage: 15),
        months: yearMonths(Array(repeating: 0, count: 12)),
        previousMonths: yearMonths(Array(repeating: 0, count: 12)),
        currencyAggregate: nil,
        toDate: nil,
        employment: employmentData(year: 2_024, percentages: Array(repeating: nil, count: 12))
      )
    }

    /// 2025 without tax, starting in June, with one euro job beside the kroner and no pay in 2024.
    private static var pastYear: YearStatsData {
      let pay: [Double] = [0, 0, 0, 0, 0, 9_400, 20_100, 17_300, 12_600, 12_200, 14_100, 18_700]
      let kroner = pay.reduce(0, +)
      return YearStatsData(
        year: 2_025,
        tax: TaxSettings(enabled: false, percentage: 0),
        months: yearMonths(pay),
        previousMonths: yearMonths(Array(repeating: 0, count: 12)),
        currencyAggregate: JobCurrencyAggregateResolution(
          primary: aggregateEntry(currency: "kr", amount: kroner),
          secondary: [aggregateEntry(currency: "€", amount: 4_850)],
          hasMixedCurrency: true
        ),
        toDate: nil,
        employment: employmentData(
          year: 2_025, percentages: [nil, nil, nil, nil, nil, 34, 75, 65, 46, 45, 53, 70])
      )
    }

    /// Hours and shift counts follow the pay at about 200 per hour and 1 700 per shift.
    private static func yearMonths(_ pay: [Double], net: (Double) -> Double = { $0 })
      -> [YearMonthStats]
    {
      pay.enumerated().map { index, gross in
        let hours = (gross / 200).rounded()
        return YearMonthStats(
          month: index + 1, earnings: gross, earningsNet: net(gross), earningsHours: hours,
          hours: hours, shifts: Int((gross / 1_700).rounded(.up)))
      }
    }

    private static func aggregateEntry(currency: String, amount: Double)
      -> JobCurrencyAggregateEntry
    {
      JobCurrencyAggregateEntry(
        key: "design-review|\(currency)", jobId: "design-review", jobName: "Weekend job",
        currency: currency, grossAmount: amount, netAmount: amount, displayAmount: amount,
        shiftCount: 1, completedShiftCount: 1, plannedShiftCount: 0, hasTaxEnabled: false)
    }
  }

  extension DayStats {
    fileprivate func scaled(by share: Double) -> DayStats {
      DayStats(
        day: day, earnings: earnings * share, hours: hours, shifts: shifts,
        otherCurrencyShifts: otherCurrencyShifts)
    }
  }
#endif
