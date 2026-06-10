import SwiftUI

// MARK: - Billing Toggle

/// Segmented control for selecting monthly vs yearly billing
/// Shows savings percentage for yearly option
internal struct BillingToggle: View {
  @Binding internal var selection: BillingPeriod
  internal var yearlySavingsPercent: Int?

  private let animationResponse: Double = 0.3
  private let animationDampingFraction: Double = 0.8
  private let badgeVerticalPadding: CGFloat = 3

  internal var body: some View {
    HStack(spacing: 0) {
      // Monthly option
      toggleOption(
        title: String(localized: .paywallMonthly),
        isSelected: selection == .monthly
      ) {
        withAnimation(
          .spring(response: animationResponse, dampingFraction: animationDampingFraction)
        ) {
          selection = .monthly
        }
      }

      // Yearly option with savings badge
      toggleOption(
        title: String(localized: .paywallYearly),
        isSelected: selection == .yearly,
        badge: yearlySavingsPercent.map { savingsPercent in
          String(
            localized: .paywallSavePercent(FormatterCache.percentagePoints(Double(savingsPercent)))
          )
        },
        action: {
          withAnimation(
            .spring(response: animationResponse, dampingFraction: animationDampingFraction)
          ) {
            selection = .yearly
          }
        }
      )
    }
    .padding(Spacing.xxs)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }

  @ViewBuilder
  private func toggleOption(
    title: String,
    isSelected: Bool,
    badge: String? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: Spacing.xxxs) {
        Text(title)
          .font(isSelected ? .tidexLabelStrong : .tidexLabel)
          .foregroundColor(isSelected ? .tidexTextPrimary : .tidexTextSecondary)

        if let badge {
          Text(badge)
            .font(.tidexMicro.bold())
            .foregroundColor(.tidexTextOnSuccess)
            .padding(.horizontal, Spacing.xxxs)
            .padding(.vertical, badgeVerticalPadding)
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
