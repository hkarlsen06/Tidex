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

        logger.info("🚀 Starting dashboard load...")

        do {
            guard let userId = try await getCurrentUserId() else {
                logger.error("❌ Not authenticated - no user ID")
                throw DashboardError.notAuthenticated
            }
            logger.info("✅ Got user ID: \(userId)")

            // Fetch data in parallel
            let currentYM = Date.currentYearMonth()
            let previousYM = Date.previousYearMonth(from: currentYM)

            let currentStartDate = Date.firstDayOfMonth(year: currentYM.year, month: currentYM.month)
            let currentEndDate = Date.lastDayOfMonth(year: currentYM.year, month: currentYM.month)
            let previousStartDate = Date.firstDayOfMonth(year: previousYM.year, month: previousYM.month)
            let previousEndDate = Date.lastDayOfMonth(year: previousYM.year, month: previousYM.month)

            logger.info("📅 Date range - Current: \(currentStartDate) to \(currentEndDate), Previous: \(previousStartDate) to \(previousEndDate)")

            // Fetch each service separately for better error isolation
            logger.info("📡 Fetching settings...")
            let fetchedSettings: UserSettings?
            do {
                fetchedSettings = try await settingsService.fetchSettings(for: userId)
                logger.info("✅ Settings fetched: \(fetchedSettings != nil ? "found" : "nil")")
            } catch {
                logger.error("❌ Settings fetch failed: \(error.localizedDescription)")
                throw error
            }

            logger.info("📡 Fetching snapshots...")
            let fetchedSnapshots: [WageSnapshot]
            do {
                fetchedSnapshots = try await snapshotsService.fetchSnapshots(for: userId)
                logger.info("✅ Snapshots fetched: \(fetchedSnapshots.count) snapshots")
            } catch {
                logger.error("❌ Snapshots fetch failed: \(error.localizedDescription)")
                throw error
            }

            logger.info("📡 Fetching current month shifts...")
            let currentShiftsData: (shifts: [ShiftRow], recurring: [RecurringShiftRow])
            do {
                currentShiftsData = try await shiftsService.fetchAllShifts(
                    for: userId,
                    startDate: currentStartDate,
                    endDate: currentEndDate
                )
                logger.info("✅ Current shifts fetched: \(currentShiftsData.shifts.count) shifts, \(currentShiftsData.recurring.count) recurring")
            } catch {
                logger.error("❌ Current shifts fetch failed: \(error.localizedDescription)")
                throw error
            }

            logger.info("📡 Fetching previous month shifts...")
            let fetchedPreviousShifts: [ShiftRow]
            do {
                fetchedPreviousShifts = try await shiftsService.fetchShifts(
                    for: userId,
                    startDate: previousStartDate,
                    endDate: previousEndDate
                )
                logger.info("✅ Previous shifts fetched: \(fetchedPreviousShifts.count) shifts")
            } catch {
                logger.error("❌ Previous shifts fetch failed: \(error.localizedDescription)")
                throw error
            }

            self.settings = fetchedSettings
            self.snapshots = fetchedSnapshots

            // Compute current month shifts with payroll
            logger.info("🧮 Computing current month payroll...")
            self.currentMonthShifts = computeShiftsWithPayroll(
                shifts: currentShiftsData.shifts,
                recurring: currentShiftsData.recurring,
                snapshots: fetchedSnapshots,
                year: currentYM.year,
                month: currentYM.month
            )
            logger.info("✅ Current month computed: \(self.currentMonthShifts.count) shifts")

            // Compute previous month shifts with payroll
            logger.info("🧮 Computing previous month payroll...")
            self.previousMonthShifts = computeShiftsWithPayroll(
                shifts: fetchedPreviousShifts,
                recurring: currentShiftsData.recurring,
                snapshots: fetchedSnapshots,
                year: previousYM.year,
                month: previousYM.month
            )
            logger.info("✅ Previous month computed: \(self.previousMonthShifts.count) shifts")

            // Build dashboard data
            logger.info("🏗️ Building dashboard data...")
            self.dashboardData = buildDashboardData()
            logger.info("✅ Dashboard data built successfully!")

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

    /// Compute shifts with payroll data
    private func computeShiftsWithPayroll(
        shifts: [ShiftRow],
        recurring: [RecurringShiftRow],
        snapshots: [WageSnapshot],
        year: Int,
        month: Int
    ) -> [ShiftWithComputations] {
        var result: [ShiftWithComputations] = []
        let payrollDay = settings?.effectivePayrollDay ?? 1
        let startDate = Date.firstDayOfMonth(year: year, month: month)
        let endDate = Date.lastDayOfMonth(year: year, month: month)

        // Regular shifts
        for shift in shifts {
            let snapshot = snapshotsService.snapshotForDate(shift.shift_date, from: snapshots)
            let taxSettings = snapshotsService.payoutTaxSettings(
                earningsYear: year,
                earningsMonth: month,
                payrollDay: payrollDay,
                from: snapshots
            )

            let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

            result.append(ShiftWithComputations(
                shift: shift,
                computed: computed,
                taxEnabled: taxSettings?.enabled ?? false,
                taxPercentage: taxSettings?.percentage ?? 0
            ))
        }

        // Virtual shifts from recurring patterns
        for recurringShift in recurring {
            let virtualShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
                year: year,
                month: month,
                recurring: recurringShift
            )

            for virtual in virtualShifts {
                // Filter to date range
                guard virtual.date >= startDate && virtual.date <= endDate else { continue }

                // Skip if a real shift exists on this date (avoid duplicates)
                if shifts.contains(where: { $0.shift_date == virtual.date }) { continue }

                // Create virtual shift row
                let virtualRow = ShiftRow(
                    id: "virtual-\(recurringShift.id)-\(virtual.date)",
                    user_id: recurringShift.user_id,
                    shift_date: virtual.date,
                    start_time: recurringShift.cleanStartTime,
                    end_time: recurringShift.cleanEndTime,
                    custom_supplements: recurringShift.date_specific_supplements?[virtual.date],
                    created_at: nil,
                    recurring_id: recurringShift.id,
                    recurring_anchor_weekday: virtual.weekday
                )

                let snapshot = snapshotsService.snapshotForDate(virtual.date, from: snapshots)
                let taxSettings = snapshotsService.payoutTaxSettings(
                    earningsYear: year,
                    earningsMonth: month,
                    payrollDay: payrollDay,
                    from: snapshots
                )

                let computed = PayrollCalculator.computeShift(virtualRow, snapshot: snapshot)

                result.append(ShiftWithComputations(
                    shift: virtualRow,
                    computed: computed,
                    taxEnabled: taxSettings?.enabled ?? false,
                    taxPercentage: taxSettings?.percentage ?? 0
                ))
            }
        }

        // Sort by date
        return result.sorted { $0.shiftDate < $1.shiftDate }
    }

    /// Build the final dashboard data from computed shifts
    private func buildDashboardData() -> DashboardData {
        let today = todayISO()
        let now = Date()
        let payrollDay = settings?.effectivePayrollDay ?? 1
        let currentYM = Date.currentYearMonth()
        let previousYM = Date.previousYearMonth(from: currentYM)

        // Calculate payroll date
        let payrollDate = calculatePayrollDate(year: currentYM.year, month: currentYM.month, day: payrollDay)
        let payrollHasPassed = now > payrollDate

        // Previous month totals (for payroll card)
        let prevGross = previousMonthShifts.reduce(0) { $0 + $1.grossPay }
        let prevTaxEnabled = previousMonthShifts.first?.taxEnabled ?? false
        let prevTaxPercent = previousMonthShifts.first?.taxPercentage ?? 0
        let prevTax: Double? = prevTaxEnabled ? prevGross * prevTaxPercent / 100 : nil
        let prevNet: Double? = prevTaxEnabled ? prevGross - (prevTax ?? 0) : nil

        // Current month: compute totals for ALL shifts (projected) and completed shifts (earned)
        let allGross = currentMonthShifts.reduce(0) { $0 + $1.grossPay }
        let currentTaxEnabled = currentMonthShifts.first?.taxEnabled ?? false
        let currentTaxPercent = currentMonthShifts.first?.taxPercentage ?? 0
        let allTax: Double? = currentTaxEnabled ? allGross * currentTaxPercent / 100 : nil
        let allNet: Double? = currentTaxEnabled ? allGross - (allTax ?? 0) : nil

        // Completed shifts: shifts where end time has passed
        let completedShifts = currentMonthShifts.filter { shift in
            Date.hasShiftEnded(
                shiftDate: shift.shiftDate,
                startTime: shift.startTime,
                endTime: shift.endTime,
                referenceDate: now
            )
        }
        let completedGross = completedShifts.reduce(0) { $0 + $1.grossPay }
        let completedTax: Double? = currentTaxEnabled ? completedGross * currentTaxPercent / 100 : nil
        let completedNet: Double? = currentTaxEnabled ? completedGross - (completedTax ?? 0) : nil

        // Planned shifts: shifts with date in the future (not yet started)
        let plannedShifts = currentMonthShifts.filter { $0.shiftDate > today }

        // Percentage change vs previous month (comparing projected totals)
        let percentChange: Double? = prevGross > 0
            ? ((allGross - prevGross) / prevGross) * 100
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
            previousMonthGross: prevGross,
            previousMonthNet: prevNet,
            previousMonthTax: prevTax,
            previousMonthTaxEnabled: prevTaxEnabled,
            currentMonthGross: allGross,
            currentMonthNet: allNet,
            currentMonthCompletedGross: completedGross,
            currentMonthCompletedNet: completedNet,
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
