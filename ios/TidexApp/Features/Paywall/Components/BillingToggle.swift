import SwiftUI

// MARK: - Billing Toggle

/// Segmented control for selecting monthly vs yearly billing
/// Shows savings percentage for yearly option
struct BillingToggle: View {
  @Binding var selection: BillingPeriod
  var yearlySavingsPercent: Int?

  var body: some View {
    HStack(spacing: 0) {
      // Monthly option
      toggleOption(
        title: String(localized: .paywallMonthly),
        isSelected: selection == .monthly
      ) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
          selection = .monthly
        }
      }

      // Yearly option with savings badge
      toggleOption(
        title: String(localized: .paywallYearly),
        badge: yearlySavingsPercent.map { String(localized: .paywallSavePercent(Int32($0))) },
        isSelected: selection == .yearly
      ) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
          selection = .yearly
        }
      }
    }
    .padding(Spacing.xxs)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }

  @ViewBuilder
  private func toggleOption(
    title: String,
    badge: String? = nil,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: Spacing.xxxs) {
        Text(title)
          .font(isSelected ? .tidexLabelStrong : .tidexLabel)
          .foregroundColor(isSelected ? .tidexTextPrimary : .tidexTextSecondary)

        if let badge = badge {
          Text(badge)
            .font(.tidexMicro.bold())
            .foregroundColor(.tidexTextOnSuccess)
            .padding(.horizontal, Spacing.xxxs)
            .padding(.vertical, 3)
            .background(Color.tidexSuccess)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.sm)
      .background(
        isSelected
          ? Color.tidexBackground
          : Color.clear
      )
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.lg) {
    BillingToggle(selection: .constant(.monthly), yearlySavingsPercent: 17)
    BillingToggle(selection: .constant(.yearly), yearlySavingsPercent: 17)
    BillingToggle(selection: .constant(.monthly), yearlySavingsPercent: nil)
  }
  .padding()
  .background(Color.tidexBackground)
}
