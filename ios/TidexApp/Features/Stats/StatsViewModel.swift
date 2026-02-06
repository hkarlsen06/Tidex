import Foundation
import SwiftUI
import Combine
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "StatsViewModel")

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
    private let monthContext: SharedMonthContext
    private let syncCoordinator: SyncCoordinator
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        statsService: StatsService? = nil,
        settingsRepository: SettingsRepository? = nil,
        monthContext: SharedMonthContext? = nil,
        syncCoordinator: SyncCoordinator? = nil
    ) {
        self.statsService = statsService ?? StatsService.shared
        self.settingsRepository = settingsRepository ?? SettingsRepository.shared
        self.monthContext = monthContext ?? SharedMonthContext.shared
        self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared

        // Initialize from shared context
        self.displayYear = self.monthContext.displayYear
        self.displayMonth = self.monthContext.displayMonth
        self.displayMonthName = self.monthContext.displayMonthName

        // Subscribe to month changes
        setupMonthSubscription()
    }

    deinit {
        // Cancel all Combine subscriptions to prevent memory leaks
        // While [weak self] prevents retain cycles, the subscriptions
        // themselves remain active without explicit cancellation
        cancellables.removeAll()
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
                Task {
                    await self.loadStats()
                }
            }
            .store(in: &cancellables)
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

    // MARK: - Public Methods

    /// Load stats for the displayed month from local data
    func loadStats() async {
        isLoading = true
        error = nil

        do {
            // Load user's currency from settings
            let session = try await AuthSessionManager.shared.getSession()
            if let settings = settingsRepository.getSettings(for: session.normalizedUserId) {
                currency = settings.currency ?? "kr"
            }

            stats = try await statsService.computeStats(year: displayYear, month: displayMonth)
            logger.info("Loaded stats for \(self.displayYear)-\(self.displayMonth): \(self.stats?.currentMonth.shiftCount ?? 0) shifts")
        } catch is CancellationError {
            logger.info("Stats load cancelled")
        } catch {
            logger.error("Failed to load stats: \(error.localizedDescription)")
            self.error = error
        }

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
