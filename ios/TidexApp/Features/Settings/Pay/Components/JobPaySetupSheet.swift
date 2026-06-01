import SwiftUI

struct JobPaySetupInput {
  let currency: String
  let payrollDay: Int
  let halfTaxMonth: Int?
  let monthlyGoal: Int?
  let baselineSnapshot: JobBaselineSnapshotInput
}

struct JobPaySetupSheet: View {
  private enum Step {
    case schedule
    case wage
    case supplements
  }

  @Environment(\.dismiss) private var dismiss

  let job: Job
  let initialCurrency: String
  let dismissTitle: String
  let onSave: (JobPaySetupInput) async -> Bool

  @State private var step: Step = .schedule
  @State private var onboardingData = OnboardingData()
  @State private var payrollDay: Int
  @State private var halfTaxMonth: Int?
  @State private var monthlyGoal: String
  @State private var isSaving = false
  @State private var saveError: String?

  init(
    job: Job,
    initialCurrency: String,
    dismissTitle: String = String(localized: .commonCancel),
    onSave: @escaping (JobPaySetupInput) async -> Bool
  ) {
    self.job = job
    self.initialCurrency = initialCurrency
    self.dismissTitle = dismissTitle
    self.onSave = onSave
    _payrollDay = State(initialValue: job.payroll_day ?? 15)
    _halfTaxMonth = State(initialValue: job.half_tax_month)
    _monthlyGoal = State(initialValue: job.monthly_goal.map(String.init) ?? "")
  }

  var body: some View {
    ZStack {
      switch step {
      case .schedule:
        scheduleStep
      case .wage:
        wageStep
      case .supplements:
        supplementsStep
      }

      if isSaving {
        savingOverlay
      }
    }
    .onAppear {
      onboardingData.currency = initialCurrency
      onboardingData.payrollDay = payrollDay
    }
  }

  private var scheduleStep: some View {
    JobPayScheduleSetupScreen(
      job: job,
      currency: Binding(
        get: { onboardingData.currency.isEmpty ? initialCurrency : onboardingData.currency },
        set: { onboardingData.currency = $0 }
      ),
      payrollDay: $payrollDay,
      halfTaxMonth: $halfTaxMonth,
      monthlyGoalText: $monthlyGoal,
      dismissTitle: dismissTitle,
      isSaving: isSaving,
      saveError: saveError,
      onCancel: {
        dismiss()
      },
      onContinue: {
        onboardingData.payrollDay = payrollDay
        step = .wage
      }
    )
  }

  private var wageStep: some View {
    WageScreen(
      data: onboardingData,
      onContinue: {
        if onboardingData.wageType == .custom {
          step = .supplements
        } else {
          Task { await submit() }
        }
      },
      onBack: {
        step = .schedule
      },
      topTrailingTitle: dismissTitle,
      onTopTrailingAction: {
        dismiss()
      }
    )
  }

  private var supplementsStep: some View {
    ZStack(alignment: .topTrailing) {
      SupplementsScreen(
        data: onboardingData,
        onContinue: {
          Task { await submit() }
        },
        onSkip: {
          Task { await submit() }
        },
        onBack: {
          step = .wage
        }
      )

      dismissButton
    }
  }

  private var dismissButton: some View {
    Button(dismissTitle) {
      dismiss()
    }
    .font(.tidexBodyMedium)
    .foregroundColor(.tidexBlue)
    .lineLimit(1)
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xs)
    .frame(minWidth: 44, minHeight: 44)
    .background(.thinMaterial, in: Capsule())
    .overlay(
      Capsule()
        .stroke(Color.tidexBorder.opacity(0.75), lineWidth: 1)
    )
    .contentShape(Capsule())
    .shadow(color: .tidexDarkBackgroundColor.opacity(0.16), radius: 8, x: 0, y: 3)
    .padding(.top, Spacing.md)
    .padding(.trailing, Spacing.lg)
    .disabled(isSaving)
  }

  private var savingOverlay: some View {
    ZStack {
      Color.tidexDarkBackgroundColor.opacity(0.35)
        .ignoresSafeArea()

      VStack(spacing: Spacing.sm) {
        ProgressView()
          .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
        Text(.commonLoading)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextOnBrand)
      }
      .padding(Spacing.md)
      .background(Color.tidexSurfacePrimary.opacity(0.9))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
    }
  }

  private func submit() async {
    isSaving = true
    saveError = nil

    let monthlyGoalValue: Int?
    if monthlyGoal.isEmpty {
      monthlyGoalValue = nil
    } else {
      monthlyGoalValue = Int(monthlyGoal)
    }

    let snapshotInput = JobBaselineSnapshotInput(
      hourlyWage: onboardingData.resolvedHourlyWage,
      wageLevel: onboardingData.resolvedWageLevel,
      tariffTypeId: onboardingData.resolvedTariffTypeId,
      supplements: onboardingData.resolvedSupplements,
      taxEnabled: onboardingData.taxEnabled,
      taxPercentage: onboardingData.taxEnabled ? onboardingData.taxPercentage : nil,
      breakEnabled: onboardingData.breakEnabled,
      breakMethod: "proportional",
      breakThresholdHours: 5.5,
      breakDeductionMinutes: 30
    )

    let didSave = await onSave(
      JobPaySetupInput(
        currency: onboardingData.currency.isEmpty ? initialCurrency : onboardingData.currency,
        payrollDay: payrollDay,
        halfTaxMonth: halfTaxMonth,
        monthlyGoal: monthlyGoalValue,
        baselineSnapshot: snapshotInput
      ))
    isSaving = false

    if didSave {
      dismiss()
    } else {
      saveError = String(localized: .settingsPayErrorSaveFailed)
      step = .schedule
    }
  }
}

private struct JobPayScheduleSetupScreen: View {
  let job: Job
  @Binding var currency: String
  @Binding var payrollDay: Int
  @Binding var halfTaxMonth: Int?
  @Binding var monthlyGoalText: String
  let dismissTitle: String
  let isSaving: Bool
  let saveError: String?
  let onCancel: () -> Void
  let onContinue: () -> Void

  private var monthlyGoalValue: Int? {
    guard !monthlyGoalText.isEmpty else { return nil }
    return Int(monthlyGoalText)
  }

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        ScrollView {
          VStack(spacing: 0) {
            HStack {
              Button(dismissTitle) {
                onCancel()
              }
              .font(.tidexBody)
              .foregroundColor(.tidexBlue)
              .lineLimit(1)
              .frame(minWidth: 44, minHeight: 44, alignment: .leading)
              .contentShape(Rectangle())
              .disabled(isSaving)

              Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .adaptiveContentWidth()

            Spacer()
              .frame(height: 24)

            VStack(spacing: Spacing.sm) {
              Image(systemName: "calendar.badge.clock")
                .font(.tidexSubheadline)
                .foregroundColor(.tidexBlue)

              Text(.settingsPaySetupScheduleTitle)
                .font(.tidexScreenTitle)
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)

              WorkplaceNameText(
                name: job.name,
                colorHex: job.color,
                font: .tidexFootnote,
                fallbackBadgeColor: .tidexBlue,
                lineLimit: 2,
                maxTextWidth: .infinity,
                maxTextAlignment: .center,
                multilineTextAlignment: .center
              )
            }
            .padding(.horizontal, Spacing.xl)
            .adaptiveContentWidth()

            Spacer()
              .frame(height: 28)

            GlobalPaySettingsCard(
              jobId: job.id,
              currency: currency,
              monthlyGoal: monthlyGoalValue,
              payrollDay: payrollDay,
              halfTaxMonth: halfTaxMonth,
              canChangeCurrency: true,
              onUpdateMonthlyGoal: { value in
                monthlyGoalText = value.map(String.init) ?? ""
              },
              onUpdatePayrollDay: { value in
                payrollDay = value
              },
              onUpdateHalfTaxMonth: { value in
                await MainActor.run {
                  halfTaxMonth = value
                }
              },
              onUpdateCurrency: { value in
                await MainActor.run {
                  currency = value
                }
              }
            )
            .padding(.horizontal, Spacing.lg)
            .adaptiveContentWidth()

            if let saveError {
              Text(saveError)
                .font(.tidexFootnote)
                .foregroundColor(.tidexError)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .adaptiveContentWidth()
            }

            Spacer()
              .frame(height: 120)
          }
        }
        .scrollDismissesKeyboard(.interactively)

        VStack(spacing: 0) {
          LinearGradient(
            colors: [Color.tidexBackground.opacity(0), Color.tidexBackground],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: 24)

          OnboardingButton(
            title: String(localized: .commonContinue),
            isEnabled: !isSaving,
            action: {
              UINotificationFeedbackGenerator().notificationOccurred(.success)
              onContinue()
            }
          )
          .padding(.horizontal, Spacing.lg)
          .padding(.bottom, Spacing.xl)
          .adaptiveContentWidth()
          .background(Color.tidexBackground)
        }
      }
    }
  }
}
