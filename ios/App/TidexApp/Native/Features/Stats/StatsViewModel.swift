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
    private let monthContext: SharedMonthContext
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(statsService: StatsService? = nil, monthContext: SharedMonthContext? = nil) {
        self.statsService = statsService ?? StatsService.shared
        self.monthContext = monthContext ?? SharedMonthContext.shared

        // Initialize from shared context
        self.displayYear = self.monthContext.displayYear
        self.displayMonth = self.monthContext.displayMonth
        self.displayMonthName = self.monthContext.displayMonthName

        // Subscribe to month changes
        setupMonthSubscription()
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

    /// Refresh stats (recompute from local data)
    func refresh() async {
        // Clear cache to force recomputation
        statsService.clearCache()
        await loadStats()
    }
}
