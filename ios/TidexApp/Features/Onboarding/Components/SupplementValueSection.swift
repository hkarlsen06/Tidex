import SwiftUI

/// Value step of the supplement rule editor: quick values, tap-to-edit amount and slider.
struct SupplementValueSection: View {
  @Binding var rule: OnboardingSupplementRule
  let currency: String
  /// Hour suffix for the fixed rate display (e.g. "kr/t", "$/hr")
  let hourRateSuffix: String

  @State private var showingValueInput = false
  @State private var valueInputText = ""
  @FocusState private var isValueInputFocused: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .title2) private var inputWidth: CGFloat = 80

  private var currencyConfig: CurrencyOption {
    CurrencyConfig.get(currency)
  }

  private var unitSuffix: String {
    rule.type == .fixed ? hourRateSuffix : "%"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.onboardingSupplementsValueLabel)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      // Quick value buttons. They wrap into a grid when large text makes the row too wide.
      quickValueButtons

      // Slider for fine-tuning
      valueEditor
    }
  }

  @ViewBuilder
  private var quickValueButtons: some View {
    if dynamicTypeSize.isAccessibilitySize {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 88), spacing: Spacing.xs)],
        alignment: .leading,
        spacing: Spacing.xs
      ) {
        quickValueItems
      }
    } else {
      HStack(spacing: Spacing.xs) {
        quickValueItems
      }
    }
  }

  @ViewBuilder
  private var quickValueItems: some View {
    ForEach(quickValues, id: \.self) { value in
      QuickValueButton(
        value: value,
        type: rule.type,
        isSelected: rule.value == value,
        action: {
          Haptics.play(.light)
          withAnimation {
            rule.value = value
          }
        }
      )
    }
  }

  /// What VoiceOver reads for the amount, for example "45 kr/t".
  private var spokenValue: String {
    "\(formatValueWithDecimals(rule.value)) \(unitSuffix)"
  }

  private var valueEditor: some View {
    VStack(spacing: Spacing.xs) {
      HStack {
        if showingValueInput {
          valueInputField
        } else {
          valueDisplayButton

          Text(unitSuffix)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextMuted)
        }
        Spacer()
      }

      Slider(
        value: $rule.value,
        in: valueRange,
        step: 1,
        onEditingChanged: { isEditing in
          if isEditing {
            Haptics.play(.light)
          }
        }
      )
      .tint(.tidexBlue)
      .accessibilityLabel(Text(.onboardingSupplementsValueLabel))
      .accessibilityValue(Text(spokenValue))
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }

  /// Editable input field
  private var valueInputField: some View {
    HStack(spacing: Spacing.xxs) {
      valueTextField

      Text(unitSuffix)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextMuted)
    }
  }

  private var valueTextField: some View {
    TextField("", text: $valueInputText)
      .font(.tidexLargeTitle)
      .foregroundColor(.tidexBlueText)
      .keyboardType(.decimalPad)
      .multilineTextAlignment(.leading)
      .focused($isValueInputFocused)
      .accessibilityLabel(Text(.onboardingSupplementsValueLabel))
      .frame(width: inputWidth)
      .padding(.horizontal, Spacing.xxs)
      .padding(.vertical, Spacing.micro)
      .background(Color.tidexBlue.opacity(0.15))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
          .stroke(Color.tidexBlue, lineWidth: 2)
      )
      .onChange(of: isValueInputFocused) { _, focused in
        if !focused {
          applyValueInput()
        }
      }
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button(String(localized: .commonDone)) {
            applyValueInput()
          }
          .fontWeight(.semibold)
        }
      }
  }

  /// Tappable display
  private var valueDisplayButton: some View {
    Button(action: {
      Haptics.play(.light)
      valueInputText = formatValueWithDecimals(rule.value)
      showingValueInput = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        isValueInputFocused = true
      }
    }) {
      Text(formatValueWithDecimals(rule.value))
        .font(.tidexLargeTitle)
        .foregroundColor(.tidexBlueText)
        .contentTransition(.numericText())
        .padding(.horizontal, Spacing.xxs)
        .padding(.vertical, Spacing.micro)
        .background(Color.tidexBlue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      Text(verbatim: "\(String(localized: .onboardingSupplementsValueLabel)), \(spokenValue)")
    )
    .accessibilityInputLabels([formatValueWithDecimals(rule.value)])
  }

  private func formatValueWithDecimals(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)).locale(.appLocale))
  }

  private func applyValueInput() {
    // Parse the input, handling both comma and period as decimal separator
    let normalized = valueInputText.replacingOccurrences(of: ",", with: ".")
    if let parsed = Double(normalized) {
      // Clamp to valid range and round to 2 decimal places
      let clamped = min(max(parsed, valueRange.lowerBound), valueRange.upperBound)
      let rounded = (clamped * 100).rounded() / 100
      rule.value = rounded
    }
    showingValueInput = false
    isValueInputFocused = false
  }

  private var quickValues: [Double] {
    switch rule.type {
    case .fixed:
      // Quick values based on currency tier
      switch currencyConfig.wageRangeTier {
      case .high:
        // NOK, CZK, Ruble - higher nominal values
        return [22, 45, 55, 110, 115]

      case .medium:
        // USD, EUR, GBP, etc. - lower nominal values
        return [2, 5, 10, 15, 20]

      case .low:
        // INR, BRL, ZAR, etc. - mid-range nominal values
        return [10, 25, 50, 75, 100]

      case .veryLow:
        // JPY, KRW - very high nominal values
        return [100, 250, 500, 750, 1_000]  // swiftlint:disable:this no_magic_numbers

      case .ultraLow:
        // IDR, VND - five-digit nominal values
        return [1_000, 2_500, 5_000, 7_500, 10_000]  // swiftlint:disable:this no_magic_numbers
      }

    case .percent:
      return [25, 50, 100, 150]
    }
  }

  private var valueRange: ClosedRange<Double> {
    switch rule.type {
    case .fixed:
      // Value range based on currency tier
      switch currencyConfig.wageRangeTier {
      case .high:
        return 1...200

      case .medium:
        return 1...50

      case .low:
        return 1...500

      case .veryLow:
        return 1...2_000  // swiftlint:disable:this no_magic_numbers

      case .ultraLow:
        return 1...20_000  // swiftlint:disable:this no_magic_numbers
      }

    case .percent:
      return 1...200
    }
  }
}
