import SwiftUI

// MARK: - Billing Toggle

/// Segmented control for selecting monthly vs yearly billing
/// Shows savings percentage for yearly option
struct BillingToggle: View {
    @Environment(\.localization) private var localization
    @Binding var selection: BillingPeriod
    var yearlySavingsPercent: Int?

    var body: some View {
        HStack(spacing: 0) {
            // Monthly option
            toggleOption(
                title: AuthStrings.string("paywall.monthly", locale: localization.currentLocale),
                isSelected: selection == .monthly
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selection = .monthly
                }
            }

            // Yearly option with savings badge
            toggleOption(
                title: AuthStrings.string("paywall.yearly", locale: localization.currentLocale),
                badge: yearlySavingsPercent.map { String(format: AuthStrings.string("paywall.savePercent", locale: localization.currentLocale), $0) },
                isSelected: selection == .yearly
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selection = .yearly
                }
            }
        }
        .padding(4)
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func toggleOption(
        title: String,
        badge: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .tidexTextPrimary : .tidexTextSecondary)

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.tidexSuccess)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                isSelected
                    ? Color.tidexBackground
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        BillingToggle(selection: .constant(.monthly), yearlySavingsPercent: 17)
        BillingToggle(selection: .constant(.yearly), yearlySavingsPercent: 17)
        BillingToggle(selection: .constant(.monthly), yearlySavingsPercent: nil)
    }
    .padding()
    .background(Color.tidexBackground)
}
