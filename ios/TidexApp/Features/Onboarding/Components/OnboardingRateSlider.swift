import SwiftUI
import UIKit

/// Unified hourly rate slider for onboarding flows
/// Supports compact (inline) and full (with label/helper) styles
struct OnboardingRateSlider: View {
  @Binding var value: Double
  var currency: String? = nil  // Optional currency override (uses locale default if nil)
  var style: Style = .compact

  @State private var showingCustomInput = false
  @State private var inputText = ""
  @FocusState private var isInputFocused: Bool

  enum Style {
    case compact  // Used inline in onboarding page 2
    case full  // Used in personalization screen with label/helper
  }

  var body: some View {
    switch style {
    case .compact:
      compactLayout
    case .full:
      fullLayout
    }
  }

  // MARK: - Currency-Aware Configuration

  /// Get the effective currency config (from parameter or locale default)
  private var currencyConfig: CurrencyOption {
    if let currency = currency {
      return CurrencyConfig.get(currency)
    }
    return Locale.current.isNorwegian ? CurrencyConfig.defaultCurrency : CurrencyConfig.get("$")
  }

  /// Whether currency symbol should appear before the amount
  private var isCurrencyPrefix: Bool {
    currencyConfig.display == .prefix
  }

  /// Get the wage range tier for the current currency
  private var wageRangeTier: WageRangeTier {
    currencyConfig.wageRangeTier
  }

  /// Wage ranges based on currency tier (not locale)
  /// This ensures appropriate slider ranges for each currency's typical hourly wages
  private var minValue: Double {
    wageRangeTier.minValue
  }

  private var maxValue: Double {
    wageRangeTier.maxValue
  }

  private var defaultValue: Double {
    wageRangeTier.defaultValue
  }

  private var currencySymbol: String {
    currencyConfig.value
  }

  private var hourSuffix: String {
    String(localized: .commonPerHourShort)
  }

  // MARK: - Compact Layout (inline)

  @ViewBuilder
  private var compactLayout: some View {
    VStack(spacing: Spacing.sm) {
      // Current value display: "Your hourly rate" on left, "200 kr/t" on right
      HStack(spacing: Spacing.xxs) {
        Text(.onboardingSliderLabel)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)

        Spacer()

        // Tappable currency display (currency-aware)
        if showingCustomInput {
          customInputField
        } else if isCurrencyPrefix {
          // Prefix currencies: "$200/hr"
          Text(currencySymbol)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextMuted)
          tappableValue(formatValueWithDecimals(value))
          Text(hourSuffix)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextMuted)
        } else {
          // Suffix currencies: "200 kr/t"
          tappableValue(formatValueWithDecimals(value))
          Text("\(currencySymbol)\(hourSuffix)")
            .font(.tidexLabel)
            .foregroundColor(.tidexTextMuted)
        }
      }

      sliderControl

      minMaxLabels(font: .tidexMicro)
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
  }

  // MARK: - Full Layout (with label and helper)

  @ViewBuilder
  private var fullLayout: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      // Label
      Text(.onboardingPersonalizeWageLabel)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      // Slider card
      VStack(spacing: Spacing.md) {
        // Current value display (currency-aware)
        HStack {
          if showingCustomInput {
            customInputFieldFull
          } else if isCurrencyPrefix {
            // Prefix currencies: "$200 per hour"
            Text(currencySymbol)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextSecondary)

            tappableValueFull(formatValueWithDecimals(value))

            Text(.commonPerHour)
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextMuted)
          } else {
            // Suffix currencies: "200 kr per time"
            tappableValueFull(formatValueWithDecimals(value))

            Text(currencySymbol)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextSecondary)

            Text(.commonPerHour)
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextMuted)
          }

          Spacer()
        }

        sliderControl

        minMaxLabels(font: .tidexCaptionRegular)
      }
      .padding(Spacing.md)
      .background(Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))

      // Helper text
      Text(.onboardingPersonalizeWageHelper)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextMuted)
    }
  }

  // MARK: - Shared Components

  @ViewBuilder
  private var sliderControl: some View {
    Slider(
      value: $value,
      in: minValue...maxValue,
      step: 1,
      onEditingChanged: { isEditing in
        if isEditing {
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
      }
    )
    .tint(.tidexBlue)
  }

  @ViewBuilder
  private func minMaxLabels(font: Font) -> some View {
    HStack {
      Text(formatCurrencyLabel(minValue))
        .font(font)
        .foregroundColor(.tidexTextMuted)

      Spacer()

      Text(formatCurrencyLabel(maxValue))
        .font(font)
        .foregroundColor(.tidexTextMuted)
    }
  }

  /// Format just the number (for inline display where currency symbol is separate)
  private func formatValue(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    return formatter.string(from: NSNumber(value: amount)) ?? "0"
  }

  /// Format with currency for min/max labels
  /// Uses prefix/suffix based on currency config
  private func formatCurrencyLabel(_ amount: Double) -> String {
    let number = formatValue(amount)
    if isCurrencyPrefix {
      return "\(currencySymbol)\(number)"
    } else {
      return "\(number) \(currencySymbol)"
    }
  }

  /// Format value for display as whole numbers.
  private func formatValueWithDecimals(_ amount: Double) -> String {
    formatValue(amount)
  }

  // MARK: - Tappable Value Views

  @ViewBuilder
  private func tappableValue(_ text: String) -> some View {
    Button(action: {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      inputText = formatValueWithDecimals(value)
      showingCustomInput = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        isInputFocused = true
      }
    }) {
      Text(text)
        .font(.tidexLargeTitle)
        .foregroundColor(.tidexBlue)
        .contentTransition(.numericText())
        .padding(.horizontal, Spacing.xxs)
        .padding(.vertical, Spacing.micro)
        .background(Color.tidexBlue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func tappableValueFull(_ text: String) -> some View {
    Button(action: {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      inputText = formatValueWithDecimals(value)
      showingCustomInput = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        isInputFocused = true
      }
    }) {
      Text(text)
        .font(.tidexScreenTitle)
        .foregroundColor(.tidexBlue)
        .contentTransition(.numericText())
        .padding(.horizontal, Spacing.xxxs)
        .padding(.vertical, Spacing.micro)
        .background(Color.tidexBlue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Custom Input Fields

  @ViewBuilder
  private var customInputField: some View {
    HStack(spacing: Spacing.xxs) {
      TextField("", text: $inputText)
        .font(.tidexLargeTitle)
        .foregroundColor(.tidexBlue)
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .focused($isInputFocused)
        .frame(width: 80)
        .padding(.horizontal, Spacing.xxs)
        .padding(.vertical, Spacing.micro)
        .background(Color.tidexBlue.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
            .stroke(Color.tidexBlue, lineWidth: 2)
        )
        .onSubmit {
          applyCustomValue()
        }
        .onChange(of: isInputFocused) { _, focused in
          if !focused {
            applyCustomValue()
          }
        }
        .toolbar {
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button(String(localized: .commonDone)) {
              applyCustomValue()
            }
            .fontWeight(.semibold)
          }
        }
    }
  }

  @ViewBuilder
  private var customInputFieldFull: some View {
    HStack(spacing: Spacing.xxs) {
      TextField("", text: $inputText)
        .font(.tidexScreenTitle)
        .foregroundColor(.tidexBlue)
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.leading)
        .focused($isInputFocused)
        .frame(width: 100)
        .padding(.horizontal, Spacing.xxxs)
        .padding(.vertical, Spacing.micro)
        .background(Color.tidexBlue.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
            .stroke(Color.tidexBlue, lineWidth: 2)
        )
        .onSubmit {
          applyCustomValue()
        }
        .onChange(of: isInputFocused) { _, focused in
          if !focused {
            applyCustomValue()
          }
        }
        .toolbar {
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button(String(localized: .commonDone)) {
              applyCustomValue()
            }
            .fontWeight(.semibold)
          }
        }
    }
  }

  private func applyCustomValue() {
    // Parse the input, handling both comma and period as decimal separator.
    let normalized = inputText.replacingOccurrences(of: ",", with: ".")
    if let parsed = Double(normalized) {
      // Allow any positive value 0-10000 when manually entered (not limited by slider range).
      let clamped = min(max(parsed, 0), 10000)
      let rounded = clamped.rounded()
      value = rounded
    }
    showingCustomInput = false
    isInputFocused = false
  }
}

#Preview("Compact") {
  OnboardingRateSlider(value: .constant(200), style: .compact)
    .padding()
    .background(Color.tidexBackground)
}

#Preview("Full") {
  OnboardingRateSlider(value: .constant(280), style: .full)
    .padding()
    .background(Color.tidexBackground)
}
