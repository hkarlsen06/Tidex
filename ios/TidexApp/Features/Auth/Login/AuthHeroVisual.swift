import SwiftUI

// MARK: - Shared Auth Hero Visual

struct AuthHeroVisual: View {
  let title: LocalizedStringResource
  let logoSize: CGFloat
  let currency: String
  var subtitle: LocalizedStringResource?
  /// The shift saved in the pre-auth demo. It replaces the sample paycheck card.
  var demoShift: PreAuthDemoShift?
  /// Shows a back button beside the logo. Nil on steps that keep their own back link.
  var onBack: (() -> Void)?

  var body: some View {
    VStack(spacing: Spacing.lg) {
      logoRow
      if let demoShift {
        AuthDemoShiftCard(shift: demoShift)
      } else {
        ghostedPaycheckPreview
      }
      Text(title)
        .font(.tidexTitle)
        .foregroundStyle(Color.tidexTextPrimary)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)

      if let subtitle {
        Text(subtitle)
          .font(.tidexBody)
          .foregroundStyle(Color.tidexTextSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, -Spacing.sm)
      }
    }
  }

  private var logoRow: some View {
    Image("TidexLogo")
      .resizable()
      .scaledToFit()
      .frame(width: min(logoSize, Spacing.huge), height: min(logoSize, Spacing.huge))
      .accessibilityHidden(true)
      .frame(maxWidth: .infinity)
      .overlay(alignment: .leading) {
        if let onBack {
          PreAuthBackButton(action: onBack)
            .transition(.opacity)
        }
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

    card.accessibilityHidden(true)
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

/// The demo shift on the sign-up screen: its dates and times.
private struct AuthDemoShiftCard: View {
  let shift: PreAuthDemoShift

  private var datesText: String {
    shift.dates.compactMap { Date.fromISODateString($0) }
      .map { $0.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.appLocale)) }
      .formatted(.list(type: .and).locale(.appLocale))
  }

  var body: some View {
    VStack(spacing: Spacing.xxs) {
      Text(verbatim: datesText)
        .font(.tidexHeadline)
        .foregroundStyle(Color.tidexTextPrimary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      Text(
        verbatim: ShiftCardFormatter.localizedTimeRange(
          start: shift.startTime, end: shift.endTime, locale: .appLocale))
        .font(.tidexAmountLarge)
        .monospacedDigit()
        .foregroundStyle(Color.tidexBlueText)
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.mlg)
    .frame(minWidth: 280)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
        .stroke(Color.tidexSeparator, lineWidth: 1)
    )
    .accessibilityElement(children: .combine)
  }
}

/// The chevron pill that leaves a pre-auth or auth screen for the previous page.
struct PreAuthBackButton: View {
  let action: () -> Void

  var body: some View {
    Button {
      Haptics.play(.light)
      action()
    } label: {
      Image(systemName: "chevron.left")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.tidexTextSecondary)
        .accessibilityHidden(true)
        .frame(width: 46, height: 34)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(SnappyButtonStyle())
    .accessibilityLabel(Text(.commonBack))
    .accessibilityIdentifier("auth.back")
  }
}
