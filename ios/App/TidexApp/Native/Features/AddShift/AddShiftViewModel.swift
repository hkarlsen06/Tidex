import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "AddShiftViewModel")

/// ViewModel for the Add Shift screen
/// Manages state for both single and recurring shift modes
@MainActor
final class AddShiftViewModel: ObservableObject {

    // MARK: - Dependencies

    private let shiftsRepository: ShiftsRepository
    private let recurringRepository: RecurringShiftsRepository
    private let settingsRepository: SettingsRepository
    private let snapshotsRepository: SnapshotsRepository
    private let syncCoordinator: SyncCoordinator

    // MARK: - Mode State

    @Published var mode: AddShiftMode = .single

    // MARK: - Shared State

    @Published var startTime: Date = AddShiftViewModel.defaultStartTime()
    @Published var endTime: Date = AddShiftViewModel.defaultEndTime()
    @Published var displayMonth: Date = Date()
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Single Mode State

    @Published var selectedDates: Set<String> = []  // ISO dates (YYYY-MM-DD)

    // MARK: - Paywall State

    /// Whether to show the paywall sheet
    @Published var showPaywall = false

    /// Set of existing months when paywall is triggered (for display purposes)
    @Published private(set) var existingShiftMonths: Set<DateComponents> = []

    // MARK: - Recurring Mode State

    @Published var repeatInterval: Int = 0  // 0 = weekly, 1 = biweekly, etc.
    @Published var selectedDays: [String: String] = [:]  // weekday "0"-"6" -> anchor ISO date
    @Published var endCondition: EndCondition? = .months(value: 6)
    @Published var showPreviewSheet = false

    // MARK: - Cached Data

    private var cachedShifts: [ShiftRow] = []
    private var cachedRecurringShifts: [RecurringShiftRow] = []
    private var cachedSnapshots: [WageSnapshot] = []
    private var cachedSettings: UserSettings?

    // MARK: - Preview Cache (computed only when preview sheet is shown)

    /// Cached projected dates for preview sheet - computed once when preview is shown
    @Published private(set) var cachedProjectedDates: [String] = []
    /// Cached conflict dates for preview sheet
    @Published private(set) var cachedConflictDates: Set<String> = []

    // MARK: - Navigation Callback

    /// Called when shifts are successfully created - used to navigate to Shifts tab
    var onShiftsCreated: (() -> Void)?

    // MARK: - Initialization

    init(
        shiftsRepository: ShiftsRepository? = nil,
        recurringRepository: RecurringShiftsRepository? = nil,
        settingsRepository: SettingsRepository? = nil,
        snapshotsRepository: SnapshotsRepository? = nil,
        syncCoordinator: SyncCoordinator? = nil
    ) {
        self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
        self.recurringRepository = recurringRepository ?? RecurringShiftsRepository.shared
        self.settingsRepository = settingsRepository ?? SettingsRepository.shared
        self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
        self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
    }

    // MARK: - Computed Properties

    /// Whether the single shift form can be submitted
    var canSubmitSingle: Bool {
        !selectedDates.isEmpty && isValidTimeRange
    }

    /// Whether the recurring shift form can be submitted
    var canSubmitRecurring: Bool {
        !selectedDays.isEmpty && isValidTimeRange
    }

    /// Whether start and end times form a valid range
    private var isValidTimeRange: Bool {
        // Times are always valid - cross-midnight is allowed
        true
    }

    /// Start time as HH:mm string
    var startTimeString: String {
        formatTimeAsHHmm(startTime)
    }

    /// End time as HH:mm string
    var endTimeString: String {
        formatTimeAsHHmm(endTime)
    }

    /// Set of dates that have existing shifts
    var existingShiftDates: Set<String> {
        var dates = Set<String>()

        // Add regular shifts
        for shift in cachedShifts {
            dates.insert(shift.shift_date)
        }

        // Add virtual shifts from recurring patterns
        let virtualDates = generateVirtualShiftDatesForDisplay()
        dates.formUnion(virtualDates)

        return dates
    }

    /// Set of dates that would conflict with the current time selection
    var conflictDates: Set<String> {
        let datesToCheck: [String]
        switch mode {
        case .single:
            datesToCheck = Array(selectedDates)
        case .recurring:
            datesToCheck = projectedRecurringDates
        }

        return ShiftConflictDetector.detectConflicts(
            dates: datesToCheck,
            startTime: startTimeString,
            endTime: endTimeString,
            existingShifts: cachedShifts,
            existingRecurringShifts: cachedRecurringShifts
        )
    }

    /// Projected dates for the recurring pattern
    var projectedRecurringDates: [String] {
        guard !selectedDays.isEmpty else { return [] }

        return RecurringShiftProjector.generateDates(
            selectedDays: selectedDays,
            repeatInterval: repeatInterval,
            endCondition: endCondition
        )
    }

    /// Number of conflicts in the current selection
    var conflictCount: Int {
        conflictDates.count
    }

    /// Preview earnings for selected dates (single mode)
    var previewEarnings: [String: Double] {
        guard canSubmitSingle else { return [:] }

        var result: [String: Double] = [:]

        for dateISO in selectedDates {
            if let earnings = computeEarningsForDate(dateISO) {
                result[dateISO] = earnings
            }
        }

        return result
    }

    // MARK: - Data Loading

    /// Load initial data from repositories
    func loadData() async {
        guard let userId = AppCoordinator.shared.userId else {
            logger.warning("Cannot load data: no user ID")
            return
        }

        // Load settings
        cachedSettings = settingsRepository.getSettings(for: userId)

        // Load snapshots
        cachedSnapshots = snapshotsRepository.getSnapshots(for: userId)

        // Load existing shifts for displayed month (for conflict detection)
        reloadShiftsForDisplayedMonth()

        // Load recurring shifts
        cachedRecurringShifts = recurringRepository.getRecurringShifts(for: userId)

        logger.info("Loaded data: \(self.cachedShifts.count) shifts, \(self.cachedRecurringShifts.count) recurring, \(self.cachedSnapshots.count) snapshots")
    }

    /// Reload shifts for the currently displayed month
    /// Call this when navigating to a new month
    func reloadShiftsForDisplayedMonth() {
        guard let userId = AppCoordinator.shared.userId else { return }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: displayMonth)
        guard let year = components.year, let month = components.month else { return }

        let startDate = Date.firstDayOfMonthDate(year: year, month: month)
        let endDate = Date.lastDayOfMonthDate(year: year, month: month)

        cachedShifts = shiftsRepository.getShifts(for: userId, startDate: startDate, endDate: endDate)
    }

    // MARK: - Single Shift Actions

    /// Toggle selection of a date (single tap behavior)
    func toggleDate(_ dateISO: String) {
        // Toggle single date
        if selectedDates.contains(dateISO) {
            selectedDates.remove(dateISO)
        } else {
            selectedDates.insert(dateISO)
        }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Clear all selected dates
    func clearSelectedDates() {
        selectedDates.removeAll()
    }

    /// Submit single shifts
    func submitSingleShifts() async {
        guard canSubmitSingle else { return }
        guard let userId = AppCoordinator.shared.userId else {
            error = "Not authenticated"
            return
        }

        isLoading = true
        error = nil

        // Get current tier for gating
        let tier = EntitlementService.shared.effectiveTier

        do {
            let sortedDates = selectedDates.sorted()

            for dateISO in sortedDates {
                guard let shiftDate = Date.fromISODateString(dateISO) else {
                    logger.warning("Invalid date: \(dateISO)")
                    continue
                }

                // Use tier-checked creation for free users
                _ = try await shiftsRepository.createShiftWithTierCheck(
                    userId: userId,
                    shiftDate: shiftDate,
                    startTime: startTimeString,
                    endTime: endTimeString,
                    customSupplements: nil,
                    tier: tier
                )
            }

            logger.info("Created \(sortedDates.count) shifts")

            // Clear form
            clearForm()

            // Success feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Notify that shifts changed (for dashboard refresh)
            NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

            // Navigate to Shifts tab
            onShiftsCreated?()

        } catch ShiftCreationError.monthLimitReached(let months) {
            // Show paywall instead of error
            logger.info("Month limit reached, showing paywall. Existing months: \(months.count)")
            existingShiftMonths = months
            showPaywall = true
        } catch {
            logger.error("Failed to create shifts: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Recurring Shift Actions

    /// Toggle anchor date for a weekday
    func toggleAnchorDate(_ dateISO: String) {
        let weekday = weekdayFromDate(dateISO)

        if selectedDays[weekday] == dateISO {
            // Remove this anchor
            selectedDays.removeValue(forKey: weekday)
        } else {
            // Set or replace anchor for this weekday
            selectedDays[weekday] = dateISO
        }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Remove anchor for a specific weekday
    func removeAnchor(weekday: String) {
        selectedDays.removeValue(forKey: weekday)

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Clear all anchors
    func clearAnchors() {
        selectedDays.removeAll()
    }

    /// Show the preview sheet - computes projected dates once
    func showPreview() {
        guard canSubmitRecurring else { return }

        // Compute projected dates once when showing preview
        cachedProjectedDates = RecurringShiftProjector.generateDates(
            selectedDays: selectedDays,
            repeatInterval: repeatInterval,
            endCondition: endCondition
        )

        // Compute conflicts once
        cachedConflictDates = ShiftConflictDetector.detectConflicts(
            dates: cachedProjectedDates,
            startTime: startTimeString,
            endTime: endTimeString,
            existingShifts: cachedShifts,
            existingRecurringShifts: cachedRecurringShifts
        )

        showPreviewSheet = true
    }

    /// Submit recurring shift
    func submitRecurringShift() async {
        guard canSubmitRecurring else { return }
        guard let userId = AppCoordinator.shared.userId else {
            error = "Not authenticated"
            return
        }

        isLoading = true
        error = nil

        do {
            // Use cached conflicts from preview
            let conflicts = cachedConflictDates

            _ = try await recurringRepository.createRecurringShift(
                userId: userId,
                startTime: startTimeString,
                endTime: endTimeString,
                repeatIntervalWeeks: repeatInterval,
                selectedDays: selectedDays,
                endCondition: endCondition,
                exclusions: Array(conflicts),
                dateSpecificSupplements: nil
            )

            logger.info("Created recurring shift with \(self.cachedProjectedDates.count) projected dates, \(conflicts.count) exclusions")

            // Clear form
            clearForm()

            // Dismiss preview sheet
            showPreviewSheet = false

            // Success feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Notify that shifts changed (for dashboard refresh)
            NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

            // Navigate to Shifts tab
            onShiftsCreated?()

        } catch {
            logger.error("Failed to create recurring shift: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Private Helpers

    /// Format Date to HH:mm string
    private func formatTimeAsHHmm(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Get weekday string ("0"-"6") from ISO date
    private func weekdayFromDate(_ dateISO: String) -> String {
        guard let date = Date.fromISODateString(dateISO) else { return "0" }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        // Calendar weekday is 1=Sun, 2=Mon, ..., 7=Sat
        // JavaScript weekday is 0=Sun, 1=Mon, ..., 6=Sat
        return String((weekday - 1) % 7)
    }

    /// Compute earnings for a single date
    private func computeEarningsForDate(_ dateISO: String) -> Double? {
        let snapshot = SnapshotsService.snapshotForDate(dateISO, from: cachedSnapshots)

        let shift = ShiftRow(
            id: "preview-\(dateISO)",
            user_id: nil,
            shift_date: dateISO,
            start_time: startTimeString,
            end_time: endTimeString,
            custom_supplements: nil
        )

        let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)
        return computed.gross
    }

    /// Generate virtual shift dates from recurring patterns for display
    private func generateVirtualShiftDatesForDisplay() -> Set<String> {
        var dates = Set<String>()
        let calendar = Calendar.current

        let now = Date()
        let startYear = calendar.component(.year, from: now)
        let startMonth = calendar.component(.month, from: now)

        // Generate for next 12 months
        for i in 0..<12 {
            var targetMonth = startMonth + i
            var targetYear = startYear

            while targetMonth > 12 {
                targetMonth -= 12
                targetYear += 1
            }

            for recurring in cachedRecurringShifts {
                let virtualShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
                    year: targetYear,
                    month: targetMonth,
                    recurring: recurring
                )

                for virtualShift in virtualShifts {
                    dates.insert(virtualShift.date)
                }
            }
        }

        return dates
    }

    /// Clear the form after successful submission
    private func clearForm() {
        selectedDates.removeAll()
        selectedDays.removeAll()
        error = nil
    }

    /// Default start time (09:00)
    private static func defaultStartTime() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components) ?? Date()
    }

    /// Default end time (17:00)
    private static func defaultEndTime() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 17
        components.minute = 0
        return calendar.date(from: components) ?? Date()
    }
}
