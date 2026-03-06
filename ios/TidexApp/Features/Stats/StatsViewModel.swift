import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "StatsViewModel")
private let startupStatsCacheKey = "statsStartupCacheV1"

private struct StartupStatsCache: Codable {
  let userId: String
  let year: Int
  let month: Int
  let stats: StatsData
  let currency: String
  let cachedAt: Date
}

// MARK: - Stats View Model

/// View model for the stats tab
/// Computes statistics locally from on-device shift data
@MainActor
final class StatsViewModel: ObservableObject {

  // MARK: - Published State

  @Published private(set) var stats: StatsData?
  @Published private(set) var isLoading = false
  @Published private(set) var error: Error?

  /// User's selected currency (from settings)
  @Published private(set) var currency: String = "kr"
  @Published private(set) var activeJobs: [Job] = []
  @Published private(set) var selectedJobId: String?

  /// Baseline monthly goal from settings (global fallback goal).
  var baselineMonthlyGoal: Int? {
    settings?.monthly_goal.flatMap { $0 > 0 ? $0 : nil }
  }

  /// Month-specific override for the currently displayed month, if present.
  var displayedMonthOverrideGoal: Int? {
    let monthKey = UserSettings.monthKey(year: displayYear, month: displayMonth)
    return settings?.monthly_goals_by_month?[monthKey].flatMap { $0 > 0 ? $0 : nil }
  }

  // MARK: - Month Navigation State (from SharedMonthContext)

  @Published private(set) var displayYear: Int
  @Published private(set) var displayMonth: Int
  @Published private(set) var displayMonthName: String = ""
  @Published private(set) var navigationDirection: MonthNavigationDirection?

  /// Whether viewing the current (real) month
  var isCurrentMonth: Bool {
    SharedMonthContext.shared.isCurrentMonth
  }

  // MARK: - Private State

  private let statsService: StatsService
  private let settingsRepository: SettingsRepository
  private let jobsRepository: JobsRepository
  private let monthContext: SharedMonthContext
  private let syncCoordinator: SyncCoordinator
  private var cancellables = Set<AnyCancellable>()
  private var settings: UserSettings?
  private var activeLoadTask: Task<Void, Never>?
  private var loadGeneration: Int = 0

  // MARK: - Initialization

  init(
    statsService: StatsService? = nil,
    settingsRepository: SettingsRepository? = nil,
    jobsRepository: JobsRepository? = nil,
    monthContext: SharedMonthContext? = nil,
    syncCoordinator: SyncCoordinator? = nil
  ) {
    self.statsService = statsService ?? StatsService.shared
    self.settingsRepository = settingsRepository ?? SettingsRepository.shared
    self.jobsRepository = jobsRepository ?? JobsRepository.shared
    self.monthContext = monthContext ?? SharedMonthContext.shared
    self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared

    // Initialize from shared context
    self.displayYear = self.monthContext.displayYear
    self.displayMonth = self.monthContext.displayMonth
    self.displayMonthName = self.monthContext.displayMonthName

    preloadInitialStateFromLocalCache()

    // Subscribe to month changes
    setupMonthSubscription()
  }

  deinit {
    // Cancel all Combine subscriptions to prevent memory leaks
    // While [weak self] prevents retain cycles, the subscriptions
    // themselves remain active without explicit cancellation
    cancellables.removeAll()
    activeLoadTask?.cancel()
  }

  // MARK: - Month Subscription

  private func setupMonthSubscription() {
    monthContext.monthChanged
      .receive(on: DispatchQueue.main)
      .sink { [weak self] year, month in
        guard let self = self else { return }

        // Update local state
        self.displayYear = year
        self.displayMonth = month
        self.displayMonthName = self.monthContext.displayMonthName
        self.navigationDirection = self.monthContext.navigationDirection

        // Reload stats for new month
        self.scheduleLoadStats()
      }
      .store(in: &cancellables)
  }

  // MARK: - Startup Cache

  /// Preload local metadata and last known stats snapshot so the first Stats frame is fully composed.
  private func preloadInitialStateFromLocalCache() {
    guard let userId = AppCoordinator.shared.getCurrentUserId() else { return }

    let jobs = jobsRepository.getNonDeletedJobs(for: userId)
    activeJobs = jobs
    if jobs.count <= 1 {
      selectedJobId = nil
    }

    if let loadedSettings = settingsRepository.getSettings(for: userId) {
      settings = loadedSettings
      currency = loadedSettings.currency ?? "kr"
    } else {
      settings = nil
    }

    if let inMemoryStats = statsService.stats,
      inMemoryStats.focusMonth.year == displayYear,
      inMemoryStats.focusMonth.month == displayMonth
    {
      stats = inMemoryStats
      logger.info("Preloaded stats from in-memory cache")
      return
    }

    guard let cached = loadStartupStatsCache(for: userId) else { return }
    stats = cached.stats
    currency = cached.currency
    logger.info("Preloaded stats from persisted startup cache")
  }

  private func loadStartupStatsCache(for userId: String) -> StartupStatsCache? {
    guard let data = UserDefaults.standard.data(forKey: startupStatsCacheKey) else {
      return nil
    }

    do {
      let cached = try JSONDecoder().decode(StartupStatsCache.self, from: data)
      guard cached.userId == userId else { return nil }
      guard cached.year == displayYear, cached.month == displayMonth else { return nil }
      // Keep cache fresh; stale snapshots feel wrong on startup.
      guard Date().timeIntervalSince(cached.cachedAt) < 60 * 60 * 24 else { return nil }
      return cached
    } catch {
      logger.warning("Failed to decode startup stats cache: \(error.localizedDescription)")
      return nil
    }
  }

  private func persistStartupStatsCache(stats: StatsData, userId: String) {
    let payload = StartupStatsCache(
      userId: userId,
      year: displayYear,
      month: displayMonth,
      stats: stats,
      currency: currency,
      cachedAt: Date()
    )

    do {
      let encoded = try JSONEncoder().encode(payload)
      UserDefaults.standard.set(encoded, forKey: startupStatsCacheKey)
    } catch {
      logger.warning("Failed to persist startup stats cache: \(error.localizedDescription)")
    }
  }

  // MARK: - Navigation Methods

  /// Navigate to the previous month
  func goToPreviousMonth() {
    monthContext.goToPreviousMonth()
  }

  /// Navigate to the next month
  func goToNextMonth() {
    monthContext.goToNextMonth()
  }

  /// Reset to current month
  func goToCurrentMonth() {
    monthContext.goToCurrentMonth()
  }

  var shouldShowJobFilter: Bool {
    activeJobs.count > 1
  }

  var selectedJobName: String? {
    guard let selectedJobId else { return nil }
    return activeJobs.first(where: { $0.id == selectedJobId })?.name
  }

  func selectJobFilter(_ jobId: String?) {
    guard selectedJobId != jobId else { return }
    selectedJobId = jobId
    scheduleLoadStats()
  }

  // MARK: - Public Methods

  /// Load stats for the displayed month from local data
  func loadStats() async {
    activeLoadTask?.cancel()
    activeLoadTask = nil
    let generation = nextLoadGeneration()
    await performLoadStats(generation: generation)
  }

  private func scheduleLoadStats() {
    let generation = nextLoadGeneration()
    activeLoadTask?.cancel()
    activeLoadTask = Task { @MainActor [weak self] in
      await self?.performLoadStats(generation: generation)
    }
  }

  private func nextLoadGeneration() -> Int {
    loadGeneration += 1
    return loadGeneration
  }

  private func performLoadStats(generation: Int) async {
    isLoading = true
    error = nil

    do {
      // Load user's currency from settings
      let session = try await AuthSessionManager.shared.getSession()
      let userId = session.normalizedUserId

      let jobs = jobsRepository.getNonDeletedJobs(for: userId)
      activeJobs = jobs
      if let selectedJobId, !jobs.contains(where: { $0.id == selectedJobId }) {
        self.selectedJobId = nil
      }
      if jobs.count <= 1 {
        self.selectedJobId = nil
      }

      if let loadedSettings = settingsRepository.getSettings(for: session.normalizedUserId) {
        settings = loadedSettings
        currency =
          jobs.first(where: { $0.id == selectedJobId })?.currency
          ?? loadedSettings.currency
          ?? "kr"
      } else {
        settings = nil
        currency = jobs.first(where: { $0.id == selectedJobId })?.currency ?? "kr"
      }

      let computedStats = try await statsService.computeStats(
        year: displayYear,
        month: displayMonth,
        jobId: selectedJobId
      )
      guard !Task.isCancelled, generation == loadGeneration else {
        logger.info("Ignoring stale stats load (generation \(generation))")
        return
      }
      stats = computedStats
      if selectedJobId == nil {
        persistStartupStatsCache(stats: computedStats, userId: userId)
      }
      logger.info(
        "Loaded stats for \(self.displayYear)-\(self.displayMonth): \(self.stats?.currentMonth.shiftCount ?? 0) shifts"
      )
    } catch is CancellationError {
      logger.info("Stats load cancelled")
      guard generation == loadGeneration else { return }
    } catch {
      guard generation == loadGeneration else { return }
      logger.error("Failed to load stats: \(error.localizedDescription)")
      self.error = error
    }

    guard generation == loadGeneration else { return }
    isLoading = false
  }

  /// Refresh stats by syncing first, then recomputing from local data
  func refresh() async {
    // SwiftUI .refreshable can cancel the parent task when the view hierarchy changes.
    // Run refresh work in an unstructured task so sync can complete reliably.
    let refreshTask = Task { @MainActor [weak self] in
      guard let self = self else { return }
      await self.performRefresh()
    }

    _ = await refreshTask.result
  }

  /// Save month-specific goal override for the displayed month.
  func saveMonthlyGoalForDisplayedMonth(_ goal: Int?) async throws {
    let session = try await AuthSessionManager.shared.getSession()

    let updatedSettings = try await settingsRepository.saveMonthlyGoalForMonth(
      userId: session.normalizedUserId,
      year: displayYear,
      month: displayMonth,
      goal: goal
    )
    if let updatedSettings {
      settings = updatedSettings
    }

    statsService.clearCache()
    await loadStats()
  }

  /// Performs pull-to-refresh sync and local recompute.
  private func performRefresh() async {
    logger.info("Pull-to-refresh: triggering sync then local stats recompute")

    do {
      let session = try await AuthSessionManager.shared.getSession()
      let syncResult = await syncCoordinator.sync(
        reason: .manualRefresh,
        userId: session.normalizedUserId
      )

      if !syncResult.success, let errorMessage = syncResult.error {
        logger.warning("Stats refresh sync had issues: \(errorMessage)")
      }
    } catch {
      // Continue with local recompute so refresh still updates visible data.
      logger.error("Stats refresh sync failed before recompute: \(error.localizedDescription)")
    }

    // Clear cache to force recomputation
    statsService.clearCache()
    await loadStats()
  }
}
