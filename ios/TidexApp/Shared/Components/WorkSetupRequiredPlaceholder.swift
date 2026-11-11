// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image closure_body_length conditional_returns_on_newline explicit_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_top_level_acl explicit_type_interface file_types_order function_body_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers
import SwiftUI

/// Shown on Home, Schedule, Stats and Add for a user without a job. Friends-only use is a
/// complete way to use Tidex, so this invites the user to add a job instead of blocking them.
struct WorkSetupRequiredPlaceholder<Header: View>: View {
  /// Content above the invitation, such as friends' next shifts on Home.
  private let header: Header

  @Environment(AppCoordinator.self) private var coordinator
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var isRefreshingBeforeSetup = false
  @State private var showAddJobSheet = false
  @State private var jobNeedingSetup: Job?
  @State private var setupInitialCurrency = "kr"
  @State private var setupInitialPayrollDay = 15

  private let jobsRepository = JobsRepository.shared
  private let settingsRepository = SettingsRepository.shared
  private let syncCoordinator = SyncCoordinator.shared
  private let workSetupStatusService = WorkSetupStatusService.shared

  init(@ViewBuilder header: () -> Header) {
    self.header = header()
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: Spacing.lg) {
          header

          VStack(spacing: Spacing.xs) {
            Text(.settingsPaySetupInviteTitle)
              .font(.tidexTitle)
              .foregroundStyle(Color.tidexTextPrimary)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)

            Text(.settingsPaySetupInviteBody)
              .font(.tidexSubheadline)
              .foregroundStyle(Color.tidexTextSecondary)
              .multilineTextAlignment(.center)
              .lineSpacing(2)
              .fixedSize(horizontal: false, vertical: true)
          }

          benefits

          setupButton

          Label(String(localized: .settingsPaySetupInviteFriendsNote), systemImage: "person.2")
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexTextSecondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: AdaptiveMaxWidth.tabContent)
        .padding(.horizontal, Spacing.lg)
        .padding(.top, topPadding(for: geometry.size.height))
        .padding(.bottom, MonthPickerLayout.totalBottomInset + Spacing.xxl)
        .frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)
      .scrollIndicators(.hidden)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .sheet(isPresented: $showAddJobSheet) {
      AddJobSheet(
        initialCurrency: setupInitialCurrency,
        initialPayrollDay: setupInitialPayrollDay,
        prefilledBasicJob: jobNeedingSetup,
        setupDismissTitle: String(localized: .settingsPaySetupLaterButton),
        onSaveBasics: { input in
          await createBasicJobForSetup(input: input)
        }
      ) { input in
        await completeJobSetup(input: input)
      }
    }
  }

  /// What a job adds, one row per tab it fills.
  private var benefits: some View {
    VStack(spacing: Spacing.xs) {
      WorkSetupPreviewRow(icon: "banknote.fill", title: .settingsPaySetupInviteBenefitPay)
      WorkSetupPreviewRow(icon: "calendar", title: .settingsPaySetupInviteBenefitShifts)
      WorkSetupPreviewRow(icon: "chart.bar.xaxis", title: .settingsPaySetupInviteBenefitStats)
    }
    .padding(Spacing.mlg)
    .tidexRowSurface(
      cornerRadius: CornerRadius.card,
      fillColor: .tidexSurfacePrimary
    )
  }

  private var setupButton: some View {
    Button {
      Task {
        await prepareAndOpenSetup()
      }
    } label: {
      HStack(spacing: Spacing.xs) {
        if isRefreshingBeforeSetup {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
            .scaleEffect(0.8)
        }

        Text(.settingsPaySetupInviteCta)
          .font(.tidexButton)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
          .minimumScaleFactor(0.85)
          .multilineTextAlignment(.center)

        Image(systemName: "arrow.right")
          .font(.tidexCaptionStrong)
          .opacity(isRefreshingBeforeSetup ? 0 : 1)
      }
      .foregroundStyle(Color.tidexTextOnBrand)
      .frame(maxWidth: .infinity)
      .frame(minHeight: Spacing.buttonHeight)
      .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? Spacing.xs : 0)
      .background(
        isRefreshingBeforeSetup
          ? Color.tidexBrandPrimary.opacity(0.7)
          : Color.tidexBrandPrimary
      )
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(isRefreshingBeforeSetup)
  }

  private func topPadding(for height: CGFloat) -> CGFloat {
    guard !dynamicTypeSize.isAccessibilitySize else {
      return Spacing.lg
    }

    let availableHeight = max(height - MonthPickerLayout.totalBottomInset, 0)
    return min(max(availableHeight * 0.12, Spacing.xl), 88)
  }

  @MainActor
  private func prepareAndOpenSetup() async {
    guard !isRefreshingBeforeSetup else { return }
    guard let userId = coordinator.getCurrentUserId() else { return }

    isRefreshingBeforeSetup = true
    defer { isRefreshingBeforeSetup = false }

    _ = await syncCoordinator.sync(
      reason: .manualRefresh,
      userId: userId,
      tables: [.jobs, .wageSnapshots],
      updateWidgetStorage: false
    )

    NotificationCenter.default.post(name: .workSetupDataDidChange, object: nil)

    let status = workSetupStatusService.status(for: userId)
    guard !status.isWorkSetupComplete else { return }

    prepareSetupSheet(for: userId, status: status)
    showAddJobSheet = true
  }

  @MainActor
  private func prepareSetupSheet(for userId: String, status: WorkSetupStatus) {
    let settings = settingsRepository.getSettings(for: userId)
    let defaultJob = jobsRepository.getDefaultJob(for: userId)
    let incompleteJob = status.activeSetupJobId.flatMap { jobsRepository.getJob(id: $0) }

    jobNeedingSetup = incompleteJob
    setupInitialCurrency =
      incompleteJob?.currency ?? defaultJob?.currency ?? settings?.currency ?? "kr"
    setupInitialPayrollDay =
      incompleteJob?.payroll_day ?? defaultJob?.payroll_day ?? settings?.effectivePayrollDay ?? 15
  }

  @MainActor
  private func createBasicJobForSetup(input: AddJobBasicsInput) async -> Job? {
    guard let userId = coordinator.getCurrentUserId() else { return nil }

    do {
      let createdJob = try await jobsRepository.createJob(
        userId: userId,
        name: input.name,
        color: input.color,
        currency: input.currency,
        payrollDay: input.payrollDay,
        halfTaxMonth: input.halfTaxMonth,
        monthlyGoal: nil
      )
      jobNeedingSetup = createdJob
      return createdJob
    } catch {
      return nil
    }
  }

  @MainActor
  private func completeJobSetup(input: AddJobSetupInput) async -> Bool {
    guard let userId = coordinator.getCurrentUserId() else { return false }

    do {
      if let existingJobSetup = input.existingJobSetup {
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

        _ = try await jobsRepository.completePaySetup(
          userId: userId,
          jobId: existingJobSetup.id,
          currency: input.currency,
          payrollDay: input.payrollDay,
          halfTaxMonth: input.halfTaxMonth,
          monthlyGoal: jobsRepository.getJob(id: existingJobSetup.id)?.monthly_goal,
          baselineSnapshot: input.baselineSnapshot
        )
      } else {
        _ = try await jobsRepository.createJobWithBaselineSnapshot(
          userId: userId,
          name: input.name,
          color: input.color,
          currency: input.currency,
          payrollDay: input.payrollDay,
          halfTaxMonth: input.halfTaxMonth,
          monthlyGoal: nil,
          baselineSnapshot: input.baselineSnapshot
        )
      }

      jobNeedingSetup = nil
      NotificationCenter.default.post(name: .workSetupDataDidChange, object: nil)
      Haptics.play(.success)
      return true
    } catch {
      return false
    }
  }
}

private struct WorkSetupPreviewRow: View {
  let icon: String
  let title: LocalizedStringResource

  var body: some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: icon)
        .font(.tidexFootnoteStrong)
        .foregroundStyle(Color.tidexBlueText)
        .frame(width: 28, height: 28)
        .background(
          Circle()
            .fill(Color.tidexBlue.opacity(0.1))
        )
        .accessibilityHidden(true)

      Text(title)
        .font(.tidexFootnoteMedium)
        .foregroundStyle(Color.tidexTextPrimary)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: Spacing.sm)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, Spacing.xxs)
  }
}

extension WorkSetupRequiredPlaceholder where Header == EmptyView {
  init() {
    self.init { EmptyView() }
  }
}
