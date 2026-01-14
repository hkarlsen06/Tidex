import Foundation
import SwiftUI
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "DashboardViewModel")

// MARK: - Dashboard Data

/// Computed dashboard data ready for display
struct DashboardData: Equatable {
    // Payroll Card (Previous Month)
    let payrollDate: Date
    let payrollHasPassed: Bool         // true = previous payout, false = next payout
    let previousMonthGross: Double
    let previousMonthNet: Double?      // nil if tax not enabled
    let previousMonthTax: Double?
    let previousMonthTaxEnabled: Bool

    // Total Card (Current Month)
    let currentMonthGross: Double      // All shifts (projected total)
    let currentMonthNet: Double?       // All shifts net (projected)
    let currentMonthCompletedGross: Double  // Only completed shifts (earned to date)
    let currentMonthCompletedNet: Double?   // Only completed shifts net
    let currentMonthShiftCount: Int    // Total shift count
    let currentMonthCompletedCount: Int     // Completed shifts count
    let currentMonthPlannedCount: Int  // Future shifts
    let percentageChangeVsPrevious: Double?
    let currentMonthTaxEnabled: Bool

    // Next Shift Card
    let nextShift: ShiftWithComputations?
    let isNextShiftToday: Bool

    // Metadata
    let currentMonthName: String
    let previousMonthName: String

    /// Whether there are future shifts (main display should be projected total)
    var hasFutureShifts: Bool {
        currentMonthPlannedCount > 0
    }
}

// MARK: - Dashboard Error

enum DashboardError: Error, LocalizedError {
    case notAuthenticated
    case dataLoadFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .dataLoadFailed(let error):
            return "Failed to load data: \(error.localizedDescription)"
        }
    }
}

// MARK: - Dashboard View Model

@MainActor
final class DashboardViewModel: ObservableObject {

    // MARK: - Dependencies

    private let shiftsService: ShiftsService
    private let settingsService: SettingsService
    private let snapshotsService: SnapshotsService

    // MARK: - Published State

    @Published private(set) var dashboardData: DashboardData?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    // MARK: - Private State

    private var currentMonthShifts: [ShiftWithComputations] = []
    private var previousMonthShifts: [ShiftWithComputations] = []
    private var settings: UserSettings?
    private var snapshots: [WageSnapshot] = []

    // MARK: - Initialization

    init(
        shiftsService: ShiftsService? = nil,
        settingsService: SettingsService? = nil,
        snapshotsService: SnapshotsService? = nil
    ) {
        // Use provided services or default to shared instances
        // Using optional parameters avoids Swift 6 MainActor isolation errors
        self.shiftsService = shiftsService ?? ShiftsService.shared
        self.settingsService = settingsService ?? SettingsService.shared
        self.snapshotsService = snapshotsService ?? SnapshotsService.shared
    }

    // MARK: - Public Methods

    /// Load all dashboard data
    func loadDashboard() async {
        isLoading = true
        error = nil

        do {
            guard let userId = try await getCurrentUserId() else {
                throw DashboardError.notAuthenticated
            }

            // Fetch data in parallel
            let currentYM = Date.currentYearMonth()
            let previousYM = Date.previousYearMonth(from: currentYM)

            let currentStartDate = Date.firstDayOfMonth(year: currentYM.year, month: currentYM.month)
            let currentEndDate = Date.lastDayOfMonth(year: currentYM.year, month: currentYM.month)
            let previousStartDate = Date.firstDayOfMonth(year: previousYM.year, month: previousYM.month)
            let previousEndDate = Date.lastDayOfMonth(year: previousYM.year, month: previousYM.month)

            // Fetch each service separately for better error isolation
            let fetchedSettings = try await settingsService.fetchSettings(for: userId)
            let fetchedSnapshots = try await snapshotsService.fetchSnapshots(for: userId)

            let currentShiftsData = try await shiftsService.fetchAllShifts(
                for: userId,
                startDate: currentStartDate,
                endDate: currentEndDate
            )

            let fetchedPreviousShifts = try await shiftsService.fetchShifts(
                for: userId,
                startDate: previousStartDate,
                endDate: previousEndDate
            )

            self.settings = fetchedSettings
            self.snapshots = fetchedSnapshots

            // Compute current month shifts with payroll using PayrollEngine
            self.currentMonthShifts = PayrollEngine.computeShiftsForMonth(
                year: currentYM.year,
                month: currentYM.month,
                shifts: currentShiftsData.shifts,
                recurring: currentShiftsData.recurring,
                snapshots: fetchedSnapshots,
                settings: fetchedSettings
            )

            // Compute previous month shifts with payroll using PayrollEngine
            self.previousMonthShifts = PayrollEngine.computeShiftsForMonth(
                year: previousYM.year,
                month: previousYM.month,
                shifts: fetchedPreviousShifts,
                recurring: currentShiftsData.recurring,
                snapshots: fetchedSnapshots,
                settings: fetchedSettings
            )

            // DEBUG: Log previous month shifts to identify discrepancy
            logger.info("=== PREVIOUS MONTH SHIFTS DEBUG ===")
            logger.info("Total shifts: \(self.previousMonthShifts.count)")
            logger.info("Regular shifts from DB: \(fetchedPreviousShifts.count)")
            logger.info("Recurring patterns: \(currentShiftsData.recurring.count)")

            // Log recurring patterns
            for recurring in currentShiftsData.recurring {
                logger.info("Recurring: id=\(recurring.id.prefix(8))... | days=\(recurring.selected_days) | interval=\(recurring.repeat_interval_weeks) | times=\(recurring.cleanStartTime)-\(recurring.cleanEndTime)")
            }

            for (index, shift) in self.previousMonthShifts.enumerated() {
                let isVirtual = shift.id.hasPrefix("virtual-")
                let recurringId = isVirtual ? String(shift.id.dropFirst(8).prefix(8)) : "n/a"
                logger.info("[\(index + 1)] \(shift.shiftDate) | \(shift.startTime)-\(shift.endTime) | gross=\(String(format: "%.2f", shift.grossPay)) | \(isVirtual ? "VIRTUAL(\(recurringId))" : "REAL")")
            }
            let totalGross = self.previousMonthShifts.reduce(0) { $0 + $1.grossPay }
            logger.info("Total gross: \(String(format: "%.2f", totalGross))")
            logger.info("=== END DEBUG ===")

            // Build dashboard data
            self.dashboardData = buildDashboardData()

        } catch {
            logger.error("❌ Dashboard load failed: \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    logger.error("   DecodingError.keyNotFound: key '\(key.stringValue)' not found, path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .typeMismatch(let type, let context):
                    logger.error("   DecodingError.typeMismatch: expected \(type), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .valueNotFound(let type, let context):
                    logger.error("   DecodingError.valueNotFound: expected \(type), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .dataCorrupted(let context):
                    logger.error("   DecodingError.dataCorrupted: \(context.debugDescription), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                @unknown default:
                    logger.error("   DecodingError: unknown")
                }
            }
            self.error = DashboardError.dataLoadFailed(underlying: error)
        }

        isLoading = false
    }

    // MARK: - Private Methods

    /// Get current authenticated user ID
    private func getCurrentUserId() async throws -> String? {
        let session = try await supabase.auth.session
        return session.user.id.uuidString.lowercased()
    }

    /// Build the final dashboard data from computed shifts
    /// Uses PayrollEngine.summarizeShiftTotals for correct half-tax and conflict exclusion
    private func buildDashboardData() -> DashboardData {
        let today = todayISO()
        let now = Date()
        let payrollDay = settings?.effectivePayrollDay ?? 1
        let halfTaxMonth = settings?.half_tax_month
        let currentYM = Date.currentYearMonth()
        let previousYM = Date.previousYearMonth(from: currentYM)

        // Calculate payroll date for current month
        let payrollDate = calculatePayrollDate(year: currentYM.year, month: currentYM.month, day: payrollDay)
        let payrollHasPassed = now > payrollDate

        // Previous month totals using PayrollEngine (for payroll card)
        // This correctly applies half-tax and conflict exclusion
        let prevTotals = PayrollEngine.summarizeShiftTotals(
            shifts: previousMonthShifts,
            halfTaxMonth: halfTaxMonth,
            earningsMonth: previousYM.month,
            now: now
        )
        let prevTaxEnabled = previousMonthShifts.first?.taxEnabled ?? false
        let prevTax: Double? = prevTaxEnabled ? prevTotals.gross - prevTotals.net : nil

        // Current month totals using PayrollEngine
        // This correctly applies half-tax and conflict exclusion
        let currentTotals = PayrollEngine.summarizeShiftTotals(
            shifts: currentMonthShifts,
            halfTaxMonth: halfTaxMonth,
            earningsMonth: currentYM.month,
            now: now
        )
        let currentTaxEnabled = currentMonthShifts.first?.taxEnabled ?? false

        // Count completed and planned shifts
        let completedShifts = currentMonthShifts.filter { shift in
            Date.hasShiftEnded(
                shiftDate: shift.shiftDate,
                startTime: shift.startTime,
                endTime: shift.endTime,
                referenceDate: now
            )
        }
        let plannedShifts = currentMonthShifts.filter { $0.shiftDate > today }

        // Percentage change vs previous month (comparing projected totals)
        let percentChange: Double? = prevTotals.gross > 0
            ? ((currentTotals.gross - prevTotals.gross) / prevTotals.gross) * 100
            : nil

        // Next shift (first shift from today onwards)
        let nextShift = currentMonthShifts.first { $0.shiftDate >= today }
        let isNextShiftToday = nextShift?.shiftDate == today

        // Month names for display
        let currentMonthName = monthName(year: currentYM.year, month: currentYM.month)
        let previousMonthName = monthName(year: previousYM.year, month: previousYM.month)

        return DashboardData(
            payrollDate: payrollDate,
            payrollHasPassed: payrollHasPassed,
            previousMonthGross: prevTotals.gross,
            previousMonthNet: prevTaxEnabled ? prevTotals.net : nil,
            previousMonthTax: prevTax,
            previousMonthTaxEnabled: prevTaxEnabled,
            currentMonthGross: currentTotals.gross,
            currentMonthNet: currentTaxEnabled ? currentTotals.net : nil,
            currentMonthCompletedGross: currentTotals.completedGross,
            currentMonthCompletedNet: currentTaxEnabled ? currentTotals.completedNet : nil,
            currentMonthShiftCount: currentMonthShifts.count,
            currentMonthCompletedCount: completedShifts.count,
            currentMonthPlannedCount: plannedShifts.count,
            percentageChangeVsPrevious: percentChange,
            currentMonthTaxEnabled: currentTaxEnabled,
            nextShift: nextShift,
            isNextShiftToday: isNextShiftToday,
            currentMonthName: currentMonthName,
            previousMonthName: previousMonthName
        )
    }

    // MARK: - Helper Methods

    private func calculatePayrollDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = Date.osloTimeZone
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }

    private func monthName(year: Int, month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        formatter.locale = Locale(identifier: LocalizationManager.shared.currentLocale.localeIdentifier)
        return formatter.string(from: date)
    }
}
