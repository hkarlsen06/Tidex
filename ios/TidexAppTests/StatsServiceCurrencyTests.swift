import SwiftData
import XCTest

@testable import Tidex

@MainActor
final class StatsServiceCurrencyTests: XCTestCase {

  func testComparisonsAndChartsKeepOneCurrencyWhenContributingJobsChange() async throws {
    for hasCurrentUSD in [false, true] {
      let shifts =
        [
          ShiftInput(job: 0, date: "2026-04-01"),
          ShiftInput(job: 1, date: "2026-04-02"),
          ShiftInput(job: 2, date: "2026-04-03"),
          ShiftInput(job: 0, date: "2026-05-01"),
        ] + (hasCurrentUSD ? [ShiftInput(job: 2, date: "2026-05-02")] : [])

      try await withFixture(shifts: shifts) { service, userId, _ in
        let stats = try await service.computeStats(year: 2_026, month: 5)
        let cumulative = try XCTUnwrap(stats.thisMonthCumulative.last)
        let aprilIncome = try XCTUnwrap(stats.yearlyIncome?.first { $0.monthNumber == 4 })
        let mayIncome = try XCTUnwrap(stats.yearlyIncome?.first { $0.monthNumber == 5 })

        XCTAssertEqual(stats.currentMonthCurrencyAggregate?.primary.currency, "kr")
        XCTAssertEqual(stats.currentMonthCurrencyAggregate?.hasMixedCurrency, hasCurrentUSD)
        XCTAssertEqual(stats.currentMonth.totalEarnings, 1_600, accuracy: 0.01)
        XCTAssertEqual(stats.lastMonth.totalEarnings, 3_200, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(stats.percentageChange), -50, accuracy: 0.01)
        XCTAssertEqual(cumulative.currentMonth, 1_600, accuracy: 0.01)
        XCTAssertEqual(cumulative.lastMonth, 3_200, accuracy: 0.01)
        XCTAssertEqual(stats.days.count, 31)
        XCTAssertEqual(stats.days.reduce(0) { $0 + $1.earnings }, 1_600, accuracy: 0.01)
        XCTAssertEqual(stats.days[1].otherCurrencyShifts, hasCurrentUSD ? 1 : 0)
        XCTAssertEqual(aprilIncome.earnings, 3_200, accuracy: 0.01)
        XCTAssertEqual(mayIncome.earnings, 1_600, accuracy: 0.01)
        XCTAssertEqual(stats.currentMonth.totalHours, hasCurrentUSD ? 16 : 8, accuracy: 0.01)
        XCTAssertEqual(stats.lastMonth.totalHours, 24, accuracy: 0.01)
        XCTAssertEqual(service.statsUserId, userId)
        XCTAssertNil(service.statsJobId)
        XCTAssertEqual(service.stats, stats)

        service.clearCache()
        XCTAssertNil(service.stats)
        XCTAssertNil(service.statsUserId)
        XCTAssertNil(service.statsJobId)
        XCTAssertNil(service.error)
        XCTAssertFalse(service.isLoading)
      }
    }
  }

  func testEmptySelectedMonthKeepsSelectedJobCurrencyForComparisonAndAnnualChart() async throws {
    try await withFixture(shifts: [
      ShiftInput(job: 0, date: "2026-05-01"),
      ShiftInput(job: 2, date: "2026-05-02"),
    ]) { service, userId, jobs in
      let stats = try await service.computeStats(year: 2_026, month: 6, jobId: jobs[2])
      let cumulative = try XCTUnwrap(stats.thisMonthCumulative.last)
      let mayIncome = try XCTUnwrap(stats.yearlyIncome?.first { $0.monthNumber == 5 })

      XCTAssertEqual(stats.currentMonthCurrencyAggregate?.primary.currency, "$")
      XCTAssertEqual(stats.currentMonth.totalEarnings, 0, accuracy: 0.01)
      XCTAssertEqual(stats.lastMonth.totalEarnings, 1_600, accuracy: 0.01)
      XCTAssertEqual(try XCTUnwrap(stats.percentageChange), -100, accuracy: 0.01)
      XCTAssertEqual(cumulative.lastMonth, 1_600, accuracy: 0.01)
      XCTAssertEqual(mayIncome.earnings, 1_600, accuracy: 0.01)
      XCTAssertEqual(service.statsUserId, userId)
      XCTAssertEqual(service.statsJobId, jobs[2])
    }
  }

  func testTodayUsesPrimaryCurrencyAndPreservesBreakdown() async throws {
    let today = Date()
    let yearMonth = today.yearMonth()
    try await withFixture(shifts: [
      ShiftInput(job: 0, date: today.toISODateString(), start: "08:00", end: "12:00"),
      ShiftInput(job: 2, date: today.toISODateString(), start: "12:00", end: "16:00"),
    ]) { service, _, _ in
      let stats = try await service.computeStats(year: yearMonth.year, month: yearMonth.month)
      let secondary = try XCTUnwrap(stats.currentMonthCurrencyAggregate?.secondary.first)
      let day = stats.days[Calendar.gregorianCurrent.component(.day, from: today) - 1]

      XCTAssertEqual(stats.currentMonthCurrencyAggregate?.primary.currency, "kr")
      XCTAssertEqual(stats.currentMonthCurrencyAggregate?.secondary.first?.currency, "$")
      XCTAssertEqual(secondary.grossAmount, 800, accuracy: 0.01)
      XCTAssertEqual(day.earnings, 800, accuracy: 0.01)
      XCTAssertEqual(day.shifts, 1)
      XCTAssertEqual(day.otherCurrencyShifts, 1)
      XCTAssertEqual(stats.currentMonth.totalHours, 8, accuracy: 0.01)
    }
  }

  func testForeignCurrencyBecomesChartCurrencyWhenDefaultJobHasNoEarnings() async throws {
    try await withFixture(shifts: [ShiftInput(job: 2, date: "2026-05-02")]) { service, _, _ in
      let stats = try await service.computeStats(year: 2_026, month: 5)
      let cumulative = try XCTUnwrap(stats.thisMonthCumulative.last)
      let mayIncome = try XCTUnwrap(stats.yearlyIncome?.first { $0.monthNumber == 5 })

      XCTAssertEqual(stats.currentMonthCurrencyAggregate?.primary.currency, "$")
      XCTAssertEqual(stats.currentMonth.totalEarnings, 1_600, accuracy: 0.01)
      XCTAssertEqual(cumulative.currentMonth, 1_600, accuracy: 0.01)
      XCTAssertEqual(stats.days.reduce(0) { $0 + $1.earnings }, 1_600, accuracy: 0.01)
      XCTAssertEqual(mayIncome.earnings, 1_600, accuracy: 0.01)
    }
  }

  func testYearMonthsMatchWhatTheMonthPageShows() async throws {
    try await withFixture(shifts: [
      ShiftInput(job: 0, date: "2025-03-02"),
      ShiftInput(job: 0, date: "2026-03-02"),
      ShiftInput(job: 0, date: "2026-03-03", start: "08:00", end: "12:00"),
      ShiftInput(job: 1, date: "2026-05-04"),
      ShiftInput(job: 1, date: "2026-05-06"),
      ShiftInput(job: 2, date: "2026-05-05"),
    ]) { service, _, _ in
      let year = try await service.computeYearStats(year: 2_026)

      XCTAssertEqual(year.months.map(\.month), Array(1...12))
      for month in [1, 3, 5] {
        let stats = try await service.computeStats(year: 2_026, month: month)
        let row = year.months[month - 1]
        XCTAssertEqual(row.earnings, stats.currentMonth.totalEarnings, accuracy: 0.01, "\(month)")
        XCTAssertEqual(
          row.earningsNet, stats.currentMonth.totalEarningsNet, accuracy: 0.01, "\(month)")
        XCTAssertEqual(row.hours, stats.currentMonth.totalHours, accuracy: 0.01, "\(month)")
        XCTAssertEqual(row.shifts, stats.currentMonth.shiftCount, "\(month)")
      }
      XCTAssertEqual(year.months[2].earnings, 2_400, accuracy: 0.01)
      XCTAssertEqual(year.previousMonths[2].earnings, 1_600, accuracy: 0.01)
    }
  }

  func testYearCountsPayInTheYearsPrimaryCurrencyOnly() async throws {
    try await withFixture(shifts: [
      ShiftInput(job: 0, date: "2026-04-01"),
      ShiftInput(job: 2, date: "2026-04-02"),
      ShiftInput(job: 2, date: "2026-06-03"),
      ShiftInput(job: 2, date: "2025-04-02"),
      ShiftInput(job: 0, date: "2025-06-01"),
    ]) { service, _, _ in
      let year = try await service.computeYearStats(year: 2_026)
      let aggregate = try XCTUnwrap(year.currencyAggregate)

      XCTAssertEqual(aggregate.primary.currency, "kr")
      XCTAssertEqual(aggregate.secondary.map(\.currency), ["$"])
      XCTAssertEqual(aggregate.secondary.first?.grossAmount ?? 0, 3_200, accuracy: 0.01)
      XCTAssertEqual(year.months[3].earnings, 1_600, accuracy: 0.01)
      XCTAssertEqual(year.months[3].earningsHours, 8, accuracy: 0.01)
      XCTAssertEqual(year.months[3].hours, 16, accuracy: 0.01)
      XCTAssertEqual(year.months[3].shifts, 2)
      XCTAssertEqual(year.months[5].earnings, 0, accuracy: 0.01)
      XCTAssertEqual(year.months[5].shifts, 1)
      // The year before uses the focus year's currency, even where it earned more in dollars.
      XCTAssertEqual(year.previousMonths[3].earnings, 0, accuracy: 0.01)
      XCTAssertEqual(year.previousMonths[5].earnings, 1_600, accuracy: 0.01)
    }
  }
}

/// Day, week, pace and year amounts against the hero, with tax on.
@MainActor
final class StatsServicePayBasisTests: XCTestCase {
  func testEveryAmountUsesTheHerosBasisWithItsOwnMonthsDeduction() async throws {
    // The default schedule pays October in November, the half-tax month, so the two months
    // deduct differently.
    let shifts = [
      ShiftInput(job: 0, date: "2025-10-06"),
      ShiftInput(job: 0, date: "2025-10-14", start: "08:00", end: "12:00"),
      ShiftInput(job: 0, date: "2025-11-03"),
      ShiftInput(job: 0, date: "2025-11-17", start: "08:00", end: "12:00"),
    ]
    try await withFixture(shifts: shifts, taxPercent: 30, halfTaxMonth: 11) { service, _, _ in
      let now = Date()
      let octoberStats = try await service.computeStats(year: 2_025, month: 10)
      let novemberStats = try await service.computeStats(year: 2_025, month: 11)
      let yearStats = try await service.computeYearStats(year: 2_025)
      let october = StatsLattice(stats: octoberStats, now: now, calendar: .gregorianCurrent)
      let november = StatsLattice(stats: novemberStats, now: now, calendar: .gregorianCurrent)
      let year = StatsYearLattice(stats: yearStats, now: now, calendar: .gregorianCurrent)

      XCTAssertNotEqual(share(october.hero), share(november.hero), accuracy: 0.001)
      assertOneBasis(october, other: november, year: year)
      assertOneBasis(november, other: october, year: year)
      XCTAssertEqual(
        november.pace.previous.values[november.pace.dayCount - 1], october.hero.amount,
        accuracy: 0.01)
      XCTAssertEqual(year.hero.amount, october.hero.amount + november.hero.amount, accuracy: 0.01)
    }
  }

  func testRunningMonthSaysWhatIsEarnedSoFar() async throws {
    try await withFixture(
      shifts: [ShiftInput(job: 0, date: "2026-11-03"), ShiftInput(job: 0, date: "2026-11-20")],
      taxPercent: 30
    ) { service, _, _ in
      let now = try XCTUnwrap(
        Calendar.gregorianCurrent.date(
          from: DateComponents(year: 2_026, month: 11, day: 12, hour: 12)))
      let stats = try await service.computeStats(year: 2_026, month: 11, now: now)
      let hero = StatsLattice(stats: stats, now: now, calendar: .gregorianCurrent).hero

      XCTAssertEqual(hero.amount, 2_240, accuracy: 0.01)
      XCTAssertEqual(try XCTUnwrap(hero.earnedSoFar), 1_120, accuracy: 0.01)
    }
  }

  func testEmptyPeriodsKeepPayAfterTax() async throws {
    try await withFixture(shifts: [ShiftInput(job: 0, date: "2025-10-06")], taxPercent: 30) {
      service, _, _ in
      let now = Date()
      let month = try await service.computeStats(year: 2_025, month: 12)
      let year = try await service.computeYearStats(year: 2_024)
      let monthHero = StatsLattice(stats: month, now: now, calendar: .gregorianCurrent).hero
      let yearHero = StatsYearLattice(stats: year, now: now, calendar: .gregorianCurrent).hero

      XCTAssertTrue(monthHero.isAfterTax)
      XCTAssertEqual(monthHero.qualifier, .noShifts(isAhead: false))
      XCTAssertTrue(yearHero.isAfterTax)
      XCTAssertEqual(yearHero.qualifier, .noShifts(isAhead: false))
    }
  }

  private func share(_ hero: StatsLattice.Hero) -> Double {
    guard case .taxed(let gross) = hero.qualifier, gross > 0 else { return 1 }
    return hero.amount / gross
  }

  /// Days, weeks, the pace line and both year charts add up to the hero's amount after tax.
  private func assertOneBasis(
    _ page: StatsLattice, other: StatsLattice, year: StatsYearLattice,
    line: UInt = #line
  ) {
    let amount = page.hero.amount
    let days = page.weeks.rows.flatMap(\.cells).reduce(0) { $0 + ($1.dayStats?.earnings ?? 0) }
    XCTAssertTrue(page.hero.isAfterTax, line: line)
    XCTAssertLessThan(share(page.hero), 1, line: line)
    XCTAssertEqual(days, amount, accuracy: 0.01, line: line)
    XCTAssertEqual(page.weeks.rows.reduce(0) { $0 + $1.total }, amount, accuracy: 0.01, line: line)
    XCTAssertEqual(
      page.pace.focus.values[page.pace.dayCount - 1], amount, accuracy: 0.01, line: line)
    XCTAssertEqual(
      page.year.months[page.month.month - 1].earnings, amount, accuracy: 0.01, line: line)
    XCTAssertEqual(
      page.year.months[other.month.month - 1].earnings, other.hero.amount, accuracy: 0.01,
      line: line)
    XCTAssertEqual(
      year.months.rows[page.month.month - 1].earnings, amount, accuracy: 0.01, line: line)
  }
}

@MainActor
extension XCTestCase {
  fileprivate struct ShiftInput {
    let job: Int
    let date: String
    var start = "08:00"
    var end = "16:00"
  }

  // swiftlint:disable:next function_body_length
  fileprivate func withFixture(
    shifts: [ShiftInput],
    taxPercent: Double? = nil,
    halfTaxMonth: Int? = nil,
    assertions: (StatsService, String, [String]) async throws -> Void
  ) async throws {
    let userId = UUID().uuidString.lowercased()
    let context = ModelContext(LocalStore.shared.container)
    let now = Date()
    var records: [any PersistentModel] = []
    let settings = LocalUserSettings(
      userId: userId, halfTaxMonth: halfTaxMonth, currency: "kr", serverUpdatedAt: now,
      serverRevision: 1, lastSyncedSnapshot: Data(), localUpdatedAt: now
    )
    records.append(settings)
    var jobIds: [String] = []

    for (index, currency) in ["kr", "kr", "$"].enumerated() {
      let jobId = UUID().uuidString.lowercased()
      jobIds.append(jobId)
      records.append(
        LocalJob(
          id: jobId, userId: userId, name: "Job \(index)", currency: currency,
          isDefault: index == 0, sortOrder: index, halfTaxMonth: halfTaxMonth,
          serverUpdatedAt: now, serverRevision: 1, lastSyncedSnapshot: Data(), localUpdatedAt: now
        ))
      let snapshot = LocalWageSnapshot.from(
        serverRow: TestFixtures.wageSnapshot(
          hourlyWage: 200, taxEnabled: taxPercent != nil, taxPercentage: taxPercent,
          breakEnabled: false, jobId: jobId),
        serverUpdatedAt: now, serverRevision: 1, serverDeletedAt: nil, context: context
      )
      snapshot.userId = userId
      records.append(snapshot)
    }
    for input in shifts {
      records.append(
        LocalUserShift(
          id: UUID().uuidString.lowercased(), userId: userId, jobId: jobIds[input.job],
          shiftDate: try XCTUnwrap(Date.fromISODateString(input.date)),
          startTime: input.start, endTime: input.end,
          serverUpdatedAt: now, serverRevision: 1, lastSyncedSnapshot: Data(), localUpdatedAt: now
        ))
    }
    for record in records { context.insert(record) }
    defer {
      MonthlyPayrollReadService.shared.invalidateSharedCache(for: userId)
      for record in records { context.delete(record) }
      do {
        try context.save()
      } catch {
        XCTFail("Could not remove currency test fixtures: \(error)")
      }
    }
    try context.save()

    let service = StatsService(userIdProvider: { userId })
    try await assertions(service, userId, jobIds)
  }
}
