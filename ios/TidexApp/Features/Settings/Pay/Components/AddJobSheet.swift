import SwiftUI
import UIKit

struct AddJobSetupInput {
  let existingJobSetup: ExistingJobSetupInput?
  let name: String
  let color: String?
  let currency: String
  let payrollDay: Int
  let halfTaxMonth: Int?
  let monthlyGoal: Int?
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
    case existingJobSetup
  }

  @Environment(\.dismiss) private var dismiss

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
  @State private var monthlyGoal: String

  @State private var isSaving = false
  @State private var validationError: String?
  @State private var showSaveError = false

  private let payrollDayOptions = [1, 10, 15, 20, 25, 31]
  init(
    initialCurrency: String,
    initialPayrollDay: Int = 15,
    initialMonthlyGoal: Int? = nil,
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
    _monthlyGoal = State(
      initialValue: (prefilledBasicJob?.monthly_goal ?? initialMonthlyGoal).map(String.init) ?? "")
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
      case .existingJobSetup:
        existingJobSetupStep
      }

      if isSaving {
        savingOverlay
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
  }

  private var jobDetailsStep: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        ScrollView {
          VStack(spacing: 0) {
            HStack {
              Button(String(localized: .commonCancel)) {
                dismiss()
              }
              .font(.tidexBody)
              .foregroundColor(.tidexBlue)
              .disabled(isSaving)
              Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .adaptiveContentWidth()

            Spacer()
              .frame(height: 24)

            VStack(spacing: Spacing.xxxs) {
              Image(systemName: "building.2")
                .font(.tidexSubheadline)
                .foregroundColor(.tidexBlue)
              Text(.settingsPayAddJobTitle)
                .font(.tidexScreenTitle)
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)
            .adaptiveContentWidth()

            Spacer()
              .frame(height: 28)

            VStack(spacing: Spacing.sm) {
              jobNameCard
              colorCard
              payDetailsCard
            }
            .padding(.horizontal, Spacing.lg)
            .adaptiveContentWidth()

            if let validationError {
              Text(validationError)
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
            isEnabled: !isSaving && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            action: {
              Task { await goToWageSetup() }
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
    .padding(Spacing.md)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .stroke(Color.tidexBorder, lineWidth: 1)
    )
  }

  private var jobNameCard: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayAddJobName)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      TextField("", text: $name, prompt: Text(.settingsPayAddJobName))
        .textInputAutocapitalization(.words)
        .foregroundColor(.tidexTextPrimary)
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .stroke(Color.tidexBorder, lineWidth: 1)
    )
  }

  private var colorCard: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayAddJobColorLabel)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      colorSelectionRow(selectedColor: $selectedColor)
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .stroke(Color.tidexBorder, lineWidth: 1)
    )
  }

  private func colorSelectionRow(selectedColor: Binding<Color>) -> some View {
    WorkplaceColorCarousel(selectedHex: normalizedHex(from: selectedColor.wrappedValue)) { hex in
      selectedColor.wrappedValue = colorFromHex(hex)
    }
  }

  private var payDetailsCard: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        Text(.settingsPayAddJobPayrollDay)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        ZStack(alignment: .trailing) {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
              ForEach(payrollDayOptions, id: \.self) { day in
                AddJobPaydayButton(
                  day: day,
                  isLast: day == 31,
                  isSelected: payrollDay == day && !showingPaydayInput,
                  action: {
                    showingPaydayInput = false
                    payrollDay = day
                  }
                )
              }

              if showingPaydayInput {
                TextField("", text: $paydayInputText)
                  .font(.tidexButton)
                  .foregroundColor(.tidexBlue)
                  .keyboardType(.numberPad)
                  .multilineTextAlignment(.center)
                  .focused($isPaydayInputFocused)
                  .frame(width: 44)
                  .frame(minHeight: 44)
                  .background(Color.tidexBlue.opacity(0.15))
                  .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                  .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                      .stroke(Color.tidexBlue, lineWidth: 1)
                  )
                  .onChange(of: isPaydayInputFocused) { _, focused in
                    if !focused {
                      applyPaydayInput()
                    }
                  }
                  .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                      Spacer()
                      Button(String(localized: .commonDone)) {
                        applyPaydayInput()
                      }
                      .fontWeight(.semibold)
                    }
                  }
              } else {
                Button(action: {
                  UIImpactFeedbackGenerator(style: .light).impactOccurred()
                  paydayInputText = !payrollDayOptions.contains(payrollDay) ? "\(payrollDay)" : ""
                  showingPaydayInput = true
                  DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPaydayInputFocused = true
                  }
                }) {
                  HStack(spacing: Spacing.xxs) {
                    Image(systemName: "pencil")
                      .font(.tidexCaptionRegular)
                    Text(.onboardingSettingsPaydayOther)
                  }
                  .font(!payrollDayOptions.contains(payrollDay) ? .tidexLabelStrong : .tidexLabel)
                  .foregroundColor(
                    !payrollDayOptions.contains(payrollDay) ? .white : .tidexTextSecondary
                  )
                  .frame(minWidth: 56, minHeight: 44)
                  .padding(.horizontal, Spacing.xs)
                  .background(
                    !payrollDayOptions.contains(payrollDay)
                      ? Color.tidexBrandPrimary : Color.tidexSurfacePrimary.opacity(0.76)
                  )
                  .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
              }
            }
            .padding(.horizontal, Spacing.micro)
            .padding(.vertical, Spacing.xxs)
            .padding(.trailing, Spacing.lg)
          }

          LinearGradient(
            colors: [Color.tidexSurfaceSecondary.opacity(0), Color.tidexSurfaceSecondary],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: 32)
          .allowsHitTesting(false)
        }

        if !payrollDayOptions.contains(payrollDay) && !showingPaydayInput {
          Text(String(localized: .onboardingSettingsPaydayCustomValue(payrollDay)))
            .font(.tidexFootnote)
            .foregroundColor(.tidexBlue)
        }
      }

    }
    .padding(Spacing.md)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .stroke(Color.tidexBorder, lineWidth: 1)
    )
  }

  private var wageStep: some View {
    WageScreen(
      data: onboardingData,
      onContinue: {
        if onboardingData.wageType == .custom {
          step = .supplements
        } else {
          proceedFromWageConfiguration()
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
          proceedFromWageConfiguration()
        },
        onBack: {
          step = .wage
        }
      )

      dismissButton
    }
  }

  private var existingJobSetupStep: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        ScrollView {
          VStack(spacing: 0) {
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
                .foregroundColor(.tidexBlue)
              }
              .disabled(isSaving)

              Spacer()

              Button(String(localized: .commonCancel)) {
                dismiss()
              }
              .font(.tidexBody)
              .foregroundColor(.tidexBlue)
              .disabled(isSaving)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .adaptiveContentWidth()

            Spacer()
              .frame(height: 24)

            VStack(spacing: Spacing.xxxs) {
              Image(systemName: "pencil.and.list.clipboard")
                .font(.tidexSubheadline)
                .foregroundColor(.tidexBlue)
              Text(.settingsPayAddJobOneLastThingTitle)
                .font(.tidexScreenTitle)
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)
            .adaptiveContentWidth()

            Spacer()
              .frame(height: 28)

            VStack(spacing: Spacing.sm) {
              existingJobSetupCard
            }
            .padding(.horizontal, Spacing.lg)
            .adaptiveContentWidth()

            if let validationError {
              Text(validationError)
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
            title: String(localized: .commonSave),
            isEnabled: !isSaving,
            action: {
              Task { await submit() }
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

  private var dismissButton: some View {
    Button(dismissTitle) {
      dismiss()
    }
    .font(.tidexBodyMedium)
    .foregroundColor(.tidexBlue)
    .lineLimit(1)
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xs)
    .background(.thinMaterial, in: Capsule())
    .overlay(
      Capsule()
        .stroke(Color.tidexBorder.opacity(0.75), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 3)
    .padding(.top, Spacing.md)
    .padding(.trailing, Spacing.lg)
    .disabled(isSaving)
  }

  private var dismissTitle: String {
    savedBasicJob == nil ? String(localized: .commonCancel) : setupDismissTitle
  }

  private var savingOverlay: some View {
    ZStack {
      Color.black.opacity(0.35)
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
        halfTaxMonth: nil,
        monthlyGoal: monthlyGoalValue
      ))
    isSaving = false

    guard let createdJob else {
      showSaveError = true
      return
    }

    savedBasicJob = createdJob
    step = .wage
  }

  private func proceedFromWageConfiguration() {
    if shouldSetupExistingJob {
      step = .existingJobSetup
      return
    }
    Task { await submit() }
  }

  private func backFromExistingJobSetup() {
    step = onboardingData.wageType == .custom ? .supplements : .wage
  }

  private func applyPaydayInput() {
    if let parsed = Int(paydayInputText) {
      payrollDay = min(max(parsed, 1), 31)
    }
    showingPaydayInput = false
    isPaydayInputFocused = false
  }

  private func submit() async {
    validationError = nil

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
        return
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
      return
    }

    let monthlyGoalValue: Int?
    monthlyGoalValue = self.monthlyGoalValue

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

    isSaving = true
    let didSave = await onSave(
      AddJobSetupInput(
        existingJobSetup: existingJobSetupInput,
        name: trimmedName,
        color: normalizedHex(from: selectedColor),
        currency: resolvedCurrency,
        payrollDay: payrollDay,
        halfTaxMonth: nil,
        monthlyGoal: monthlyGoalValue,
        baselineSnapshot: snapshotInput
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

  private var monthlyGoalValue: Int? {
    guard !monthlyGoal.isEmpty else { return nil }
    return Int(monthlyGoal)
  }

  private func normalizedHex(from color: Color) -> String? {
    let uiColor = UIColor(color)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return nil
    }

    return String(
      format: "#%02X%02X%02X",
      Int(red * 255),
      Int(green * 255),
      Int(blue * 255)
    )
  }

  private func colorFromHex(_ hex: String) -> Color {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") {
      value.removeFirst()
    }
    guard value.count == 6, let intValue = Int(value, radix: 16) else {
      return Color.tidexBlue
    }

    let red = Double((intValue >> 16) & 0xFF) / 255.0
    let green = Double((intValue >> 8) & 0xFF) / 255.0
    let blue = Double(intValue & 0xFF) / 255.0
    return Color(red: red, green: green, blue: blue)
  }
}

private struct AddJobPaydayButton: View {
  let day: Int
  let isLast: Bool
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      action()
    }) {
      Text(isLast ? String(localized: .onboardingPersonalizePaydayLastDay) : "\(day)")
        .font(isSelected ? .tidexButton : .tidexBodyMedium)
        .foregroundColor(isSelected ? .white : .tidexTextSecondary)
        .frame(minWidth: 56, minHeight: 44)
        .background(isSelected ? Color.tidexBrandPrimary : Color.tidexSurfacePrimary.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}
