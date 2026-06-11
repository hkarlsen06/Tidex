import Foundation

struct PayrollReadContext {
  let userId: String
  let settings: UserSettings?
  let snapshots: [WageSnapshot]
  let recurringShifts: [RecurringShiftRow]
  let jobs: [Job]
}

struct PayrollReadMonth: Hashable {
  let year: Int
  let month: Int
}

struct PayrollReadWindow: Hashable {
  let startDate: Date
  let endDate: Date

  internal static func month(year: Int, month: Int) -> Self {
    Self(
      startDate: Date.firstDayOfMonthDate(year: year, month: month),
      endDate: Date.lastDayOfMonthDate(year: year, month: month)
    )
  }

  internal static func visibleCalendarMonth(year: Int, month: Int) -> Self {
    let range = Date.visibleCalendarRange(year: year, month: month)
    return Self(startDate: range.start, endDate: range.end)
  }
}

struct PayrollRawWindowData {
  let window: PayrollReadWindow
  let shifts: [ShiftRow]
  let events: [EventRow]
}

@MainActor
final class MonthlyPayrollReadService {
  static let shared = MonthlyPayrollReadService()

  private struct ContextCacheKey: Hashable {
    let userId: String
    let jobId: String?
  }

  private struct RawWindowCacheKey: Hashable {
    let userId: String
    let jobId: String?
    let startDate: Date
    let endDate: Date
  }

  private struct CacheEntry<Value> {
    let value: Value
    let createdAt: Date
  }

  private static let cacheTTL: TimeInterval = 30
  private static let cacheLock = NSLock()
  private static var cacheGeneration = 0
  private static var contextCache: [ContextCacheKey: CacheEntry<PayrollReadContext>] = [:]
  private static var rawWindowCache: [RawWindowCacheKey: CacheEntry<PayrollRawWindowData>] = [:]

  private let shiftsRepository: ShiftsRepository
  private let eventsRepository: EventsRepository
  private let settingsRepository: SettingsRepository
  private let snapshotsRepository: SnapshotsRepository
  private let recurringShiftsRepository: RecurringShiftsRepository
  private let jobsRepository: JobsRepository
  private let localStore: LocalStore
  private let usesSharedCache: Bool

  init(
    shiftsRepository: ShiftsRepository? = nil,
    eventsRepository: EventsRepository? = nil,
    settingsRepository: SettingsRepository? = nil,
    snapshotsRepository: SnapshotsRepository? = nil,
    recurringShiftsRepository: RecurringShiftsRepository? = nil,
    jobsRepository: JobsRepository? = nil,
    localStore: LocalStore? = nil
  ) {
    self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
    self.eventsRepository = eventsRepository ?? EventsRepository.shared
    self.settingsRepository = settingsRepository ?? SettingsRepository.shared
    self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
    self.recurringShiftsRepository = recurringShiftsRepository ?? RecurringShiftsRepository.shared
    self.jobsRepository = jobsRepository ?? JobsRepository.shared
    self.localStore = localStore ?? LocalStore.shared
    self.usesSharedCache =
      self.shiftsRepository === ShiftsRepository.shared
      && self.eventsRepository === EventsRepository.shared
      && self.settingsRepository === SettingsRepository.shared
      && self.snapshotsRepository === SnapshotsRepository.shared
      && self.recurringShiftsRepository === RecurringShiftsRepository.shared
      && self.jobsRepository === JobsRepository.shared
      && self.localStore === LocalStore.shared
  }

  func invalidateSharedCache(for userId: String? = nil) {
    Self.cacheLock.lock()
    defer { Self.cacheLock.unlock() }
    Self.cacheGeneration += 1

    guard let userId else {
      Self.contextCache.removeAll()
      Self.rawWindowCache.removeAll()
      return
    }

    Self.contextCache = Self.contextCache.filter { $0.key.userId != userId }
    Self.rawWindowCache = Self.rawWindowCache.filter { $0.key.userId != userId }
  }

  func loadContext(for userId: String, jobId: String? = nil) -> PayrollReadContext {
    let key: ContextCacheKey = ContextCacheKey(userId: userId, jobId: jobId)
    if usesSharedCache, let cached = Self.cachedContext(for: key) {
      return cached.value
    }
    let generation: Int = Self.cacheGenerationSnapshot()

    let context: PayrollReadContext = PayrollReadContext(
      userId: userId,
      settings: settingsRepository.getSettings(for: userId),
      snapshots: snapshotsRepository.getSnapshots(for: userId, jobId: jobId),
      recurringShifts: recurringShiftsRepository.getRecurringShifts(for: userId, jobId: jobId),
      jobs: jobsRepository.getNonDeletedJobs(for: userId)
    )
    if usesSharedCache {
      Self.storeContext(context, for: key, generation: generation)
    }
    return context
  }

  internal func loadContextOffMain(  // swiftlint:disable:this type_contents_order
    for userId: String,
    jobId: String? = nil
  ) async -> PayrollReadContext {
    let key: ContextCacheKey = ContextCacheKey(userId: userId, jobId: jobId)
    if usesSharedCache, let cached = Self.cachedContext(for: key) {
      return cached.value
    }
    let generation: Int = Self.cacheGenerationSnapshot()

    async let settings: UserSettings? = localStore.storeActor.fetchUserSettings(userId: userId)
    async let snapshots: [WageSnapshot] = localStore.storeActor.fetchSnapshots(
      userId: userId,
      jobId: jobId
    )
    async let recurringShifts: [RecurringShiftRow] = localStore.storeActor.fetchRecurringShifts(
      userId: userId,
      jobId: jobId
    )
    async let jobs: [Job] = localStore.storeActor.fetchNonDeletedJobs(userId: userId)

    let context: PayrollReadContext = await PayrollReadContext(
      userId: userId,
      settings: settings,
      snapshots: snapshots,
      recurringShifts: recurringShifts,
      jobs: jobs
    )
    if usesSharedCache {
      Self.storeContext(context, for: key, generation: generation)
    }
    return context
  }

  func loadShiftRows(
    for userId: String,
    year: Int,
    month: Int,
    jobId: String? = nil
  ) async -> [ShiftRow] {
    let startDate = Date.firstDayOfMonthDate(year: year, month: month)
    let endDate = Date.lastDayOfMonthDate(year: year, month: month)

    return await shiftsRepository.getShiftsOffMain(
      for: userId,
      startDate: startDate,
      endDate: endDate,
      jobId: jobId
    )
  }

  func loadShiftRows(
    for userId: String,
    startDate: Date,
    endDate: Date,
    jobId: String? = nil
  ) async -> [ShiftRow] {
    await shiftsRepository.getShiftsOffMain(
      for: userId,
      startDate: startDate,
      endDate: endDate,
      jobId: jobId
    )
  }

  func loadShiftRows(
    for userId: String,
    months: [PayrollReadMonth],
    jobId: String? = nil
  ) async -> [PayrollReadMonth: [ShiftRow]] {
    var results: [PayrollReadMonth: [ShiftRow]] = [:]

    for month in months {
      results[month] = await loadShiftRows(
        for: userId,
        year: month.year,
        month: month.month,
        jobId: jobId
      )
    }

    return results
  }

  func loadRawWindow(
    for userId: String,
    window: PayrollReadWindow,
    jobId: String? = nil
  ) async -> PayrollRawWindowData {
    let key = RawWindowCacheKey(
      userId: userId,
      jobId: jobId,
      startDate: window.startDate,
      endDate: window.endDate
    )
    if usesSharedCache, let cached = Self.cachedRawWindow(for: key) {
      return cached.value
    }
    let generation: Int = Self.cacheGenerationSnapshot()

    async let shifts = shiftsRepository.getShiftsOffMain(
      for: userId,
      startDate: window.startDate,
      endDate: window.endDate,
      jobId: jobId
    )
    async let events = eventsRepository.getEventsOffMain(
      for: userId,
      startDate: window.startDate,
      endDate: window.endDate
    )

    let data = await PayrollRawWindowData(window: window, shifts: shifts, events: events)
    if usesSharedCache {
      Self.storeRawWindow(data, for: key, generation: generation)
    }
    return data
  }

  private static func cacheGenerationSnapshot() -> Int {
    cacheLock.lock()
    defer { cacheLock.unlock() }

    return cacheGeneration
  }

  private static func cachedContext(for key: ContextCacheKey) -> CacheEntry<PayrollReadContext>? {
    cacheLock.lock()
    defer { cacheLock.unlock() }

    guard let cached = contextCache[key] else { return nil }
    guard isFresh(cached.createdAt) else {
      contextCache.removeValue(forKey: key)
      return nil
    }
    return cached
  }

  private static func storeContext(
    _ context: PayrollReadContext,
    for key: ContextCacheKey,
    generation: Int
  ) {
    cacheLock.lock()
    defer { cacheLock.unlock() }

    guard generation == cacheGeneration else { return }
    contextCache[key] = CacheEntry(value: context, createdAt: Date())
  }

  private static func cachedRawWindow(for key: RawWindowCacheKey) -> CacheEntry<
    PayrollRawWindowData
  >? {
    cacheLock.lock()
    defer { cacheLock.unlock() }

    guard let cached = rawWindowCache[key] else { return nil }
    guard isFresh(cached.createdAt) else {
      rawWindowCache.removeValue(forKey: key)
      return nil
    }
    return cached
  }

  private static func storeRawWindow(
    _ data: PayrollRawWindowData,
    for key: RawWindowCacheKey,
    generation: Int
  ) {
    cacheLock.lock()
    defer { cacheLock.unlock() }

    guard generation == cacheGeneration else { return }
    rawWindowCache[key] = CacheEntry(value: data, createdAt: Date())
  }

  private static func isFresh(_ createdAt: Date) -> Bool {
    Date().timeIntervalSince(createdAt) < cacheTTL
  }
}
