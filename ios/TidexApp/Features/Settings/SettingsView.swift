import SwiftUI
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "SettingsView")

/// Settings main menu view
/// Shown as the profile tab, and as a sheet when another screen opens a settings page directly.
struct SettingsView: View {
  @Environment(AppCoordinator.self) private var coordinator
  @Environment(\.dismiss) private var dismiss
  @Environment(\.layoutDirection) private var layoutDirection
  private let initialDestination: SettingsDestination?
  private let sheetPresentationDetent: Binding<PresentationDetent>?
  private let directPayManagerCompactDetent: PresentationDetent
  /// Set when shown as the profile tab. Deep links write a request here to open a page.
  private let tabRequest: Binding<TabRequest?>?

  /// Email shown under the name in the profile card
  @State private var profileEmail: String?

  /// Whether the current user can access admin settings
  /// Requires both admin role and AAL2 assurance level.
  @State private var canAccessAdminSettings = false
  /// Whether to show the pay job chooser before opening pay settings.
  @State private var showPayJobChooser = false
  /// Whether to show the calendar-link shift import sheet.
  @State private var showCalendarImport = false
  /// Whether to show quick add-job sheet from the pay chooser.
  @State private var showPayAddJobSheet = false
  /// Current presentation size for the pay job chooser sheet.
  @State private var payChooserPresentationDetent: PresentationDetent = .medium
  /// Job detail currently presented from the pay job chooser.
  @State private var payChooserDetailRoute: PayChooserDetailRoute?
  /// Active jobs used in pay chooser.
  @State private var payChooserJobs: [Job] = []
  /// Archived jobs for optional display in the job picker.
  @State private var payArchivedJobs: [Job] = []
  /// Jobs that already have the required baseline wage snapshot.
  @State private var payConfiguredJobIds: Set<String> = []
  /// Currency used to initialize job wage setup flow.
  @State private var payChooserCurrency: String = "kr"
  /// Payroll day inherited by newly created basic jobs.
  @State private var payChooserPayrollDay = 15
  /// User ID for the current pay chooser session.
  @State private var payChooserUserId: String?
  /// Selected job in the pay chooser (confirmed explicitly before navigation).
  @State private var selectedPayChooserJobId: String?
  /// Toggles archived jobs visibility in the management sheet.
  @State private var showArchivedPayJobs = false
  /// Error shown when preparing pay chooser/add fails.
  @State private var payChooserError: String?
  /// Alert shown for pay chooser errors that require immediate attention.
  @State private var payChooserErrorAlert: PayChooserErrorAlert?
  /// Job currently processing a row action.
  @State private var payJobManagementLoadingJobId: String?
  /// Job awaiting destructive delete confirmation from the pay chooser.
  @State private var pendingPayChooserDeleteJob: JobDeletionPreview?
  /// Job currently being configured with a baseline wage snapshot.
  @State private var paySetupJob: Job?
  /// Follow-up action after a pay setup sheet succeeds.
  @State private var pendingPaySetupAction: PaySetupAction?
  /// What to present once the pay chooser sheet finishes dismissing.
  @State private var pendingChooserDismissAction: PendingChooserDismissAction?
  /// What to present once the pay setup sheet finishes dismissing.
  @State private var pendingPaySetupDismissAction: PendingPaySetupDismissAction?
  /// Guards against duplicate pay-entry taps while loading job state.
  @State private var isOpeningPaySettings = false
  /// Navigation path for settings subviews
  @State private var navigationPath = NavigationPath()
  @State private var didApplyInitialDestination = false

  private let jobsRepository = JobsRepository.shared
  private let settingsRepository = SettingsRepository.shared
  private let jobPaySetupStatusService = JobPaySetupStatusService.shared

  private enum PaySetupAction: Equatable {
    case openPay
    case setDefault
  }

  /// What to present once the pay chooser sheet has finished dismissing.
  private enum PendingChooserDismissAction {
    case presentJobSetup(Job)
    case presentAddJobSheet
  }

  /// What to present once the pay setup sheet has finished dismissing.
  private enum PendingPaySetupDismissAction {
    case presentChooser
    case presentPayScreen(jobId: String)
  }

  private struct PayChooserDetailRoute: Identifiable, Hashable {
    let jobId: String

    var id: String { jobId }
  }

  private struct PayChooserErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
  }

  /// Asks the profile tab to return to its root and optionally open a page.
  struct TabRequest: Equatable {
    let id = UUID()
    let destination: SettingsDestination?
  }

  /// Settings navigation destinations
  enum SettingsDestination: Hashable {
    case profile
    case security
    case notifications
    case appearance
    case pay(jobId: String?)
    case recurringShifts
    case calendarSync(calendarSetupIntent: CalendarSubscriptionSetupIntent? = nil)
    case data
    case feedback
    case admin
    #if DEBUG
      case debug
    #endif
  }

  /// Compute user initials from display name for avatar fallback
  private var userInitials: String {
    let components = coordinator.userDisplayName.split(separator: " ")
    if components.count >= 2 {
      return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
    }
    return String(coordinator.userDisplayName.prefix(1)).uppercased()
  }

  init(
    initialDestination: SettingsDestination? = nil,
    sheetPresentationDetent: Binding<PresentationDetent>? = nil,
    directPayManagerCompactDetent: PresentationDetent = .medium
  ) {
    self.initialDestination = initialDestination
    self.sheetPresentationDetent = sheetPresentationDetent
    self.directPayManagerCompactDetent = directPayManagerCompactDetent
    self.tabRequest = nil
  }

  /// Creates the profile tab root.
  init(tabRequest: Binding<TabRequest?>) {
    self.initialDestination = nil
    self.sheetPresentationDetent = nil
    self.directPayManagerCompactDetent = .medium
    self.tabRequest = tabRequest
  }

  private var isTabRoot: Bool {
    tabRequest != nil
  }

  var body: some View {
    Group {
      if presentsPayChooserDirectly {
        payJobChooserDirectView
      } else {
        settingsRootView
      }
    }
    .task {
      await loadAccountDetails()
    }
    .sheet(isPresented: $showPayJobChooser, onDismiss: handleChooserDismiss) {
      payJobChooserSheet
    }
    .sheet(isPresented: $showCalendarImport) {
      CalendarImportView()
    }
    .sheet(isPresented: $showPayAddJobSheet, onDismiss: handlePaySetupDismiss) {
      AddJobSheet(
        initialCurrency: payChooserCurrency,
        initialPayrollDay: payChooserPayrollDay,
        setupDismissTitle: String(localized: .settingsPaySetupLaterButton),
        onSaveBasics: { input in
          await createBasicPayJobForSetup(input: input)
        }
      ) { input in
        await completeConfiguredPayJob(input: input)
      }
    }
    .sheet(item: $paySetupJob, onDismiss: handlePaySetupDismiss) { job in
      JobPaySetupSheet(
        job: job,
        initialCurrency: job.currency,
        dismissTitle: String(localized: .settingsPaySetupLaterButton)
      ) { input in
        await completePaySetup(for: job, input: input)
      }
    }
    .onAppear {
      applyInitialDestinationIfNeeded()
      applyTabRequestIfNeeded()
    }
    .onChange(of: tabRequest?.wrappedValue) { _, _ in
      applyTabRequestIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: .tabReselected)) { notification in
      guard isTabRoot, notification.userInfo?["tab"] as? MainTabView.Tab == .profile else {
        return
      }
      navigationPath = NavigationPath()
    }
  }

  private var presentsPayChooserDirectly: Bool {
    guard case .pay(let jobId)? = initialDestination else { return false }
    return jobId == nil
  }

  private var settingsRootView: some View {
    NavigationStack(path: $navigationPath) {
      List {
        Group {
          Section {
            profileCard
          }

          accountSection
          preferencesSection
          workSection
          supportSection
          adminSection
          debugSection
        }
        .listRowBackground(Color.tidexSurfacePrimary)
      }
      .listStyle(.insetGrouped)
      .tidexListBackground()
      .navigationTitle(String(localized: .settingsTitle))
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        if !isTabRoot {
          ToolbarItem(placement: .confirmationAction) {
            Button(String(localized: .commonDone)) {
              dismiss()
            }
          }
        }
      }
      .addShiftDestination(in: isTabRoot ? .profile : nil)
      .navigationDestination(for: SettingsDestination.self) { destination in
        Group {
          switch destination {
          case .profile:
            ProfileSettingsView {
              navigationPath.append(SettingsDestination.security)
            }

          case .security:
            SecuritySettingsView()

          case .notifications:
            NotificationSettingsView()

          case .appearance:
            AppearanceSettingsView()

          case .pay(let jobId):
            PaySettingsView(initialJobId: jobId)

          case .recurringShifts:
            RecurringShiftsSettingsView()

          case .calendarSync(let calendarSetupIntent):
            CalendarSyncSettingsView(calendarSetupIntent: calendarSetupIntent)

          case .data:
            DataSettingsView()

          case .feedback:
            FeedbackSettingsView()

          case .admin:
            AdminSettingsView()

          #if DEBUG
            case .debug:
              SyncDebugView()
          #endif
          }
        }
        .toolbarRole(.editor)
      }
    }
  }

  private var payJobChooserDirectView: some View {
    payJobChooserNavigationStack(isPresentedAsNestedSheet: false)
      .task {
        await openPaySettings(presentAsSheet: false)
      }
  }

  private let profileAvatarSize: CGFloat = 64

  private var profileCard: some View {
    NavigationLink(value: SettingsDestination.profile) {
      HStack(spacing: Spacing.md) {
        AvatarView(
          url: coordinator.userAvatarUrl,
          initials: userInitials,
          size: profileAvatarSize
        )

        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(coordinator.userDisplayName)
            .font(.tidexLargeTitle)
            .foregroundColor(.tidexTextPrimary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

          if let profileEmail, !profileEmail.isEmpty {
            Text(profileEmail)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextSecondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }
        .layoutPriority(1)
      }
      .padding(.vertical, Spacing.xs)
    }
    .accessibilityIdentifier("settings.profile-card")
  }

  private var accountSection: some View {
    Section(String(localized: .settingsMenuAccountLabel)) {
      NavigationLink(value: SettingsDestination.security) {
        Label(String(localized: .settingsMenuSecurityLabel), systemImage: "lock.shield")
      }
    }
  }

  private var preferencesSection: some View {
    Section(String(localized: .settingsGroupPreferences)) {
      NavigationLink(value: SettingsDestination.notifications) {
        Label(String(localized: .settingsMenuNotificationsLabel), systemImage: "bell")
      }

      NavigationLink(value: SettingsDestination.appearance) {
        Label(String(localized: .settingsMenuAppearanceLabel), systemImage: "paintpalette")
      }
    }
  }

  private var workSection: some View {
    Section(String(localized: .settingsGroupWork)) {
      Button {
        Task { await openPaySettings() }
      } label: {
        HStack {
          Label(String(localized: .settingsMenuPayLabel), systemImage: "banknote")
          Spacer()
          if isOpeningPaySettings {
            ProgressView()
          }
        }
      }
      // A Button row draws its label in the tint color, so match the NavigationLink rows.
      .tint(.tidexTextPrimary)
      .disabled(isOpeningPaySettings)

      NavigationLink(value: SettingsDestination.recurringShifts) {
        Label(String(localized: .settingsMenuRecurringShiftsLabel), systemImage: "repeat.circle")
      }

      NavigationLink(value: SettingsDestination.calendarSync()) {
        Label(String(localized: .calendarSubscriptionTitle), systemImage: "calendar.badge.clock")
      }

      Button {
        showCalendarImport = true
      } label: {
        Label(String(localized: .calendarImportTitle), systemImage: "calendar.badge.plus")
      }
      .tint(.tidexTextPrimary)
    }
  }

  private var supportSection: some View {
    Section(String(localized: .settingsGroupSupportData)) {
      NavigationLink(value: SettingsDestination.feedback) {
        Label(String(localized: .settingsMenuFeedbackLabel), systemImage: "message")
      }

      NavigationLink(value: SettingsDestination.data) {
        Label(String(localized: .settingsMenuDataLabel), systemImage: "externaldrive")
      }
    }
  }

  @ViewBuilder
  private var adminSection: some View {
    if canAccessAdminSettings {
      Section(String(localized: .settingsGroupAdmin)) {
        NavigationLink(value: SettingsDestination.admin) {
          Label(
            String(localized: .settingsMenuAdminLabel),
            systemImage: "shield.lefthalf.filled.badge.checkmark"
          )
        }
      }
    }
  }

  @ViewBuilder
  private var debugSection: some View {
    #if DEBUG
      Section("Debug") {
        NavigationLink(value: SettingsDestination.debug) {
          Label("Debug", systemImage: "ladybug")
        }
      }
    #endif
  }

  // MARK: - Actions

  private func applyInitialDestinationIfNeeded() {
    guard !didApplyInitialDestination, let initialDestination else { return }
    didApplyInitialDestination = true
    open(initialDestination)
  }

  /// Consumes a deep link request from the tab bar: back to the root, then the requested page.
  private func applyTabRequestIfNeeded() {
    guard let tabRequest, let request = tabRequest.wrappedValue else { return }
    tabRequest.wrappedValue = nil
    navigationPath = NavigationPath()
    if let destination = request.destination {
      open(destination)
    }
  }

  private func open(_ destination: SettingsDestination) {
    switch destination {
    case .pay(let jobId):
      if let jobId {
        navigationPath.append(SettingsDestination.pay(jobId: jobId))
      } else if !presentsPayChooserDirectly {
        // This deep link can arrive while MainTabView is still switching to the Profile
        // tab (and possibly dismissing an unrelated sheet), which owns that transition.
        // There's no local dismiss/completion to hook into, so wait it out before
        // presenting the chooser sheet on top.
        Task {
          try? await Task.sleep(nanoseconds: 350_000_000)
          await openPaySettings()
        }
      }

    default:
      navigationPath.append(destination)
    }
  }

  /// Loads the email for the profile card and checks admin access from the same session.
  private func loadAccountDetails() async {
    do {
      let session = try await AuthSessionManager.shared.getSession()
      profileEmail = session.user.email
      guard let appMetadata = session.user.appMetadata["role"],
        case .string(let role) = appMetadata,
        role == "admin"
      else {
        canAccessAdminSettings = false
        return
      }

      let mfaStatus = try await AuthService.shared.getMFAStatus()
      canAccessAdminSettings = mfaStatus.currentLevel == "aal2"
    } catch {
      // Silently fail closed - hide admin menu item by default.
      canAccessAdminSettings = false
      logger.debug("Could not check admin access status: \(error.localizedDescription)")
    }
  }

  private func openPaySettings(presentAsSheet: Bool = true) async {
    guard !isOpeningPaySettings else { return }
    isOpeningPaySettings = true
    defer { isOpeningPaySettings = false }

    do {
      let userId = try await AuthSessionManager.shared.getUserId()
      payChooserUserId = userId
      refreshPayJobLists(for: userId)
      refreshPayChooserDefaults(for: userId)
      clearPayChooserError()
      showArchivedPayJobs = false
      payChooserDetailRoute = nil
      applyPayChooserDetent(archivedVisible: false)
      if presentAsSheet {
        showPayJobChooser = true
      }
    } catch {
      logger.error("Failed to prepare pay settings: \(error.localizedDescription)")
      presentPayChooserError(error)
      if presentAsSheet {
        showPayJobChooser = true
      }
    }
  }

  private func applyPayChooserDetent(
    archivedVisible: Bool? = nil
  ) {
    let isArchivedVisible = archivedVisible ?? showArchivedPayJobs
    let targetDetent: PresentationDetent = isArchivedVisible ? .large : compactPayChooserDetent

    if presentsPayChooserDirectly {
      sheetPresentationDetent?.wrappedValue = targetDetent
    } else {
      payChooserPresentationDetent = targetDetent
    }
  }

  private var compactPayChooserDetent: PresentationDetent {
    presentsPayChooserDirectly ? directPayManagerCompactDetent : .medium
  }

  private func createBasicPayJobForSetup(input: AddJobBasicsInput) async -> Job? {
    do {
      let userId: String
      if let payChooserUserId {
        userId = payChooserUserId
      } else {
        userId = try await AuthSessionManager.shared.getUserId()
        payChooserUserId = userId
      }

      let createdJob = try await jobsRepository.createJob(
        userId: userId,
        name: input.name,
        color: input.color,
        currency: input.currency,
        payrollDay: input.payrollDay,
        halfTaxMonth: input.halfTaxMonth,
        monthlyGoal: nil
      )

      selectedPayChooserJobId = createdJob.id
      refreshPayJobLists(for: userId)
      refreshPayChooserDefaults(for: userId)
      return createdJob
    } catch {
      logger.error("Failed to create basic job from chooser: \(error.localizedDescription)")
      presentPayChooserError(error)
      return nil
    }
  }

  private func completeConfiguredPayJob(input: AddJobSetupInput) async -> Bool {
    let resolvedUserId: String?
    if let payChooserUserId {
      resolvedUserId = payChooserUserId
    } else {
      resolvedUserId = try? await AuthSessionManager.shared.getUserId()
    }

    guard let userId = resolvedUserId else {
      presentPayChooserError(String(localized: .settingsPayChooseJobErrorNotAuthenticated))
      return false
    }

    guard let existingJobSetup = input.existingJobSetup else {
      presentPayChooserError(String(localized: .settingsPayErrorSaveFailed))
      return false
    }

    do {
      guard
        try await jobsRepository.updateJob(
          userId: userId,
          jobId: existingJobSetup.id,
          name: input.name,
          color: input.color
        ) != nil
      else {
        throw JobsRepositoryError.jobNotFound
      }

      let configuredJob = try await jobsRepository.completePaySetup(
        userId: userId,
        jobId: existingJobSetup.id,
        currency: input.currency,
        payrollDay: input.payrollDay,
        halfTaxMonth: input.halfTaxMonth,
        monthlyGoal: jobsRepository.getJob(id: existingJobSetup.id)?.monthly_goal,
        baselineSnapshot: input.baselineSnapshot
      )

      selectedPayChooserJobId = configuredJob.id
      pendingPaySetupAction = nil
      refreshPayJobLists(for: userId)
      refreshPayChooserDefaults(for: userId)
      pendingPaySetupDismissAction = .presentPayScreen(jobId: configuredJob.id)

      Haptics.play(.success)
      return true
    } catch {
      logger.error("Failed to complete added job pay setup: \(error.localizedDescription)")
      presentPayChooserError(error)
      return false
    }
  }

  private func openPayForSelectedJob(_ job: Job) {
    selectedPayChooserJobId = job.id
    guard payConfiguredJobIds.contains(job.id) else {
      beginPaySetup(for: job, action: .openPay)
      return
    }

    presentPayChooserPayScreen(jobId: job.id)
  }

  private func openAddPayJob() {
    presentAfterChooserDismiss(.presentAddJobSheet)
  }

  /// Presents `action` once the pay chooser sheet dismisses. When the chooser is the
  /// screen's root (deep-linked directly, so there's no sheet to dismiss), this presents
  /// immediately instead of waiting on `onDismiss`, which never fires in that mode.
  private func presentAfterChooserDismiss(_ action: PendingChooserDismissAction) {
    guard !presentsPayChooserDirectly else {
      applyChooserDismissAction(action)
      return
    }
    pendingChooserDismissAction = action
    showPayJobChooser = false
  }

  /// Presents whatever the pay chooser sheet was dismissed to make way for.
  private func handleChooserDismiss() {
    guard let action = pendingChooserDismissAction else { return }
    pendingChooserDismissAction = nil
    applyChooserDismissAction(action)
  }

  private func applyChooserDismissAction(_ action: PendingChooserDismissAction) {
    switch action {
    case .presentJobSetup(let job):
      paySetupJob = job

    case .presentAddJobSheet:
      showPayAddJobSheet = true
    }
  }

  /// Presents whatever the pay setup sheet was dismissed to make way for.
  private func handlePaySetupDismiss() {
    guard let action = pendingPaySetupDismissAction else { return }
    pendingPaySetupDismissAction = nil

    switch action {
    case .presentChooser:
      showPayJobChooser = true

    case .presentPayScreen(let jobId):
      presentPayChooserPayScreen(jobId: jobId)
    }
  }

  private func refreshPayJobLists(for userId: String) {
    payChooserJobs = sortJobs(jobsRepository.getActiveJobs(for: userId))
    payConfiguredJobIds = jobPaySetupStatusService.configuredJobIds(for: userId)

    payArchivedJobs = sortJobs(
      jobsRepository.getAllJobs(for: userId, includeArchived: true, includeDeleted: false)
        .filter { $0.archived_at != nil }
    )
    // The archived section hides once it is empty, so drop back to the compact sheet.
    if payArchivedJobs.isEmpty, showArchivedPayJobs {
      showArchivedPayJobs = false
      applyPayChooserDetent(archivedVisible: false)
    }

    if let selectedPayChooserJobId,
      payChooserJobs.contains(where: { $0.id == selectedPayChooserJobId }) == false
    {
      self.selectedPayChooserJobId =
        payChooserJobs.first(where: \.is_default)?.id
        ?? payChooserJobs.first?.id
      return
    }

    if selectedPayChooserJobId == nil {
      selectedPayChooserJobId =
        payChooserJobs.first(where: \.is_default)?.id
        ?? payChooserJobs.first?.id
    }
  }

  private func refreshPayChooserDefaults(for userId: String) {
    let settings = settingsRepository.getSettings(for: userId)
    let defaultJob = jobsRepository.getDefaultJob(for: userId)

    payChooserCurrency = defaultJob?.currency ?? settings?.currency ?? "kr"
    payChooserPayrollDay = defaultJob?.payroll_day ?? settings?.effectivePayrollDay ?? 15
  }

  private func sortJobs(_ jobs: [Job]) -> [Job] {
    jobs.sorted { lhs, rhs in
      if lhs.is_default != rhs.is_default {
        return lhs.is_default && !rhs.is_default
      }
      if lhs.sort_order == rhs.sort_order {
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
      return lhs.sort_order < rhs.sort_order
    }
  }

  private func clearPayChooserError() {
    payChooserError = nil
    payChooserErrorAlert = nil
  }

  private func presentPayChooserError(_ message: String, title: String? = nil) {
    let resolvedTitle = title ?? String(localized: .commonError)
    payChooserError = message
    payChooserErrorAlert = PayChooserErrorAlert(title: resolvedTitle, message: message)
  }

  private func presentPayChooserError(_ error: Error) {
    presentPayChooserError(
      error.localizedDescription,
      title: (error as? JobsRepositoryError)?.alertTitle
    )
  }

  private func archivePayJob(_ jobId: String) async {
    guard let payChooserUserId else {
      presentPayChooserError(String(localized: .settingsPayChooseJobErrorNotAuthenticated))
      return
    }

    clearPayChooserError()
    payJobManagementLoadingJobId = jobId
    defer { payJobManagementLoadingJobId = nil }

    do {
      try await jobsRepository.archiveJob(userId: payChooserUserId, jobId: jobId)
      refreshPayJobLists(for: payChooserUserId)
    } catch {
      presentPayChooserError(error)
    }
  }

  private func restorePayJob(_ jobId: String) async {
    guard let payChooserUserId else {
      presentPayChooserError(String(localized: .settingsPayChooseJobErrorNotAuthenticated))
      return
    }

    clearPayChooserError()
    payJobManagementLoadingJobId = jobId
    defer { payJobManagementLoadingJobId = nil }

    do {
      try await jobsRepository.restoreJob(userId: payChooserUserId, jobId: jobId)
      refreshPayJobLists(for: payChooserUserId)
    } catch {
      presentPayChooserError(error)
    }
  }

  private func preparePayJobDeletion(_ jobId: String) async {
    guard let payChooserUserId, payJobManagementLoadingJobId == nil else { return }
    clearPayChooserError()
    payJobManagementLoadingJobId = jobId
    defer { payJobManagementLoadingJobId = nil }

    do {
      let preview = try await jobsRepository.prepareJobDeletion(
        userId: payChooserUserId, jobId: jobId)
      guard self.payChooserUserId == payChooserUserId else { return }
      pendingPayChooserDeleteJob = preview
      refreshPayJobLists(for: payChooserUserId)
    } catch {
      presentPayChooserError(error)
    }
  }

  private func deletePayJob(_ preview: JobDeletionPreview) async {
    guard let payChooserUserId else {
      presentPayChooserError(String(localized: .settingsPayChooseJobErrorNotAuthenticated))
      return
    }

    clearPayChooserError()
    payJobManagementLoadingJobId = preview.jobId
    defer { payJobManagementLoadingJobId = nil }

    do {
      try await jobsRepository.deleteJob(userId: payChooserUserId, preview: preview)
      refreshPayJobLists(for: payChooserUserId)
      Haptics.play(.success)
    } catch {
      refreshPayJobLists(for: payChooserUserId)
      presentPayChooserError(error)
    }
  }

  private func setDefaultPayJob(_ jobId: String) async {
    guard let payChooserUserId else {
      presentPayChooserError(String(localized: .settingsPayChooseJobErrorNotAuthenticated))
      return
    }

    guard payConfiguredJobIds.contains(jobId) else {
      if let job = payChooserJobs.first(where: { $0.id == jobId }) {
        beginPaySetup(for: job, action: .setDefault)
      }
      return
    }

    clearPayChooserError()
    payJobManagementLoadingJobId = jobId
    defer { payJobManagementLoadingJobId = nil }

    do {
      try await jobsRepository.setDefaultJob(userId: payChooserUserId, jobId: jobId)
      selectedPayChooserJobId = jobId
      refreshPayJobLists(for: payChooserUserId)
    } catch {
      presentPayChooserError(error)
    }
  }

  private func beginPaySetup(for job: Job, action: PaySetupAction) {
    pendingPaySetupAction = action
    presentAfterChooserDismiss(.presentJobSetup(job))
  }

  private func completePaySetup(for job: Job, input: JobPaySetupInput) async -> Bool {
    let resolvedUserId: String?
    if let payChooserUserId {
      resolvedUserId = payChooserUserId
    } else {
      resolvedUserId = try? await AuthSessionManager.shared.getUserId()
    }

    guard let userId = resolvedUserId else {
      presentPayChooserError(String(localized: .settingsPayChooseJobErrorNotAuthenticated))
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
      refreshPayJobLists(for: userId)
      refreshPayChooserDefaults(for: userId)

      switch pendingPaySetupAction {
      case .setDefault:
        try await jobsRepository.setDefaultJob(userId: userId, jobId: configuredJob.id)
        selectedPayChooserJobId = configuredJob.id
        refreshPayJobLists(for: userId)
        pendingPaySetupAction = nil
        pendingPaySetupDismissAction = .presentChooser

      case .openPay, .none:
        selectedPayChooserJobId = configuredJob.id
        pendingPaySetupAction = nil
        pendingPaySetupDismissAction = .presentPayScreen(jobId: configuredJob.id)
      }

      Haptics.play(.success)
      return true
    } catch {
      logger.error("Failed to complete pay setup: \(error.localizedDescription)")
      presentPayChooserError(error)
      return false
    }
  }

  private func presentPayChooserPayScreen(jobId: String) {
    if !presentsPayChooserDirectly {
      showPayJobChooser = true
    }

    payChooserDetailRoute = PayChooserDetailRoute(jobId: jobId)
  }

  @ViewBuilder
  private var payJobChooserSheet: some View {
    payJobChooserNavigationStack(isPresentedAsNestedSheet: true)
      .presentationDetents([.medium, .large], selection: $payChooserPresentationDetent)
      .presentationDragIndicator(.visible)
  }

  private func payJobChooserNavigationStack(isPresentedAsNestedSheet: Bool) -> some View {
    let defaultJob = payChooserJobs.first(where: \.is_default)  // swiftlint:disable:this explicit_type_interface

    return NavigationStack {
      List {
        Group {
          Section {
            if payChooserJobs.isEmpty {
              Text(.settingsPayChooseJobEmpty)
                .font(.tidexFootnote)
                .foregroundColor(.tidexTextSecondary)
            } else {
              ForEach(payChooserJobs, id: \.id) { job in
                payChooserWorkplaceRow(job, isDefault: job.id == defaultJob?.id)
              }
            }

            Button {
              openAddPayJob()
            } label: {
              Label {
                Text(.settingsPayAddJobCta)
                  .foregroundColor(.tidexBlue)
              } icon: {
                Image(systemName: "plus.circle.fill")
                  .foregroundColor(.tidexBlue)
              }
              .font(.tidexBodyMedium)
            }
          } footer: {
            if !payChooserJobs.isEmpty {
              Text(.settingsPayManageJobsFooter)
            }
          }

          if !payArchivedJobs.isEmpty {
            archivedPayJobsSection
          }

          if let payChooserError {
            Section {
              Text(payChooserError)
                .font(.tidexFootnote)
                .foregroundColor(.tidexError)
            }
          }
        }
        .listRowBackground(Color.tidexSurfacePrimary)
      }
      .tidexListBackground()
      .navigationTitle(String(localized: .settingsPayManageJobsTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(
            isPresentedAsNestedSheet
              ? String(localized: .commonCancel) : String(localized: .commonDone)
          ) {
            if isPresentedAsNestedSheet {
              showPayJobChooser = false
            } else {
              dismiss()
            }
          }
        }
      }
      .alert(
        payChooserErrorAlert?.title ?? String(localized: .commonError),
        isPresented: .init(
          get: { payChooserErrorAlert != nil },
          set: { if !$0 { clearPayChooserError() } }
        )
      ) {
        Button(String(localized: .commonOk)) {
          clearPayChooserError()
        }
      } message: {
        if let payChooserErrorAlert {
          Text(payChooserErrorAlert.message)
        }
      }
      .confirmationDialog(
        String(localized: .settingsPayJobActionsDeleteHistoryConfirmTitle),
        isPresented: .init(
          get: { pendingPayChooserDeleteJob != nil },
          set: { if !$0 { pendingPayChooserDeleteJob = nil } }
        ),
        titleVisibility: .visible,
        presenting: pendingPayChooserDeleteJob
      ) { preview in
        Button(String(localized: .settingsPayJobActionsDeleteHistory), role: .destructive) {
          pendingPayChooserDeleteJob = nil
          Task {
            await deletePayJob(preview)
          }
        }

        Button(role: .cancel) {
          pendingPayChooserDeleteJob = nil
        } label: {
          Text(.commonCancel)
        }
      } message: { preview in
        Text(preview.confirmationMessage)
      }
      .sheet(item: $payChooserDetailRoute) { route in
        payChooserDetailSheet(route)
      }
      .simultaneousGesture(
        payChooserManagementExitGesture(isEnabled: !isPresentedAsNestedSheet)
      )
    }
    .onReceive(NotificationCenter.default.publisher(for: .workSetupDataDidChange)) { _ in
      guard let payChooserUserId else { return }
      refreshPayJobLists(for: payChooserUserId)
      refreshPayChooserDefaults(for: payChooserUserId)
    }
  }

  private func payChooserDetailSheet(_ route: PayChooserDetailRoute) -> some View {
    NavigationStack {
      PaySettingsView(initialJobId: route.jobId)
        .toolbarRole(.editor)
    }
    .contentShape(Rectangle())
    .simultaneousGesture(payChooserDetailExitGesture)
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }

  private var payChooserDetailExitGesture: some Gesture {
    DragGesture(minimumDistance: 24, coordinateSpace: .local)
      .onEnded { value in
        guard isLayoutDirectionExitSwipe(value) else { return }

        payChooserDetailRoute = nil
      }
  }

  private func payChooserManagementExitGesture(isEnabled: Bool) -> some Gesture {
    DragGesture(minimumDistance: 24, coordinateSpace: .local)
      .onEnded { value in
        guard isEnabled, isLayoutDirectionExitSwipe(value) else { return }

        dismiss()
      }
  }

  private func isLayoutDirectionExitSwipe(_ value: DragGesture.Value) -> Bool {
    let horizontalDistance = value.translation.width
    let verticalDistance = abs(value.translation.height)
    let predictedHorizontalDistance = value.predictedEndTranslation.width
    let directionMultiplier: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
    let exitDistance = horizontalDistance * directionMultiplier
    let predictedExitDistance = predictedHorizontalDistance * directionMultiplier

    return exitDistance > 64
      && predictedExitDistance > 110
      && exitDistance > verticalDistance * 1.4
  }

  private var archivedPayJobsSection: some View {
    Section {
      DisclosureGroup(
        isExpanded: Binding(
          get: { showArchivedPayJobs },
          set: { isVisible in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
              showArchivedPayJobs = isVisible
              applyPayChooserDetent(archivedVisible: isVisible)
            }
          }
        )
      ) {
        ForEach(payArchivedJobs, id: \.id) { job in
          payChooserArchivedJobRow(job)
        }
      } label: {
        Label {
          HStack(spacing: Spacing.sm) {
            Text(.settingsPayManageJobsArchivedTitle)
              .foregroundColor(.tidexTextSecondary)

            Spacer(minLength: Spacing.sm)

            Text(payArchivedJobs.count, format: .number)
              .foregroundColor(.tidexTextMuted)
              .monospacedDigit()
          }
        } icon: {
          Image(systemName: "archivebox")
            .foregroundColor(.tidexTextMuted)
        }
        .font(.tidexBodyMedium)
      }
      .tint(.tidexTextMuted)
    }
  }

  private func payChooserWorkplaceRow(_ job: Job, isDefault: Bool) -> some View {
    Button {
      openPayForSelectedJob(job)
    } label: {
      HStack(spacing: Spacing.sm) {
        WorkplaceNameText(
          name: job.name,
          colorHex: job.color,
          font: .tidexBodyMedium,
          fallbackBadgeColor: .tidexBlue,
          lineLimit: 2,
          badgeCornerRadius: CornerRadius.md,
          badgeHorizontalPadding: Spacing.sm,
          badgeVerticalPadding: Spacing.xs
        )
        .layoutPriority(1)

        Spacer(minLength: Spacing.sm)

        if payJobManagementLoadingJobId == job.id {
          ProgressView()
            .controlSize(.small)
        } else {
          JobStatusBadges(
            isDefault: isDefault,
            requiresPaySetup: !payConfiguredJobIds.contains(job.id)
          )
            .layoutPriority(2)
        }

        Image(systemName: layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right")
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
          .accessibilityHidden(true)
      }
      .contentShape(Rectangle())
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      activePayJobActions(job)
    }
    .contextMenu {
      activePayJobActions(job)
    }
  }

  private func payChooserArchivedJobRow(_ job: Job) -> some View {
    HStack(spacing: Spacing.sm) {
      WorkplaceNameText(
        name: job.name,
        colorHex: job.color,
        font: .tidexBodyMedium,
        fallbackBadgeColor: .tidexBlue,
        lineLimit: 2
      )
      .opacity(0.72)

      Spacer(minLength: Spacing.sm)

      if payJobManagementLoadingJobId == job.id {
        ProgressView()
          .controlSize(.small)
      }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      archivedPayJobActions(job)
    }
    .contextMenu {
      archivedPayJobActions(job)
    }
  }

  @ViewBuilder
  private func activePayJobActions(_ job: Job) -> some View {
    if !job.is_default {
      Button {
        Task {
          await setDefaultPayJob(job.id)
        }
      } label: {
        Label(
          String(localized: .settingsPayJobActionsSetDefault),
          systemImage: "checkmark.circle"
        )
      }
      .tint(.tidexBlue)
      .disabled(payJobManagementLoadingJobId != nil)
    }

    if payChooserJobs.count > 1, !job.is_default {
      Button {
        Task {
          await archivePayJob(job.id)
        }
      } label: {
        Label(
          String(localized: .settingsPayJobActionsArchive),
          systemImage: "archivebox"
        )
      }
      .tint(.tidexTextMuted)
      .disabled(payJobManagementLoadingJobId != nil)
    }
  }

  @ViewBuilder
  private func archivedPayJobActions(_ job: Job) -> some View {
    Button {
      Task {
        await restorePayJob(job.id)
      }
    } label: {
      Label(
        String(localized: .settingsPayManageJobsRestore),
        systemImage: "arrow.uturn.backward.circle"
      )
    }
    .tint(.tidexBlue)
    .disabled(payJobManagementLoadingJobId != nil)

    Button(role: .destructive) {
      Task {
        await preparePayJobDeletion(job.id)
      }
    } label: {
      Label(
        String(localized: .settingsPayJobActionsDeleteHistory),
        systemImage: "trash"
      )
    }
    .disabled(payJobManagementLoadingJobId != nil)
  }
}

// MARK: - Recurring Shifts Settings

private struct RecurringShiftsSettingsView: View {
  @State private var recurringShifts: [RecurringShiftRow] = []
  @State private var recurringShiftToEdit: RecurringShiftRow?
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    List {
      Group {
        if let errorMessage {
          Section {
            Label {
              Text(errorMessage)
                .foregroundColor(.tidexError)
            } icon: {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.tidexError)
            }
            .font(.tidexSubheadline)
          }
        }

        if isLoading && recurringShifts.isEmpty {
          Section {
            ProgressView()
              .frame(maxWidth: .infinity)
          }
        } else if !recurringShifts.isEmpty {
          Section {
            ForEach(recurringShifts, id: \.id) { recurring in
              recurringShiftRow(recurring)
            }
          } footer: {
            Text(.settingsRecurringShiftsSubtitle)
          }
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .overlay {
      if !isLoading, recurringShifts.isEmpty, errorMessage == nil {
        ContentUnavailableView {
          Label(String(localized: .settingsRecurringShiftsEmptyTitle), systemImage: "repeat")
        } description: {
          Text(.settingsRecurringShiftsEmptyDescription)
        }
      }
    }
    .navigationTitle(String(localized: .settingsRecurringShiftsTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadRecurringShifts()
    }
    .refreshable {
      await loadRecurringShifts()
    }
    .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { _ in
      Task {
        await loadRecurringShifts()
      }
    }
    .sheet(item: $recurringShiftToEdit) { recurring in
      RecurringShiftEditorSheet(
        recurringShift: recurring,
        onSave: { editResult in
          recurringShiftToEdit = nil
          Task {
            await updateRecurringShift(editResult)
          }
        },
        onDelete: {
          let recurringId = recurring.id
          recurringShiftToEdit = nil
          Task {
            await deleteRecurringShift(recurringId)
          }
        }
      )
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    .sensoryFeedback(.impact(weight: .light), trigger: recurringShiftToEdit) { _, new in
      new != nil
    }
  }

  private func recurringShiftRow(_ recurring: RecurringShiftRow) -> some View {
    let exclusionCount = recurring.effectiveExclusions.count
    var details = [weekdaySummary(for: recurring.selected_days), repeatLabel(for: recurring.repeat_interval_weeks)]
    if exclusionCount > 0 {
      details.append(String(localized: .settingsRecurringShiftsExcludedCount(exclusionCount)))
    }

    return Button {
      recurringShiftToEdit = recurring
    } label: {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(verbatim: "\(recurring.cleanStartTime) - \(recurring.cleanEndTime)")
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)
          .monospacedDigit()

        Text(verbatim: details.joined(separator: " • "))
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }
      .padding(.vertical, Spacing.xxxs)
    }
  }

  private func loadRecurringShifts() async {
    isLoading = true
    errorMessage = nil

    do {
      let userId = try await resolveRecurringSettingsUserId()
      let shifts = RecurringShiftsRepository.shared.getRecurringShifts(for: userId)
      recurringShifts = sortRecurringShifts(shifts)
    } catch {
      logger.error("Failed to load recurring shifts settings: \(error.localizedDescription)")
      errorMessage = String(localized: .settingsRecurringShiftsLoadFailed)
    }

    isLoading = false
  }

  private func resolveRecurringSettingsUserId() async throws -> String {
    do {
      let session = try await AuthSessionManager.shared.getSession()
      return session.normalizedUserId
    } catch {
      guard AuthSessionManager.shared.isTransientSessionResolutionError(error),
        let offlineUserId = AuthSessionManager.shared.offlineUserIdFallback()
      else {
        throw error
      }

      return offlineUserId
    }
  }

  private func updateRecurringShift(_ editResult: RecurringShiftEditResult) async {
    do {
      _ = try await RecurringShiftsRepository.shared.updateRecurringShift(
        id: editResult.recurringId,
        startTime: editResult.startTime,
        endTime: editResult.endTime,
        repeatIntervalWeeks: editResult.repeatIntervalWeeks,
        selectedDays: editResult.selectedDays,
        endCondition: editResult.endCondition,
        exclusions: editResult.exclusions
      )

      await loadRecurringShifts()
      NotificationCenter.default.postShiftsDidChange(context: .fullReload)
      Haptics.play(.success)
    } catch {
      logger.error("Failed to update recurring shift from settings: \(error.localizedDescription)")
      errorMessage = String(localized: .settingsRecurringShiftsSaveFailed)
    }
  }

  private func deleteRecurringShift(_ recurringId: String) async {
    do {
      try await RecurringShiftsRepository.shared.deleteRecurringShift(id: recurringId)
      await loadRecurringShifts()
      NotificationCenter.default.postShiftsDidChange(context: .fullReload)
      Haptics.play(.success)
    } catch {
      logger.error("Failed to delete recurring shift from settings: \(error.localizedDescription)")
      errorMessage = String(localized: .settingsRecurringShiftsDeleteFailed)
    }
  }

  private func sortRecurringShifts(_ shifts: [RecurringShiftRow]) -> [RecurringShiftRow] {
    shifts.sorted { lhs, rhs in
      let lhsEarliestAnchor = lhs.selected_days.values.min() ?? "9999-12-31"
      let rhsEarliestAnchor = rhs.selected_days.values.min() ?? "9999-12-31"
      if lhsEarliestAnchor != rhsEarliestAnchor {
        return lhsEarliestAnchor < rhsEarliestAnchor
      }
      if lhs.cleanStartTime != rhs.cleanStartTime {
        return lhs.cleanStartTime < rhs.cleanStartTime
      }
      return lhs.id < rhs.id
    }
  }

  private func weekdaySummary(for selectedDays: SelectedDays) -> String {
    let order = ["1", "2", "3", "4", "5", "6", "0"]
    var calendar = Calendar.current
    calendar.locale = Locale(identifier: Locale.current.identifier)
    let symbols = calendar.shortWeekdaySymbols
    let labels =
      order
      .filter { selectedDays[$0] != nil }
      .compactMap { key -> String? in
        guard let index = Int(key), index >= 0, index < symbols.count else { return nil }
        return symbols[index]
      }
    return labels.joined(separator: ", ")
  }

  private func repeatLabel(for repeatInterval: Int) -> String {
    String(localized: .addShiftEveryNWeeks(repeatInterval + 1))
  }
}

// MARK: - Preview

#Preview {
  SettingsView()
    .environment(AppCoordinator.shared)
}
