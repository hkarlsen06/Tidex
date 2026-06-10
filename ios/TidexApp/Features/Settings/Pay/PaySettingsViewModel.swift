import Combine
import Foundation
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
  @Published var isLoading = true

  /// Error message to display
  @Published var errorMessage: String?
  /// Optional specific title for the current error alert.
  @Published var errorTitle: String?

  /// Whether a job-level action is currently being applied.
  @Published private(set) var isProcessingJobAction = false

  /// Active jobs for job-scoped timeline filtering.
  @Published private(set) var activeJobs: [Job] = []
  /// Whether the user has archived workplaces.
  @Published private(set) var hasArchivedJobs = false

  /// Selected job for this screen's wage timeline.
  @Published private(set) var selectedJobId: String?
  /// Whether the selected active job has the required baseline wage snapshot.
  @Published private(set) var isSelectedJobConfigured = false
  /// True when a previously selected entry job is no longer active and user must choose again.
  @Published private(set) var requiresJobReselection = false

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
  private let jobsRepository = JobsRepository.shared

  private var userId: String?
  private var pendingInitialSelectedJobId: String?

  // MARK: - Debounce

  private var monthlyGoalSaveTask: Task<Void, Never>?
  private var payrollDaySaveTask: Task<Void, Never>?

  // MARK: - Init

  init(initialSelectedJobId: String? = nil) {
    pendingInitialSelectedJobId = initialSelectedJobId
  }

  deinit {
    // Cancel any pending debounce tasks to prevent orphaned operations
    monthlyGoalSaveTask?.cancel()
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

      // Selected job was archived/deleted before load. Force user to pick again when multiple jobs exist.
      if jobs.count > 1 {
        selectedJobId = nil
        requiresJobReselection = true
        return
      }
    }

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
    requiresJobReselection && activeJobs.count > 1 && selectedJobId == nil
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

  var canDeleteSelectedJob: Bool {
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

  var selectedJobMonthlyGoal: Int? {
    selectedJob?.monthly_goal
  }

  var selectedJobHalfTaxMonth: Int? {
    selectedJob?.half_tax_month
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

  func archiveSelectedJob() async {
    guard let userId = currentLocalUserId() else {
      errorMessage = String(localized: .settingsPayErrorNotAuthenticated)
      return
    }
    guard let selectedJob else {
      errorMessage = String(localized: .settingsPayErrorLoadFailed)
      return
    }
    guard canArchiveSelectedJob else {
      if let selectedJobManagementHint {
        errorMessage = selectedJobManagementHint
      }
      return
    }

    isProcessingJobAction = true
    defer { isProcessingJobAction = false }

    do {
      try await jobsRepository.archiveJob(userId: userId, jobId: selectedJob.id)
      refreshData()
      notifyDashboardDataChanged()
      Haptics.play(.success)
    } catch {
      logger.error("Failed to archive selected job: \(error.localizedDescription)")
      errorMessage = error.localizedDescription
    }
  }

  func deleteSelectedJob() async {
    guard let userId = currentLocalUserId() else {
      errorMessage = String(localized: .settingsPayErrorNotAuthenticated)
      return
    }
    guard let selectedJob else {
      errorMessage = String(localized: .settingsPayErrorLoadFailed)
      return
    }
    guard canDeleteSelectedJob else {
      if let selectedJobManagementHint {
        errorMessage = selectedJobManagementHint
      }
      return
    }

    isProcessingJobAction = true
    defer { isProcessingJobAction = false }

    do {
      try await jobsRepository.deleteJob(
        userId: userId,
        jobId: selectedJob.id
      )
      refreshData()
      notifyDashboardDataChanged()
      Haptics.play(.success)
    } catch {
      logger.error("Failed to delete selected job: \(error.localizedDescription)")
      errorTitle = (error as? JobsRepositoryError)?.alertTitle
      errorMessage = error.localizedDescription
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
        monthlyGoal: input.monthlyGoal,
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
        jobId: selectedJobId,
        fromDate: fromDate,
        hourlyWage: input.hourlyWage,
        wageLevel: input.wageLevel,
        tariffTypeId: input.tariffTypeId,
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
      let isoDate = ISO8601DateFormatter.dateOnlyString(from: fromDate)
      if hasSnapshotOnDate(isoDate, excludingId: id) {
        errorMessage = String(localized: .settingsPayErrorDateConflict)
        return false
      }
    }

    do {
      _ = try await snapshotsRepository.updateSnapshot(
        id: id,
        jobId: selectedJobId,
        hourlyWage: input.hourlyWage,
        wageLevel: input.wageLevel,
        updateWageLevel: true,
        tariffTypeId: input.tariffTypeId,
        updateTariffTypeId: true,
        supplements: input.supplements,
        taxEnabled: input.taxEnabled,
        taxPercentage: input.taxPercentage,
        updateTaxPercentage: true,
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

    // Sort snapshots by date
    let sortedSnapshots = snapshots.sorted { s1, s2 in
      let d1 = s1.from_date ?? ""
      let d2 = s2.from_date ?? ""
      return d1 > d2
    }

    // Find this snapshot's index
    guard let index = sortedSnapshots.firstIndex(where: { $0.id == snapshot.id }),
      let fromDate = snapshot.from_date
    else {
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
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second debounce
        guard !Task.isCancelled else { return }

        await saveMonthlyGoal(value)
      } catch {
        // Task was cancelled
      }
    }
  }

  private func saveMonthlyGoal(_ value: Int?) async {
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
        monthlyGoal: value
      )

      refreshData()
      notifyDashboardDataChanged()
      logger.info("Updated monthly goal to: \(value ?? 0)")
    } catch {
      logger.error("Failed to update monthly goal: \(error.localizedDescription)")
      errorMessage = String(localized: .settingsPayErrorSaveFailed)
    }
  }

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
        monthlyGoal: selectedJob.monthly_goal
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
        monthlyGoal: selectedJob.monthly_goal
      )

      refreshData()
      notifyDashboardDataChanged()
      logger.info("Updated half tax month to: \(value ?? 0)")
    } catch {
      logger.error("Failed to update half tax month: \(error.localizedDescription)")
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

    if let snapshot {
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
