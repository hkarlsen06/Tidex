import SwiftUI
import UIKit

// MARK: - Tax Deduction Section

/// Section for configuring tax deduction settings
struct TaxDeductionSection: View {
  @Binding var enabled: Bool
  @Binding var percentage: Double

  @State private var showingPercentageInput = false
  @State private var percentageInputText = ""
  @FocusState private var isPercentageInputFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      // Section header with toggle
      HStack {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(.settingsPayEditorTaxTitle)
            .font(.tidexButton)
            .foregroundColor(.tidexTextPrimary)

          Text(.settingsPayEditorTaxDescription)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
        }

        Spacer()

        Toggle("", isOn: $enabled)
          .labelsHidden()
          .tint(.tidexBrandPrimary)
          .onChange(of: enabled) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
          }
      }

      // Percentage input (only shown when enabled)
      if enabled {
        percentageInput
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: enabled)
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
        HStack(spacing: Spacing.xs) {
          ForEach([0, 20, 22, 25, 30], id: \.self) { value in
            QuickPercentageButton(
              value: value,
              isSelected: Int(percentage) == value,
              action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
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
                .frame(width: 50)
                .padding(.horizontal, Spacing.xxs)
                .padding(.vertical, Spacing.micro)
                .background(Color.tidexBlue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
                .overlay(
                  RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
                    .stroke(Color.tidexBlue, lineWidth: 2)
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
                  .padding(.horizontal, Spacing.xxs)
                  .padding(.vertical, Spacing.micro)
                  .background(Color.tidexBlue.opacity(0.08))
                  .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))

                Text("%")
                  .font(.tidexLabel)
                  .foregroundColor(.tidexTextMuted)
              }
            }
            .buttonStyle(.plain)
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
    formatter.locale = Locale(identifier: "nb_NO")
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
        .foregroundColor(isSelected ? .white : .tidexTextSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(isSelected ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
            .stroke(isSelected ? Color.clear : Color.tidexBorder, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
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
