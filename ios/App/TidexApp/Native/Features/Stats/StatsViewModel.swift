import Foundation
import SwiftUI
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

    // MARK: - Private State

    private let statsService: StatsService

    // MARK: - Initialization

    init(statsService: StatsService? = nil) {
        self.statsService = statsService ?? StatsService.shared
    }

    // MARK: - Public Methods

    /// Load stats for the current month from local data
    func loadStats() async {
        isLoading = true
        error = nil

        do {
            stats = try await statsService.computeStats()
            logger.info("Loaded stats: \(self.stats?.currentMonth.shiftCount ?? 0) shifts")
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
