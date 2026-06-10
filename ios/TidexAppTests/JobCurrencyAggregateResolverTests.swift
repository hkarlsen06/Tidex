import Nimble
import XCTest

@testable import Tidex

final class JobCurrencyAggregateResolverTests: XCTestCase {
  func testResolveUsesDefaultJobAsPrimaryWhenItHasEarnings() {
    let jobs = [
      TestFixtures.job(id: "job-default", isDefault: true, currency: "kr"),
      TestFixtures.job(id: "job-usd", isDefault: false, currency: "$"),
    ]
    let shifts = [
      TestFixtures.computedShift(
        id: "s-default",
        shiftDate: "2026-03-01",
        startTime: "08:00",
        endTime: "16:00",
        jobId: "job-default",
        gross: 800
      ),
      TestFixtures.computedShift(
        id: "s-usd",
        shiftDate: "2026-03-02",
        startTime: "08:00",
        endTime: "16:00",
        jobId: "job-usd",
        gross: 1_200
      ),
    ]

    let resolution = JobCurrencyAggregateResolver.resolve(
      shifts: shifts,
      jobs: jobs,
      fallbackCurrency: "kr",
      referenceDate: Date.fromDateAndTime("2026-03-31", time: "18:00") ?? Date()
    )

    XCTAssertEqual(resolution.primary.jobId, "job-default")
    XCTAssertEqual(resolution.primary.currency, "kr")
    XCTAssertTrue(resolution.hasMixedCurrency)
    XCTAssertEqual(resolution.secondary.count, 1)
    XCTAssertEqual(resolution.secondary.first?.jobId, "job-usd")
  }

  func testResolveFallsBackToHighestGrossWhenDefaultJobHasNoEarnings() {
    let jobs = [
      TestFixtures.job(id: "job-default", isDefault: true, currency: "kr"),
      TestFixtures.job(id: "job-eur", isDefault: false, currency: "EUR"),
    ]
    let shifts = [
      TestFixtures.computedShift(
        id: "s-eur",
        shiftDate: "2026-03-03",
        startTime: "08:00",
        endTime: "16:00",
        jobId: "job-eur",
        gross: 1_400
      )
    ]

    let resolution = JobCurrencyAggregateResolver.resolve(
      shifts: shifts,
      jobs: jobs,
      fallbackCurrency: "kr",
      referenceDate: Date.fromDateAndTime("2026-03-31", time: "18:00") ?? Date()
    )

    XCTAssertEqual(resolution.primary.jobId, "job-eur")
    XCTAssertEqual(resolution.primary.currency, "EUR")
    XCTAssertEqual(resolution.secondary.count, 0)
  }

  func testResolveAggregatesSameCurrencyJobsIntoPrimaryDisplayBucket() {
    let jobs = [
      TestFixtures.job(id: "job-default", isDefault: true, currency: "kr"),
      TestFixtures.job(id: "job-extra", isDefault: false, currency: "kr"),
    ]
    let shifts = [
      TestFixtures.computedShift(
        id: "s-default",
        shiftDate: "2026-03-01",
        startTime: "08:00",
        endTime: "16:00",
        jobId: "job-default",
        gross: 1_000
      ),
      TestFixtures.computedShift(
        id: "s-extra",
        shiftDate: "2026-03-02",
        startTime: "08:00",
        endTime: "16:00",
        jobId: "job-extra",
        gross: 2_000
      ),
    ]

    let resolution = JobCurrencyAggregateResolver.resolve(
      shifts: shifts,
      jobs: jobs,
      fallbackCurrency: "kr",
      referenceDate: Date.fromDateAndTime("2026-03-31", time: "18:00") ?? Date()
    )
    let primaryShifts = JobCurrencyAggregateResolver.shifts(
      matching: resolution.primary,
      in: shifts,
      jobs: jobs,
      fallbackCurrency: "kr"
    )

    XCTAssertEqual(resolution.primary.jobId, "job-default")
    XCTAssertEqual(resolution.primary.currency, "kr")
    expect(resolution.primary.grossAmount).to(beCloseTo(3_000, within: 0.0001))
    expect(resolution.primary.displayAmount).to(beCloseTo(3_000, within: 0.0001))
    XCTAssertEqual(resolution.primary.shiftCount, 2)
    XCTAssertFalse(resolution.hasMixedCurrency)
    XCTAssertTrue(resolution.secondary.isEmpty)
    XCTAssertEqual(Set(primaryShifts.map(\.id)), Set(["s-default", "s-extra"]))
  }

  func testResolveAggregatesPrimaryCurrencyWhenOtherCurrenciesExist() {
    let jobs = [
      TestFixtures.job(id: "job-default", isDefault: true, currency: "kr"),
      TestFixtures.job(id: "job-extra", isDefault: false, currency: "kr"),
      TestFixtures.job(id: "job-usd", isDefault: false, currency: "$"),
    ]
    let shifts = [
      TestFixtures.computedShift(
        id: "s-default",
        shiftDate: "2026-03-01",
        startTime: "08:00",
        endTime: "16:00",
        jobId: "job-default",
        gross: 1_000
      ),
      TestFixtures.computedShift(
        id: "s-extra",
        shiftDate: "2026-03-02",
        startTime: "08:00",
        endTime: "16:00",
        jobId: "job-extra",
        gross: 500
      ),
      TestFixtures.computedShift(
        id: "s-usd",
        shiftDate: "2026-03-03",
        startTime: "08:00",
        endTime: "16:00",
        jobId: "job-usd",
        gross: 2_000
      ),
    ]

    let resolution = JobCurrencyAggregateResolver.resolve(
      shifts: shifts,
      jobs: jobs,
      fallbackCurrency: "kr",
      referenceDate: Date.fromDateAndTime("2026-03-31", time: "18:00") ?? Date()
    )
    let primaryShifts = JobCurrencyAggregateResolver.shifts(
      matching: resolution.primary,
      in: shifts,
      jobs: jobs,
      fallbackCurrency: "kr"
    )

    XCTAssertEqual(resolution.primary.jobId, "job-default")
    XCTAssertEqual(resolution.primary.currency, "kr")
    expect(resolution.primary.grossAmount).to(beCloseTo(1_500, within: 0.0001))
    XCTAssertTrue(resolution.hasMixedCurrency)
    XCTAssertEqual(resolution.secondary.count, 1)
    XCTAssertEqual(resolution.secondary.first?.jobId, "job-usd")
    XCTAssertEqual(Set(primaryShifts.map(\.id)), Set(["s-default", "s-extra"]))
    XCTAssertTrue(
      JobCurrencyAggregateResolver.matches(
        entry: resolution.primary,
        jobId: "job-default",
        jobs: jobs,
        fallbackCurrency: "kr"
      )
    )
    XCTAssertTrue(
      JobCurrencyAggregateResolver.matches(
        entry: resolution.primary,
        jobId: "job-extra",
        jobs: jobs,
        fallbackCurrency: "kr"
      )
    )
    XCTAssertFalse(
      JobCurrencyAggregateResolver.matches(
        entry: resolution.primary,
        jobId: "job-usd",
        jobs: jobs,
        fallbackCurrency: "kr"
      )
    )
  }

  func testResolveReturnsZeroPrimaryInDefaultJobCurrencyWhenMonthIsEmpty() {
    let jobs = [
      TestFixtures.job(id: "job-default", isDefault: true, currency: "kr"),
      TestFixtures.job(id: "job-usd", isDefault: false, currency: "$"),
    ]

    let resolution = JobCurrencyAggregateResolver.resolve(
      shifts: [],
      jobs: jobs,
      fallbackCurrency: "kr"
    )

    XCTAssertEqual(resolution.primary.jobId, "job-default")
    XCTAssertEqual(resolution.primary.currency, "kr")
    XCTAssertEqual(resolution.primary.displayAmount, 0, accuracy: 0.0001)
    XCTAssertFalse(resolution.hasMixedCurrency)
    XCTAssertTrue(resolution.secondary.isEmpty)
  }

  func testResolveExcludesZeroSecondaryEntriesFromBreakdown() {
    let jobs = [
      TestFixtures.job(id: "job-default", isDefault: true, currency: "kr"),
      TestFixtures.job(id: "job-usd", isDefault: false, currency: "$"),
    ]
    let shifts = [
      TestFixtures.computedShift(
        id: "s-default",
        shiftDate: "2026-03-10",
        startTime: "08:00",
        endTime: "16:00",
        jobId: "job-default",
        gross: 1_000
      ),
      TestFixtures.computedShift(
        id: "s-usd-zero",
        shiftDate: "2026-03-11",
        startTime: "08:00",
        endTime: "16:00",
        jobId: "job-usd",
        gross: 0
      ),
    ]

    let resolution = JobCurrencyAggregateResolver.resolve(
      shifts: shifts,
      jobs: jobs,
      fallbackCurrency: "kr",
      referenceDate: Date.fromDateAndTime("2026-03-31", time: "18:00") ?? Date()
    )

    XCTAssertEqual(resolution.primary.jobId, "job-default")
    XCTAssertTrue(resolution.secondary.isEmpty)
    XCTAssertFalse(resolution.hasMixedCurrency)
  }
}
