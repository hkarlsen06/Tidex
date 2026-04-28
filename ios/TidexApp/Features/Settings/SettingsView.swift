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
  /// Whether sign out is in progress
  @State private var isSigningOut = false
  /// Whether global sign out is in progress
  @State private var isSigningOutGlobal = false
  /// Whether to show the global sign out confirmation alert
  @State private var showSignOutEverywhereAlert = false
  /// Whether to show the pay job chooser before opening pay settings.
  @State private var showPayJobChooser = false
  /// Whether to show quick add-job sheet from the pay chooser.
  @State private var showPayAddJobSheet = false
  /// Whether to show job management from pay chooser.
  @State private var showPayJobManagement = false
  /// Active jobs used in pay chooser.
  @State private var payChooserJobs: [Job] = []
  /// Archived jobs for optional display in job management.
  @State private var payArchivedJobs: [Job] = []
  /// Currency used to initialize job wage setup flow.
  @State private var payChooserCurrency: String = "kr"
  /// User ID for the current pay chooser session.
  @State private var payChooserUserId: String?
  /// Selected job in the pay chooser (confirmed explicitly before navigation).
  @State private var selectedPayChooserJobId: String?
  /// Toggles archived jobs visibility in the management sheet.
  @State private var showArchivedPayJobs = false
  /// Error shown when preparing pay chooser/add fails.
  @State private var payChooserError: String?
  /// Error shown when managing jobs from the pay chooser.
  @State private var payJobManagementError: String?
  /// Job currently processing a workplace management action.
  @State private var payJobManagementLoadingJobId: String?
  /// Guards against duplicate pay-entry taps while loading job state.
  @State private var isOpeningPaySettings = false
  /// Navigation path for settings subviews
  @State private var navigationPath = NavigationPath()
  @State private var didApplyInitialDestination = false

  private let jobsRepository = JobsRepository.shared
  private let settingsRepository = SettingsRepository.shared

  /// Settings navigation destinations
  enum SettingsDestination: Hashable {
    case profile
    case security
    case subscription
    case notifications
    case appearance
    case pay(jobId: String?)
    case recurringShifts
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
              title: String(localized: .settingsMenuPayLabel)
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

          // MARK: - Sign Out
          settingsMenuSection {
            signOutRow
            settingsMenuDivider
            signOutEverywhereRow
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
            ProfileSettingsView()
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
        existingJobNeedingSetup: payChooserJobs.count == 1 ? payChooserJobs.first : nil
      ) { input in
        await createPayJobAndOpen(input: input)
      }
    }
    .alert(
      String(localized: .userMenuLogoutEverywhereConfirmTitle),
      isPresented: $showSignOutEverywhereAlert
    ) {
      Button(String(localized: .userMenuLogoutEverywhereConfirmCancel), role: .cancel) {}
      Button(String(localized: .userMenuLogoutEverywhereConfirmAction), role: .destructive) {
        Task {
          await signOutGlobal()
        }
      }
    } message: {
      Text(.userMenuLogoutEverywhereConfirmDescription)
    }
    .onAppear {
      guard !didApplyInitialDestination, let initialDestination else { return }
      navigationPath.append(initialDestination)
      didApplyInitialDestination = true
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
      .padding(.leading, 38 + Spacing.sm)
  }

  // MARK: - Sign Out Rows

  /// Sign out from this device only (local scope)
  private var signOutRow: some View {
    Button {
      Task {
        await signOut()
      }
    } label: {
      HStack(spacing: Spacing.sm) {
        SettingsRowIcon(
          systemName: "rectangle.portrait.and.arrow.right",
          foregroundColor: .tidexError,
          backgroundColor: .tidexError.opacity(0.12),
          borderColor: .tidexError.opacity(0.18)
        )

        if isSigningOut {
          ProgressView()
            .tint(.tidexError)
          Text(String(localized: .userMenuLoggingOut))
            .foregroundColor(.tidexError)
        } else {
          Text(String(localized: .userMenuLogout))
            .foregroundColor(.tidexError)
        }

        Spacer()
      }
      .padding(.horizontal, Spacing.md)
    }
    .disabled(isSigningOut || isSigningOutGlobal)
  }

  /// Sign out from ALL devices (global scope)
  private var signOutEverywhereRow: some View {
    Button {
      showSignOutEverywhereAlert = true
    } label: {
      HStack(spacing: Spacing.sm) {
        SettingsRowIcon(
          systemName: "rectangle.portrait.and.arrow.right.fill",
          foregroundColor: .tidexTextSecondary,
          backgroundColor: .tidexSurfaceSecondary,
          borderColor: .tidexBorderSubtle
        )

        if isSigningOutGlobal {
          ProgressView()
            .tint(.tidexTextSecondary)
          Text(String(localized: .userMenuLogoutEverywhereLoading))
            .foregroundColor(.tidexTextSecondary)
        } else {
          Text(String(localized: .userMenuLogoutEverywhere))
            .foregroundColor(.tidexTextSecondary)
        }

        Spacer()
      }
      .padding(.horizontal, Spacing.md)
    }
    .disabled(isSigningOut || isSigningOutGlobal)
  }

  // MARK: - Actions

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

  private func signOut() async {
    isSigningOut = true
    await coordinator.signOut()
    dismiss()
    isSigningOut = false
  }

  private func signOutGlobal() async {
    isSigningOutGlobal = true
    await coordinator.signOutGlobal()
    dismiss()
    isSigningOutGlobal = false
  }

  private func openPaySettings() async {
    guard !isOpeningPaySettings else { return }
    isOpeningPaySettings = true
    defer { isOpeningPaySettings = false }

    do {
      let userId = try await AuthSessionManager.shared.getUserId()
      payChooserUserId = userId
      refreshPayJobLists(for: userId)
      payChooserCurrency = settingsRepository.getSettings(for: userId)?.currency ?? "kr"
      payChooserError = nil
      payJobManagementError = nil
      showArchivedPayJobs = false

      if payChooserJobs.count > 1 || !payArchivedJobs.isEmpty {
        showPayJobChooser = true
      } else {
        navigationPath.append(SettingsDestination.pay(jobId: payChooserJobs.first?.id))
      }
    } catch {
      logger.error("Failed to prepare pay settings: \(error.localizedDescription)")
      payChooserError = error.localizedDescription
      showPayJobChooser = true
    }
  }

  private func createPayJobAndOpen(input: AddJobSetupInput) async -> Bool {
    do {
      let userId = try await AuthSessionManager.shared.getUserId()

      if let existingJobSetup = input.existingJobSetup {
        guard
          try await jobsRepository.updateJob(
            userId: userId,
            jobId: existingJobSetup.id,
            name: existingJobSetup.name,
            color: existingJobSetup.color
          ) != nil
        else {
          payChooserError = String(localized: .settingsPayErrorLoadFailed)
          return false
        }
      }

      let createdJob = try await jobsRepository.createJobWithBaselineSnapshot(
        userId: userId,
        name: input.name,
        color: input.color,
        currency: input.currency,
        payrollDay: input.payrollDay,
        halfTaxMonth: input.halfTaxMonth,
        monthlyGoal: input.monthlyGoal,
        baselineSnapshot: input.baselineSnapshot
      )

      refreshPayJobLists(for: userId)

      showPayJobChooser = false
      showPayJobManagement = false
      navigationPath.append(SettingsDestination.pay(jobId: createdJob.id))
      return true
    } catch {
      logger.error("Failed to create pay job from chooser: \(error.localizedDescription)")
      payChooserError = error.localizedDescription
      return false
    }
  }

  private func openPayForSelectedJob(_ jobId: String) {
    selectedPayChooserJobId = jobId
    showPayJobChooser = false
    navigationPath.append(SettingsDestination.pay(jobId: jobId))
  }

  private func openAddPayJob() {
    showPayJobManagement = false
    showPayJobChooser = false
    DispatchQueue.main.async {
      showPayAddJobSheet = true
    }
  }

  private func refreshPayJobLists(for userId: String) {
    payChooserJobs = sortJobs(jobsRepository.getActiveJobs(for: userId))

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

  private func sortJobs(_ jobs: [Job]) -> [Job] {
    jobs.sorted { lhs, rhs in
      if lhs.sort_order == rhs.sort_order {
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
      return lhs.sort_order < rhs.sort_order
    }
  }

  private func archivePayJob(_ jobId: String) async {
    guard let payChooserUserId else {
      payJobManagementError = String(localized: "settings.pay.choose_job.error_not_authenticated")
      return
    }

    payJobManagementError = nil
    payJobManagementLoadingJobId = jobId
    defer { payJobManagementLoadingJobId = nil }

    do {
      try await jobsRepository.archiveJob(userId: payChooserUserId, jobId: jobId)
      refreshPayJobLists(for: payChooserUserId)
    } catch {
      payJobManagementError = error.localizedDescription
    }
  }

  private func restorePayJob(_ jobId: String) async {
    guard let payChooserUserId else {
      payJobManagementError = String(localized: "settings.pay.choose_job.error_not_authenticated")
      return
    }

    payJobManagementError = nil
    payJobManagementLoadingJobId = jobId
    defer { payJobManagementLoadingJobId = nil }

    do {
      try await jobsRepository.restoreJob(userId: payChooserUserId, jobId: jobId)
      refreshPayJobLists(for: payChooserUserId)
    } catch {
      payJobManagementError = error.localizedDescription
    }
  }

  private func deletePayJob(_ jobId: String) async {
    guard let payChooserUserId else {
      payJobManagementError = String(localized: "settings.pay.choose_job.error_not_authenticated")
      return
    }

    payJobManagementError = nil
    payJobManagementLoadingJobId = jobId
    defer { payJobManagementLoadingJobId = nil }

    do {
      try await jobsRepository.deleteJob(userId: payChooserUserId, jobId: jobId)
      refreshPayJobLists(for: payChooserUserId)
    } catch {
      payJobManagementError = error.localizedDescription
    }
  }

  private func setDefaultPayJob(_ jobId: String) async {
    guard let payChooserUserId else {
      payJobManagementError = String(localized: "settings.pay.choose_job.error_not_authenticated")
      return
    }

    payJobManagementError = nil
    payJobManagementLoadingJobId = jobId
    defer { payJobManagementLoadingJobId = nil }

    do {
      try await jobsRepository.setDefaultJob(userId: payChooserUserId, jobId: jobId)
      selectedPayChooserJobId = jobId
      refreshPayJobLists(for: payChooserUserId)
    } catch {
      payJobManagementError = error.localizedDescription
    }
  }

  @ViewBuilder
  private var payJobChooserSheet: some View {
    let defaultJob = payChooserJobs.first(where: { $0.is_default })
    let nonDefaultJobs = payChooserJobs.filter { !$0.is_default }

    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.sm) {
          Button {
            showPayJobManagement = true
          } label: {
            HStack(spacing: Spacing.sm) {
              Image(systemName: "slider.horizontal.3")
                .font(.tidexBodyMedium)
                .foregroundColor(.tidexBlue)

              Text(String(localized: "settings.pay.manage_jobs.title"))
                .font(.tidexBodyMedium)
                .foregroundColor(.tidexTextPrimary)

              Spacer()

              Image(systemName: "chevron.right")
                .font(.tidexCaptionRegular)
                .foregroundColor(.tidexTextMuted)
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

          ForEach(nonDefaultJobs, id: \.id) { job in
            payChooserWorkplaceRow(job, isDefault: false)
          }

          if let defaultJob {
            payChooserWorkplaceRow(defaultJob, isDefault: true)
          }

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
      .navigationTitle(String(localized: "settings.pay.choose_workplace.title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            showPayJobChooser = false
          }
        }
      }
    }
    .presentationDetents([.height(payJobChooserDetentHeight)])
    .presentationDragIndicator(.visible)
    .sheet(isPresented: $showPayJobManagement) {
      payJobManagementSheet
    }
  }

  @ViewBuilder
  private func payChooserWorkplaceRow(_ job: Job, isDefault: Bool) -> some View {
    Button {
      openPayForSelectedJob(job.id)
    } label: {
      HStack(spacing: Spacing.sm) {
        WorkplaceNameText(
          name: job.name,
          colorHex: job.color,
          font: .tidexBodyMedium,
          fallbackBadgeColor: .tidexBlue
        )

        Spacer()

        if isDefault {
          Text(String(localized: "settings.pay.choose_job.default_badge"))
            .font(.tidexFootnote)
            .foregroundColor(.tidexBlue)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxxs)
            .background(Color.tidexBlue.opacity(0.12))
            .clipShape(Capsule())
        }

        Image(systemName: "chevron.right")
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
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
  }

  @ViewBuilder
  private var payJobManagementSheet: some View {
    NavigationStack {
      List {
        Section {
          ForEach(payChooserJobs, id: \.id) { job in
            HStack(spacing: Spacing.sm) {
              WorkplaceNameText(
                name: job.name,
                colorHex: job.color,
                fallbackBadgeColor: .tidexBlue
              )

              Spacer()

              if job.is_default {
                Label(
                  String(localized: "settings.pay.choose_job.default_badge"),
                  systemImage: "checkmark.circle.fill"
                )
                .font(.tidexFootnote)
                .foregroundColor(.tidexBlue)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxxs)
                .background(Color.tidexBlue.opacity(0.12))
                .clipShape(Capsule())
              }

              if payJobManagementLoadingJobId == job.id {
                ProgressView()
                  .controlSize(.small)
              } else {
                if !job.is_default {
                  Menu {
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

                    if payChooserJobs.count > 1 {
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
                  } label: {
                    Image(systemName: "ellipsis.circle")
                      .font(.tidexBodyMedium)
                      .foregroundColor(.tidexTextMuted)
                  }
                }
              }
            }
          }
        } header: {
          Text(String(localized: "settings.pay.manage_jobs.active_title"))
        } footer: {
          Text(String(localized: "settings.pay.manage_jobs.active_footer"))
        }

        Section {
          Button(
            showArchivedPayJobs
              ? String(localized: "settings.pay.manage_jobs.hide_archived")
              : String(localized: "settings.pay.manage_jobs.show_archived")
          ) {
            showArchivedPayJobs.toggle()
          }
        }

        if showArchivedPayJobs {
          if payArchivedJobs.isEmpty {
            Section {
              HStack(spacing: Spacing.xs) {
                Image(systemName: "archivebox")
                  .font(.tidexFootnote)
                  .foregroundColor(.tidexTextMuted)
                Text(String(localized: "settings.pay.manage_jobs.archived_empty"))
                  .font(.tidexFootnote)
                  .foregroundColor(.tidexTextSecondary)
              }
            } header: {
              Text(String(localized: "settings.pay.manage_jobs.archived_title"))
            }
          } else {
            Section(String(localized: "settings.pay.manage_jobs.archived_title")) {
              ForEach(payArchivedJobs, id: \.id) { job in
                HStack(spacing: Spacing.sm) {
                  WorkplaceNameText(
                    name: job.name,
                    colorHex: job.color,
                    fallbackBadgeColor: .tidexBlue
                  )

                  Spacer()

                  if payJobManagementLoadingJobId == job.id {
                    ProgressView()
                      .controlSize(.small)
                  } else {
                    Menu {
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
                    } label: {
                      Image(systemName: "ellipsis.circle")
                        .font(.tidexBodyMedium)
                        .foregroundColor(.tidexTextMuted)
                    }
                  }
                }
              }
            }
          }
        }

        if let payJobManagementError {
          Section {
            Text(payJobManagementError)
              .font(.tidexFootnote)
              .foregroundColor(.tidexError)
          }
        }
      }
      .navigationTitle(String(localized: "settings.pay.manage_jobs.title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(String(localized: .commonCancel)) {
            showPayJobManagement = false
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private var payJobChooserDetentHeight: CGFloat {
    let visibleRows = max(3, min(payChooserJobs.count + 2, 7))
    let errorHeight = payChooserError == nil ? 0 : 32
    return CGFloat(visibleRows) * 70 + 120 + CGFloat(errorHeight)
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
      let session = try await AuthSessionManager.shared.getSession()
      let shifts = RecurringShiftsRepository.shared.getRecurringShifts(
        for: session.normalizedUserId)
      recurringShifts = sortRecurringShifts(shifts)
    } catch {
      logger.error("Failed to load recurring shifts settings: \(error.localizedDescription)")
      errorMessage = String(localized: .settingsRecurringShiftsLoadFailed)
    }

    isLoading = false
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
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)
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
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)
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

/// A single settings menu item with colored icon background, title, and chevron
/// Designed for use inside a List section (iOS Settings style)
struct SettingsMenuItem: View {
  let icon: String
  let title: String
  let action: () -> Void

  @Environment(\.layoutDirection) private var layoutDirection
  private let rowHeight: CGFloat = 52

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

        // Chevron
        Image(systemName: layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right")
          .font(.tidexFootnoteMedium)
          .foregroundStyle(.tertiary)
      }
      .frame(minHeight: rowHeight)
      .padding(.horizontal, Spacing.md)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
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
  private let badgeSize: CGFloat = 38
  private let glyphBoxSize: CGFloat = 18

  var body: some View {
    Image(systemName: systemName)
      .resizable()
      .scaledToFit()
      .foregroundColor(foregroundColor)
      .frame(width: glyphBoxSize, height: glyphBoxSize)
      .frame(width: badgeSize, height: badgeSize)
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
