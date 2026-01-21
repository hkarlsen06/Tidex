import Foundation
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "StatsService")

// MARK: - Stats Service

/// Service for computing stats locally from on-device data
/// Uses the same PayrollEngine as the Dashboard for consistent calculations
@MainActor
final class StatsService: ObservableObject {
    static let shared = StatsService()

    // MARK: - Dependencies

    private let shiftsRepository: ShiftsRepository
    private let settingsRepository: SettingsRepository
    private let snapshotsRepository: SnapshotsRepository
    private let recurringShiftsRepository: RecurringShiftsRepository

    // MARK: - Published State

    @Published private(set) var stats: StatsData?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    // MARK: - Private State

    private var cachedUserId: String?

    // MARK: - Initialization

    init(
        shiftsRepository: ShiftsRepository? = nil,
        settingsRepository: SettingsRepository? = nil,
        snapshotsRepository: SnapshotsRepository? = nil,
        recurringShiftsRepository: RecurringShiftsRepository? = nil
    ) {
        self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
        self.settingsRepository = settingsRepository ?? SettingsRepository.shared
        self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
        self.recurringShiftsRepository = recurringShiftsRepository ?? RecurringShiftsRepository.shared
    }

    // MARK: - Public API

    /// Compute stats for a specific month from local data
    /// - Parameters:
    ///   - year: Year to compute stats for (defaults to current year)
    ///   - month: Month to compute stats for (defaults to current month)
    /// - Returns: Computed stats data
    func computeStats(
        year: Int? = nil,
        month: Int? = nil
    ) async throws -> StatsData {
        let calendar = Calendar.current
        let now = Date()
        let targetYear = year ?? calendar.component(.year, from: now)
        let targetMonth = month ?? calendar.component(.month, from: now)

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Get user ID
            if cachedUserId == nil {
                let session = try await supabase.auth.session
                cachedUserId = session.user.id.uuidString.lowercased()
            }

            guard let userId = cachedUserId else {
                throw StatsServiceError.notAuthenticated
            }

            // Load data from local repositories
            guard let settings = settingsRepository.getSettings(for: userId) else {
                throw StatsServiceError.noLocalData
            }

            let snapshots = snapshotsRepository.getSnapshots(for: userId)
            let recurringShifts = recurringShiftsRepository.getRecurringShifts(for: userId)

            // Calculate date ranges
            let currentYM = (year: targetYear, month: targetMonth)
            let previousYM = Date.previousYearMonth(from: currentYM)

            let currentStartDate = Date.firstDayOfMonthDate(year: currentYM.year, month: currentYM.month)
            let currentEndDate = Date.lastDayOfMonthDate(year: currentYM.year, month: currentYM.month)
            let previousStartDate = Date.firstDayOfMonthDate(year: previousYM.year, month: previousYM.month)
            let previousEndDate = Date.lastDayOfMonthDate(year: previousYM.year, month: previousYM.month)

            // Load shifts from local repositories
            let currentMonthShiftsRaw = shiftsRepository.getShifts(
                for: userId,
                startDate: currentStartDate,
                endDate: currentEndDate
            )
            let previousMonthShiftsRaw = shiftsRepository.getShifts(
                for: userId,
                startDate: previousStartDate,
                endDate: previousEndDate
            )

            // Compute shifts with payroll using PayrollEngine
            let currentMonthShifts = PayrollEngine.computeShiftsForMonth(
                year: currentYM.year,
                month: currentYM.month,
                shifts: currentMonthShiftsRaw,
                recurring: recurringShifts,
                snapshots: snapshots,
                settings: settings
            )

            let previousMonthShifts = PayrollEngine.computeShiftsForMonth(
                year: previousYM.year,
                month: previousYM.month,
                shifts: previousMonthShiftsRaw,
                recurring: recurringShifts,
                snapshots: snapshots,
                settings: settings
            )

            // Get totals using PayrollEngine
            let halfTaxMonth = settings.half_tax_month
            let currentTotals = PayrollEngine.summarizeShiftTotals(
                shifts: currentMonthShifts,
                halfTaxMonth: halfTaxMonth,
                earningsMonth: currentYM.month,
                now: now
            )
            let previousTotals = PayrollEngine.summarizeShiftTotals(
                shifts: previousMonthShifts,
                halfTaxMonth: halfTaxMonth,
                earningsMonth: previousYM.month,
                now: now
            )

            // Calculate total hours
            let currentHours = currentMonthShifts.reduce(0) { $0 + $1.paidHours }
            let previousHours = previousMonthShifts.reduce(0) { $0 + $1.paidHours }

            // Get tax settings from first shift or snapshots
            let taxEnabled = currentMonthShifts.first?.taxEnabled ?? false
            let taxPercentage = currentMonthShifts.first?.taxPercentage ?? 0

            // Calculate percentage change
            let percentageChange: Double?
            if previousTotals.gross > 0 {
                percentageChange = ((currentTotals.gross - previousTotals.gross) / previousTotals.gross) * 100
            } else if currentTotals.gross > 0 {
                percentageChange = nil // Can't compute meaningful change from zero
            } else {
                percentageChange = nil
            }

            // Build monthly goal
            let monthlyGoal: MonthlyGoal
            if let goalTarget = settings.monthly_goal, goalTarget > 0 {
                let progress = currentTotals.net
                let percentage = (progress / Double(goalTarget)) * 100
                let remaining = max(Double(goalTarget) - progress, 0)
                monthlyGoal = MonthlyGoal(
                    enabled: true,
                    target: Double(goalTarget),
                    progress: progress,
                    percentage: percentage,
                    remaining: remaining
                )
            } else {
                monthlyGoal = MonthlyGoal(
                    enabled: false,
                    target: 0,
                    progress: 0,
                    percentage: 0,
                    remaining: 0
                )
            }

            // Build stats data
            let statsData = StatsData(
                focusMonth: FocusMonth(year: targetYear, month: targetMonth),
                tax: TaxSettings(enabled: taxEnabled, percentage: taxPercentage),
                currentMonth: MonthStats(
                    totalEarnings: currentTotals.gross,
                    totalEarningsNet: currentTotals.net,
                    totalHours: currentHours,
                    shiftCount: currentMonthShifts.count
                ),
                lastMonth: MonthStats(
                    totalEarnings: previousTotals.gross,
                    totalEarningsNet: previousTotals.net,
                    totalHours: previousHours,
                    shiftCount: previousMonthShifts.count
                ),
                percentageChange: percentageChange,
                monthlyGoal: monthlyGoal
            )

            stats = statsData
            logger.info("Computed stats: \(currentMonthShifts.count) shifts, \(Int(currentHours))h, \(Int(currentTotals.gross)) gross")

            return statsData

        } catch let error as StatsServiceError {
            self.error = error
            throw error
        } catch {
            let wrappedError = StatsServiceError.computationFailed(underlying: error)
            self.error = wrappedError
            throw wrappedError
        }
    }

    /// Clear cached data
    func clearCache() {
        stats = nil
        cachedUserId = nil
    }
}

// MARK: - Errors

enum StatsServiceError: Error, LocalizedError {
    case notAuthenticated
    case noLocalData
    case computationFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .noLocalData:
            return "No local data available. Please wait for sync to complete."
        case .computationFailed(let error):
            return "Failed to compute stats: \(error.localizedDescription)"
        }
    }
}
