import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "PaySettingsViewModel")

// MARK: - Pay Settings ViewModel

/// ViewModel for the Pay Settings screen
/// Manages wage snapshots (timeline) and global pay settings
@MainActor
final class PaySettingsViewModel: ObservableObject {

    // MARK: - Published State

    /// Raw snapshots from repository (ordered by from_date DESC)
    @Published private(set) var snapshots: [WageSnapshot] = []

    /// Processed timeline entries for display
    @Published private(set) var timelineEntries: [WageTimelineEntry] = []

    /// Global user settings
    @Published private(set) var globalSettings: UserSettings?

    /// Loading state
    @Published var isLoading = false

    /// Error message to display
    @Published var errorMessage: String?

    /// Success message to display
    @Published var successMessage: String?

    // MARK: - Currency

    /// User's current currency
    var userCurrency: String {
        globalSettings?.currency ?? "kr"
    }

    /// Whether any snapshot uses tariff (wage_level is set)
    var hasTariffSnapshots: Bool {
        snapshots.contains { $0.wage_level != nil }
    }

    /// Whether user can change their currency
    /// Only allowed if no snapshots use tariff rates
    var canChangeCurrency: Bool {
        !hasTariffSnapshots
    }

    // MARK: - Editor State

    /// Whether the editor sheet is showing
    @Published var showingEditor = false

    /// Current editor mode
    @Published var editorMode: EditorMode = .create

    /// Selected snapshot for editing (nil for create mode)
    @Published var selectedSnapshot: WageSnapshot?

    // MARK: - Delete Confirmation State

    /// Whether delete confirmation dialog is showing
    @Published var showingDeleteConfirmation = false

    /// Snapshot pending deletion
    @Published private(set) var snapshotToDelete: WageSnapshot?

    /// Number of shifts affected by deletion
    @Published private(set) var affectedShiftCount = 0

    // MARK: - Editor Mode

    enum EditorMode {
        case create
        case edit
    }

    // MARK: - Dependencies

    private let snapshotsRepository = SnapshotsRepository.shared
    private let settingsRepository = SettingsRepository.shared
    private let shiftsRepository = ShiftsRepository.shared

    private var userId: String?

    // MARK: - Debounce

    private var monthlyGoalSaveTask: Task<Void, Never>?
    private var payrollDaySaveTask: Task<Void, Never>?

    // MARK: - Init

    init() {}

    deinit {
        // Cancel any pending debounce tasks to prevent orphaned operations
        monthlyGoalSaveTask?.cancel()
        payrollDaySaveTask?.cancel()
    }

    // MARK: - Load Data

    /// Load all data for the pay settings screen
    func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            userId = try await AuthSessionManager.shared.getUserId()

            guard let userId = userId else {
                throw PaySettingsError.notAuthenticated
            }

            // Load snapshots and settings
            snapshots = snapshotsRepository.getSnapshots(for: userId)
            globalSettings = settingsRepository.getSettings(for: userId)

            // Process timeline entries
            processTimelineEntries()

            logger.info("Loaded \(self.snapshots.count) snapshots for pay settings")
        } catch {
            logger.error("Failed to load pay settings: \(error.localizedDescription)")
            errorMessage = String(localized: .settingsPayErrorLoadFailed)
        }

        isLoading = false
    }

    /// Refresh data after changes
    func refreshData() {
        guard let userId = userId else { return }

        snapshots = snapshotsRepository.getSnapshots(for: userId)
        globalSettings = settingsRepository.getSettings(for: userId)
        processTimelineEntries()
    }

    // MARK: - Timeline Processing

    private func processTimelineEntries() {
        timelineEntries = WageTimelineProcessor.processSnapshots(
            snapshots,
            locale: Locale.current
        )
    }

    // MARK: - Editor Actions

    /// Open editor in create mode
    func openCreateEditor() {
        editorMode = .create
        selectedSnapshot = nil
        showingEditor = true
    }

    /// Open editor in edit mode for a specific snapshot
    func openEditEditor(snapshot: WageSnapshot) {
        editorMode = .edit
        selectedSnapshot = snapshot
        showingEditor = true
    }

    /// Close the editor
    func closeEditor() {
        showingEditor = false
        selectedSnapshot = nil
    }

    // MARK: - Snapshot CRUD

    /// Create a new wage snapshot
    func createSnapshot(input: WageSnapshotEditorInput) async -> Bool {
        guard let userId = userId else {
            errorMessage = String(localized: .settingsPayErrorNotAuthenticated)
            return false
        }

        // Validate date uniqueness
        if let fromDate = input.fromDate {
            let isoDate = ISO8601DateFormatter.dateOnlyString(from: fromDate)
            if hasSnapshotOnDate(isoDate, excludingId: nil) {
                errorMessage = String(localized: .settingsPayErrorDateConflict)
                return false
            }
        }

        do {
            let fromDate = input.fromDate

            _ = try await snapshotsRepository.createSnapshot(
                userId: userId,
                fromDate: fromDate,
                hourlyWage: input.hourlyWage,
                wageLevel: input.wageLevel,
                supplements: input.supplements,
                taxEnabled: input.taxEnabled,
                taxPercentage: input.taxPercentage,
                breakEnabled: input.breakEnabled,
                breakMethod: input.breakMethod.rawValue,
                breakThresholdHours: input.breakThresholdHours,
                breakDeductionMinutes: input.breakDeductionMinutes
            )

            // Refresh UI
            refreshData()
            closeEditor()

            logger.info("Created new wage snapshot")
            return true
        } catch {
            logger.error("Failed to create snapshot: \(error.localizedDescription)")
            errorMessage = String(localized: .settingsPayErrorCreateFailed)
            return false
        }
    }

    /// Update an existing wage snapshot
    func updateSnapshot(id: String, input: WageSnapshotEditorInput) async -> Bool {
        guard userId != nil else {
            errorMessage = String(localized: .settingsPayErrorNotAuthenticated)
            return false
        }

        // Validate date uniqueness (excluding current snapshot)
        if let fromDate = input.fromDate {
            let isoDate = ISO8601DateFormatter.dateOnlyString(from: fromDate)
            if hasSnapshotOnDate(isoDate, excludingId: id) {
                errorMessage = String(localized: .settingsPayErrorDateConflict)
                return false
            }
        }

        do {
            _ = try await snapshotsRepository.updateSnapshot(
                id: id,
                hourlyWage: input.hourlyWage,
                wageLevel: input.wageLevel,
                supplements: input.supplements,
                taxEnabled: input.taxEnabled,
                taxPercentage: input.taxPercentage,
                breakEnabled: input.breakEnabled,
                breakMethod: input.breakMethod.rawValue,
                breakThresholdHours: input.breakThresholdHours,
                breakDeductionMinutes: input.breakDeductionMinutes
            )

            // Refresh UI
            refreshData()
            closeEditor()

            logger.info("Updated wage snapshot: \(id)")
            return true
        } catch {
            logger.error("Failed to update snapshot: \(error.localizedDescription)")
            errorMessage = String(localized: .settingsPayErrorUpdateFailed)
            return false
        }
    }

    // MARK: - Delete Flow

    /// Request deletion of a snapshot (shows confirmation)
    func requestDelete(snapshot: WageSnapshot) {
        // Check if this is baseline and there are other snapshots
        if snapshot.isBaseline {
            let datedSnapshots = snapshots.filter { !$0.isBaseline }
            if !datedSnapshots.isEmpty {
                errorMessage = String(localized: .settingsPayErrorCannotDeleteBaseline)
                return
            }
        }

        // Count affected shifts
        affectedShiftCount = countAffectedShifts(for: snapshot)
        snapshotToDelete = snapshot
        showingDeleteConfirmation = true
    }

    /// Confirm and execute deletion
    func confirmDelete() async {
        guard let snapshot = snapshotToDelete, userId != nil else {
            showingDeleteConfirmation = false
            snapshotToDelete = nil
            return
        }

        do {
            try await snapshotsRepository.deleteSnapshot(id: snapshot.id)

            // Refresh UI
            refreshData()
            closeEditor()

            logger.info("Deleted wage snapshot: \(snapshot.id)")
        } catch {
            logger.error("Failed to delete snapshot: \(error.localizedDescription)")
            errorMessage = String(localized: .settingsPayErrorDeleteFailed)
        }

        showingDeleteConfirmation = false
        snapshotToDelete = nil
        affectedShiftCount = 0
    }

    /// Cancel deletion
    func cancelDelete() {
        showingDeleteConfirmation = false
        snapshotToDelete = nil
        affectedShiftCount = 0
    }

    // MARK: - Affected Shifts Calculation

    /// Count shifts that would be affected by deleting a snapshot
    private func countAffectedShifts(for snapshot: WageSnapshot) -> Int {
        guard let userId = userId else { return 0 }

        // Get all shifts
        let shifts = shiftsRepository.getAllShifts(for: userId)

        // Sort snapshots by date
        let sortedSnapshots = snapshots.sorted { s1, s2 in
            let d1 = s1.from_date ?? ""
            let d2 = s2.from_date ?? ""
            return d1 > d2
        }

        // Find this snapshot's index
        guard let index = sortedSnapshots.firstIndex(where: { $0.id == snapshot.id }),
              let fromDate = snapshot.from_date else {
            return 0
        }

        // Get the date range: from this snapshot's date to the next snapshot's date (or nil if none)
        let nextFromDate = index > 0 ? sortedSnapshots[index - 1].from_date : nil

        return shifts.filter { shift in
            let shiftDate = shift.shift_date
            let afterStart = shiftDate >= fromDate
            let beforeEnd: Bool
            if let nextDate = nextFromDate {
                beforeEnd = shiftDate < nextDate
            } else {
                beforeEnd = true
            }
            return afterStart && beforeEnd
        }.count
    }

    // MARK: - Validation Helpers

    /// Check if a snapshot exists on a given date
    private func hasSnapshotOnDate(_ isoDate: String?, excludingId: String?) -> Bool {
        return snapshots.contains { snapshot in
            guard snapshot.id != excludingId else { return false }
            return snapshot.from_date == isoDate
        }
    }

    // MARK: - Global Settings Updates

    /// Update monthly goal with debouncing
    func updateMonthlyGoal(_ value: Int?) {
        monthlyGoalSaveTask?.cancel()

        monthlyGoalSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
                guard !Task.isCancelled else { return }

                await saveMonthlyGoal(value)
            } catch {
                // Task was cancelled
            }
        }
    }

    private func saveMonthlyGoal(_ value: Int?) async {
        guard let userId = userId else { return }

        do {
            _ = try await settingsRepository.updateSettings(
                for: userId,
                monthlyGoal: value
            )

            refreshData()
            logger.info("Updated monthly goal to: \(value ?? 0)")
        } catch {
            logger.error("Failed to update monthly goal: \(error.localizedDescription)")
        }
    }

    /// Update payroll day with debouncing
    func updatePayrollDay(_ value: Int) {
        payrollDaySaveTask?.cancel()

        payrollDaySaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
                guard !Task.isCancelled else { return }

                await savePayrollDay(value)
            } catch {
                // Task was cancelled
            }
        }
    }

    private func savePayrollDay(_ value: Int) async {
        guard let userId = userId else { return }

        do {
            _ = try await settingsRepository.updateSettings(
                for: userId,
                payrollDay: value
            )

            refreshData()
            logger.info("Updated payroll day to: \(value)")
        } catch {
            logger.error("Failed to update payroll day: \(error.localizedDescription)")
        }
    }

    /// Update half tax month (immediate, no debounce needed for picker)
    func updateHalfTaxMonth(_ value: Int?) async {
        guard let userId = userId else { return }

        do {
            _ = try await settingsRepository.updateSettings(
                for: userId,
                halfTaxMonth: value
            )

            refreshData()
            logger.info("Updated half tax month to: \(value ?? 0)")
        } catch {
            logger.error("Failed to update half tax month: \(error.localizedDescription)")
        }
    }

    /// Update currency (immediate, no debounce needed for picker)
    /// Only allowed if no snapshots use tariff rates
    func updateCurrency(_ value: String) async {
        guard let userId = userId else { return }
        guard canChangeCurrency else {
            errorMessage = Locale.current.tidexIsNorwegian
                ? "Du kan ikke endre valuta når du har lønnstrinn-innstillinger"
                : "Cannot change currency when using tariff wage settings"
            return
        }

        do {
            _ = try await settingsRepository.updateSettings(
                for: userId,
                currency: value
            )

            refreshData()
            logger.info("Updated currency to: \(value)")
        } catch {
            logger.error("Failed to update currency: \(error.localizedDescription)")
        }
    }

    // MARK: - Message Clearing

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}

// MARK: - Editor Input Model

/// Input data for creating/updating a wage snapshot
struct WageSnapshotEditorInput {
    var fromDate: Date?
    var hourlyWage: Double
    var wageLevel: Int?
    var supplements: SupplementRulesSnapshot
    var taxEnabled: Bool
    var taxPercentage: Double
    var breakEnabled: Bool
    var breakMethod: BreakMethod
    var breakThresholdHours: Double
    var breakDeductionMinutes: Int
    /// Tariff type ID when using tariff rates (e.g., "hk_retail")
    var tariffTypeId: String?

    /// Create input from an existing snapshot
    init(from snapshot: WageSnapshot) {
        if let fromDateString = snapshot.from_date {
            self.fromDate = ISO8601DateFormatter.dateFromDateOnlyString(fromDateString)
        } else {
            self.fromDate = nil
        }
        self.hourlyWage = snapshot.hourly_wage
        self.wageLevel = snapshot.wage_level
        self.supplements = snapshot.supplements
        self.taxEnabled = snapshot.effectiveTaxEnabled
        self.taxPercentage = snapshot.effectiveTaxPercentage
        self.breakEnabled = snapshot.effectiveBreakEnabled
        self.breakMethod = snapshot.breakMethod
        self.breakThresholdHours = snapshot.effectiveBreakThresholdHours
        self.breakDeductionMinutes = snapshot.effectiveBreakDeductionMinutes
        self.tariffTypeId = snapshot.tariff_type_id
    }

    /// Create default input for new snapshot
    init(prefillFrom snapshot: WageSnapshot? = nil) {
        self.fromDate = Date()

        if let snapshot = snapshot {
            self.hourlyWage = snapshot.hourly_wage
            self.wageLevel = snapshot.wage_level
            self.supplements = snapshot.supplements
            self.taxEnabled = snapshot.effectiveTaxEnabled
            self.taxPercentage = snapshot.effectiveTaxPercentage
            self.breakEnabled = snapshot.effectiveBreakEnabled
            self.breakMethod = snapshot.breakMethod
            self.breakThresholdHours = snapshot.effectiveBreakThresholdHours
            self.breakDeductionMinutes = snapshot.effectiveBreakDeductionMinutes
            self.tariffTypeId = snapshot.tariff_type_id
        } else {
            self.hourlyWage = 184.54
            self.wageLevel = 1
            self.supplements = SupplementRulesSnapshot(rules: PayrollCalculator.presetSupplementRules)
            self.taxEnabled = false
            self.taxPercentage = 0
            self.breakEnabled = true
            self.breakMethod = .proportional
            self.breakThresholdHours = 5.5
            self.breakDeductionMinutes = 30
            self.tariffTypeId = nil
        }
    }
}

// MARK: - Errors

enum PaySettingsError: Error {
    case notAuthenticated
    case dateConflict
    case cannotDeleteBaseline
}
