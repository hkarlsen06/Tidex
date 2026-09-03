import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "StatsViewModel")  // swiftlint:disable:this explicit_type_interface line_length prefixed_toplevel_constant
private let startupStatsCacheKey = "statsStartupCacheV1"  // swiftlint:disable:this explicit_type_interface line_length prefixed_toplevel_constant

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
final class StatsViewModel: ObservableObject {  // swiftlint:disable:this explicit_acl explicit_top_level_acl line_length

  // MARK: - Published State

  @Published private(set) var stats: StatsData?  // swiftlint:disable:this explicit_acl
  @Published private(set) var isLoading = false  // swiftlint:disable:this explicit_acl explicit_type_interface
  @Published private(set) var error: Error?  // swiftlint:disable:this explicit_acl

  /// User's selected currency (from settings)
  @Published private(set) var currency: String = "kr"  // swiftlint:disable:this explicit_acl
  @Published private(set) var activeJobs: [Job] = []  // swiftlint:disable:this explicit_acl
  @Published private(set) var selectedJobId: String?  // swiftlint:disable:this explicit_acl

  // MARK: - Month Navigation State (from SharedMonthContext)

  @Published private(set) var displayYear: Int  // swiftlint:disable:this explicit_acl
  @Published private(set) var displayMonth: Int  // swiftlint:disable:this explicit_acl
  @Published private(set) var displayMonthName: String = ""  // swiftlint:disable:this explicit_acl
  @Published private(set) var navigationDirection: MonthNavigationDirection?  // swiftlint:disable:this explicit_acl

  /// Whether viewing the current (real) month
  var isCurrentMonth: Bool {  // swiftlint:disable:this explicit_acl
    SharedMonthContext.shared.isCurrentMonth
  }

  // MARK: - Private State

  private let statsService: StatsService
  private let settingsRepository: SettingsRepository
  private let jobsRepository: JobsRepository
  private let monthContext: SharedMonthContext
  private let syncCoordinator: SyncCoordinator
  private var cancellables = Set<AnyCancellable>()  // swiftlint:disable:this explicit_type_interface
  private var settings: UserSettings?
  private var activeLoadTask: Task<Void, Never>?
  private var loadGeneration: Int = 0

  // MARK: - Initialization

  init(  // swiftlint:disable:this explicit_acl type_contents_order
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

  deinit {  // swiftlint:disable:this type_contents_order
    // Cancel all Combine subscriptions to prevent memory leaks
    // While [weak self] prevents retain cycles, the subscriptions
    // themselves remain active without explicit cancellation
    cancellables.removeAll()
    activeLoadTask?.cancel()
  }

  // MARK: - Month Subscription

  private func setupMonthSubscription() {  // swiftlint:disable:this type_contents_order
    monthContext.monthChanged
      .receive(on: DispatchQueue.main)
      .sink { [weak self] year, month in
        guard let self else { return }  // swiftlint:disable:this conditional_returns_on_newline

        // Update local state
        displayYear = year
        displayMonth = month
        displayMonthName = monthContext.displayMonthName
        navigationDirection = monthContext.navigationDirection

        // Reload stats for new month
        scheduleLoadStats()
      }
      .store(in: &cancellables)
  }

  // MARK: - Startup Cache

  /// Preload local metadata and last known stats snapshot so the first Stats frame is fully composed.
  private func preloadInitialStateFromLocalCache() {  // swiftlint:disable:this type_contents_order
    guard
      let userId = AppCoordinator.shared.getCurrentUserId()
        ?? AuthSessionManager.shared.offlineUserIdFallback()
    else { return }

    let jobs = jobsRepository.getNonDeletedJobs(for: userId)  // swiftlint:disable:this explicit_type_interface
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

    guard let cached = loadStartupStatsCache(for: userId) else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    stats = cached.stats
    currency = cached.currency
    logger.info("Preloaded stats from persisted startup cache")
  }

  private func loadStartupStatsCache(for userId: String) -> StartupStatsCache? {  // swiftlint:disable:this line_length type_contents_order
    guard let data = UserDefaults.standard.data(forKey: startupStatsCacheKey) else {
      return nil
    }

    do {
      let cached = try JSONDecoder().decode(StartupStatsCache.self, from: data)  // swiftlint:disable:this explicit_type_interface line_length
      guard cached.userId == userId else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
      guard cached.year == displayYear, cached.month == displayMonth else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length
      // Keep cache fresh; stale snapshots feel wrong on startup.
      guard Date().timeIntervalSince(cached.cachedAt) < 60 * 60 * 24 else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length no_magic_numbers
      return cached
    } catch {
      logger.warning("Failed to decode startup stats cache: \(error.localizedDescription)")
      return nil
    }
  }

  private func persistStartupStatsCache(stats: StatsData, userId: String) {  // swiftlint:disable:this line_length type_contents_order
    let payload = StartupStatsCache(  // swiftlint:disable:this explicit_type_interface
      userId: userId,
      year: displayYear,
      month: displayMonth,
      stats: stats,
      currency: currency,
      cachedAt: Date()
    )

    do {
      let encoded = try JSONEncoder().encode(payload)  // swiftlint:disable:this explicit_type_interface
      UserDefaults.standard.set(encoded, forKey: startupStatsCacheKey)
    } catch {
      logger.warning("Failed to persist startup stats cache: \(error.localizedDescription)")
    }
  }

  // MARK: - Navigation Methods

  /// Navigate to the previous month
  func goToPreviousMonth() {  // swiftlint:disable:this explicit_acl type_contents_order
    monthContext.goToPreviousMonth()
  }

  /// Navigate to the next month
  func goToNextMonth() {  // swiftlint:disable:this explicit_acl type_contents_order
    monthContext.goToNextMonth()
  }

  /// Reset to current month
  func goToCurrentMonth() {  // swiftlint:disable:this explicit_acl type_contents_order
    monthContext.goToCurrentMonth()
  }

  var shouldShowJobFilter: Bool {  // swiftlint:disable:this explicit_acl
    activeJobs.count > 1
  }

  var selectedJobName: String? {  // swiftlint:disable:this explicit_acl
    guard let selectedJobId else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return activeJobs.first(where: { $0.id == selectedJobId })?.name
  }

  func selectJobFilter(_ jobId: String?) {  // swiftlint:disable:this explicit_acl
    guard selectedJobId != jobId else { return }  // swiftlint:disable:this conditional_returns_on_newline
    selectedJobId = jobId
    scheduleLoadStats()
  }

  // MARK: - Public Methods

  /// Load stats for the displayed month from local data
  func loadStats() async {  // swiftlint:disable:this explicit_acl
    activeLoadTask?.cancel()
    activeLoadTask = nil
    let generation = nextLoadGeneration()  // swiftlint:disable:this explicit_type_interface
    await performLoadStats(generation: generation)
  }

  private func scheduleLoadStats() {
    let generation = nextLoadGeneration()  // swiftlint:disable:this explicit_type_interface
    activeLoadTask?.cancel()
    activeLoadTask = Task { @MainActor [weak self] in
      await self?.performLoadStats(generation: generation)
    }
  }

  private func nextLoadGeneration() -> Int {
    loadGeneration += 1
    return loadGeneration
  }

  private func performLoadStats(generation: Int) async {  // swiftlint:disable:this cyclomatic_complexity function_body_length line_length
    isLoading = true
    error = nil

    do {
      // Load user's currency from settings
      let userId = try await resolveUserIdForLocalStats()  // swiftlint:disable:this explicit_type_interface

      let jobs = jobsRepository.getNonDeletedJobs(for: userId)  // swiftlint:disable:this explicit_type_interface
      activeJobs = jobs
      if let selectedJobId, !jobs.contains(where: { $0.id == selectedJobId }) {
        self.selectedJobId = nil
      }
      if jobs.count <= 1 {
        self.selectedJobId = nil
      }

      if let loadedSettings = settingsRepository.getSettings(for: userId) {
        settings = loadedSettings
        currency =
          jobs.first(where: { $0.id == selectedJobId })?.currency
          ?? loadedSettings.currency
          ?? "kr"
      } else {
        settings = nil
        currency = jobs.first(where: { $0.id == selectedJobId })?.currency ?? "kr"
      }

      let computedStats = try await statsService.computeStats(  // swiftlint:disable:this explicit_type_interface
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
      guard generation == loadGeneration else { return }  // swiftlint:disable:this conditional_returns_on_newline
    } catch {
      guard generation == loadGeneration else { return }  // swiftlint:disable:this conditional_returns_on_newline
      logger.error("Failed to load stats: \(error.localizedDescription)")
      self.error = error
    }

    guard generation == loadGeneration else { return }  // swiftlint:disable:this conditional_returns_on_newline
    isLoading = false
  }

  private func resolveUserIdForLocalStats() async throws -> String {
    do {
      let session = try await AuthSessionManager.shared.getSession()  // swiftlint:disable:this explicit_type_interface
      return session.normalizedUserId
    } catch {
      guard AuthSessionManager.shared.isTransientSessionResolutionError(error),
        let offlineUserId = AuthSessionManager.shared.offlineUserIdFallback()
      else {
        throw error
      }

      logger.info("Using offline user id fallback for local stats")
      return offlineUserId
    }
  }

  /// Refresh stats by syncing first, then recomputing from local data
  func refresh() async {  // swiftlint:disable:this explicit_acl
    // SwiftUI .refreshable can cancel the parent task when the view hierarchy changes.
    // Run refresh work in an unstructured task so sync can complete reliably.
    let refreshTask = Task { @MainActor [weak self] in  // swiftlint:disable:this explicit_type_interface
      guard let self else { return }  // swiftlint:disable:this conditional_returns_on_newline
      await performRefresh()
    }

    _ = await refreshTask.result
  }

  /// Performs pull-to-refresh sync and local recompute.
  private func performRefresh() async {
    logger.info("Pull-to-refresh: triggering sync then local stats recompute")

    do {
      let session = try await AuthSessionManager.shared.getSession()  // swiftlint:disable:this explicit_type_interface
      let syncResult = await syncCoordinator.sync(  // swiftlint:disable:this explicit_type_interface
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
