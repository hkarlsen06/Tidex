import SwiftUI

// MARK: - Global Pay Settings Card

/// Card for editing a job's pay settings: currency, pay period, payroll day, and half-tax month
struct GlobalPaySettingsCard: View {
  let jobId: String?
  let currency: String
  let payrollDay: Int
  let halfTaxMonth: Int?
  let canChangeCurrency: Bool
  let onUpdatePayrollDay: (Int) -> Void
  let onUpdateHalfTaxMonth: (Int?) async -> Void
  let onUpdateCurrency: (String) async -> Void
  var payPeriod: PayPeriod = .calendarMonth
  /// Shows the pay period picker when set.
  var onUpdatePayPeriod: ((PayPeriod) async -> Void)?

  @State private var selectedCurrency: String = "kr"
  @State private var selectedPayrollDay: Int = 1
  @State private var selectedHalfTaxMonth: Int?
  @State private var initializedJobId: String?
  @State private var showingCurrencyPicker = false

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.mlg) {
      // Section header
      Text(.settingsPayGlobalTitle)
        .font(.tidexButton)
        .foregroundColor(.tidexTextPrimary)

      // Currency selector
      currencyInput

      if let onUpdatePayPeriod {
        PayPeriodSettingsSection(
          jobId: jobId,
          payPeriod: payPeriod,
          payrollDay: selectedPayrollDay,
          onUpdate: onUpdatePayPeriod
        )
      }

      // Two-weekly pay has its own paydays, so the monthly payday only applies to monthly periods.
      if !payPeriod.isBiweekly {
        payrollDayInput
      }

      // Half-tax month
      halfTaxMonthPicker
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .onAppear {
      initializeFromInputs(force: true)
    }
    .onChange(of: jobId) { _, _ in
      initializeFromInputs(force: true)
    }
    .sheet(isPresented: $showingCurrencyPicker) {
      CurrencyPickerSheet(
        selectedCurrency: $selectedCurrency,
        isPresented: $showingCurrencyPicker,
        onSelect: { newCurrency in
          Task {
            await onUpdateCurrency(newCurrency)
          }
        }
      )
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
  }

  private func initializeFromInputs(force: Bool = false) {
    if !force, initializedJobId == jobId {
      return
    }

    selectedCurrency = currency

    selectedPayrollDay = payrollDay
    selectedHalfTaxMonth = halfTaxMonth
    initializedJobId = jobId
  }

  // MARK: - Currency Input

  @ViewBuilder
  private var currencyInput: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayGlobalCurrency)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      Button(action: {
        if canChangeCurrency {
          showingCurrencyPicker = true
        }
      }) {
        HStack {
          Text(CurrencyConfig.get(selectedCurrency).label)
            .font(.tidexBody)
            .foregroundColor(canChangeCurrency ? .tidexTextPrimary : .tidexTextMuted)

          Spacer()

          if canChangeCurrency {
            Image(systemName: "chevron.down")
              .font(.tidexLabel)
              .foregroundColor(.tidexTextMuted)
          } else {
            Image(systemName: "lock.fill")
              .font(.tidexCaptionRegular)
              .foregroundColor(.tidexTextMuted)
          }
        }
        .padding(Spacing.sm)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
      }
      .buttonStyle(.plain)
      .disabled(!canChangeCurrency)
      .sensoryFeedback(.impact(weight: .light), trigger: showingCurrencyPicker) { _, new in new }

      if !canChangeCurrency {
        Text(.settingsPayCurrencyTariffWarning)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
      }
    }
  }

  // MARK: - Payroll Day Input

  @ViewBuilder
  private var payrollDayInput: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayGlobalPayrollDay)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      Picker("", selection: $selectedPayrollDay) {
        ForEach(1...31, id: \.self) { day in
          Text(payrollDayOptionTitle(day)).tag(day)
        }
      }
      .pickerStyle(.menu)
      .tint(.tidexBlue)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.sm)
      .background(Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
      .onChange(of: selectedPayrollDay) { _, newValue in
        onUpdatePayrollDay(newValue)
      }
      .sensoryFeedback(.selection, trigger: selectedPayrollDay)

      if payPeriod.isCalendarMonth {
        Text(.settingsPayGlobalPayrollDayHelper)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
      }
    }
  }

  private func payrollDayOptionTitle(_ day: Int) -> String {
    if day == 31 {
      return String(localized: .settingsPayPayrollDayLastDay)
    }

    return formatPayrollDay(day)
  }

  private func formatPayrollDay(_ day: Int) -> String {
    // Format ordinal based on language
    let ordinal: String
    if Locale.current.isNorwegian {
      ordinal = "\(day)"
    } else {
      // English ordinal suffixes
      let suffix: String
      switch day {
      case 1, 21, 31: suffix = "st"
      case 2, 22: suffix = "nd"
      case 3, 23: suffix = "rd"
      default: suffix = "th"
      }
      ordinal = "\(day)\(suffix)"
    }
    return String(localized: .settingsPayPayrollDayFormat(ordinal))
  }

  // MARK: - Half-Tax Month Picker

  @ViewBuilder
  private var halfTaxMonthPicker: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayGlobalHalfTaxMonth)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      Picker("", selection: $selectedHalfTaxMonth) {
        Text(.settingsPayGlobalHalfTaxMonthOff)
          .tag(nil as Int?)
        Text(.settingsPayGlobalHalfTaxMonthNovember)
          .tag(11 as Int?)
        Text(.settingsPayGlobalHalfTaxMonthDecember)
          .tag(12 as Int?)
      }
      .pickerStyle(.menu)
      .tint(.tidexBlue)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.sm)
      .background(Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
      .onChange(of: selectedHalfTaxMonth) { _, newValue in
        Task {
          await onUpdateHalfTaxMonth(newValue)
        }
      }
      .sensoryFeedback(.selection, trigger: selectedHalfTaxMonth)

      Text(.settingsPayGlobalHalfTaxMonthHelper)
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)
    }
  }
}

// MARK: - Currency Picker Sheet

private struct CurrencyPickerSheet: View {
  @Binding var selectedCurrency: String
  @Binding var isPresented: Bool
  let onSelect: (String) -> Void

  var body: some View {
    NavigationStack {
      ZStack {
        Color.tidexBackground
          .ignoresSafeArea()

        ScrollView {
          LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
            ForEach(CurrencyConfig.groups) { group in
              Section {
                ForEach(group.options) { option in
                  CurrencyRow(
                    option: option,
                    isSelected: selectedCurrency == option.value,
                    action: {
                      selectedCurrency = option.value
                      onSelect(option.value)
                      isPresented = false
                    }
                  )
                }
              } header: {
                HStack {
                  Text(group.localizedLabel)
                    .font(.tidexFootnoteStrong)
                    .foregroundColor(.tidexTextMuted)
                    .textCase(.uppercase)
                  Spacer()
                }
                .padding(.horizontal, Spacing.mlg)
                .padding(.vertical, Spacing.xs)
                .background(Color.tidexBackground)
              }
            }
          }
          .padding(.top, Spacing.xs)
        }
      }
      .navigationTitle(String(localized: .settingsPayGlobalCurrencyTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            isPresented = false
          }
        }
      }
    }
    .sensoryFeedback(.selection, trigger: selectedCurrency)
  }
}

private struct CurrencyRow: View {
  let option: CurrencyOption
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack {
        Text(option.label)
          .font(isSelected ? .tidexHeadline : .tidexBody)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .font(.tidexButton)
            .foregroundColor(.tidexBrandPrimary)
        }
      }
      .contentShape(Rectangle())
      .padding(.horizontal, Spacing.mlg)
      .padding(.vertical, Spacing.sm)
      .background(isSelected ? Color.tidexBrandPrimary.opacity(0.08) : Color.clear)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Preview

#Preview {
  ScrollView {
    GlobalPaySettingsCard(
      jobId: "test-job",
      currency: "kr",
      payrollDay: 15,
      halfTaxMonth: nil,
      canChangeCurrency: true,
      onUpdatePayrollDay: { _ in },
      onUpdateHalfTaxMonth: { _ in },
      onUpdateCurrency: { _ in }
    )
    .padding()
  }
  .background(Color.tidexBackground)
}
