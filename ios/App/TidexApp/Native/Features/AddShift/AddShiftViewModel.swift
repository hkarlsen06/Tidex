import Foundation
import SwiftUI
import Combine
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "AddShiftViewModel")

// MARK: - Calendar Display Data

/// Pre-computed display data for calendar cells to avoid redundant computation
struct CalendarDisplayData {
    /// Set of dates that have existing shifts
    let existingShiftDates: Set<String>
    /// Earnings by date for existing shifts
    let existingShiftEarnings: [String: Double]
    /// Virtual shifts with computed earnings (cached)
    let virtualShifts: [VirtualShiftWithEarnings]
    /// Year and month this data is for
    let year: Int
    let month: Int
    /// Timestamp for cache invalidation
    let timestamp: Date

    /// Virtual shift with computed earnings
    struct VirtualShiftWithEarnings {
        let date: String
        let earnings: Double
    }

    /// Check if cache is valid for the given month
    func isValid(for year: Int, month: Int) -> Bool {
        self.year == year && self.month == month
    }
}

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
    private let monthContext: SharedMonthContext
    private let addShiftCoordinator: AddShiftCoordinator

    // MARK: - Mode State

    @Published var mode: AddShiftMode = .single {
        didSet { publishStateToCoordinator() }
    }

    // MARK: - Shared State

    @Published var startTime: Date? = nil {
        didSet {
            // Debounce time changes - schedule recomputation
            schedulePreviewUpdate()
            publishStateToCoordinator()
        }
    }
    @Published var endTime: Date? = nil {
        didSet {
            // Debounce time changes - schedule recomputation
            schedulePreviewUpdate()
            publishStateToCoordinator()
        }
    }
    @Published var isLoading = false {
        didSet { publishStateToCoordinator() }
    }
    @Published var error: String?

    // MARK: - Time Input Debouncing

    /// Debounce timer for time input changes
    private var previewUpdateTask: Task<Void, Never>?

    /// Debounce delay in seconds (wait for user to finish typing)
    private static let previewDebounceDelay: UInt64 = 300_000_000 // 300ms

    /// Display month as Date - computed from SharedMonthContext
    /// Setter updates the SharedMonthContext to sync with other tabs
    var displayMonth: Date {
        get {
            var components = DateComponents()
            components.year = monthContext.displayYear
            components.month = monthContext.displayMonth
            components.day = 1
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month], from: newValue)
            if let year = components.year, let month = components.month {
                // Update tracking immediately to prevent the subscription from double-triggering
                lastObservedYear = year
                lastObservedMonth = month

                // Update shared context (this will trigger other tabs)
                monthContext.navigateTo(year: year, month: month)

                // Notify SwiftUI that the view should update
                objectWillChange.send()
            }
        }
    }

    /// Subscription to SharedMonthContext changes
    private var monthContextCancellable: AnyCancellable?

    /// Subscription to tab bar add action trigger
    private var addActionCancellable: AnyCancellable?

    /// Track the last observed month to detect changes
    private var lastObservedYear: Int = 0
    private var lastObservedMonth: Int = 0

    /// Direction of last navigation (for animations) - synced from SharedMonthContext
    @Published private(set) var navigationDirection: MonthNavigationDirection?

    // MARK: - Display Properties (from SharedMonthContext)

    /// Currently displayed year - synced from SharedMonthContext
    var displayYear: Int { monthContext.displayYear }

    /// Currently displayed month 1-12 - synced from SharedMonthContext
    var displayMonthNumber: Int { monthContext.displayMonth }

    /// Whether viewing the current (real) month
    var isCurrentMonth: Bool { monthContext.isCurrentMonth }

    /// Computed month name for display
    var displayMonthName: String { monthContext.displayMonthName }

    // MARK: - Single Mode State

    @Published var selectedDates: Set<String> = [] {  // ISO dates (YYYY-MM-DD)
        didSet { publishStateToCoordinator() }
    }

    // MARK: - Paywall State

    /// Whether to show the month limit sheet
    @Published var showMonthLimitSheet = false

    /// Set of existing months when paywall is triggered (for display purposes)
    @Published private(set) var existingShiftMonths: Set<DateComponents> = []

    /// Target month the user is trying to add shifts to (for month limit sheet)
    @Published private(set) var targetMonth: DateComponents = DateComponents()

    // MARK: - Recurring Mode State

    @Published var repeatInterval: Int = 0  // 0 = weekly, 1 = biweekly, etc.
    @Published var selectedDays: [String: String] = [:] {  // weekday "0"-"6" -> anchor ISO date
        didSet { publishStateToCoordinator() }
    }
    @Published var endCondition: EndCondition? = .months(value: 6)
    @Published var showPreviewSheet = false

    // MARK: - Cached Data

    /// Triggers view updates when cached data changes
    /// We use this instead of making cachedShifts @Published to avoid exposing internal data
    @Published private var cacheVersion: Int = 0

    private var cachedShifts: [ShiftRow] = []
    private var cachedRecurringShifts: [RecurringShiftRow] = []
    private var cachedSnapshots: [WageSnapshot] = []
    private var cachedSettings: UserSettings?

    // MARK: - Performance Optimized Caches

    /// Cached calendar display data - computed once per month, not per view update
    @Published private(set) var cachedDisplayData: CalendarDisplayData?

    /// Cached conflict dates - only recomputed when dates or times change
    @Published private(set) var cachedConflictDatesForCalendar: Set<String> = []

    /// Cached preview earnings - only recomputed when selection or times change
    @Published private(set) var cachedPreviewEarnings: [String: Double] = [:]

    /// Cached projected recurring dates for calendar display (current month only)
    @Published private(set) var cachedProjectedRecurringDates: [String] = []

    /// Cached earnings per anchor weekday - computed once per anchor, shared by all projected dates
    @Published private(set) var cachedAnchorEarnings: [String: Double] = [:]

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
        syncCoordinator: SyncCoordinator? = nil,
        monthContext: SharedMonthContext? = nil,
        addShiftCoordinator: AddShiftCoordinator? = nil
    ) {
        self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
        self.recurringRepository = recurringRepository ?? RecurringShiftsRepository.shared
        self.settingsRepository = settingsRepository ?? SettingsRepository.shared
        self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
        self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
        self.monthContext = monthContext ?? SharedMonthContext.shared
        self.addShiftCoordinator = addShiftCoordinator ?? AddShiftCoordinator.shared

        // Initialize tracking to current month context values
        self.lastObservedYear = self.monthContext.displayYear
        self.lastObservedMonth = self.monthContext.displayMonth

        // Subscribe to month context changes
        setupMonthContextSubscription()

        // Subscribe to tab bar add action trigger
        setupAddActionSubscription()
    }

    deinit {
        monthContextCancellable?.cancel()
        addActionCancellable?.cancel()
        previewUpdateTask?.cancel()
    }

    /// Subscribe to SharedMonthContext changes to reload data when month changes
    private func setupMonthContextSubscription() {
        monthContextCancellable = monthContext.monthChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMonth in
                guard let self = self else { return }

                // Only reload if month actually changed
                guard newMonth.year != self.lastObservedYear || newMonth.month != self.lastObservedMonth else {
                    return
                }

                // Update tracking
                self.lastObservedYear = newMonth.year
                self.lastObservedMonth = newMonth.month

                // Sync navigation direction from context (for animations)
                self.navigationDirection = self.monthContext.navigationDirection

                // Trigger objectWillChange to refresh calendar views
                self.objectWillChange.send()

                // Reload shifts for conflict detection in the new month
                self.reloadShiftsForDisplayedMonth()
            }
    }

    /// Subscribe to tab bar add action trigger
    private func setupAddActionSubscription() {
        addActionCancellable = addShiftCoordinator.triggerAddAction
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleTabBarAddTrigger()
            }
    }

    /// Handle the add action triggered from tab bar
    private func handleTabBarAddTrigger() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        switch mode {
        case .single:
            Task {
                await submitSingleShifts()
            }
        case .recurring:
            showPreview()
        }
    }

    /// Publish current state to the coordinator (call after state changes)
    private func publishStateToCoordinator() {
        let canSubmit = mode == .single ? canSubmitSingle : canSubmitRecurring
        addShiftCoordinator.updateCanSubmit(canSubmit)
        addShiftCoordinator.updateMode(mode)
        addShiftCoordinator.updateIsLoading(isLoading)
    }

    // MARK: - Month Navigation

    /// Navigate to the previous month
    /// Delegates to SharedMonthContext - data reload happens via subscription
    func goToPreviousMonth() {
        monthContext.goToPreviousMonth()
    }

    /// Navigate to the next month
    /// Delegates to SharedMonthContext - data reload happens via subscription
    func goToNextMonth() {
        monthContext.goToNextMonth()
    }

    /// Reset to current month
    /// Delegates to SharedMonthContext - data reload happens via subscription
    func goToCurrentMonth() {
        monthContext.goToCurrentMonth()
    }

    // MARK: - Computed Properties

    /// Whether the single shift form can be submitted
    var canSubmitSingle: Bool {
        !selectedDates.isEmpty && hasValidTimes
    }

    /// Whether the recurring shift form can be submitted
    var canSubmitRecurring: Bool {
        !selectedDays.isEmpty && hasValidTimes
    }

    /// Whether both start and end times have been entered
    private var hasValidTimes: Bool {
        startTime != nil && endTime != nil
    }

    /// Start time as HH:mm string
    var startTimeString: String {
        guard let time = startTime else { return "" }
        return formatTimeAsHHmm(time)
    }

    /// End time as HH:mm string
    var endTimeString: String {
        guard let time = endTime else { return "" }
        return formatTimeAsHHmm(time)
    }

    /// Set of dates that have existing shifts - uses cached data for performance
    var existingShiftDates: Set<String> {
        cachedDisplayData?.existingShiftDates ?? Set<String>()
    }

    /// Computed earnings for existing shifts by date - uses cached data for performance
    var existingShiftEarnings: [String: Double] {
        cachedDisplayData?.existingShiftEarnings ?? [:]
    }

    /// Set of dates that would conflict with the current time selection - uses cached data
    var conflictDates: Set<String> {
        cachedConflictDatesForCalendar
    }

    /// Projected dates for the recurring pattern - uses cached data
    var projectedRecurringDates: [String] {
        cachedProjectedRecurringDates
    }

    /// Number of conflicts in the current selection
    var conflictCount: Int {
        cachedConflictDatesForCalendar.count
    }

    /// Preview earnings for selected dates (single mode) - uses cached data
    var previewEarnings: [String: Double] {
        cachedPreviewEarnings
    }

    /// Get earnings for a recurring date by looking up its anchor's earnings
    /// All dates on the same weekday share the same earnings
    func earningsForRecurringDate(_ dateISO: String) -> Double? {
        let weekday = weekdayFromDate(dateISO)
        return cachedAnchorEarnings[weekday]
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

        // Build cached display data for the current month
        rebuildCalendarDisplayData()

        // Check for pre-selected date from SharedMonthContext (e.g., tapping empty day in Shifts tab)
        applyPreselectedDate()

        // Trigger view update now that cached data is loaded
        cacheVersion += 1

        logger.info("Loaded data: \(self.cachedShifts.count) shifts, \(self.cachedRecurringShifts.count) recurring, \(self.cachedSnapshots.count) snapshots")
    }

    /// Check and apply any pre-selected date from SharedMonthContext
    /// Called from onAppear when tab becomes visible
    func checkPreselectedDate() {
        applyPreselectedDate()
    }

    /// Apply and consume the pre-selected date from SharedMonthContext
    /// Called when the user taps an empty day in the Shifts calendar
    private func applyPreselectedDate() {
        guard let dateISO = monthContext.preselectedDate else { return }

        // Consume the pre-selected date (one-time use)
        monthContext.preselectedDate = nil

        // Ensure we're in single mode for date selection
        mode = .single

        // Add the date to selection
        selectedDates.insert(dateISO)

        // Navigate to the month containing the pre-selected date
        if let date = Date.fromISODateString(dateISO) {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month], from: date)
            if let year = components.year, let month = components.month {
                monthContext.navigateTo(year: year, month: month)
            }
        }

        logger.info("Applied pre-selected date: \(dateISO)")
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

        // Rebuild display data for the new month
        rebuildCalendarDisplayData()

        // Update conflicts and preview earnings
        updateConflictsAndPreviews()

        // Trigger view update for new month's shift indicators
        cacheVersion += 1
    }

    // MARK: - Single Shift Actions

    /// Toggle selection of a date (single tap behavior)
    func toggleDate(_ dateISO: String) {
        // Toggle single date
        if selectedDates.contains(dateISO) {
            selectedDates.remove(dateISO)
            // Incremental update: remove from preview earnings
            cachedPreviewEarnings.removeValue(forKey: dateISO)
            // Update conflicts after removing date
            updateConflictsIncrementally(removedDate: dateISO)
        } else {
            selectedDates.insert(dateISO)
            // Incremental update: only compute earnings for this new date
            updatePreviewEarningsIncrementally(addedDate: dateISO)
            // Update conflicts after adding date
            updateConflictsIncrementally(addedDate: dateISO)
        }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Clear all selected dates
    func clearSelectedDates() {
        selectedDates.removeAll()
        cachedPreviewEarnings.removeAll()
        cachedConflictDatesForCalendar.removeAll()
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

            // Play success sound
            SoundManager.shared.play("success")

            // Trigger celebration with the dates that were added
            // Use the current display month as the origin for confetti
            CelebrationManager.shared.celebrate(
                dates: Set(sortedDates),
                originMonth: (year: displayYear, month: displayMonthNumber)
            )

            // Clear form
            clearForm()

            // Notify that shifts changed (for dashboard refresh)
            NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

            // Navigate to Shifts tab
            onShiftsCreated?()

        } catch ShiftCreationError.monthLimitReached(let months) {
            // Show month limit sheet instead of error
            logger.info("Month limit reached, showing month limit sheet. Existing months: \(months.count)")
            existingShiftMonths = months

            // Calculate target month from first selected date
            if let firstDate = selectedDates.sorted().first,
               let date = Date.fromISODateString(firstDate) {
                let calendar = Calendar.current
                targetMonth = calendar.dateComponents([.year, .month], from: date)
            }

            showMonthLimitSheet = true
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
            cachedAnchorEarnings.removeValue(forKey: weekday)
        } else {
            // Set or replace anchor for this weekday
            selectedDays[weekday] = dateISO
        }

        // Update projected dates for the new anchor configuration
        updateProjectedRecurringDates()

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Remove anchor for a specific weekday
    func removeAnchor(weekday: String) {
        selectedDays.removeValue(forKey: weekday)
        cachedAnchorEarnings.removeValue(forKey: weekday)

        // Update projected dates
        updateProjectedRecurringDates()

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Clear all anchors
    func clearAnchors() {
        selectedDays.removeAll()
        cachedAnchorEarnings.removeAll()
        cachedProjectedRecurringDates.removeAll()
        cachedConflictDatesForCalendar.removeAll()
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

            // Play success sound
            SoundManager.shared.play("success")

            // Get non-excluded dates for celebration (the ones actually created)
            let createdDates = Set(cachedProjectedDates).subtracting(conflicts)

            // Trigger celebration with created dates
            // Use the current display month as the origin for confetti
            CelebrationManager.shared.celebrate(
                dates: createdDates,
                originMonth: (year: displayYear, month: displayMonthNumber)
            )

            // Clear form
            clearForm()

            // Dismiss preview sheet
            showPreviewSheet = false

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

    // MARK: - Delete Shifts (Month Limit)

    /// Delete shifts in other months (when free tier user chooses this option)
    /// Returns true if successful
    func deleteShiftsInOtherMonths() async -> Bool {
        guard let userId = AppCoordinator.shared.userId else {
            logger.warning("Cannot delete shifts: no user ID")
            return false
        }

        do {
            let deletedCount = try await shiftsRepository.deleteShiftsInOtherMonths(
                userId: userId,
                targetMonth: targetMonth
            )

            logger.info("Deleted \(deletedCount) shifts in other months")

            // Clear existing months since they're now deleted
            existingShiftMonths.removeAll()

            // Reload cached data to reflect deletions in UI
            reloadShiftsForDisplayedMonth()

            // Notify that shifts changed (for other views like dashboard)
            NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

            return true
        } catch {
            logger.error("Failed to delete shifts in other months: \(error.localizedDescription)")
            return false
        }
    }

    /// Called when deletion is complete and user wants to proceed with creating shifts
    func onDeleteComplete() {
        // Re-attempt shift creation now that other months are cleared
        Task {
            await submitSingleShifts()
        }
    }

    /// Called when user upgrades successfully - auto-retry shift creation
    func onUpgradeComplete() {
        // Re-attempt shift creation now that user has paid tier
        Task {
            await submitSingleShifts()
        }
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

    /// Virtual shift with computed earnings
    struct VirtualShiftWithEarnings {
        let date: String
        let earnings: Double
    }

    /// Generate virtual shift dates from recurring patterns for display
    private func generateVirtualShiftDatesForDisplay() -> Set<String> {
        Set(generateVirtualShiftsForDisplay().map { $0.date })
    }

    /// Generate virtual shifts with computed earnings from recurring patterns
    private func generateVirtualShiftsForDisplay() -> [VirtualShiftWithEarnings] {
        var results: [VirtualShiftWithEarnings] = []

        // Only generate for the currently displayed month
        let year = displayYear
        let month = displayMonthNumber

        for recurring in cachedRecurringShifts {
            let virtualShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
                year: year,
                month: month,
                recurring: recurring
            )

            for virtualShift in virtualShifts {
                // Create a temporary shift to compute earnings
                let shift = ShiftRow(
                    id: "virtual-\(virtualShift.date)",
                    user_id: nil,
                    shift_date: virtualShift.date,
                    start_time: recurring.start_time,
                    end_time: recurring.end_time,
                    custom_supplements: nil
                )

                let snapshot = SnapshotsService.snapshotForDate(virtualShift.date, from: cachedSnapshots)
                let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

                results.append(VirtualShiftWithEarnings(
                    date: virtualShift.date,
                    earnings: computed.gross
                ))
            }
        }

        return results
    }

    /// Clear the form after successful submission
    private func clearForm() {
        // Clear date selections
        selectedDates.removeAll()
        selectedDays.removeAll()

        // Clear cached computation data
        cachedPreviewEarnings.removeAll()
        cachedConflictDatesForCalendar.removeAll()
        cachedProjectedRecurringDates.removeAll()
        cachedAnchorEarnings.removeAll()

        // Cancel any pending preview update before clearing times
        previewUpdateTask?.cancel()
        previewUpdateTask = nil

        // Clear times so user can start fresh
        startTime = nil
        endTime = nil

        // Reset recurring options
        repeatInterval = 0
        endCondition = .months(value: 6)

        // NOTE: Do NOT reset the month context here!
        // The user should stay on the month where they just added shifts
        // so that when they're navigated to the Shifts tab, they see their new shifts.

        // Clear error state
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

    // MARK: - Performance Optimization Methods

    /// Schedule a debounced preview update after time input changes
    private func schedulePreviewUpdate() {
        // Cancel any pending update
        previewUpdateTask?.cancel()

        // Schedule new update with debounce delay
        previewUpdateTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.previewDebounceDelay)

                // Check if cancelled during sleep
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self?.updateConflictsAndPreviews()
                }
            } catch {
                // Task was cancelled - this is expected
            }
        }
    }

    /// Rebuild the calendar display data from cached shifts (called once per month change)
    private func rebuildCalendarDisplayData() {
        let year = displayYear
        let month = displayMonthNumber

        // Build set of existing shift dates
        var existingDates = Set<String>()
        var existingEarnings: [String: Double] = [:]

        // Add regular shifts
        for shift in cachedShifts {
            existingDates.insert(shift.shift_date)

            // Compute earnings for regular shifts
            let snapshot = SnapshotsService.snapshotForDate(shift.shift_date, from: cachedSnapshots)
            let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)
            existingEarnings[shift.shift_date, default: 0] += computed.gross
        }

        // Generate virtual shifts with computed earnings
        var virtualShiftsWithEarnings: [CalendarDisplayData.VirtualShiftWithEarnings] = []

        for recurring in cachedRecurringShifts {
            let virtualShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
                year: year,
                month: month,
                recurring: recurring
            )

            for virtualShift in virtualShifts {
                existingDates.insert(virtualShift.date)

                // Create a temporary shift to compute earnings
                let shift = ShiftRow(
                    id: "virtual-\(virtualShift.date)",
                    user_id: nil,
                    shift_date: virtualShift.date,
                    start_time: recurring.start_time,
                    end_time: recurring.end_time,
                    custom_supplements: nil
                )

                let snapshot = SnapshotsService.snapshotForDate(virtualShift.date, from: cachedSnapshots)
                let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

                virtualShiftsWithEarnings.append(CalendarDisplayData.VirtualShiftWithEarnings(
                    date: virtualShift.date,
                    earnings: computed.gross
                ))

                // Also add to existing earnings map
                existingEarnings[virtualShift.date, default: 0] += computed.gross
            }
        }

        // Store the cached display data
        cachedDisplayData = CalendarDisplayData(
            existingShiftDates: existingDates,
            existingShiftEarnings: existingEarnings,
            virtualShifts: virtualShiftsWithEarnings,
            year: year,
            month: month,
            timestamp: Date()
        )

        logger.info("Rebuilt calendar display data: \(existingDates.count) dates, \(virtualShiftsWithEarnings.count) virtual shifts")
    }

    /// Update conflicts and preview earnings (called after time changes or initial load)
    private func updateConflictsAndPreviews() {
        // Update conflicts based on current mode
        let datesToCheck: [String]
        switch mode {
        case .single:
            datesToCheck = Array(selectedDates)
        case .recurring:
            // Regenerate projected dates for calendar display only (current month)
            if !selectedDays.isEmpty {
                cachedProjectedRecurringDates = RecurringShiftProjector.generateDatesForCalendarDisplay(
                    selectedDays: selectedDays,
                    repeatInterval: repeatInterval,
                    displayMonth: displayMonth,
                    endCondition: endCondition
                )

                // Compute earnings once per anchor (all dates on same weekday share earnings)
                if hasValidTimes {
                    var anchorEarnings: [String: Double] = [:]
                    for (weekday, anchorISO) in selectedDays {
                        if let earnings = computeEarningsForDate(anchorISO) {
                            anchorEarnings[weekday] = earnings
                        }
                    }
                    cachedAnchorEarnings = anchorEarnings
                }
            } else {
                cachedProjectedRecurringDates = []
                cachedAnchorEarnings = [:]
            }
            datesToCheck = cachedProjectedRecurringDates
        }

        // Only check conflicts if we have valid times and dates
        guard hasValidTimes, !datesToCheck.isEmpty else {
            cachedConflictDatesForCalendar = []
            cachedPreviewEarnings = [:]
            return
        }

        // Compute conflicts
        cachedConflictDatesForCalendar = ShiftConflictDetector.detectConflicts(
            dates: datesToCheck,
            startTime: startTimeString,
            endTime: endTimeString,
            existingShifts: cachedShifts,
            existingRecurringShifts: cachedRecurringShifts
        )

        // Compute preview earnings for all selected dates
        if mode == .single {
            var newPreviewEarnings: [String: Double] = [:]
            for dateISO in selectedDates {
                if let earnings = computeEarningsForDate(dateISO) {
                    newPreviewEarnings[dateISO] = earnings
                }
            }
            cachedPreviewEarnings = newPreviewEarnings
        }
    }

    /// Incrementally update preview earnings when a single date is added
    private func updatePreviewEarningsIncrementally(addedDate: String) {
        guard hasValidTimes else { return }

        if let earnings = computeEarningsForDate(addedDate) {
            cachedPreviewEarnings[addedDate] = earnings
        }
    }

    /// Incrementally update conflicts when a date is added
    private func updateConflictsIncrementally(addedDate: String) {
        guard hasValidTimes else { return }

        // Check if the added date conflicts with existing shifts
        let conflicts = ShiftConflictDetector.detectConflicts(
            dates: [addedDate],
            startTime: startTimeString,
            endTime: endTimeString,
            existingShifts: cachedShifts,
            existingRecurringShifts: cachedRecurringShifts
        )

        // Add any conflicts found
        cachedConflictDatesForCalendar.formUnion(conflicts)
    }

    /// Incrementally update conflicts when a date is removed
    private func updateConflictsIncrementally(removedDate: String) {
        // Simply remove the date from conflicts (it can't conflict if it's not selected)
        cachedConflictDatesForCalendar.remove(removedDate)
    }

    /// Update projected recurring dates when recurring settings change
    func updateProjectedRecurringDates() {
        guard !selectedDays.isEmpty else {
            cachedProjectedRecurringDates = []
            cachedAnchorEarnings = [:]
            return
        }

        // Only generate dates for calendar display (current month)
        cachedProjectedRecurringDates = RecurringShiftProjector.generateDatesForCalendarDisplay(
            selectedDays: selectedDays,
            repeatInterval: repeatInterval,
            displayMonth: displayMonth,
            endCondition: endCondition
        )

        // Compute earnings once per anchor
        if hasValidTimes {
            var anchorEarnings: [String: Double] = [:]
            for (weekday, anchorISO) in selectedDays {
                if let earnings = computeEarningsForDate(anchorISO) {
                    anchorEarnings[weekday] = earnings
                }
            }
            cachedAnchorEarnings = anchorEarnings

            // Update conflicts for the projected dates
            cachedConflictDatesForCalendar = ShiftConflictDetector.detectConflicts(
                dates: cachedProjectedRecurringDates,
                startTime: startTimeString,
                endTime: endTimeString,
                existingShifts: cachedShifts,
                existingRecurringShifts: cachedRecurringShifts
            )
        }
    }
}
