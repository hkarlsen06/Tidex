#if DEBUG
  import SwiftUI

  /// Stats from fixtures with a fixed today, 12 November 2026, so the screens look the same on
  /// any day. TIDEX_DESIGN_SCREEN=stats shows a busy current month, stats-empty a past month
  /// without shifts, and stats-february a short month with pay in a second currency.
  internal struct DesignReviewStats: View {
    let screen: String

    private static let now: Date =
      Calendar.gregorianCurrent.date(
        from: DateComponents(year: 2_026, month: 11, day: 12, hour: 12)) ?? .now

    internal var body: some View {
      NavigationStack {
        ScrollView {
          StatsContent(
            lattice: StatsLattice(stats: stats, now: Self.now, calendar: .gregorianCurrent),
            onSelectMonth: { _ in },
            onExport: {}
          )
          .statsContentFrame()
        }
        .background(Color.tidexBackground)
        .navigationTitle(Text(.tabsStats))
        .navigationBarTitleDisplayMode(.inline)
      }
      .userCurrency("kr")
    }

    private var stats: StatsData {
      switch screen {
      case "stats-empty": Self.emptyMarch
      case "stats-february": Self.february
      default: Self.busyNovember
      }
    }

    // MARK: Fixtures

    /// Pay and employment for each month of a year. The focus month's pay comes from its days.
    private struct YearFixture {
      let pay: [Double]
      let employment: [Double?]
    }

    private static let year2026 = YearFixture(
      pay: [16_200, 2_240, 17_100, 15_900, 18_800, 23_400, 31_200, 27_100, 17_300, 19_640, 0, 6_900],
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
        taxPercent: 15, year: year2026)
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

    private static func stats(
      _ month: FocusMonth,
      days: [DayStats],
      previous: [DayStats],
      taxPercent: Double?,
      year: YearFixture,
      aggregate: JobCurrencyAggregateResolution? = nil
    ) -> StatsData {
      let gross = days.reduce(0) { $0 + $1.earnings }
      let previousGross = previous.reduce(0) { $0 + $1.earnings }
      let net = taxPercent.map { gross * (1 - $0 / 100) } ?? gross
      var pay = year.pay
      pay[month.month - 1] = gross
      return StatsData(
        focusMonth: month,
        tax: TaxSettings(enabled: taxPercent != nil, percentage: taxPercent ?? 0),
        currentMonth: MonthStats(
          totalEarnings: gross, totalEarningsNet: net,
          totalHours: days.reduce(0) { $0 + $1.hours },
          shiftCount: days.reduce(0) { $0 + $1.shifts + $1.otherCurrencyShifts }),
        currentMonthCurrencyAggregate: aggregate,
        lastMonth: MonthStats(
          totalEarnings: previousGross, totalEarningsNet: previousGross,
          totalHours: previous.reduce(0) { $0 + $1.hours },
          shiftCount: previous.reduce(0) { $0 + $1.shifts }),
        percentageChange: previousGross > 0 ? (gross - previousGross) / previousGross * 100 : nil,
        thisMonthCumulative: cumulative(month, days: days, previous: previous),
        days: days,
        employment: employmentData(year: month.year, percentages: year.employment),
        yearlyIncome: yearlyIncome(year: month.year, pay: pay)
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

    private static func aggregateEntry(currency: String, amount: Double)
      -> JobCurrencyAggregateEntry
    {
      JobCurrencyAggregateEntry(
        key: "design-review|\(currency)", jobId: "design-review", jobName: "Weekend job",
        currency: currency, grossAmount: amount, netAmount: amount, displayAmount: amount,
        shiftCount: 1, completedShiftCount: 1, plannedShiftCount: 0, hasTaxEnabled: false)
    }
  }
#endif
