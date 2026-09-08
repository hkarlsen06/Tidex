import SwiftData
import XCTest

@testable import Tidex

@MainActor
final class StatsServiceCurrencyTests: XCTestCase {
  func testMonthLabelsRespectLocale() {
    let english = StatsService.monthNames(locale: Locale(identifier: "en_US"))
    let norwegian = StatsService.monthNames(locale: Locale(identifier: "nb_NO"))
    XCTAssertEqual(english.short.count, 12)
    XCTAssertEqual(english.full.count, 12)
    XCTAssertEqual(english.short[4], "May")
    XCTAssertEqual(english.full[11], "December")
    XCTAssertEqual(norwegian.short[4], "mai")
    XCTAssertEqual(norwegian.full[11], "Desember")
    XCTAssertEqual(StatsService.monthNames().short, StatsService.monthNames(locale: .current).short)
  }

  func testWeekdayLabelsRespectLocale() throws {
    let date = try XCTUnwrap(Date.fromISODateString("2026-09-07"))
    let calendar = Calendar(identifier: .gregorian)
    let english = Locale(identifier: "en_US")
    let norwegian = Locale(identifier: "nb_NO")
    XCTAssertEqual(
      StatsService.shortWeekdayName(for: date, calendar: calendar, locale: english), "Mon")
    XCTAssertEqual(
      StatsService.fullWeekdayName(for: date, calendar: calendar, locale: english), "Monday")
    XCTAssertEqual(
      StatsService.fullWeekdayName(for: date, calendar: calendar, locale: norwegian), "Mandag")
    XCTAssertEqual(
      StatsService.fullWeekdayName(for: date, calendar: calendar),
      StatsService.fullWeekdayName(for: date, calendar: calendar, locale: .current)
    )
  }

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
        let bestWeek = try XCTUnwrap(stats.bestWeek)
        let aprilIncome = try XCTUnwrap(stats.yearlyIncome?.first { $0.monthNumber == 4 })
        let mayIncome = try XCTUnwrap(stats.yearlyIncome?.first { $0.monthNumber == 5 })

        XCTAssertEqual(stats.currentMonthCurrencyAggregate?.primary.currency, "kr")
        XCTAssertEqual(stats.currentMonthCurrencyAggregate?.hasMixedCurrency, hasCurrentUSD)
        XCTAssertEqual(stats.currentMonth.totalEarnings, 1_600, accuracy: 0.01)
        XCTAssertEqual(stats.lastMonth.totalEarnings, 3_200, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(stats.percentageChange), -50, accuracy: 0.01)
        XCTAssertEqual(cumulative.currentMonth, 1_600, accuracy: 0.01)
        XCTAssertEqual(cumulative.lastMonth, 3_200, accuracy: 0.01)
        XCTAssertEqual(bestWeek.totalEarnings, 1_600, accuracy: 0.01)
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

  func testCurrentWeekUsesPrimaryCurrencyAndPreservesBreakdown() async throws {
    let today = Date()
    let yearMonth = today.yearMonth()
    try await withFixture(shifts: [
      ShiftInput(job: 0, date: today.toISODateString(), start: "08:00", end: "12:00"),
      ShiftInput(job: 2, date: today.toISODateString(), start: "12:00", end: "16:00"),
    ]) { service, _, _ in
      let stats = try await service.computeStats(year: yearMonth.year, month: yearMonth.month)
      let secondary = try XCTUnwrap(stats.currentMonthCurrencyAggregate?.secondary.first)
      let week = try XCTUnwrap(stats.thisWeek)

      XCTAssertEqual(stats.currentMonthCurrencyAggregate?.primary.currency, "kr")
      XCTAssertEqual(stats.currentMonthCurrencyAggregate?.secondary.first?.currency, "$")
      XCTAssertEqual(secondary.grossAmount, 800, accuracy: 0.01)
      XCTAssertEqual(week.reduce(0) { $0 + $1.earnings }, 800, accuracy: 0.01)
      XCTAssertEqual(stats.currentMonth.totalHours, 8, accuracy: 0.01)
    }
  }

  func testForeignCurrencyBecomesChartCurrencyWhenDefaultJobHasNoEarnings() async throws {
    try await withFixture(shifts: [ShiftInput(job: 2, date: "2026-05-02")]) { service, _, _ in
      let stats = try await service.computeStats(year: 2_026, month: 5)
      let cumulative = try XCTUnwrap(stats.thisMonthCumulative.last)
      let bestWeek = try XCTUnwrap(stats.bestWeek)
      let mayIncome = try XCTUnwrap(stats.yearlyIncome?.first { $0.monthNumber == 5 })

      XCTAssertEqual(stats.currentMonthCurrencyAggregate?.primary.currency, "$")
      XCTAssertEqual(stats.currentMonth.totalEarnings, 1_600, accuracy: 0.01)
      XCTAssertEqual(cumulative.currentMonth, 1_600, accuracy: 0.01)
      XCTAssertEqual(bestWeek.totalEarnings, 1_600, accuracy: 0.01)
      XCTAssertEqual(mayIncome.earnings, 1_600, accuracy: 0.01)
    }
  }

  private struct ShiftInput {
    let job: Int
    let date: String
    var start = "08:00"
    var end = "16:00"
  }

  // swiftlint:disable:next function_body_length
  private func withFixture(
    shifts: [ShiftInput],
    assertions: (StatsService, String, [String]) async throws -> Void
  ) async throws {
    let userId = UUID().uuidString.lowercased()
    let context = ModelContext(LocalStore.shared.container)
    let now = Date()
    var records: [any PersistentModel] = []
    let settings = LocalUserSettings(
      userId: userId, currency: "kr", serverUpdatedAt: now, serverRevision: 1,
      lastSyncedSnapshot: Data(), localUpdatedAt: now
    )
    records.append(settings)
    var jobIds: [String] = []

    for (index, currency) in ["kr", "kr", "$"].enumerated() {
      let jobId = UUID().uuidString.lowercased()
      jobIds.append(jobId)
      records.append(
        LocalJob(
          id: jobId, userId: userId, name: "Job \(index)", currency: currency,
          isDefault: index == 0, sortOrder: index,
          serverUpdatedAt: now, serverRevision: 1, lastSyncedSnapshot: Data(), localUpdatedAt: now
        ))
      let snapshot = LocalWageSnapshot.from(
        serverRow: TestFixtures.wageSnapshot(hourlyWage: 200, breakEnabled: false, jobId: jobId),
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
