import SwiftUI

struct WorkSetupRequiredPlaceholder: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var isRefreshingBeforeSetup = false
  @State private var showAddJobSheet = false
  @State private var jobNeedingSetup: Job?
  @State private var setupInitialCurrency = "kr"
  @State private var setupInitialPayrollDay = 15
  @State private var setupInitialMonthlyGoal: Int?

  private let jobsRepository = JobsRepository.shared
  private let settingsRepository = SettingsRepository.shared
  private let syncCoordinator = SyncCoordinator.shared
  private let workSetupStatusService = WorkSetupStatusService.shared

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: Spacing.lg) {
          setupPreview

          VStack(spacing: Spacing.xs) {
            Text("settings.pay.setup.scheduleTitle", tableName: "Localizable")
              .font(.tidexTitle)
              .foregroundColor(.tidexTextPrimary)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)

            Text("work_setup.required.description", tableName: "Localizable")
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextSecondary)
              .multilineTextAlignment(.center)
              .lineSpacing(2)
              .fixedSize(horizontal: false, vertical: true)
          }

          setupButton
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
        initialMonthlyGoal: setupInitialMonthlyGoal,
        prefilledBasicJob: jobNeedingSetup,
        setupDismissTitle: String(localized: "settings.pay.setup.laterButton"),
        onSaveBasics: { input in
          await createBasicJobForSetup(input: input)
        }
      ) { input in
        await completeJobSetup(input: input)
      }
    }
  }

  private var setupPreview: some View {
    VStack(spacing: Spacing.md) {
      HStack(spacing: Spacing.md) {
        ZStack {
          RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
            .fill(Color.tidexBlue.opacity(0.12))

          Image(systemName: "building.2")
            .font(.system(size: 24, weight: .semibold))
            .foregroundColor(.tidexBlue)
        }
        .frame(width: 52, height: 52)

        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text("settings.pay.setup.requiredBadge", tableName: "Localizable")
            .font(.tidexCaptionStrong)
            .foregroundColor(.tidexBlue)
            .lineLimit(1)
            .minimumScaleFactor(0.85)

          Text("settings.pay.setup.finishTitle", tableName: "Localizable")
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }

        Spacer(minLength: Spacing.sm)
      }

      Rectangle()
        .fill(Color.tidexBorderSubtle.opacity(0.35))
        .frame(height: 1)

      VStack(spacing: Spacing.xs) {
        WorkSetupPreviewRow(
          icon: "banknote.fill",
          title: LocalizedStringResource("settings.pay.editor.wageSource", table: "Localizable")
        )
        WorkSetupPreviewRow(
          icon: "calendar",
          title: LocalizedStringResource("tabs.shifts", table: "Localizable")
        )
        WorkSetupPreviewRow(
          icon: "chart.bar.xaxis",
          title: LocalizedStringResource("tabs.stats", table: "Localizable")
        )
      }
    }
    .padding(Spacing.mlg)
    .tidexRowSurface(
      cornerRadius: CornerRadius.card,
      fillColor: .tidexSurfacePrimary,
      shadowLevel: .card
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

        Text("work_setup.required.cta", tableName: "Localizable")
          .font(.tidexButton)
          .lineLimit(1)
          .minimumScaleFactor(0.85)

        Image(systemName: "arrow.right")
          .font(.tidexCaptionStrong)
          .opacity(isRefreshingBeforeSetup ? 0 : 1)
      }
      .foregroundColor(.tidexTextOnBrand)
      .frame(maxWidth: .infinity)
      .frame(height: Spacing.buttonHeight)
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

    coordinator.objectWillChange.send()
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
    setupInitialMonthlyGoal =
      incompleteJob?.monthly_goal ?? defaultJob?.monthly_goal
      ?? settings?.monthly_goal
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
        monthlyGoal: input.monthlyGoal
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
          monthlyGoal: input.monthlyGoal,
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
          monthlyGoal: input.monthlyGoal,
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
        .foregroundColor(.tidexBlue)
        .frame(width: 28, height: 28)
        .background(
          Circle()
            .fill(Color.tidexBlue.opacity(0.1))
        )

      Text(title)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexTextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)

      Spacer(minLength: Spacing.sm)

      Image(systemName: "lock.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.tidexTextMuted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, Spacing.xxs)
  }
}
