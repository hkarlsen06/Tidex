import Foundation
import SwiftUI
import Supabase

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
    let currentMonthGross: Double
    let currentMonthNet: Double?
    let currentMonthShiftCount: Int
    let currentMonthPlannedCount: Int  // Future shifts
    let percentageChangeVsPrevious: Double?
    let currentMonthTaxEnabled: Bool

    // Next Shift Card
    let nextShift: ShiftWithComputations?
    let isNextShiftToday: Bool

    // Metadata
    let currentMonthName: String
    let previousMonthName: String
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

            async let settingsTask = settingsService.fetchSettings(for: userId)
            async let snapshotsTask = snapshotsService.fetchSnapshots(for: userId)
            async let currentShiftsTask = shiftsService.fetchAllShifts(
                for: userId,
                startDate: currentStartDate,
                endDate: currentEndDate
            )
            async let previousShiftsTask = shiftsService.fetchShifts(
                for: userId,
                startDate: previousStartDate,
                endDate: previousEndDate
            )

            let (
                fetchedSettings,
                fetchedSnapshots,
                currentShiftsData,
                fetchedPreviousShifts
            ) = try await (
                settingsTask,
                snapshotsTask,
                currentShiftsTask,
                previousShiftsTask
            )

            self.settings = fetchedSettings
            self.snapshots = fetchedSnapshots

            // Compute current month shifts with payroll
            self.currentMonthShifts = computeShiftsWithPayroll(
                shifts: currentShiftsData.shifts,
                recurring: currentShiftsData.recurring,
                snapshots: fetchedSnapshots,
                year: currentYM.year,
                month: currentYM.month
            )

            // Compute previous month shifts with payroll
            // Note: We reuse recurring shifts from current month fetch for virtual shifts
            self.previousMonthShifts = computeShiftsWithPayroll(
                shifts: fetchedPreviousShifts,
                recurring: currentShiftsData.recurring,
                snapshots: fetchedSnapshots,
                year: previousYM.year,
                month: previousYM.month
            )

            // Build dashboard data
            self.dashboardData = buildDashboardData()

        } catch {
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
                    hourly_wage_snapshot: nil,
                    supplement_rules_snapshot: nil,
                    custom_supplements: recurringShift.date_specific_supplements?[virtual.date],
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
        let payrollDay = settings?.effectivePayrollDay ?? 1
        let currentYM = Date.currentYearMonth()
        let previousYM = Date.previousYearMonth(from: currentYM)

        // Calculate payroll date
        let payrollDate = calculatePayrollDate(year: currentYM.year, month: currentYM.month, day: payrollDay)
        let payrollHasPassed = Date() > payrollDate

        // Previous month totals (for payroll card)
        let prevGross = previousMonthShifts.reduce(0) { $0 + $1.grossPay }
        let prevTaxEnabled = previousMonthShifts.first?.taxEnabled ?? false
        let prevTaxPercent = previousMonthShifts.first?.taxPercentage ?? 0
        let prevTax: Double? = prevTaxEnabled ? prevGross * prevTaxPercent / 100 : nil
        let prevNet: Double? = prevTaxEnabled ? prevGross - (prevTax ?? 0) : nil

        // Current month totals (split by past/future)
        let pastShifts = currentMonthShifts.filter { $0.shiftDate <= today }
        let futureShifts = currentMonthShifts.filter { $0.shiftDate > today }

        let currentGross = pastShifts.reduce(0) { $0 + $1.grossPay }
        let currentTaxEnabled = pastShifts.first?.taxEnabled ?? false
        let currentTaxPercent = pastShifts.first?.taxPercentage ?? 0
        let currentTax: Double? = currentTaxEnabled ? currentGross * currentTaxPercent / 100 : nil
        let currentNet: Double? = currentTaxEnabled ? currentGross - (currentTax ?? 0) : nil

        // Percentage change vs previous month
        let percentChange: Double? = prevGross > 0
            ? ((currentGross - prevGross) / prevGross) * 100
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
            currentMonthGross: currentGross,
            currentMonthNet: currentNet,
            currentMonthShiftCount: pastShifts.count,
            currentMonthPlannedCount: futureShifts.count,
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
