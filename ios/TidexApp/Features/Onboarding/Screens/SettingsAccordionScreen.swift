import SwiftUI

/// Screen for configuring break, tax, and payday with progressive accordion
/// Each section expands one at a time for focused input
struct SettingsAccordionScreen: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order line_length type_body_length
  @Bindable var data: OnboardingData
  let onContinue: () -> Void
  var onBack: (() -> Void)?  // swiftlint:disable:this explicit_acl type_contents_order
  var showsPayday: Bool = true
  var continueTitle: String = String(localized: .commonContinue)
  @ScaledMetric(relativeTo: .subheadline) private var taxPresetMinimumWidth: CGFloat = 64
  @ScaledMetric(relativeTo: .headline) private var taxInputWidth: CGFloat = 60
  @ScaledMetric(relativeTo: .headline) private var paydayInputWidth: CGFloat = 44

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var currentSection: SettingsSection? = .breakDeduction
  @State private var completedSections: Set<SettingsSection> = []
  @State private var showingTaxInput = false
  @State private var taxInputText = ""
  @FocusState private var isTaxInputFocused: Bool
  @State private var showingPaydayInput = false
  @State private var paydayInputText = ""
  @FocusState private var isPaydayInputFocused: Bool

  private enum SettingsSection: Int, CaseIterable {
    case breakDeduction = 0
    case tax = 1
    case payday = 2
  }

  private let payrollDayOptions = [1, 10, 15, 20, 25, 31]
  private let taxPresets: [Double] = [22, 25, 30, 40]

  var body: some View {
    ZStack {
      // Background
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        ScrollView {
          scrollContent
        }

        // Final continue button (visible when all sections complete)
        if allSectionsComplete {
          OnboardingButton(
            title: continueTitle,
            action: {
              Haptics.play(.success)
              onContinue()
            }
          )
          .padding(.horizontal, Spacing.lg)
          .padding(.bottom, Spacing.xl)
          .adaptiveContentWidth()
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
      }
      .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: currentSection)
      .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: completedSections)
    }
  }

  private var scrollContent: some View {
    VStack(spacing: 0) {
      // Back button (if provided)
      if let onBack {
        backButton(onBack)
      }

      Spacer()
        .frame(height: onBack != nil ? 24 : 60)

      header

      Spacer()
        .frame(height: Spacing.xl)

      // Accordion sections
      VStack(spacing: Spacing.sm) {
        // Break deduction section
        breakSection

        // Tax section
        taxSection

        // Payday section
        if showsPayday {
          paydaySection
        }
      }
      .padding(.horizontal, Spacing.lg)
      .adaptiveContentWidth()

      Spacer()
        .frame(height: Spacing.xxxl)
    }
  }

  private func backButton(_ onBack: @escaping () -> Void) -> some View {
    HStack {
      Button(action: {
        Haptics.play(.light)
        onBack()
      }) {
        HStack(spacing: Spacing.xxs) {
          Image(systemName: "chevron.left")
            .font(.tidexButton)
            .accessibilityHidden(true)
          Text(.commonBack)
            .font(.tidexBody)
        }
        .foregroundColor(.tidexBlueText)
        .frame(minHeight: 44)
      }
      .buttonStyle(.plain)
      Spacer()
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.top, Spacing.md)
    .adaptiveContentWidth()
  }

  private var header: some View {
    VStack(spacing: Spacing.sm) {
      Text(.onboardingSettingsTitle)
        .font(.tidexLargeTitle)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)

      Text(.onboardingSettingsSubtitle)
        .font(.tidexBody)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, Spacing.xl)
    .adaptiveContentWidth()
  }

  private var allSectionsComplete: Bool {
    completedSections.contains(.breakDeduction) && completedSections.contains(.tax)
      && (!showsPayday || completedSections.contains(.payday))
  }

  // MARK: - Break Section

  @ViewBuilder
  private var breakSection: some View {
    AccordionSectionView(
      title: String(localized: .onboardingSettingsBreakTitle),
      summary: breakSummary,
      isExpanded: currentSection == .breakDeduction,
      isComplete: completedSections.contains(.breakDeduction),
      onContinue: {
        completeSection(.breakDeduction)
      },
      onHeaderTap: {
        openSection(.breakDeduction)
      }
    ) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        Toggle(isOn: $data.breakEnabled) {
          Text(.onboardingSettingsBreakEnable)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextPrimary)
        }
        .tint(.tidexBrandPrimary)

        Text(.onboardingSettingsBreakHint)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
          .fixedSize(horizontal: false, vertical: true)

        if data.breakEnabled {
          Text(.onboardingSettingsBreakDefault)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var breakSummary: String {
    if data.breakEnabled {
      return String(localized: .onboardingSettingsBreakEnabledSummary)
    }
    return String(localized: .onboardingSettingsBreakDisabledSummary)
  }

  // MARK: - Tax Section

  @ViewBuilder
  private var taxSection: some View {
    AccordionSectionView(
      title: String(localized: .onboardingSettingsTaxTitle),
      summary: taxSummary,
      isExpanded: currentSection == .tax,
      isComplete: completedSections.contains(.tax),
      onContinue: {
        completeSection(.tax)
      },
      onHeaderTap: {
        openSection(.tax)
      },
      isLocked: !completedSections.contains(.breakDeduction)
    ) {
      taxContent
    }
    .opacity(completedSections.contains(.breakDeduction) || currentSection == .tax ? 1 : 0.5)
  }

  private var taxContent: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      Toggle(isOn: $data.taxEnabled) {
        Text(.onboardingSettingsTaxEnable)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextPrimary)
      }
      .tint(.tidexBrandPrimary)

      Text(.onboardingSettingsTaxHint)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
        .fixedSize(horizontal: false, vertical: true)

      if data.taxEnabled {
        taxPercentageControls
      }
    }
  }

  private var taxPercentageControls: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.onboardingSettingsTaxPercentage)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      taxPresetGrid

      // Current value display - tappable
      HStack {
        if showingTaxInput {
          taxInputField
        } else {
          taxValueButton
        }
        Spacer()
      }

      Slider(
        value: $data.taxPercentage,
        in: 0...50,
        step: 1,
        onEditingChanged: { isEditing in
          if isEditing {
            Haptics.play(.light)
          }
        }
      )
      .tint(.tidexBlue)
      .accessibilityLabel(Text(.onboardingSettingsTaxPercentage))
      .accessibilityValue(Text(verbatim: "\(formatTaxValue(data.taxPercentage))%"))
    }
  }

  /// Tax preset buttons
  private var taxPresetGrid: some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: taxPresetMinimumWidth), spacing: Spacing.xs)],
      spacing: Spacing.xs
    ) {
      ForEach(taxPresets, id: \.self) { preset in
        TaxPresetButton(
          value: preset,
          isSelected: data.taxPercentage == preset,
          action: {
            withAnimation(reduceMotion ? nil : .default) {
              data.taxPercentage = preset
            }
          }
        )
      }
    }
  }

  /// Editable input field
  private var taxInputField: some View {
    HStack(spacing: Spacing.xxs) {
      taxTextField

      Text("%")
        .font(.tidexLabel)
        .foregroundColor(.tidexTextMuted)
    }
  }

  private var taxTextField: some View {
    TextField("", text: $taxInputText)
      .font(.tidexTitle2)
      .foregroundColor(.tidexBlueText)
      .keyboardType(.decimalPad)
      .multilineTextAlignment(.leading)
      .focused($isTaxInputFocused)
      .accessibilityLabel(Text(.onboardingSettingsTaxPercentage))
      .frame(width: taxInputWidth)
      .padding(.horizontal, Spacing.xxs)
      .padding(.vertical, Spacing.micro)
      .background(Color.tidexBlue.opacity(0.15))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
          .stroke(Color.tidexBlue, lineWidth: 2)
      )
      .onChange(of: isTaxInputFocused) { _, focused in
        if !focused {
          applyTaxInput()
        }
      }
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button(String(localized: .commonDone)) {
            applyTaxInput()
          }
          .fontWeight(.semibold)
        }
      }
  }

  /// Tappable display
  private var taxValueButton: some View {
    Button(action: {
      Haptics.play(.light)
      taxInputText = formatTaxValue(data.taxPercentage)
      showingTaxInput = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        isTaxInputFocused = true
      }
    }) {
      taxValueLabel
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      Text(verbatim: "\(String(localized: .onboardingSettingsTaxPercentage)), \(formatTaxValue(data.taxPercentage))%")
    )
    .accessibilityInputLabels([formatTaxValue(data.taxPercentage)])
  }

  private var taxValueLabel: some View {
    HStack(spacing: Spacing.micro) {
      Text(formatTaxValue(data.taxPercentage))
        .font(.tidexTitle2)
        .foregroundColor(.tidexBlueText)
        .contentTransition(.numericText())
      Text("%")
        .font(.tidexLabel)
        .foregroundColor(.tidexTextMuted)
    }
    .padding(.horizontal, Spacing.xxxs)
    .padding(.vertical, Spacing.micro)
    .background(Color.tidexBlue.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
  }

  private var taxSummary: String {
    if data.taxEnabled {
      return "\(Int(data.taxPercentage))%"
    }
    return String(localized: .onboardingSettingsTaxDisabledSummary)
  }

  // MARK: - Payday Section

  @ViewBuilder
  private var paydaySection: some View {
    AccordionSectionView(
      title: String(localized: .onboardingSettingsPaydayTitle),
      summary: paydaySummary,
      isExpanded: currentSection == .payday,
      isComplete: completedSections.contains(.payday),
      onContinue: {
        completeSection(.payday)
      },
      onHeaderTap: {
        openSection(.payday)
      },
      isLocked: !completedSections.contains(.tax)
    ) {
      paydayContent
    }
    .opacity(completedSections.contains(.tax) || currentSection == .payday ? 1 : 0.5)
  }

  private var paydayContent: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.onboardingSettingsPaydayHint)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextMuted)

      // Horizontal scroll with day options + custom input
      // Overlay with fade gradient to hint there's more content
      ZStack(alignment: .trailing) {
        ScrollView(.horizontal, showsIndicators: false) {
          paydayOptions
        }

        // Trailing fade gradient to hint more content
        LinearGradient(
          colors: [Color.tidexSurfaceSecondary.opacity(0), Color.tidexSurfaceSecondary],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(width: 32)
        .allowsHitTesting(false)
      }

      // Show current custom value if not a preset
      if !payrollDayOptions.contains(data.payrollDay), !showingPaydayInput {
        Text(String(localized: .onboardingSettingsPaydayCustomValue(data.payrollDay)))
          .font(.tidexFootnote)
          .foregroundColor(.tidexBlueText)
      }
    }
  }

  private var paydayOptions: some View {
    HStack(spacing: Spacing.xs) {
      ForEach(payrollDayOptions, id: \.self) { day in
        PaydayButton(
          day: day,
          isLast: day == 31,
          isSelected: data.payrollDay == day && !showingPaydayInput,
          action: {
            showingPaydayInput = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
              data.payrollDay = day
            }
          }
        )
      }

      // Custom day input button/field
      if showingPaydayInput {
        paydayInputField
      } else {
        paydayOtherButton
      }
    }
    .padding(.trailing, Spacing.lg)  // Extra padding for fade area
  }

  private var paydayInputField: some View {
    HStack(spacing: Spacing.xxs) {
      TextField("", text: $paydayInputText)
        .font(.tidexButton)
        .foregroundColor(.tidexBlueText)
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .focused($isPaydayInputFocused)
        .accessibilityLabel(Text(.onboardingSettingsPaydayTitle))
        .frame(width: paydayInputWidth)
        .frame(minHeight: 44)
        .background(Color.tidexBlue.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
            .stroke(Color.tidexBlue, lineWidth: 2)
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
    }
  }

  /// "Other" button to enter custom day
  private var paydayOtherButton: some View {
    let isCustomDay = !payrollDayOptions.contains(data.payrollDay)
    return Button(action: {
      Haptics.play(.light)
      paydayInputText = isCustomDay ? "\(data.payrollDay)" : ""
      showingPaydayInput = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        isPaydayInputFocused = true
      }
    }) {
      HStack(spacing: Spacing.xxs) {
        Image(systemName: "pencil")
          .font(.tidexCaptionRegular)
          .accessibilityHidden(true)
        Text(.onboardingSettingsPaydayOther)
      }
      .font(isCustomDay ? .tidexLabelStrong : .tidexLabel)
      .foregroundColor(isCustomDay ? .tidexTextOnBrand : .tidexTextSecondary)
      .frame(minWidth: 56, minHeight: 44)
      .padding(.horizontal, Spacing.xs)
      .background(isCustomDay ? Color.tidexBrandPrimary : Color.tidexBackground)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
          .stroke(isCustomDay ? Color.clear : Color.tidexBorder, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isCustomDay ? .isSelected : [])
  }

  private var paydaySummary: String {
    if data.payrollDay == 31 {
      return String(localized: .onboardingPersonalizePaydayLastDay)
    }
    return "\(data.payrollDay)."
  }

  // MARK: - Helpers

  /// Opens a collapsed section. A section opens once the one before it is complete, or when it is done already.
  private func openSection(_ section: SettingsSection) {
    guard currentSection != section else { return }
    let isUnlocked: Bool
    switch section {
    case .breakDeduction:
      isUnlocked = true

    case .tax:
      isUnlocked = completedSections.contains(.tax) || completedSections.contains(.breakDeduction)

    case .payday:
      isUnlocked = completedSections.contains(.payday) || completedSections.contains(.tax)
    }
    guard isUnlocked else { return }
    withAnimation(reduceMotion ? nil : .default) {
      currentSection = section
    }
  }

  private func completeSection(_ section: SettingsSection) {
    withAnimation(reduceMotion ? nil : .default) {
      completedSections.insert(section)

      // Move to next section
      switch section {
      case .breakDeduction:
        currentSection = .tax

      case .tax:
        currentSection = showsPayday ? .payday : nil

      case .payday:
        // All done - collapse the final section so its completed state is visible.
        currentSection = nil
      }
    }
  }

  private func formatTaxValue(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)).locale(.appLocale))
  }

  private func applyTaxInput() {
    // Parse the input, handling both comma and period as decimal separator
    let normalized = taxInputText.replacingOccurrences(of: ",", with: ".")
    if let parsed = Double(normalized) {
      // Clamp to valid range (0-50%)
      let clamped = min(max(parsed, 0), 50)
      let rounded = (clamped * 10).rounded() / 10
      data.taxPercentage = rounded
    }
    showingTaxInput = false
    isTaxInputFocused = false
  }

  private func applyPaydayInput() {
    if let parsed = Int(paydayInputText) {
      // Clamp to valid range (1-31)
      let clamped = min(max(parsed, 1), 31)
      data.payrollDay = clamped
    }
    showingPaydayInput = false
    isPaydayInputFocused = false
  }
}

// MARK: - Tax Preset Button

private struct TaxPresetButton: View {
  let value: Double
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: {
      Haptics.play(.light)
      action()
    }) {
      Text("\(Int(value))%")
        .font(isSelected ? .tidexLabelStrong : .tidexLabel)
        .foregroundColor(isSelected ? .tidexTextOnBrand : .tidexTextSecondary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(isSelected ? Color.tidexBrandPrimary : Color.tidexBackground)
        .clipShape(Capsule())
        .overlay(
          Capsule()
            .stroke(isSelected ? Color.clear : Color.tidexBorder, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

// MARK: - Payday Button

private struct PaydayButton: View {
  let day: Int
  let isLast: Bool
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: {
      Haptics.play(.light)
      action()
    }) {
      Text(isLast ? String(localized: .onboardingPersonalizePaydayLastDay) : "\(day)")
        .font(isSelected ? .tidexButton : .tidexBodyMedium)
        .foregroundColor(isSelected ? .tidexTextOnBrand : .tidexTextSecondary)
        .frame(minWidth: 56, minHeight: 44)
        .background(isSelected ? Color.tidexBrandPrimary : Color.tidexBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
            .stroke(isSelected ? Color.clear : Color.tidexBorder, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

#Preview {
  SettingsAccordionScreen(data: OnboardingData(), onContinue: {})
}  // swiftlint:disable:this file_length
