import SwiftUI
import UIKit

struct AddJobSetupInput {
  let existingJobSetup: ExistingJobSetupInput?
  let name: String
  let color: String?
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
  let existingJobNeedingSetup: Job?
  let onSave: (AddJobSetupInput) async -> Bool

  @State private var step: Step = .jobDetails
  @State private var onboardingData = OnboardingData()

  @State private var name = ""
  @State private var selectedColor = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
  @State private var existingJobName = ""
  @State private var existingJobColor = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
  @State private var payrollDay = 15
  @State private var halfTaxMonth: Int?
  @State private var monthlyGoal = "20000"

  @State private var isSaving = false
  @State private var validationError: String?
  @State private var showSaveError = false

  init(
    initialCurrency: String,
    existingJobNeedingSetup: Job? = nil,
    onSave: @escaping (AddJobSetupInput) async -> Bool
  ) {
    self.initialCurrency = initialCurrency
    self.existingJobNeedingSetup = existingJobNeedingSetup
    self.onSave = onSave
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
      onboardingData.currency = initialCurrency
      onboardingData.payrollDay = payrollDay
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
      Text(String(localized: .settingsPayErrorSaveFailed))
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
              Text(String(localized: "settings.pay.add_job.title"))
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
              goToWageSetup()
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
      Text(String(localized: "settings.pay.add_job.current_workplace_title"))
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(String(localized: "settings.pay.add_job.name"))
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        TextField(
          "",
          text: $existingJobName,
          prompt: Text(String(localized: "settings.pay.add_job.name"))
        )
        .textInputAutocapitalization(.words)
        .foregroundColor(.tidexTextPrimary)
      }

      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(String(localized: "settings.pay.add_job.color_label"))
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
      Text(String(localized: "settings.pay.add_job.name"))
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      TextField("", text: $name, prompt: Text(String(localized: "settings.pay.add_job.name")))
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
      Text(String(localized: "settings.pay.add_job.color_label"))
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
    VStack(spacing: 0) {
      payDetailsRow(
        title: String(localized: "settings.pay.add_job.payroll_day"),
        value: "\(payrollDay)",
        options: (1...31).map { day in
          (label: "\(day)", action: { payrollDay = day })
        }
      )

      Divider()
        .background(Color.tidexBorder)

      payDetailsRow(
        title: String(localized: "settings.pay.add_job.half_tax_month"),
        value: halfTaxLabel,
        options: [
          (
            label: String(localized: "settings.pay.add_job.half_tax_off"),
            action: { halfTaxMonth = nil }
          ),
          (
            label: String(localized: "settings.pay.add_job.half_tax_nov"),
            action: { halfTaxMonth = 11 }
          ),
          (
            label: String(localized: "settings.pay.add_job.half_tax_dec"),
            action: { halfTaxMonth = 12 }
          ),
        ]
      )

      Divider()
        .background(Color.tidexBorder)

      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(String(localized: "settings.pay.add_job.monthly_goal"))
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        TextField("", text: $monthlyGoal)
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)
          .keyboardType(.numberPad)
          .onChange(of: monthlyGoal) { _, newValue in
            let filtered = newValue.filter { $0.isNumber }
            if filtered != newValue {
              monthlyGoal = filtered
            }
          }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, Spacing.sm)
    }
    .padding(.horizontal, Spacing.md)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .stroke(Color.tidexBorder, lineWidth: 1)
    )
  }

  private func payDetailsRow(
    title: String,
    value: String,
    options: [(label: String, action: () -> Void)]
  ) -> some View {
    HStack {
      Text(title)
        .font(.tidexBody)
        .foregroundColor(.tidexTextPrimary)

      Spacer()

      Menu {
        ForEach(Array(options.enumerated()), id: \.offset) { item in
          Button(item.element.label) {
            item.element.action()
          }
        }
      } label: {
        HStack(spacing: Spacing.xxxs) {
          Text(value)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexBlue)
          Image(systemName: "chevron.up.chevron.down")
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexBlue)
        }
      }
    }
    .padding(.vertical, Spacing.sm)
  }

  private var halfTaxLabel: String {
    switch halfTaxMonth {
    case 11:
      return String(localized: "settings.pay.add_job.half_tax_nov")
    case 12:
      return String(localized: "settings.pay.add_job.half_tax_dec")
    default:
      return String(localized: "settings.pay.add_job.half_tax_off")
    }
  }

  private var wageStep: some View {
    ZStack(alignment: .topTrailing) {
      WageScreen(
        data: onboardingData,
        onContinue: {
          if onboardingData.wageType == .custom {
            step = .supplements
          } else {
            proceedFromWageConfiguration()
          }
        },
        onBack: {
          step = .jobDetails
        }
      )

      dismissButton
    }
  }

  private var supplementsStep: some View {
    ZStack(alignment: .topTrailing) {
      SupplementsScreen(
        data: onboardingData,
        onContinue: {
          proceedFromWageConfiguration()
        },
        onSkip: {
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
              Text(String(localized: "settings.pay.add_job.one_last_thing_title"))
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
    Button(String(localized: .commonCancel)) {
      dismiss()
    }
    .padding(.top, Spacing.md)
    .padding(.trailing, Spacing.md)
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

  private func goToWageSetup() {
    validationError = nil

    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      validationError = String(localized: "settings.pay.add_job.error_name")
      return
    }

    onboardingData.payrollDay = payrollDay
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

  private func submit() async {
    validationError = nil

    var existingJobSetupInput: ExistingJobSetupInput?
    if let existingJobNeedingSetup {
      let trimmedExistingName = existingJobName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedExistingName.isEmpty else {
        step = .existingJobSetup
        validationError = String(localized: "settings.pay.add_job.error_current_name")
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
      validationError = String(localized: "settings.pay.add_job.error_name")
      return
    }

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

    isSaving = true
    let didSave = await onSave(
      AddJobSetupInput(
        existingJobSetup: existingJobSetupInput,
        name: trimmedName,
        color: normalizedHex(from: selectedColor),
        payrollDay: payrollDay,
        halfTaxMonth: halfTaxMonth,
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
