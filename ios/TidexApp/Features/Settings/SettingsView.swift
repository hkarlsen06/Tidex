import SwiftUI
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "SettingsView")

/// Settings main menu view
/// Displays a list of settings options in iOS Settings style
struct SettingsView: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @Environment(\.dismiss) private var dismiss
  @Environment(\.layoutDirection) private var layoutDirection
  private let initialDestination: SettingsDestination?

  /// Whether the current user can access admin settings
  /// Requires both admin role and AAL2 assurance level.
  @State private var canAccessAdminSettings = false
  /// Whether to show the pay job chooser before opening pay settings.
  @State private var showPayJobChooser = false
  /// Whether to show quick add-job sheet from the pay chooser.
  @State private var showPayAddJobSheet = false
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
  /// Half-tax month inherited by newly created basic jobs.
  @State private var payChooserHalfTaxMonth: Int?
  /// Monthly goal inherited by newly created basic jobs.
  @State private var payChooserMonthlyGoal: Int?
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
  /// Job currently being configured with a baseline wage snapshot.
  @State private var paySetupJob: Job?
  /// Follow-up action after a pay setup sheet succeeds.
  @State private var pendingPaySetupAction: PaySetupAction?
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

  private struct PayChooserErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
  }

  /// Settings navigation destinations
  enum SettingsDestination: Hashable {
    case profile
    case security
    case subscription
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

  init(initialDestination: SettingsDestination? = nil) {
    self.initialDestination = initialDestination
  }

  var body: some View {
    NavigationStack(path: $navigationPath) {
      ScrollView {
        // MARK: - Profile Card
        VStack(alignment: .leading, spacing: Spacing.lg) {
          Button {
            navigationPath.append(SettingsDestination.profile)
          } label: {
            HStack(spacing: Spacing.sm) {
              AvatarView(
                url: coordinator.userAvatarUrl,
                initials: userInitials,
                size: AvatarView.Size.large
              )

              Text(coordinator.userDisplayName)
                .font(.tidexTitle)
                .foregroundColor(.tidexTextPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

              Spacer(minLength: Spacing.xs)

              Image(
                systemName: layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right"
              )
              .font(.tidexFootnoteMedium)
              .foregroundStyle(.tertiary)
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 84, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .settingsCardSurface()

          // MARK: - Account
          settingsMenuSection(title: String(localized: .settingsMenuAccountLabel)) {
            SettingsMenuItem(
              icon: "lock.shield",
              title: String(localized: .settingsMenuSecurityLabel)
            ) {
              navigationPath.append(SettingsDestination.security)
            }

            settingsMenuDivider

            SettingsMenuItem(
              icon: "creditcard",
              title: String(localized: .settingsMenuSubscriptionLabel)
            ) {
              navigationPath.append(SettingsDestination.subscription)
            }
          }

          // MARK: - Preferences
          settingsMenuSection(title: String(localized: .settingsGroupPreferences)) {
            SettingsMenuItem(
              icon: "bell",
              title: String(localized: .settingsMenuNotificationsLabel)
            ) {
              navigationPath.append(SettingsDestination.notifications)
            }

            settingsMenuDivider

            SettingsMenuItem(
              icon: "paintpalette",
              title: String(localized: .settingsMenuAppearanceLabel)
            ) {
              navigationPath.append(SettingsDestination.appearance)
            }
          }

          // MARK: - Work
          settingsMenuSection(title: String(localized: .settingsGroupWork)) {
            SettingsMenuItem(
              icon: "banknote",
              title: String(localized: .settingsMenuPayLabel),
              isLoading: isOpeningPaySettings
            ) {
              Task {
                await openPaySettings()
              }
            }

            settingsMenuDivider

            SettingsMenuItem(
              icon: "repeat.circle",
              title: String(localized: .settingsMenuRecurringShiftsLabel)
            ) {
              navigationPath.append(SettingsDestination.recurringShifts)
            }

            settingsMenuDivider

            SettingsMenuItem(
              icon: "calendar.badge.clock",
              title: String(localized: "calendar.subscription.title")
            ) {
              navigationPath.append(SettingsDestination.calendarSync())
            }
          }

          // MARK: - Support & Data
          settingsMenuSection(title: String(localized: .settingsGroupSupportData)) {
            SettingsMenuItem(
              icon: "message",
              title: String(localized: .settingsMenuFeedbackLabel)
            ) {
              navigationPath.append(SettingsDestination.feedback)
            }

            settingsMenuDivider

            SettingsMenuItem(
              icon: "externaldrive",
              title: String(localized: .settingsMenuDataLabel)
            ) {
              navigationPath.append(SettingsDestination.data)
            }
          }

          // MARK: - Admin
          if canAccessAdminSettings {
            settingsMenuSection(title: String(localized: .settingsGroupAdmin)) {
              SettingsMenuItem(
                icon: "shield.lefthalf.filled.badge.checkmark",
                title: String(localized: .settingsMenuAdminLabel)
              ) {
                navigationPath.append(SettingsDestination.admin)
              }
            }
          }

          // MARK: - Debug (DEBUG builds only)
          #if DEBUG
            settingsMenuSection(title: "Debug") {
              SettingsMenuItem(
                icon: "ladybug",
                title: "Debug"
              ) {
                navigationPath.append(SettingsDestination.debug)
              }
            }
          #endif
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.lg)
      }
      .background(Color.tidexBackgroundSecondary)
      .navigationTitle(String(localized: .settingsTitle))
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: .commonDone)) {
            dismiss()
          }
        }
      }
      .navigationDestination(for: SettingsDestination.self) { destination in
        Group {
          switch destination {
          case .profile:
            ProfileSettingsView {
              navigationPath.append(SettingsDestination.security)
            }
          case .security:
            SecuritySettingsView()
          case .subscription:
            SubscriptionSettingsView()
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
    .task {
      await checkAdminStatus()
    }
    .sheet(isPresented: $showPayJobChooser) {
      payJobChooserSheet
    }
    .sheet(isPresented: $showPayAddJobSheet) {
      AddJobSheet(
        initialCurrency: payChooserCurrency,
        initialPayrollDay: payChooserPayrollDay,
        initialHalfTaxMonth: payChooserHalfTaxMonth,
        initialMonthlyGoal: payChooserMonthlyGoal,
        setupDismissTitle: String(localized: "settings.pay.setup.laterButton"),
        onSaveBasics: { input in
          await createBasicPayJobForSetup(input: input)
        }
      ) { input in
        await completeConfiguredPayJob(input: input)
      }
    }
    .sheet(item: $paySetupJob) { job in
      JobPaySetupSheet(
        job: job,
        initialCurrency: job.currency,
        dismissTitle: String(localized: "settings.pay.setup.laterButton")
      ) { input in
        await completePaySetup(for: job, input: input)
      }
    }
    .onAppear {
      applyInitialDestinationIfNeeded()
    }
  }

  @ViewBuilder
  private func settingsMenuSection<Content: View>(
    title: String? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if let title {
        Text(title)
          .font(.tidexFootnoteMedium)
          .foregroundColor(.tidexTextSecondary)
          .textCase(.uppercase)
          .padding(.horizontal, Spacing.sm)
      }

      VStack(spacing: 0) {
        content()
      }
      .settingsCardSurface()
    }
  }

  private var settingsMenuDivider: some View {
    Divider()
      .background(Color.tidexBorderSubtle)
      .padding(
        .leading, SettingsMenuLayout.iconEdgeInset + SettingsMenuLayout.iconBadgeSize + Spacing.sm)
  }

  // MARK: - Actions

  private func applyInitialDestinationIfNeeded() {
    guard !didApplyInitialDestination, let initialDestination else { return }
    didApplyInitialDestination = true

    switch initialDestination {
    case .pay(let jobId):
      if let jobId {
        navigationPath.append(SettingsDestination.pay(jobId: jobId))
      } else {
        Task {
          await openPaySettings()
        }
      }
    default:
      navigationPath.append(initialDestination)
    }
  }

  private func checkAdminStatus() async {
    do {
      let session = try await AuthSessionManager.shared.getSession()
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

  private func openPaySettings() async {
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
      showPayJobChooser = true
    } catch {
      logger.error("Failed to prepare pay settings: \(error.localizedDescription)")
      presentPayChooserError(error)
      showPayJobChooser = true
    }
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
        monthlyGoal: input.monthlyGoal
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
      presentPayChooserError(String(localized: "settings.pay.choose_job.error_not_authenticated"))
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
        monthlyGoal: input.monthlyGoal,
        baselineSnapshot: input.baselineSnapshot
      )

      selectedPayChooserJobId = configuredJob.id
      pendingPaySetupAction = nil
      refreshPayJobLists(for: userId)
      refreshPayChooserDefaults(for: userId)

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        self.navigationPath.append(SettingsDestination.pay(jobId: configuredJob.id))
      }

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

    showPayJobChooser = false
    navigationPath.append(SettingsDestination.pay(jobId: job.id))
  }

  private func openAddPayJob() {
    showPayJobChooser = false
    DispatchQueue.main.async {
      showPayAddJobSheet = true
    }
  }

  private func refreshPayJobLists(for userId: String) {
    payChooserJobs = sortJobs(jobsRepository.getActiveJobs(for: userId))
    payConfiguredJobIds = jobPaySetupStatusService.configuredJobIds(for: userId)

    payArchivedJobs = sortJobs(
      jobsRepository.getAllJobs(for: userId, includeArchived: true, includeDeleted: false)
        .filter { $0.archived_at != nil }
    )

    if let selectedPayChooserJobId,
      payChooserJobs.contains(where: { $0.id == selectedPayChooserJobId }) == false
    {
      self.selectedPayChooserJobId =
        payChooserJobs.first(where: { $0.is_default })?.id
        ?? payChooserJobs.first?.id
      return
    }

    if selectedPayChooserJobId == nil {
      selectedPayChooserJobId =
        payChooserJobs.first(where: { $0.is_default })?.id
        ?? payChooserJobs.first?.id
    }
  }

  private func refreshPayChooserDefaults(for userId: String) {
    let settings = settingsRepository.getSettings(for: userId)
    let defaultJob = jobsRepository.getDefaultJob(for: userId)

    payChooserCurrency = defaultJob?.currency ?? settings?.currency ?? "kr"
    payChooserPayrollDay = defaultJob?.payroll_day ?? settings?.effectivePayrollDay ?? 15
    payChooserHalfTaxMonth = defaultJob?.half_tax_month ?? settings?.half_tax_month
    payChooserMonthlyGoal = defaultJob?.monthly_goal ?? settings?.monthly_goal
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
      presentPayChooserError(String(localized: "settings.pay.choose_job.error_not_authenticated"))
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
      presentPayChooserError(String(localized: "settings.pay.choose_job.error_not_authenticated"))
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

  private func deletePayJob(_ jobId: String) async {
    guard let payChooserUserId else {
      presentPayChooserError(String(localized: "settings.pay.choose_job.error_not_authenticated"))
      return
    }

    clearPayChooserError()
    payJobManagementLoadingJobId = jobId
    defer { payJobManagementLoadingJobId = nil }

    do {
      try await jobsRepository.deleteJob(userId: payChooserUserId, jobId: jobId)
      refreshPayJobLists(for: payChooserUserId)
    } catch {
      presentPayChooserError(error)
    }
  }

  private func setDefaultPayJob(_ jobId: String) async {
    guard let payChooserUserId else {
      presentPayChooserError(String(localized: "settings.pay.choose_job.error_not_authenticated"))
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
    showPayJobChooser = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      self.paySetupJob = job
    }
  }

  private func completePaySetup(for job: Job, input: JobPaySetupInput) async -> Bool {
    let resolvedUserId: String?
    if let payChooserUserId {
      resolvedUserId = payChooserUserId
    } else {
      resolvedUserId = try? await AuthSessionManager.shared.getUserId()
    }

    guard let userId = resolvedUserId else {
      presentPayChooserError(String(localized: "settings.pay.choose_job.error_not_authenticated"))
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
      refreshPayJobLists(for: userId)
      refreshPayChooserDefaults(for: userId)

      switch pendingPaySetupAction {
      case .setDefault:
        try await jobsRepository.setDefaultJob(userId: userId, jobId: configuredJob.id)
        selectedPayChooserJobId = configuredJob.id
        refreshPayJobLists(for: userId)
        pendingPaySetupAction = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
          self.showPayJobChooser = true
        }
      case .openPay, .none:
        selectedPayChooserJobId = configuredJob.id
        pendingPaySetupAction = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
          self.navigationPath.append(SettingsDestination.pay(jobId: configuredJob.id))
        }
      }

      Haptics.play(.success)
      return true
    } catch {
      logger.error("Failed to complete pay setup: \(error.localizedDescription)")
      presentPayChooserError(error)
      return false
    }
  }

  @ViewBuilder
  private var payJobChooserSheet: some View {
    let defaultJob = payChooserJobs.first(where: { $0.is_default })

    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.sm) {
          Button {
            openAddPayJob()
          } label: {
            HStack(spacing: Spacing.sm) {
              Image(systemName: "plus.circle.fill")
                .font(.tidexBodyMedium)
                .foregroundColor(.tidexBlue)

              Text(String(localized: "settings.pay.add_job.cta"))
                .font(.tidexBodyMedium)
                .foregroundColor(.tidexTextPrimary)

              Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
          }
          .buttonStyle(.plain)
          .frame(maxWidth: .infinity)

          if payChooserJobs.isEmpty {
            Text(String(localized: "settings.pay.chooseJob.empty"))
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextSecondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, Spacing.sm)
          } else {
            ForEach(payChooserJobs, id: \.id) { job in
              payChooserWorkplaceRow(job, isDefault: job.id == defaultJob?.id)
            }
          }

          archivedPayJobsSection
            .padding(.top, Spacing.lg)

          if let payChooserError {
            Text(payChooserError)
              .font(.tidexFootnote)
              .foregroundColor(.tidexError)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .padding(.horizontal, Spacing.md)
      .padding(.top, Spacing.sm)
      .padding(.bottom, Spacing.md)
      .background(Color.tidexBackground)
      .navigationTitle(String(localized: "settings.pay.choose_job.title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            showPayJobChooser = false
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
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  @ViewBuilder
  private var archivedPayJobsSection: some View {
    VStack(spacing: Spacing.sm) {
      Button {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
          showArchivedPayJobs.toggle()
        }
      } label: {
        HStack(spacing: Spacing.sm) {
          Image(systemName: "archivebox")
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextMuted)
            .frame(width: 22)

          Text(String(localized: "settings.pay.manage_jobs.archived_title"))
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextSecondary)
            .lineLimit(1)

          Spacer(minLength: Spacing.sm)

          if !payArchivedJobs.isEmpty {
            Text("\(payArchivedJobs.count)")
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)
              .padding(.horizontal, Spacing.xs)
              .padding(.vertical, Spacing.xxxs)
              .background(Color.tidexBackground.opacity(0.9))
              .clipShape(Capsule())
          }

          Image(systemName: showArchivedPayJobs ? "chevron.up" : "chevron.down")
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tidexSurfaceSecondary.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(String(localized: "settings.pay.manage_jobs.archived_title"))

      if showArchivedPayJobs {
        VStack(spacing: Spacing.sm) {
          if payArchivedJobs.isEmpty {
            Text(String(localized: "settings.pay.manage_jobs.archived_empty"))
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, Spacing.md)
              .padding(.vertical, Spacing.sm)
          } else {
            ForEach(payArchivedJobs, id: \.id) { job in
              payChooserArchivedJobRow(job)
            }
          }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }

  @ViewBuilder
  private func payChooserWorkplaceRow(_ job: Job, isDefault: Bool) -> some View {
    HStack(spacing: Spacing.sm) {
      Button {
        openPayForSelectedJob(job)
      } label: {
        HStack(spacing: Spacing.sm) {
          WorkplaceNameText(
            name: job.name,
            colorHex: job.color,
            font: .tidexBodyMedium,
            fallbackBadgeColor: .tidexBlue,
            maxTextWidth: 172,
            badgeCornerRadius: CornerRadius.md,
            badgeHorizontalPadding: Spacing.sm,
            badgeVerticalPadding: Spacing.xs
          )
          .layoutPriority(1)

          Spacer(minLength: Spacing.sm)

          payJobBadges(job, isDefault: isDefault)
            .layoutPriority(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)

      if payJobManagementLoadingJobId == job.id {
        ProgressView()
          .controlSize(.small)
      } else if hasActivePayJobActions(for: job) {
        Menu {
          activePayJobActions(job)
        } label: {
          Image(systemName: "ellipsis.circle")
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextMuted)
        }
      }

      Button {
        openPayForSelectedJob(job)
      } label: {
        Image(systemName: "chevron.right")
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
          .fixedSize()
      }
      .buttonStyle(.plain)
      .accessibilityHidden(true)
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .contextMenu {
      activePayJobActions(job)
    }
  }

  @ViewBuilder
  private func payChooserArchivedJobRow(_ job: Job) -> some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: "archivebox")
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextMuted)
        .frame(width: 18)

      WorkplaceNameText(
        name: job.name,
        colorHex: job.color,
        font: .tidexBodyMedium,
        fallbackBadgeColor: .tidexBlue
      )
      .lineLimit(1)
      .truncationMode(.tail)
      .opacity(0.72)
      .frame(maxWidth: .infinity, alignment: .leading)

      Spacer(minLength: Spacing.sm)

      if payJobManagementLoadingJobId == job.id {
        ProgressView()
          .controlSize(.small)
      } else {
        Button {
          Task {
            await restorePayJob(job.id)
          }
        } label: {
          Image(systemName: "arrow.uturn.backward.circle")
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexBlue)
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "settings.pay.manage_jobs.restore"))
      }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.tidexSurfaceSecondary.opacity(0.44))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .contextMenu {
      archivedPayJobActions(job)
    }
  }

  @ViewBuilder
  private func payJobBadges(_ job: Job, isDefault: Bool) -> some View {
    HStack(spacing: Spacing.xs) {
      if isDefault {
        payJobBadge(
          title: String(localized: "settings.pay.choose_job.default_badge"),
          foregroundColor: .tidexBlue,
          backgroundColor: .tidexBlue.opacity(0.14)
        )
      }

      if !payConfiguredJobIds.contains(job.id) {
        payJobBadge(
          title: String(localized: "settings.pay.setup.requiredBadge"),
          foregroundColor: .tidexWarning,
          backgroundColor: .tidexWarning.opacity(0.14)
        )
      }
    }
    .fixedSize(horizontal: true, vertical: false)
  }

  private func payJobBadge(
    title: String,
    foregroundColor: Color,
    backgroundColor: Color
  ) -> some View {
    Text(title)
      .font(.tidexCaptionStrong)
      .foregroundColor(foregroundColor)
      .lineLimit(1)
      .truncationMode(.tail)
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, Spacing.xsm)
      .padding(.vertical, Spacing.xxs)
      .background(backgroundColor)
      .clipShape(Capsule())
  }

  private func hasActivePayJobActions(for job: Job) -> Bool {
    !job.is_default
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
          String(localized: "settings.pay.choose_job.default_badge"),
          systemImage: "checkmark.circle"
        )
      }
    }

    if payChooserJobs.count > 1 && !job.is_default {
      Button {
        Task {
          await archivePayJob(job.id)
        }
      } label: {
        Label(
          String(localized: "settings.pay.manage_jobs.archive"),
          systemImage: "archivebox"
        )
      }
    }

    if !job.is_default {
      Button(role: .destructive) {
        Task {
          await deletePayJob(job.id)
        }
      } label: {
        Label(
          String(localized: .commonDelete),
          systemImage: "trash"
        )
      }
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
        String(localized: "settings.pay.manage_jobs.restore"),
        systemImage: "arrow.uturn.backward.circle"
      )
    }

    Button(role: .destructive) {
      Task {
        await deletePayJob(job.id)
      }
    } label: {
      Label(
        String(localized: .commonDelete),
        systemImage: "trash"
      )
    }
  }
}

// MARK: - Recurring Shifts Settings

private struct RecurringShiftsSettingsView: View {
  @State private var recurringShifts: [RecurringShiftRow] = []
  @State private var recurringShiftToEdit: RecurringShiftRow?
  @State private var isLoading = true
  @State private var errorMessage: String?

  private let impactHaptic = UIImpactFeedbackGenerator(style: .light)

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.mlg) {
        headerSection

        if let errorMessage {
          errorBanner(errorMessage)
        }

        if isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Spacing.lg)
        } else if recurringShifts.isEmpty {
          emptyState
        } else {
          VStack(spacing: Spacing.xsm) {
            ForEach(recurringShifts, id: \.id) { recurring in
              recurringShiftRow(recurring)
            }
          }
        }
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.lg)
    }
    .background(Color.tidexBackground)
    .navigationTitle(String(localized: .settingsRecurringShiftsTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
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
  }

  private var headerSection: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      Text(.settingsRecurringShiftsTitle)
        .font(.title2)
        .fontWeight(.bold)
        .foregroundColor(.tidexTextPrimary)

      Text(.settingsRecurringShiftsSubtitle)
        .font(.subheadline)
        .foregroundColor(.tidexTextSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var emptyState: some View {
    VStack(spacing: Spacing.xs) {
      Text(.settingsRecurringShiftsEmptyTitle)
        .font(.tidexButton)
        .foregroundColor(.tidexTextPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Text(.settingsRecurringShiftsEmptyDescription)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.lg)
    .tidexCardShadow(cornerRadius: CornerRadius.lg)
  }

  private func recurringShiftRow(_ recurring: RecurringShiftRow) -> some View {
    let exclusionCount = recurring.effectiveExclusions.count

    return Button {
      impactHaptic.impactOccurred()
      recurringShiftToEdit = recurring
    } label: {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(verbatim: "\(recurring.cleanStartTime) - \(recurring.cleanEndTime)")
          .font(.tidexButton)
          .foregroundColor(.tidexTextPrimary)

        HStack(spacing: Spacing.xxxs) {
          Text(weekdaySummary(for: recurring.selected_days))
          Text("•")
          Text(repeatLabel(for: recurring.repeat_interval_weeks))
          if exclusionCount > 0 {
            Text("•")
            Text(String(localized: .settingsRecurringShiftsExcludedCount(exclusionCount)))
          }
        }
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.md)
      .background(Color.tidexSurfacePrimary)
      .cornerRadius(CornerRadius.lg)
      .tidexCardShadow(cornerRadius: CornerRadius.lg)
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func errorBanner(_ message: String) -> some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.tidexSubheadline)
        .foregroundColor(.tidexError)
      Text(message)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexError)
      Spacer()
    }
    .padding(Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.lg)
        .fill(Color.tidexError.opacity(0.1))
    )
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
    if repeatInterval == 0 {
      return String(localized: .addShiftEveryWeek)
    }
    return String(localized: .addShiftEveryNWeeks(repeatInterval + 1))
  }
}

// MARK: - Settings Menu Item

private enum SettingsMenuLayout {
  static let rowHeight: CGFloat = 52
  static let iconBadgeSize: CGFloat = 38
  static var iconEdgeInset: CGFloat { (rowHeight - iconBadgeSize) / 2 }
}

/// A single settings menu item with colored icon background, title, and chevron
/// Designed for use inside a List section (iOS Settings style)
struct SettingsMenuItem: View {
  let icon: String
  let title: String
  var isLoading: Bool = false
  let action: () -> Void

  @Environment(\.layoutDirection) private var layoutDirection

  var body: some View {
    Button(action: action) {
      HStack(spacing: Spacing.sm) {
        SettingsRowIcon(
          systemName: icon,
          foregroundColor: .tidexTextSecondary,
          backgroundColor: .tidexSurfaceSecondary,
          borderColor: .tidexBorderSubtle
        )

        Text(title)
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(1)

        Spacer()

        if isLoading {
          ProgressView()
            .controlSize(.small)
            .tint(.tidexBlue)
        } else {
          Image(systemName: layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right")
            .font(.tidexFootnoteMedium)
            .foregroundStyle(.tertiary)
        }
      }
      .frame(minHeight: SettingsMenuLayout.rowHeight)
      .padding(.leading, SettingsMenuLayout.iconEdgeInset)
      .padding(.trailing, Spacing.md)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isLoading)
  }
}

private struct SettingsCardSurfaceModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(Color.tidexSurfacePrimary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      .tidexCardShadow(cornerRadius: CornerRadius.lg)
  }
}

extension View {
  fileprivate func settingsCardSurface() -> some View {
    modifier(SettingsCardSurfaceModifier())
  }
}

private struct SettingsRowIcon: View {
  let systemName: String
  var foregroundColor: Color = .tidexTextPrimary
  var backgroundColor: Color = .tidexSurfaceSecondary
  var borderColor: Color = .tidexBorder
  private let glyphBoxSize: CGFloat = 18

  var body: some View {
    Image(systemName: systemName)
      .resizable()
      .scaledToFit()
      .foregroundColor(foregroundColor)
      .frame(width: glyphBoxSize, height: glyphBoxSize)
      .frame(width: SettingsMenuLayout.iconBadgeSize, height: SettingsMenuLayout.iconBadgeSize)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
          .fill(backgroundColor)
      )
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
          .stroke(borderColor, lineWidth: 1)
      )
      .accessibilityHidden(true)
  }
}

// MARK: - Preview

#Preview {
  SettingsView()
    .environmentObject(AppCoordinator.shared)
}
