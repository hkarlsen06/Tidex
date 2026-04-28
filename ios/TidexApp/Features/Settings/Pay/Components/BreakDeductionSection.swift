import SwiftUI
import UIKit

// MARK: - Break Deduction Section

/// Section for configuring break deduction settings
struct BreakDeductionSection: View {
  @Binding var enabled: Bool
  @Binding var method: BreakMethod
  @Binding var thresholdHours: Double
  @Binding var deductionMinutes: Int

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      // Section header with toggle
      HStack {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(.settingsPayEditorBreakTitle)
            .font(.tidexButton)
            .foregroundColor(.tidexTextPrimary)

          Text(.settingsPayEditorBreakDescription)
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

    }
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: enabled)
    .onAppear {
      applyStandardBreakDeduction()
    }
    .onChange(of: enabled) { _, isEnabled in
      guard isEnabled else { return }
      applyStandardBreakDeduction()
    }
  }

  private func applyStandardBreakDeduction() {
    method = .proportional
    thresholdHours = 5.5
    deductionMinutes = 30
  }
}

// MARK: - Preview

#Preview {
  ScrollView {
    BreakDeductionSection(
      enabled: .constant(true),
      method: .constant(.proportional),
      thresholdHours: .constant(5.5),
      deductionMinutes: .constant(30)
    )
    .padding()
  }
  .background(Color.tidexBackground)
}
