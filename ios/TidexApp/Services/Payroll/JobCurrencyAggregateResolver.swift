import Foundation

struct JobCurrencyAggregateEntry: Codable, Equatable, Identifiable {
  let key: String
  let jobId: String
  let jobName: String
  let currency: String
  let grossAmount: Double
  let netAmount: Double
  let displayAmount: Double
  let shiftCount: Int
  let completedShiftCount: Int
  let plannedShiftCount: Int
  let hasTaxEnabled: Bool

  var id: String { key }
}

struct JobCurrencyAggregateResolution: Codable, Equatable {
  let primary: JobCurrencyAggregateEntry
  let secondary: [JobCurrencyAggregateEntry]
  let hasMixedCurrency: Bool
}

enum JobCurrencyAggregateResolver {
  static func resolve(
    shifts: [ShiftWithComputations],
    jobs: [Job],
    fallbackCurrency: String,
    referenceDate: Date = Date()
  ) -> JobCurrencyAggregateResolution {
    let context = ResolutionContext(jobs: jobs, fallbackCurrency: fallbackCurrency)
    var buckets: [String: MutableBucket] = [:]
    let todayISODate = isoDateString(referenceDate)

    for shift in shifts {
      guard let identity = identity(for: shift, context: context) else { continue }

      var bucket =
        buckets[identity.key]
        ?? MutableBucket(
          jobId: identity.jobId,
          jobName: identity.jobName,
          currency: identity.currency
        )

      bucket.grossAmount += shift.grossPay
      bucket.netAmount += shift.taxEnabled ? shift.netPay : shift.grossPay
      bucket.shiftCount += 1
      bucket.hasTaxEnabled = bucket.hasTaxEnabled || shift.taxEnabled

      if Date.hasShiftEnded(
        shiftDate: shift.shiftDate,
        startTime: shift.startTime,
        endTime: shift.endTime,
        referenceDate: referenceDate
      ) {
        bucket.completedShiftCount += 1
      } else if shift.shiftDate > todayISODate {
        bucket.plannedShiftCount += 1
      }

      buckets[identity.key] = bucket
    }

    let entries = buckets.map { key, value in
      JobCurrencyAggregateEntry(
        key: key,
        jobId: value.jobId,
        jobName: value.jobName,
        currency: value.currency,
        grossAmount: value.grossAmount,
        netAmount: value.netAmount,
        displayAmount: value.hasTaxEnabled ? value.netAmount : value.grossAmount,
        shiftCount: value.shiftCount,
        completedShiftCount: value.completedShiftCount,
        plannedShiftCount: value.plannedShiftCount,
        hasTaxEnabled: value.hasTaxEnabled
      )
    }
    .sorted { lhs, rhs in
      if lhs.grossAmount != rhs.grossAmount {
        return lhs.grossAmount > rhs.grossAmount
      }
      if lhs.shiftCount != rhs.shiftCount {
        return lhs.shiftCount > rhs.shiftCount
      }
      return lhs.jobName.localizedCaseInsensitiveCompare(rhs.jobName) == .orderedAscending
    }

    let primary = selectPrimaryEntry(from: entries, context: context)
    let secondary =
      entries
      .filter { $0.key != primary.key && $0.grossAmount > 0 }
      .sorted { lhs, rhs in
        if lhs.grossAmount != rhs.grossAmount {
          return lhs.grossAmount > rhs.grossAmount
        }
        return lhs.jobName.localizedCaseInsensitiveCompare(rhs.jobName) == .orderedAscending
      }

    let currencies = Set(([primary] + secondary).filter { $0.grossAmount > 0 }.map(\.currency))
    let hasMixedCurrency = currencies.count > 1

    return JobCurrencyAggregateResolution(
      primary: primary,
      secondary: secondary,
      hasMixedCurrency: hasMixedCurrency
    )
  }

  static func shifts(
    matching entry: JobCurrencyAggregateEntry,
    in shifts: [ShiftWithComputations],
    jobs: [Job],
    fallbackCurrency: String
  ) -> [ShiftWithComputations] {
    let context = ResolutionContext(jobs: jobs, fallbackCurrency: fallbackCurrency)

    return shifts.filter { shift in
      guard let identity = identity(for: shift, context: context) else { return false }
      return identity.key == entry.key
    }
  }

  private static func selectPrimaryEntry(
    from entries: [JobCurrencyAggregateEntry],
    context: ResolutionContext
  ) -> JobCurrencyAggregateEntry {
    if let defaultEntry = entries.first(where: {
      $0.jobId == context.defaultJobId && $0.grossAmount > 0
    }) {
      return defaultEntry
    }

    if let highestGross = entries.first(where: { $0.grossAmount > 0 }) {
      return highestGross
    }

    return JobCurrencyAggregateEntry(
      key: "\(context.defaultJobId)|\(context.defaultCurrency)",
      jobId: context.defaultJobId,
      jobName: context.defaultJobName,
      currency: context.defaultCurrency,
      grossAmount: 0,
      netAmount: 0,
      displayAmount: 0,
      shiftCount: 0,
      completedShiftCount: 0,
      plannedShiftCount: 0,
      hasTaxEnabled: false
    )
  }

  private static func identity(
    for shift: ShiftWithComputations,
    context: ResolutionContext
  ) -> ShiftIdentity? {
    let effectiveJobId = shift.shift.job_id ?? context.defaultJobId
    guard !effectiveJobId.isEmpty else { return nil }

    let job = context.jobsById[effectiveJobId]
    let currency = job?.currency ?? context.fallbackCurrency
    let key = "\(effectiveJobId)|\(currency)"

    return ShiftIdentity(
      key: key,
      jobId: effectiveJobId,
      jobName: job?.name ?? context.defaultJobName,
      currency: currency
    )
  }

  private static func isoDateString(_ date: Date) -> String {
    FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone).string(from: date)
  }

  private struct MutableBucket {
    let jobId: String
    let jobName: String
    let currency: String
    var grossAmount: Double = 0
    var netAmount: Double = 0
    var shiftCount: Int = 0
    var completedShiftCount: Int = 0
    var plannedShiftCount: Int = 0
    var hasTaxEnabled: Bool = false
  }

  private struct ShiftIdentity {
    let key: String
    let jobId: String
    let jobName: String
    let currency: String
  }

  private struct ResolutionContext {
    let jobsById: [String: Job]
    let fallbackCurrency: String
    let defaultJobId: String
    let defaultCurrency: String
    let defaultJobName: String

    init(jobs: [Job], fallbackCurrency: String) {
      self.fallbackCurrency = fallbackCurrency
      self.jobsById = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })

      let activeJobs = jobs.filter { $0.deleted_at == nil && $0.archived_at == nil }
      let fallbackDefaultJob =
        activeJobs.first(where: { $0.is_default })
        ?? activeJobs.first
        ?? jobs.first(where: { $0.is_default })
        ?? jobs.first

      self.defaultJobId = fallbackDefaultJob?.id ?? "default"
      self.defaultCurrency = fallbackDefaultJob?.currency ?? fallbackCurrency
      self.defaultJobName = fallbackDefaultJob?.name ?? "Jobb"
    }
  }
}
