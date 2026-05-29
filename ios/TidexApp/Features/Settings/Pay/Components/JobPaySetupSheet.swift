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
  let onSave: (JobPaySetupInput) async -> Bool

  @State private var step: Step = .schedule
  @State private var onboardingData = OnboardingData()
  @State private var payrollDay: Int
  @State private var halfTaxMonth: Int?
  @State private var monthlyGoal: String
  @State private var isSaving = false
  @State private var saveError: String?

  private let payrollDayOptions = [1, 10, 15, 20, 25, 31]

  init(
    job: Job,
    initialCurrency: String,
    onSave: @escaping (JobPaySetupInput) async -> Bool
  ) {
    self.job = job
    self.initialCurrency = initialCurrency
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
    NavigationStack {
      Form {
        Section {
          Picker(String(localized: "settings.pay.add_job.payroll_day"), selection: $payrollDay) {
            ForEach(payrollDayOptions, id: \.self) { day in
              Text(
                day == 31
                  ? String(localized: .onboardingPersonalizePaydayLastDay)
                  : "\(day)"
              )
              .tag(day)
            }
          }

          Picker(String(localized: "settings.pay.add_job.half_tax_month"), selection: $halfTaxMonth)
          {
            Text(String(localized: "settings.pay.add_job.half_tax_off"))
              .tag(Int?.none)
            Text(String(localized: "settings.pay.add_job.half_tax_nov"))
              .tag(Int?.some(11))
            Text(String(localized: "settings.pay.add_job.half_tax_dec"))
              .tag(Int?.some(12))
          }

          TextField(
            String(localized: "settings.pay.add_job.monthly_goal"),
            text: $monthlyGoal
          )
          .keyboardType(.numberPad)
          .onChange(of: monthlyGoal) { _, newValue in
            let filtered = newValue.filter { $0.isNumber }
            if filtered != newValue {
              monthlyGoal = filtered
            }
          }
        } header: {
          Text(String(localized: "settings.pay.setup.scheduleTitle"))
        }

        if let saveError {
          Section {
            Text(saveError)
              .font(.tidexFootnote)
              .foregroundColor(.tidexError)
          }
        }
      }
      .navigationTitle("\(String(localized: "settings.pay.setup.titlePrefix")) \(job.name)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            dismiss()
          }
          .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: .commonContinue)) {
            onboardingData.payrollDay = payrollDay
            step = .wage
          }
          .disabled(isSaving)
        }
      }
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
            Task { await submit() }
          }
        },
        onBack: {
          step = .schedule
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
    Button(String(localized: .commonCancel)) {
      dismiss()
    }
    .padding(.top, Spacing.md)
    .padding(.trailing, Spacing.md)
    .disabled(isSaving)
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
