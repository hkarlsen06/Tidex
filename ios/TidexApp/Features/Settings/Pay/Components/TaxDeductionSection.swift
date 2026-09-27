import SwiftUI
import UIKit

// MARK: - Tax Deduction Section

/// Section for configuring tax deduction settings
struct TaxDeductionSection: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .subheadline) private var presetMinimumWidth: CGFloat = 52
  @ScaledMetric(relativeTo: .headline) private var percentageInputWidth: CGFloat = 64
  @Binding var enabled: Bool
  @Binding var percentage: Double

  @State private var showingPercentageInput = false
  @State private var percentageInputText = ""
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
      .onChange(of: enabled) { _, _ in
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
      }

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
        // Quick percentage buttons
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: presetMinimumWidth), spacing: Spacing.xs)],
          spacing: Spacing.xs
        ) {
          ForEach([0, 20, 22, 25, 30], id: \.self) { value in
            QuickPercentageButton(
              value: value,
              isSelected: percentage == Double(value),
              action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.8)) {
                  percentage = Double(value)
                }
              }
            )
          }
        }

        // Slider with value display
        HStack(spacing: Spacing.sm) {
          // Tappable value display
          if showingPercentageInput {
            HStack(spacing: Spacing.micro) {
              TextField("", text: $percentageInputText)
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
                .onChange(of: isPercentageInputFocused) { _, focused in
                  if !focused {
                    applyPercentageInput()
                  }
                }
                .toolbar {
                  ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(String(localized: .commonDone)) {
                      applyPercentageInput()
                    }
                    .fontWeight(.semibold)
                  }
                }

              Text("%")
                .font(.tidexLabel)
                .foregroundColor(.tidexTextMuted)
            }
          } else {
            Button(action: {
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
              percentageInputText = formatPercentageValue(percentage)
              showingPercentageInput = true
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPercentageInputFocused = true
              }
            }) {
              HStack(spacing: Spacing.micro) {
                Text(formatPercentageValue(percentage))
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

          Slider(
            value: $percentage,
            in: 0...50,
            step: 1,
            onEditingChanged: { isEditing in
              if isEditing {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
              }
            }
          )
          .tint(.tidexBlue)
          .accessibilityLabel(Text(.settingsPayEditorTaxPercentage))
          .accessibilityValue(FormatterCache.percentagePoints(percentage))
        }
        .padding(Spacing.sm)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
      }
    }
  }

  private func formatPercentageValue(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    formatter.locale = .appLocale
    return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
  }

  private func applyPercentageInput() {
    // Parse the input, handling both comma and period as decimal separator
    let normalized = percentageInputText.replacingOccurrences(of: ",", with: ".")
    if let parsed = Double(normalized) {
      // Clamp to valid range
      let clamped = min(max(parsed, 0), 100)
      percentage = clamped
    }
    showingPercentageInput = false
    isPercentageInputFocused = false
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
