import SwiftUI

struct WorkSetupRequiredPlaceholder: View {
  @EnvironmentObject private var coordinator: AppCoordinator

  var body: some View {
    VStack(spacing: Spacing.mlg) {
      Spacer()

      Image(systemName: "briefcase.badge.plus")
        .font(.system(size: 52, weight: .regular))
        .foregroundColor(.tidexBlue.opacity(0.8))

      VStack(spacing: Spacing.sm) {
        Text("work_setup.required.title", tableName: "Localizable")
          .font(.tidexTitle2)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.center)

        Text("work_setup.required.description", tableName: "Localizable")
          .font(.tidexBody)
          .foregroundColor(.tidexTextSecondary)
          .multilineTextAlignment(.center)
      }

      Button {
        coordinator.requestPostAuthOnboardingReentry()
      } label: {
        Text("work_setup.required.cta", tableName: "Localizable")
          .font(.tidexButton)
          .foregroundColor(.tidexTextOnBrand)
          .frame(maxWidth: .infinity)
          .frame(height: 54)
          .background(Color.tidexBrandPrimary)
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
      }
      .buttonStyle(.plain)

      Spacer()
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, Spacing.lg)
  }
}
