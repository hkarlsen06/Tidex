import SwiftUI

// MARK: - Shared Auth Hero Visual

struct AuthHeroVisual: View {
  let title: LocalizedStringResource
  let logoSize: CGFloat
  let currency: String
  var onLogoTap: (() -> Void)?

  var body: some View {
    VStack(spacing: Spacing.lg) {
      logoSection
      ghostedPaycheckPreview
      Text(title)
        .font(.tidexTitle)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
    }
  }

  @ViewBuilder
  private var logoSection: some View {
    let content = Image("TidexLogo")
      .resizable()
      .scaledToFit()
      .frame(width: min(logoSize, Spacing.huge), height: min(logoSize, Spacing.huge))
      .accessibilityLabel(Text(verbatim: "Tidex"))

    if let onLogoTap {
      content
        .onTapGesture(perform: onLogoTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(.authRestartPreAuthOnboarding))
    } else {
      content
        .accessibilityHidden(true)
    }
  }

  private var ghostedAmountText: String {
    let hourlyWage = OnboardingCurrencyResolver.defaultHourlyWage(for: currency)
    let estimatedMonthlyHours = 162.0
    let estimatedNet = hourlyWage * estimatedMonthlyHours * 0.8
    return CurrencyConfig.format(estimatedNet, currency: currency)
  }

  @ViewBuilder
  private var ghostedPaycheckPreview: some View {
    let card = ZStack {
      VStack(spacing: Spacing.xs) {
        RoundedRectangle(cornerRadius: CornerRadius.xxs)
          .fill(Color.tidexTextMuted.opacity(0.2))
          .frame(width: 80, height: 8)

        Spacer().frame(height: 4)

        Text(ghostedAmountText)
          .font(.tidexAmountLarge)
          .foregroundStyle(Color.tidexTextPrimary)

        Spacer().frame(height: 8)

        ghostedRow(labelWidth: 80, valueWidth: 55)
        ghostedRow(labelWidth: 65, valueWidth: 50)
        ghostedRow(labelWidth: 90, valueWidth: 60)
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.mlg)
      .frame(width: 280)
      .background(heroCardBackground)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
          .stroke(Color.tidexSeparator, lineWidth: 1)
      )

    }

    if let onLogoTap {
      card
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
        .onTapGesture(perform: onLogoTap)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(.authRestartPreAuthOnboarding))
    } else {
      card.accessibilityHidden(true)
    }
  }

  private func ghostedRow(labelWidth: CGFloat, valueWidth: CGFloat) -> some View {
    HStack {
      RoundedRectangle(cornerRadius: 3)
        .fill(Color.tidexTextMuted.opacity(0.2))
        .frame(width: labelWidth, height: 6)
      Spacer()
      RoundedRectangle(cornerRadius: 3)
        .fill(Color.tidexTextMuted.opacity(0.2))
        .frame(width: valueWidth, height: 6)
    }
  }

  private var heroCardBackground: some View {
    Color.tidexSurfacePrimary
  }

}
