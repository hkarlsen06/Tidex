import SwiftUI

struct JobPaySetupInput {
  let currency: String
  let payrollDay: Int
  let halfTaxMonth: Int?
  let baselineSnapshot: JobBaselineSnapshotInput
}

struct JobPaySetupSheet: View {
  private enum Step {
    case schedule
    case wage
    case supplements
    case deductions
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let job: Job
  let initialCurrency: String
  let dismissTitle: String
  let onSave: (JobPaySetupInput) async -> Bool

  @State private var step: Step = .schedule
  @State private var onboardingData = OnboardingData()
  @State private var payrollDay: Int
  @State private var halfTaxMonth: Int?
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

      case .deductions:
        SettingsAccordionScreen(
          data: onboardingData,
          onContinue: { Task { await submit() } },
          onBack: { step = onboardingData.wageType == .custom ? .supplements : .wage },
          showsPayday: false,
          continueTitle: String(localized: .commonSave)
        )
        .overlay(alignment: .topTrailing) { dismissButton }
      }

      if isSaving {
        savingOverlay
      }
    }
    .onAppear {
      onboardingData.currency = initialCurrency
      onboardingData.payrollDay = payrollDay
    }
    .interactiveDismissDisabled(isSaving)
    // Steps replace each other in place, so tell VoiceOver the screen changed.
    .onChange(of: step) { _, _ in
      AccessibilityNotification.ScreenChanged().post()
    }
    .alert(
      String(localized: .commonError),
      isPresented: Binding(
        get: { saveError != nil }, set: { if !$0 { saveError = nil } }
      )
    ) {
      Button(String(localized: .commonOk)) { saveError = nil }
    } message: {
      Text(saveError ?? "")
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
          step = .deductions
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
          step = .deductions
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
    .foregroundColor(.tidexBlueText)
    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xs)
    .frame(minWidth: 44, minHeight: 44)
    .background(Color.tidexSurfacePrimary, in: Capsule())
    .overlay(
      Capsule()
        .stroke(Color.tidexBorder, lineWidth: 1)
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
        Text(.commonLoading)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextPrimary)
      }
      .padding(Spacing.md)
      .background(Color.tidexSurfacePrimary.opacity(0.9))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
    }
    // Keeps VoiceOver on the saving message instead of the controls behind it.
    .accessibilityAddTraits(.isModal)
  }

  private func submit() async {
    guard !isSaving else { return }
    isSaving = true
    saveError = nil

    let snapshotInput = onboardingData.baselineSnapshotInput

    let didSave = await onSave(
      JobPaySetupInput(
        currency: onboardingData.currency.isEmpty ? initialCurrency : onboardingData.currency,
        payrollDay: payrollDay,
        halfTaxMonth: halfTaxMonth,
        baselineSnapshot: snapshotInput
      ))
    isSaving = false

    if didSave {
      dismiss()
    } else {
      saveError = String(localized: .settingsPayErrorSaveFailed)
    }
  }
}

private struct JobPayScheduleSetupScreen: View {
  let job: Job
  @Binding var currency: String
  @Binding var payrollDay: Int
  @Binding var halfTaxMonth: Int?
  let dismissTitle: String
  let isSaving: Bool
  let saveError: String?
  let onCancel: () -> Void
  let onContinue: () -> Void

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        ScrollView {
          VStack(spacing: 0) {
            cancelRow

            Spacer()
              .frame(height: 24)

            titleBlock

            Spacer()
              .frame(height: 28)

            payrollSettingsCard

            if let saveError {
              Text(saveError)
                .font(.tidexFootnote)
                .foregroundColor(.tidexError)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .adaptiveContentWidth()
                .announcesToVoiceOver(saveError)
            }

            Spacer()
              .frame(height: 120)
          }
        }
        .scrollDismissesKeyboard(.interactively)

        continueBar
      }
    }
  }

  private var cancelRow: some View {
    HStack {
      Button(dismissTitle) {
        onCancel()
      }
      .font(.tidexBody)
      .foregroundColor(.tidexBlueText)
      .frame(minWidth: 44, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
      .disabled(isSaving)

      Spacer()
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.top, Spacing.md)
    .adaptiveContentWidth()
  }

  private var titleBlock: some View {
    VStack(spacing: Spacing.sm) {
      Image(systemName: "calendar.badge.clock")
        .font(.tidexSubheadline)
        .foregroundColor(.tidexBlueText)
        .accessibilityHidden(true)

      Text(.settingsPaySetupScheduleTitle)
        .font(.tidexScreenTitle)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)

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
  }

  private var payrollSettingsCard: some View {
    GlobalPaySettingsCard(
      jobId: job.id,
      currency: currency,
      payrollDay: payrollDay,
      halfTaxMonth: halfTaxMonth,
      canChangeCurrency: true,
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
  }

  private var continueBar: some View {
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
          Haptics.play(.success)
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
