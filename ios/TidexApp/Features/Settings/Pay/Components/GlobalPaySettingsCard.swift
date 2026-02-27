import SwiftUI
import UIKit

// MARK: - Global Pay Settings Card

/// Card for editing global pay settings: currency, monthly goal, payroll day, half-tax month
struct GlobalPaySettingsCard: View {
  let jobId: String?
  let currency: String
  let monthlyGoal: Int?
  let payrollDay: Int
  let halfTaxMonth: Int?
  /// Whether currency can be changed (false if tariff snapshots exist)
  let canChangeCurrency: Bool
  let onUpdateMonthlyGoal: (Int?) -> Void
  let onUpdatePayrollDay: (Int) -> Void
  let onUpdateHalfTaxMonth: (Int?) async -> Void
  let onUpdateCurrency: (String) async -> Void

  @State private var selectedCurrency: String = "kr"
  @State private var monthlyGoalText: String = ""
  @State private var selectedPayrollDay: Int = 1
  @State private var selectedHalfTaxMonth: Int? = nil
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

      // Monthly goal
      monthlyGoalInput

      // Payroll day
      payrollDayInput

      // Half-tax month
      halfTaxMonthPicker
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .tidexCardShadow()
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

    if let goal = monthlyGoal {
      monthlyGoalText = "\(goal)"
    } else {
      monthlyGoalText = ""
    }

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
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

      if !canChangeCurrency {
        Text(.settingsPayCurrencyTariffWarning)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
      }
    }
  }

  // MARK: - Monthly Goal Input

  @ViewBuilder
  private var monthlyGoalInput: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayGlobalMonthlyGoal)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      HStack {
        TextField(
          String(localized: .settingsPayGlobalMonthlyGoalPlaceholder),
          text: $monthlyGoalText
        )
        .keyboardType(.numberPad)
        .font(.tidexBody)
        .foregroundColor(.tidexTextPrimary)
        .onChange(of: monthlyGoalText) { _, newValue in
          // Filter to digits only
          let filtered = newValue.filter { $0.isNumber }
          if filtered != newValue {
            monthlyGoalText = filtered
          }

          // Debounced save
          if let value = Int(filtered), value > 0 {
            onUpdateMonthlyGoal(value)
          } else if filtered.isEmpty {
            onUpdateMonthlyGoal(nil)
          }
        }

        Text(selectedCurrency)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextMuted)
      }
      .padding(Spacing.sm)
      .background(Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))

      Text(.settingsPayGlobalMonthlyGoalHelper)
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)
    }
  }

  // MARK: - Payroll Day Input

  @ViewBuilder
  private var payrollDayInput: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayGlobalPayrollDay)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      HStack {
        Text(formatPayrollDay(selectedPayrollDay))
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Picker("", selection: $selectedPayrollDay) {
          ForEach(1...31, id: \.self) { day in
            Text("\(day)").tag(day)
          }
        }
        .pickerStyle(.menu)
        .tint(.tidexBlue)
        .onChange(of: selectedPayrollDay) { _, newValue in
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          onUpdatePayrollDay(newValue)
        }
      }
      .padding(Spacing.sm)
      .background(Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))

      Text(.settingsPayGlobalPayrollDayHelper)
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)
    }
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
          await onUpdateHalfTaxMonth(newValue)
        }
      }

      Text(.settingsPayGlobalHalfTaxMonthHelper)
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)
    }
  }
}

// MARK: - Currency Picker Sheet

/// Sheet for selecting a currency
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
                      UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
  }
}

// MARK: - Currency Row

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
      monthlyGoal: 20000,
      payrollDay: 15,
      halfTaxMonth: nil,
      canChangeCurrency: true,
      onUpdateMonthlyGoal: { _ in },
      onUpdatePayrollDay: { _ in },
      onUpdateHalfTaxMonth: { _ in },
      onUpdateCurrency: { _ in }
    )
    .padding()
  }
  .background(Color.tidexBackground)
}
