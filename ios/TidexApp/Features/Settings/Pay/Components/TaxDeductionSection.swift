import SwiftUI

// MARK: - Tax Deduction Section

/// Section for configuring tax deduction settings
struct TaxDeductionSection: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .subheadline) private var presetMinimumWidth: CGFloat = 52
  @ScaledMetric(relativeTo: .headline) private var percentageInputWidth: CGFloat = 64
  @Binding var enabled: Bool
  @Binding var percentage: Double

  @State private var showingPercentageInput = false
  @FocusState private var isPercentageInputFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      // Section header with toggle
      Toggle(isOn: $enabled) {
        Text(.settingsPayEditorTaxTitle)
          .font(.tidexButton)
          .foregroundColor(.tidexTextPrimary)
      }
      .accessibilityIdentifier("pay-settings.tax-toggle")
      .tint(.tidexBrandPrimary)

      Text(.settingsPayEditorTaxDescription)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
        .fixedSize(horizontal: false, vertical: true)

      // Percentage input (only shown when enabled)
      if enabled {
        percentageInput
          .transition(.opacity.combined(with: .move(edge: .top)))

        Text(.settingsPayEditorTaxFlatRateHint)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .transition(.opacity)
      }

      Text(.settingsPayReviewDateExplanation)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: enabled)
  }

  // MARK: - Percentage Input

  @ViewBuilder
  private var percentageInput: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayEditorTaxPercentage)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      VStack(spacing: Spacing.sm) {
        quickPercentageGrid
        percentageSliderRow
      }
    }
    .sensoryFeedback(.selection, trigger: percentage)
    .sensoryFeedback(.impact(weight: .light), trigger: showingPercentageInput)
  }

  private var quickPercentageGrid: some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: presetMinimumWidth), spacing: Spacing.xs)],
      spacing: Spacing.xs
    ) {
      ForEach([0, 20, 22, 25, 30], id: \.self) { value in
        QuickPercentageButton(
          value: value,
          isSelected: percentage == Double(value),
          action: {
            withAnimation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.8)) {
              percentage = Double(value)
            }
          }
        )
      }
    }
  }

  /// Slider with value display
  private var percentageSliderRow: some View {
    HStack(spacing: Spacing.sm) {
      // Tappable value display
      if showingPercentageInput {
        percentageTextField
      } else {
        percentageValueButton
      }

      Slider(value: $percentage, in: 0...50, step: 1)
        .tint(.tidexBlue)
        .accessibilityLabel(Text(.settingsPayEditorTaxPercentage))
        .accessibilityValue(FormatterCache.percentagePoints(percentage))
    }
    .padding(Spacing.sm)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
  }

  private var percentageTextField: some View {
    HStack(spacing: Spacing.micro) {
      percentageInputField

      Text("%")
        .font(.tidexLabel)
        .foregroundColor(.tidexTextMuted)
    }
  }

  private var percentageInputField: some View {
    TextField(
      "",
      value: $percentage,
      format: .number.precision(.fractionLength(0...1)).locale(.appLocale)
    )
    .font(.tidexTitle2)
    .foregroundColor(.tidexBlue)
    .keyboardType(.decimalPad)
    .multilineTextAlignment(.trailing)
    .focused($isPercentageInputFocused)
    .frame(width: percentageInputWidth)
    .frame(minHeight: 44)
    .accessibilityLabel(Text(.settingsPayEditorTaxPercentage))
    .padding(.horizontal, Spacing.xxs)
    .padding(.vertical, Spacing.micro)
    .background(Color.tidexBlue.opacity(0.15))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
        .stroke(Color.tidexBlue, lineWidth: 1)
    )
    .onChange(of: percentage) { _, newValue in
      let clamped = min(max(newValue, 0), 100)
      if clamped != newValue { percentage = clamped }
    }
    .onChange(of: isPercentageInputFocused) { _, focused in
      if !focused {
        showingPercentageInput = false
      }
    }
    .toolbar { keyboardDoneToolbar }
  }

  @ToolbarContentBuilder
  private var keyboardDoneToolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .keyboard) {
      Spacer()
      Button(String(localized: .commonDone)) {
        isPercentageInputFocused = false
      }
      .fontWeight(.semibold)
    }
  }

  private var percentageValueButton: some View {
    Button(action: {
      showingPercentageInput = true
      isPercentageInputFocused = true
    }) {
      HStack(spacing: Spacing.micro) {
        Text(
          percentage, format: .number.precision(.fractionLength(0...1)).locale(.appLocale)
        )
        .font(.tidexTitle2)
        .foregroundColor(.tidexBlue)
        .contentTransition(.numericText())

        Text("%")
          .font(.tidexLabel)
          .foregroundColor(.tidexTextMuted)
      }
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(.settingsPayEditorTaxPercentage))
    .accessibilityValue(FormatterCache.percentagePoints(percentage))
  }
}

// MARK: - Quick Percentage Button

private struct QuickPercentageButton: View {
  let value: Int
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text("\(value)%")
        .font(isSelected ? .tidexLabelStrong : .tidexLabel)
        .foregroundColor(isSelected ? .tidexTextOnBrand : .tidexTextSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 44)
        .background(isSelected ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
            .stroke(isSelected ? Color.clear : Color.tidexBorder, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

// MARK: - Preview

#Preview {
  ScrollView {
    TaxDeductionSection(
      enabled: .constant(true),
      percentage: .constant(22)
    )
    .padding()
  }
  .background(Color.tidexBackground)
}
