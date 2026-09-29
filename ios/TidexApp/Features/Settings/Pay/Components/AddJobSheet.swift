import SwiftUI
import UIKit

struct AddJobSetupInput {
  let existingJobSetup: ExistingJobSetupInput?
  let name: String
  let color: String?
  let currency: String
  let payrollDay: Int
  let halfTaxMonth: Int?
  let baselineSnapshot: JobBaselineSnapshotInput
}

struct ExistingJobSetupInput {
  let id: String
  let name: String
  let color: String?
}

struct AddJobSheet: View {
  private enum Step {
    case jobDetails
    case wage
    case supplements
    case deductions
    case existingJobSetup
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let initialCurrency: String
  let prefilledBasicJob: Job?
  let existingJobNeedingSetup: Job?
  let setupDismissTitle: String
  let onSaveBasics: ((AddJobBasicsInput) async -> Job?)?
  let onSave: (AddJobSetupInput) async -> Bool

  @State private var step: Step = .jobDetails
  @State private var onboardingData = OnboardingData()
  @State private var savedBasicJob: Job?

  @State private var name = ""
  @State private var selectedColor = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
  @State private var existingJobName = ""
  @State private var existingJobColor = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
  @State private var payrollDay: Int
  @State private var showingPaydayInput = false
  @State private var paydayInputText = ""
  @FocusState private var isPaydayInputFocused: Bool
  @State private var isSaving = false
  @State private var validationError: String?
  @State private var showSaveError = false

  init(
    initialCurrency: String,
    initialPayrollDay: Int = 15,
    prefilledBasicJob: Job? = nil,
    existingJobNeedingSetup: Job? = nil,
    setupDismissTitle: String = String(localized: .commonCancel),
    onSaveBasics: ((AddJobBasicsInput) async -> Job?)? = nil,
    onSave: @escaping (AddJobSetupInput) async -> Bool
  ) {
    self.initialCurrency = initialCurrency
    self.prefilledBasicJob = prefilledBasicJob
    self.existingJobNeedingSetup = existingJobNeedingSetup
    self.setupDismissTitle = setupDismissTitle
    self.onSaveBasics = onSaveBasics
    self.onSave = onSave
    _savedBasicJob = State(initialValue: prefilledBasicJob)
    _name = State(initialValue: prefilledBasicJob?.name ?? "")
    _payrollDay = State(initialValue: prefilledBasicJob?.payroll_day ?? initialPayrollDay)
  }

  var body: some View {
    ZStack {
      switch step {
      case .jobDetails:
        jobDetailsStep

      case .wage:
        wageStep

      case .supplements:
        supplementsStep

      case .deductions:
        SettingsAccordionScreen(
          data: onboardingData,
          onContinue: proceedFromDeductions,
          onBack: { step = onboardingData.wageType == .custom ? .supplements : .wage },
          showsPayday: false,
          continueTitle: String(localized: shouldSetupExistingJob ? .commonContinue : .commonSave)
        )
        .overlay(alignment: .topTrailing) { dismissButton }

      case .existingJobSetup:
        existingJobSetupStep
      }

      if isSaving {
        AddJobSavingOverlay()
      }
    }
    .onAppear {
      onboardingData.currency =
        prefilledBasicJob?.currency ?? existingJobNeedingSetup?.currency
        ?? initialCurrency
      onboardingData.payrollDay = payrollDay
      if let color = prefilledBasicJob?.color {
        selectedColor = colorFromHex(color)
      }
      if let existingJobNeedingSetup {
        existingJobName = existingJobNeedingSetup.name
        if let color = existingJobNeedingSetup.color {
          existingJobColor = colorFromHex(color)
        }
      }
    }
    .alert(String(localized: .commonError), isPresented: $showSaveError) {
      Button(String(localized: .commonOk), role: .cancel) {}
    } message: {
      Text(.settingsPayErrorSaveFailed)
    }
    .interactiveDismissDisabled(isSaving)
    // Steps replace each other in place, so tell VoiceOver the screen changed.
    .onChange(of: step) { _, _ in
      AccessibilityNotification.ScreenChanged().post()
    }
  }

}

extension AddJobSheet {
  private var jobDetailsStep: some View {
    AddJobStepPage(
      icon: "building.2",
      title: .settingsPayAddJobTitle,
      continueTitle: String(localized: .commonContinue),
      isContinueEnabled: !isSaving && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      validationError: validationError,
      onContinue: { Task { await goToWageSetup() } }
    ) {
      HStack {
        Button(String(localized: .commonCancel)) {
          dismiss()
        }
        .font(.tidexBody)
        .foregroundColor(.tidexBlueText)
        .disabled(isSaving)
        Spacer()
      }
    } cards: {
      jobNameCard
      colorCard
      payDetailsCard
    }
  }

  private var shouldSetupExistingJob: Bool {
    existingJobNeedingSetup != nil
  }

  private var existingJobSetupCard: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.settingsPayAddJobCurrentWorkplaceTitle)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(.settingsPayAddJobName)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        TextField(
          "",
          text: $existingJobName,
          prompt: Text(.settingsPayAddJobName)
        )
        .accessibilityLabel(Text(.settingsPayAddJobName))
        .textInputAutocapitalization(.words)
        .foregroundColor(.tidexTextPrimary)
      }

      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(.settingsPayAddJobColorLabel)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        colorSelectionRow(selectedColor: $existingJobColor)
      }
    }
    .addJobCardChrome()
  }

  private var jobNameCard: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayAddJobName)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      TextField("", text: $name, prompt: Text(.settingsPayAddJobName))
        .accessibilityLabel(Text(.settingsPayAddJobName))
        .textInputAutocapitalization(.words)
        .foregroundColor(.tidexTextPrimary)
    }
    .addJobCardChrome()
  }

  private var colorCard: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayAddJobColorLabel)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      colorSelectionRow(selectedColor: $selectedColor)
    }
    .addJobCardChrome()
  }

  private var payDetailsCard: some View {
    AddJobPayDetailsCard(
      payrollDay: $payrollDay,
      showingPaydayInput: $showingPaydayInput,
      paydayInputText: $paydayInputText,
      isPaydayInputFocused: $isPaydayInputFocused,
      onApplyPaydayInput: applyPaydayInput
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
      onBack: wageBackAction,
      topTrailingTitle: dismissTitle,
      onTopTrailingAction: {
        dismiss()
      }
    )
  }

  private var wageBackAction: (() -> Void)? {
    guard savedBasicJob == nil else { return nil }
    return {
      step = .jobDetails
    }
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

  private var existingJobSetupStep: some View {
    AddJobStepPage(
      icon: "pencil.and.list.clipboard",
      title: .settingsPayAddJobOneLastThingTitle,
      continueTitle: String(localized: .commonSave),
      isContinueEnabled: !isSaving,
      validationError: validationError,
      onContinue: { Task { await submit() } }
    ) {
      HStack {
        Button {
          backFromExistingJobSetup()
        } label: {
          HStack(spacing: Spacing.xxxs) {
            Image(systemName: "chevron.left")
              .font(.tidexSubheadline)
            Text(.commonBack)
          }
          .font(.tidexBody)
          .foregroundColor(.tidexBlueText)
        }
        .disabled(isSaving)

        Spacer()

        Button(String(localized: .commonCancel)) {
          dismiss()
        }
        .font(.tidexBody)
        .foregroundColor(.tidexBlueText)
        .disabled(isSaving)
      }
    } cards: {
      existingJobSetupCard
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
    .frame(minHeight: 44)
    .background(Color.tidexSurfacePrimary, in: Capsule())
    .overlay(
      Capsule()
        .stroke(Color.tidexBorder, lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 3)
    .padding(.top, Spacing.md)
    .padding(.trailing, Spacing.lg)
    .disabled(isSaving)
  }

  private var dismissTitle: String {
    savedBasicJob == nil ? String(localized: .commonCancel) : setupDismissTitle
  }

  private func goToWageSetup() async {
    validationError = nil

    if showingPaydayInput {
      applyPaydayInput()
    }

    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      validationError = String(localized: .settingsPayAddJobErrorName)
      return
    }

    onboardingData.payrollDay = payrollDay
    guard savedBasicJob == nil, !shouldSetupExistingJob, let onSaveBasics else {
      step = .wage
      return
    }

    isSaving = true
    let createdJob = await onSaveBasics(
      AddJobBasicsInput(
        name: trimmedName,
        color: normalizedHex(from: selectedColor),
        currency: resolvedCurrency,
        payrollDay: payrollDay,
        halfTaxMonth: nil
      ))
    isSaving = false

    guard let createdJob else {
      showSaveError = true
      return
    }

    savedBasicJob = createdJob
    step = .wage
  }

  private func proceedFromDeductions() {
    if shouldSetupExistingJob {
      step = .existingJobSetup
      return
    }
    Task { await submit() }
  }

  private func backFromExistingJobSetup() {
    step = .deductions
  }

  private func applyPaydayInput() {
    if let parsed = Int(paydayInputText) {
      payrollDay = min(max(parsed, 1), 31)
    }
    showingPaydayInput = false
    isPaydayInputFocused = false
  }

  /// Checks the job names on both pages. When one is empty, this shows that page with an
  /// error and returns nil.
  private func validatedSetup() -> (name: String, existingJobSetup: ExistingJobSetupInput?)? {
    var existingJobSetupInput: ExistingJobSetupInput?
    if let savedBasicJob {
      existingJobSetupInput = ExistingJobSetupInput(
        id: savedBasicJob.id,
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        color: normalizedHex(from: selectedColor)
      )
    } else if let existingJobNeedingSetup {
      let trimmedExistingName = existingJobName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedExistingName.isEmpty else {
        step = .existingJobSetup
        validationError = String(localized: .settingsPayAddJobErrorCurrentName)
        return nil
      }
      existingJobSetupInput = ExistingJobSetupInput(
        id: existingJobNeedingSetup.id,
        name: trimmedExistingName,
        color: normalizedHex(from: existingJobColor)
      )
    }

    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      step = .jobDetails
      validationError = String(localized: .settingsPayAddJobErrorName)
      return nil
    }
    return (trimmedName, existingJobSetupInput)
  }

  private func submit() async {
    guard !isSaving else { return }
    validationError = nil
    guard let setup = validatedSetup() else { return }

    isSaving = true
    let didSave = await onSave(
      AddJobSetupInput(
        existingJobSetup: setup.existingJobSetup,
        name: setup.name,
        color: normalizedHex(from: selectedColor),
        currency: resolvedCurrency,
        payrollDay: payrollDay,
        halfTaxMonth: nil,
        baselineSnapshot: onboardingData.baselineSnapshotInput
      )
    )
    isSaving = false

    if didSave {
      dismiss()
    } else {
      showSaveError = true
    }
  }

  private var resolvedCurrency: String {
    if !onboardingData.currency.isEmpty {
      return onboardingData.currency
    }
    if !initialCurrency.isEmpty {
      return initialCurrency
    }
    return "kr"
  }
}  // swiftlint:disable:this file_length
