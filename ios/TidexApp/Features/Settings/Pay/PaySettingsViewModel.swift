import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "PaySettingsViewModel")

// MARK: - Pay Settings ViewModel

/// ViewModel for the Pay Settings screen
/// Manages wage snapshots (timeline) and global pay settings
@MainActor
@Observable
final class PaySettingsViewModel {

  // MARK: - Published State

  /// Raw snapshots from repository (ordered by from_date DESC)
  private(set) var snapshots: [WageSnapshot] = []

  /// Processed timeline entries for display
  private(set) var timelineEntries: [WageTimelineEntry] = []

  var reviewDate: Date

  /// Global user settings
  private(set) var globalSettings: UserSettings?

  /// Loading state
  var isLoading = true

  /// Error message to display
  var errorMessage: String?
  /// Optional specific title for the current error alert.
  var errorTitle: String?

  /// Whether a job-level action is currently being applied.
  private(set) var isProcessingJobAction = false

  /// Active jobs for job-scoped timeline filtering.
  private(set) var activeJobs: [Job] = []
  /// Whether the user has archived workplaces.
  private(set) var hasArchivedJobs = false

  /// Selected job for this screen's wage timeline.
  private(set) var selectedJobId: String?
  /// Whether the selected active job has the required baseline wage snapshot.
  private(set) var isSelectedJobConfigured = false
  /// True when a previously selected entry job is no longer active and user must choose again.
  private(set) var requiresJobReselection = false

  // MARK: - Currency

  /// User's current currency
  var userCurrency: String {
    selectedJob?.currency ?? globalSettings?.currency ?? "kr"
  }

  /// Whether any snapshot uses tariff (wage_level is set)
  var hasTariffSnapshots: Bool {
    snapshots.contains { $0.wage_level != nil || $0.tariff_type_id != nil }
  }

  /// Whether the selected job can change currency.
  var canChangeCurrency: Bool {
    !hasTariffSnapshots
  }

  // MARK: - Editor State

  /// Whether the editor sheet is showing
  var showingEditor = false

  /// Current editor mode
  var editorMode: EditorMode = .create

  /// Selected snapshot for editing (nil for create mode)
  var selectedSnapshot: WageSnapshot?
  var editorSection: WageSnapshotEditorSection?

  // MARK: - Delete Confirmation State

  /// Whether delete confirmation dialog is showing
  var showingDeleteConfirmation = false

  /// Snapshot pending deletion
  private(set) var snapshotToDelete: WageSnapshot?

  /// Number of shifts affected by deletion
  private(set) var affectedShiftCount = 0

  // MARK: - Editor Mode

  enum EditorMode {
    case create
    case edit
  }

  // MARK: - Dependencies

  private let snapshotsRepository = SnapshotsRepository.shared
  private let settingsRepository = SettingsRepository.shared
  private let shiftsRepository = ShiftsRepository.shared
  private let jobsRepository = JobsRepository.shared

  private var userId: String?
  private var pendingInitialSelectedJobId: String?

  // MARK: - Debounce

  @ObservationIgnored private var payrollDaySaveTask: Task<Void, Never>?

  // MARK: - Init

  init(initialSelectedJobId: String? = nil, initialDate: Date = Date()) {
    pendingInitialSelectedJobId = initialSelectedJobId
    reviewDate = initialDate
  }

  deinit {
    // Cancel any pending debounce tasks to prevent orphaned operations
    payrollDaySaveTask?.cancel()
  }

  // MARK: - Load Data

  /// Load all data for the pay settings screen
  func loadData() async {
    isLoading = true
    clearError()

    do {
      let userId = try await resolveUserIdForLocalData()
      self.userId = userId
      let jobs = jobsRepository.getActiveJobs(for: userId)
      activeJobs = jobs
      hasArchivedJobs = jobsRepository.getNonDeletedJobs(for: userId).contains {
        $0.archived_at != nil
      }
      applySelection(from: jobs)

      // Load snapshots and settings
      if let selectedJobId {
        snapshots = snapshotsRepository.getSnapshots(for: userId, jobId: selectedJobId)
      } else {
        snapshots = []
      }
      updateSelectedJobConfiguration()
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
    guard let userId = currentLocalUserId() else { return }

    let jobs = jobsRepository.getActiveJobs(for: userId)
    activeJobs = jobs
    hasArchivedJobs = jobsRepository.getNonDeletedJobs(for: userId).contains {
      $0.archived_at != nil
    }
    applySelection(from: jobs)

    if let selectedJobId {
      snapshots = snapshotsRepository.getSnapshots(for: userId, jobId: selectedJobId)
    } else {
      snapshots = []
    }
    updateSelectedJobConfiguration()
    globalSettings = settingsRepository.getSettings(for: userId)
    processTimelineEntries()
  }

  private func updateSelectedJobConfiguration() {
    isSelectedJobConfigured = selectedJobId != nil && snapshots.contains(where: \.isBaseline)
  }

  private func applySelection(from jobs: [Job]) {
    if let forcedJobId = pendingInitialSelectedJobId {
      pendingInitialSelectedJobId = nil

      if jobs.contains(where: { $0.id == forcedJobId }) {
        selectedJobId = forcedJobId
        requiresJobReselection = false
        return
      }

      // A calculation link must never silently open a different workplace's settings.
      selectedJobId = nil
      requiresJobReselection = true
      return
    }

    if requiresJobReselection, selectedJobId == nil { return }

    if let selectedJobId, jobs.contains(where: { $0.id == selectedJobId }) {
      requiresJobReselection = false
      return
    }

    selectedJobId =
      jobs.first(where: \.is_default)?.id
      ?? jobs.first?.id
    requiresJobReselection = false
  }

  var shouldRequireJobReselectionSheet: Bool {
    requiresJobReselection && !activeJobs.isEmpty && selectedJobId == nil
  }

  var shouldShowWorkplaceHeader: Bool {
    selectedJob != nil
  }

  var selectedJobName: String? {
    guard let selectedJobId else { return nil }
    return activeJobs.first(where: { $0.id == selectedJobId })?.name
  }

  var selectedJob: Job? {
    guard let selectedJobId else { return nil }
    return activeJobs.first(where: { $0.id == selectedJobId })
  }

  var isSelectedJobDefault: Bool {
    selectedJob?.is_default == true
  }

  var shouldShowUseAsStandardAction: Bool {
    guard let selectedJob else { return false }
    return !selectedJob.is_default
  }

  var canSetSelectedJobAsDefault: Bool {
    shouldShowUseAsStandardAction && isSelectedJobConfigured
  }

  var canArchiveSelectedJob: Bool {
    guard let selectedJob else { return false }
    return !selectedJob.is_default && activeJobs.count > 1
  }

  var selectedJobManagementHint: String? {
    guard let selectedJob else { return nil }

    if !isSelectedJobConfigured, !selectedJob.is_default {
      return String(localized: .settingsPayJobActionsSetupHint)
    }

    if activeJobs.count <= 1 {
      return String(localized: .settingsPayJobActionsLastJobHint)
    }

    if selectedJob.is_default {
      return String(localized: .settingsPayJobActionsDefaultHint)
    }

    return nil
  }

  private func currentLocalUserId() -> String? {
    if let userId {
      return userId
    }

    guard let offlineUserId = AuthSessionManager.shared.offlineUserIdFallback() else {
      return nil
    }

    userId = offlineUserId
    logger.info("Using offline user id fallback for pay settings")
    return offlineUserId
  }

  private func resolveUserIdForLocalData() async throws -> String {
    do {
      return try await AuthSessionManager.shared.getUserId()
    } catch {
      guard AuthSessionManager.shared.isTransientSessionResolutionError(error) else {
        throw error
      }

      if let offlineUserId = AuthSessionManager.shared.offlineUserIdFallback() {
        logger.info("Using offline user id fallback for pay settings")
        return offlineUserId
      }

      throw error
    }
  }

  var jobNeedingSetupBeforeAddingSecond: Job? {
    guard activeJobs.count == 1 else { return nil }
    return activeJobs.first
  }

  var selectedJobPayrollDay: Int {
    selectedJob?.payroll_day ?? 1
  }

  var selectedJobHalfTaxMonth: Int? {
    selectedJob?.half_tax_month
  }

  var selectedJobPayPeriod: PayPeriod {
    selectedJob?.pay_period ?? .calendarMonth
  }

  func selectJob(_ jobId: String) {
    guard selectedJobId != jobId else { return }
    requiresJobReselection = false
    selectedJobId = jobId
    refreshData()
  }

  func resolveRequiredJobSelection(_ jobId: String) {
    guard activeJobs.contains(where: { $0.id == jobId }) else { return }
    requiresJobReselection = false
    selectedJobId = jobId
    refreshData()
  }

  func setSelectedJobAsDefault() async {
    guard let userId = currentLocalUserId() else {
      errorMessage = String(localized: .settingsPayErrorNotAuthenticated)
      return
    }
    guard let selectedJob else {
      errorMessage = String(localized: .settingsPayErrorLoadFailed)
      return
    }
    guard canSetSelectedJobAsDefault else {
      if let selectedJobManagementHint {
        errorMessage = selectedJobManagementHint
      }
      return
    }

    isProcessingJobAction = true
    defer { isProcessingJobAction = false }

    do {
      try await jobsRepository.setDefaultJob(userId: userId, jobId: selectedJob.id)
      refreshData()
      notifyDashboardDataChanged()
      Haptics.play(.success)
    } catch {
      logger.error("Failed to set selected job as default: \(error.localizedDescription)")
      errorMessage = error.localizedDescription
    }
  }

  func archiveSelectedJob() async -> Bool {
    guard let userId = currentLocalUserId() else {
      errorMessage = String(localized: .settingsPayErrorNotAuthenticated)
      return false
    }
    guard let selectedJob else {
      errorMessage = String(localized: .settingsPayErrorLoadFailed)
      return false
    }
    guard canArchiveSelectedJob else {
      if let selectedJobManagementHint {
        errorMessage = selectedJobManagementHint
      }
      return false
    }

    isProcessingJobAction = true
    defer { isProcessingJobAction = false }

    do {
      try await jobsRepository.archiveJob(userId: userId, jobId: selectedJob.id)
      // Keep this job visible during dismissal instead of selecting another active job.
      notifyDashboardDataChanged()
      Haptics.play(.success)
      return true
    } catch {
      logger.error("Failed to archive selected job: \(error.localizedDescription)")
      errorMessage = error.localizedDescription
      return false
    }
  }

  func completePaySetup(for job: Job, input: JobPaySetupInput) async -> Bool {
    guard let userId = currentLocalUserId() else {
      errorMessage = String(localized: .settingsPayErrorNotAuthenticated)
      return false
    }

    do {
      let configuredJob = try await jobsRepository.completePaySetup(
        userId: userId,
        jobId: job.id,
        currency: input.currency,
        payrollDay: input.payrollDay,
        halfTaxMonth: input.halfTaxMonth,
        monthlyGoal: job.monthly_goal,
        baselineSnapshot: input.baselineSnapshot
      )
      requiresJobReselection = false
      selectedJobId = configuredJob.id
      refreshData()
      notifyDashboardDataChanged()
      Haptics.play(.success)
      return true
    } catch {
      logger.error("Failed to complete job pay setup: \(error.localizedDescription)")
      errorMessage = error.localizedDescription
      return false
    }
  }

  func updateSelectedJobMetadata(name: String, color: String?) async -> Bool {
    guard let userId = currentLocalUserId() else {
      errorMessage = String(localized: .settingsPayErrorNotAuthenticated)
      return false
    }
    guard let selectedJobId else {
      errorMessage = String(localized: .settingsPayErrorLoadFailed)
      return false
    }

    do {
      guard
        try await jobsRepository.updateJob(
          userId: userId,
          jobId: selectedJobId,
          name: name,
          color: color
        ) != nil
      else {
        errorMessage = String(localized: .settingsPayErrorLoadFailed)
        return false
      }

      refreshData()
      notifyDashboardDataChanged()
      Haptics.play(.success)
      return true
    } catch {
      logger.error("Failed to update selected job metadata: \(error.localizedDescription)")
      errorMessage = error.localizedDescription
      return false
    }
  }

  func updateCurrency(_ value: String) async {
    guard let userId = currentLocalUserId() else {
      errorMessage = String(localized: .settingsPayErrorNotAuthenticated)
      return
    }
    guard let selectedJob else {
      errorMessage = String(localized: .settingsPayErrorLoadFailed)
      return
    }
    guard selectedJob.currency != value else { return }
    guard canChangeCurrency else { return }

    do {
      guard
        try await jobsRepository.updateJobCurrency(
          userId: userId,
          jobId: selectedJob.id,
          currency: value
        ) != nil
      else {
        errorMessage = String(localized: .settingsPayErrorLoadFailed)
        return
      }

      refreshData()
      notifyDashboardDataChanged()
      Haptics.play(.success)
    } catch {
      logger.error("Failed to update selected job currency: \(error.localizedDescription)")
      errorMessage = error.localizedDescription
    }
  }

  // MARK: - Timeline Processing

  private func processTimelineEntries() {
    timelineEntries = WageTimelineProcessor.processSnapshots(
      snapshots,
      locale: Locale.appLocale,
      currency: userCurrency
    )
  }

  // MARK: - Editor Actions

  /// Open editor in create mode
  func openCreateEditor() {
    clearError()
    editorMode = .create
    editorSection = nil
    selectedSnapshot = nil
    showingEditor = true
  }

  /// Open editor in edit mode for a specific snapshot
  func openEditEditor(snapshot: WageSnapshot, section: WageSnapshotEditorSection? = nil) {
    clearError()
    editorMode = .edit
    editorSection = section
    selectedSnapshot = snapshot
    showingEditor = true
  }

  /// Close the editor
  func closeEditor() {
    showingEditor = false
    selectedSnapshot = nil
  }

  private func notifyDashboardDataChanged() {
    NotificationCenter.default.postShiftsDidChange(context: .fullReload)
  }

  // MARK: - Snapshot CRUD

  /// Create a new wage snapshot
  func createSnapshot(input: WageSnapshotEditorInput) async -> Bool {
    guard let userId = currentLocalUserId() else {
      errorMessage = String(localized: .settingsPayErrorNotAuthenticated)
      return false
    }

    // Validate date uniqueness
    if let fromDate = input.fromDate {
      let isoDate = fromDate.toISODateString()
      if hasSnapshotOnDate(isoDate, excludingId: nil) {
        errorMessage = String(localized: .settingsPayErrorDateConflict)
        return false
      }
    }

    do {
      let fromDate = input.fromDate

      _ = try await snapshotsRepository.createSnapshot(
        userId: userId,
        jobId: selectedJobId,
        fromDate: fromDate,
        hourlyWage: input.hourlyWage,
        wageLevel: input.wageLevel,
        tariffTypeId: input.tariffTypeId,
        supplements: input.supplements,
        overtime: input.overtime,
        taxEnabled: input.taxEnabled,
        taxPercentage: input.taxPercentage,
        breakEnabled: input.breakEnabled,
        breakMethod: input.breakMethod.rawValue,
        breakThresholdHours: input.breakThresholdHours,
        breakDeductionMinutes: input.breakDeductionMinutes
      )

      // Refresh UI
      refreshData()
      notifyDashboardDataChanged()
      Haptics.play(.success)
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
    guard currentLocalUserId() != nil else {
      errorMessage = String(localized: .settingsPayErrorNotAuthenticated)
      return false
    }

    // Validate date uniqueness (excluding current snapshot)
    if let fromDate = input.fromDate {
      let isoDate = fromDate.toISODateString()
      if hasSnapshotOnDate(isoDate, excludingId: id) {
        errorMessage = String(localized: .settingsPayErrorDateConflict)
        return false
      }
    }

    do {
      guard
        try await snapshotsRepository.updateSnapshot(
          id: id,
          jobId: selectedJobId,
          fromDate: input.fromDate,
          hourlyWage: input.hourlyWage,
          wageLevel: input.wageLevel,
          updateWageLevel: true,
          tariffTypeId: input.tariffTypeId,
          updateTariffTypeId: true,
          supplements: input.supplements,
          overtime: input.overtime,
          taxEnabled: input.taxEnabled,
          taxPercentage: input.taxPercentage,
          updateTaxPercentage: true,
          breakEnabled: input.breakEnabled,
          breakMethod: input.breakMethod.rawValue,
          breakThresholdHours: input.breakThresholdHours,
          breakDeductionMinutes: input.breakDeductionMinutes
        ) != nil
      else {
        errorMessage = String(localized: .settingsPayErrorUpdateFailed)
        return false
      }

      // Refresh UI
      refreshData()
      notifyDashboardDataChanged()
      Haptics.play(.success)
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
    if snapshot.isBaseline {
      errorMessage = String(localized: .settingsPayErrorCannotDeleteBaseline)
      return
    }

    // Count affected shifts
    affectedShiftCount = countAffectedShifts(for: snapshot)
    snapshotToDelete = snapshot
    showingDeleteConfirmation = true
  }

  /// Confirm and execute deletion
  func confirmDelete() async {
    guard let snapshot = snapshotToDelete, currentLocalUserId() != nil else {
      showingDeleteConfirmation = false
      snapshotToDelete = nil
      return
    }

    do {
      try await snapshotsRepository.deleteSnapshot(id: snapshot.id)

      // Refresh UI
      refreshData()
      notifyDashboardDataChanged()
      Haptics.play(.success)
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
    guard let userId = currentLocalUserId() else { return 0 }

    // Get all shifts
    let effectiveJobId = snapshot.job_id ?? selectedJobId
    let shifts = shiftsRepository.getAllShifts(for: userId, jobId: effectiveJobId)

    return shifts.filter { shift in
      guard let date = Date.fromISODateString(shift.shift_date) else { return false }
      let context = PaySettingsContext(
        workDate: date, snapshots: snapshots, payrollDay: selectedJobPayrollDay,
        halfTaxMonth: selectedJobHalfTaxMonth, payPeriod: selectedJobPayPeriod)
      return context.wageSnapshot?.id == snapshot.id || context.taxSnapshot?.id == snapshot.id
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

  /// Update payroll day with debouncing
  func updatePayrollDay(_ value: Int) {
    payrollDaySaveTask?.cancel()

    payrollDaySaveTask = Task {
      do {
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second debounce
        guard !Task.isCancelled else { return }

        await savePayrollDay(value)
      } catch {
        // Task was cancelled
      }
    }
  }

  private func savePayrollDay(_ value: Int) async {
    guard
      let userId = currentLocalUserId(),
      let selectedJobId,
      let selectedJob
    else { return }

    do {
      _ = try await jobsRepository.updateJobPaySettings(
        userId: userId,
        jobId: selectedJobId,
        payrollDay: value,
        halfTaxMonth: selectedJob.half_tax_month,
        monthlyGoal: selectedJob.monthly_goal,
        payPeriod: selectedJob.pay_period
      )

      refreshData()
      notifyDashboardDataChanged()
      logger.info("Updated payroll day to: \(value)")
    } catch {
      logger.error("Failed to update payroll day: \(error.localizedDescription)")
      errorMessage = String(localized: .settingsPayErrorSaveFailed)
    }
  }

  /// Update half tax month (immediate, no debounce needed for picker)
  func updateHalfTaxMonth(_ value: Int?) async {
    guard
      let userId = currentLocalUserId(),
      let selectedJobId,
      let selectedJob
    else { return }

    do {
      _ = try await jobsRepository.updateJobPaySettings(
        userId: userId,
        jobId: selectedJobId,
        payrollDay: selectedJob.payroll_day ?? 1,
        halfTaxMonth: value,
        monthlyGoal: selectedJob.monthly_goal,
        payPeriod: selectedJob.pay_period
      )

      refreshData()
      notifyDashboardDataChanged()
      logger.info("Updated half tax month to: \(value ?? 0)")
    } catch {
      logger.error("Failed to update half tax month: \(error.localizedDescription)")
      errorMessage = String(localized: .settingsPayErrorSaveFailed)
    }
  }

  func updatePayPeriod(_ value: PayPeriod) async {
    guard
      let userId = currentLocalUserId(),
      let selectedJobId,
      let selectedJob
    else { return }

    do {
      _ = try await jobsRepository.updateJobPaySettings(
        userId: userId,
        jobId: selectedJobId,
        payrollDay: selectedJob.payroll_day ?? 1,
        halfTaxMonth: selectedJob.half_tax_month,
        monthlyGoal: selectedJob.monthly_goal,
        payPeriod: value.isCalendarMonth ? nil : value
      )

      refreshData()
      notifyDashboardDataChanged()
      logger.info("Updated pay period")
    } catch {
      logger.error("Failed to update pay period: \(error.localizedDescription)")
      errorMessage = String(localized: .settingsPayErrorSaveFailed)
    }
  }

  // MARK: - Message Clearing

  func clearError() {
    errorMessage = nil
    errorTitle = nil
  }
}

// MARK: - Editor Input Model

/// Input data for creating/updating a wage snapshot
struct WageSnapshotEditorInput {
  var fromDate: Date?
  var hourlyWage: Double
  var wageLevel: Int?
  var supplements: SupplementRulesSnapshot
  var overtime: OvertimeConfig
  var taxEnabled: Bool
  var taxPercentage: Double
  var breakEnabled: Bool
  var breakMethod: BreakMethod
  var breakThresholdHours: Double
  var breakDeductionMinutes: Int
  /// Tariff type ID when using tariff rates (e.g., "hk_retail")
  var tariffTypeId: String?

  init(effectiveDate: Date, snapshots: [WageSnapshot]) {
    self.init(
      prefillFrom: SnapshotsService.snapshotForDate(
        effectiveDate.toISODateString(), from: snapshots
      ))
    fromDate = effectiveDate
  }

  /// When a new change moves to another period, carry forward that period's
  /// settings while retaining the fields the user has deliberately changed.
  func rebasingUneditedSettings(from previous: WageSnapshot, onto next: WageSnapshot) -> Self {
    let original = Self(from: previous)
    let replacement = Self(from: next)
    var result = self

    if hourlyWage == original.hourlyWage, wageLevel == original.wageLevel,
      tariffTypeId == original.tariffTypeId
    {
      result.hourlyWage = replacement.hourlyWage
      result.wageLevel = replacement.wageLevel
      result.tariffTypeId = replacement.tariffTypeId
    }
    if supplements == original.supplements {
      result.supplements = replacement.supplements
    }
    if overtime == original.overtime {
      result.overtime = replacement.overtime
    }
    if taxEnabled == original.taxEnabled, taxPercentage == original.taxPercentage {
      result.taxEnabled = replacement.taxEnabled
      result.taxPercentage = replacement.taxPercentage
    }
    if breakEnabled == original.breakEnabled, breakMethod == original.breakMethod,
      breakThresholdHours == original.breakThresholdHours,
      breakDeductionMinutes == original.breakDeductionMinutes
    {
      result.breakEnabled = replacement.breakEnabled
      result.breakMethod = replacement.breakMethod
      result.breakThresholdHours = replacement.breakThresholdHours
      result.breakDeductionMinutes = replacement.breakDeductionMinutes
    }
    return result
  }

  /// Create input from an existing snapshot
  init(from snapshot: WageSnapshot) {
    if let fromDateString = snapshot.from_date {
      self.fromDate = Date.fromISODateString(fromDateString)
    } else {
      self.fromDate = nil
    }
    self.hourlyWage = snapshot.hourly_wage
    self.wageLevel = snapshot.wage_level
    self.supplements = snapshot.supplements
    self.overtime = snapshot.overtime
    self.taxEnabled = snapshot.effectiveTaxEnabled
    self.taxPercentage = snapshot.effectiveTaxPercentage
    self.breakEnabled = snapshot.effectiveBreakEnabled && snapshot.breakMethod != .none
    self.breakMethod = snapshot.breakMethod
    self.breakThresholdHours = snapshot.effectiveBreakThresholdHours
    self.breakDeductionMinutes = snapshot.effectiveBreakDeductionMinutes
    self.tariffTypeId = snapshot.tariff_type_id
  }

  /// Create default input for new snapshot
  init(prefillFrom snapshot: WageSnapshot? = nil) {
    self.fromDate = Date()

    if let snapshot {
      self.hourlyWage = snapshot.hourly_wage
      self.wageLevel = snapshot.wage_level
      self.supplements = snapshot.supplements
      self.overtime = snapshot.overtime
      self.taxEnabled = snapshot.effectiveTaxEnabled
      self.taxPercentage = snapshot.effectiveTaxPercentage
      self.breakEnabled = snapshot.effectiveBreakEnabled && snapshot.breakMethod != .none
      self.breakMethod = snapshot.breakMethod
      self.breakThresholdHours = snapshot.effectiveBreakThresholdHours
      self.breakDeductionMinutes = snapshot.effectiveBreakDeductionMinutes
      self.tariffTypeId = snapshot.tariff_type_id
    } else {
      self.hourlyWage = 184.54
      self.wageLevel = 1
      self.supplements = SupplementRulesSnapshot(rules: PayrollCalculator.presetSupplementRules)
      self.overtime = .disabled
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
