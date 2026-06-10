import SwiftUI

/// Card displaying previous month's earnings and payroll information
/// Design matches NextPayrollCard from the Next.js app
struct PayrollCard: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  private static let centeredTrailingAmountOffset: CGFloat = 11

  let payrollDate: Date  // swiftlint:disable:this explicit_acl
  let label: String  // swiftlint:disable:this explicit_acl
  var labelColorHex: String?  // swiftlint:disable:this explicit_acl
  var labelIsWorkplace: Bool = false  // swiftlint:disable:this explicit_acl
  var workplaceBadges: [PayrollCardBadge] = []  // swiftlint:disable:this explicit_acl
  let gross: Double  // swiftlint:disable:this explicit_acl
  let net: Double?  // swiftlint:disable:this explicit_acl
  let tax: Double?  // swiftlint:disable:this explicit_acl
  let taxEnabled: Bool  // swiftlint:disable:this explicit_acl
  var hasPayrollAdjustments: Bool = false  // swiftlint:disable:this explicit_acl
  /// Progress through the month until payroll (0-100), shows a subtle progress bar when provided
  var progress: Double?  // swiftlint:disable:this explicit_acl
  /// When true, shows skeleton state with shimmer animation (for loading)
  var isLoading: Bool = false  // swiftlint:disable:this explicit_acl
  /// Allows transition placeholders to use the loading layout without starting shimmer.
  var showsLoadingShimmer: Bool = true  // swiftlint:disable:this explicit_acl

  @Environment(\.userCurrency) private var currency  // swiftlint:disable:this explicit_type_interface
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface
  @Environment(\.colorScheme) private var colorScheme  // swiftlint:disable:this explicit_type_interface

  /// Animated progress value for smooth entrance animation
  @State private var animatedProgress: Double = 0
  @State private var previousPrimaryAmount: Double?
  @State private var previousHasTrailingBottomContent: Bool?  // swiftlint:disable:this discouraged_optional_boolean

  // MARK: - Computed Properties

  private var isPayrollToday: Bool {
    Calendar.current.isDateInToday(payrollDate)
  }

  private var showBreakdown: Bool {
    taxEnabled && (tax ?? 0) > 0
  }

  private var hasPayoutData: Bool {
    gross > 0
  }

  private var showPayout: Bool {
    !isLoading && hasPayoutData
  }

  private var primaryAmount: Double {
    taxEnabled ? (net ?? gross) : gross
  }

  private var usesFixedCardHeight: Bool {
    !dynamicTypeSize.isAccessibilitySize
  }

  private var shouldCenterTrailingAmount: Bool {
    showPayout && !showBreakdown
  }

  // MARK: - Body

  /// Whether to show the progress bar (valid progress between 1-100)
  private var hasProgress: Bool {
    guard let progress else { return false }  // swiftlint:disable:this conditional_returns_on_newline
    return progress >= 1 && progress <= 100
  }

  var body: some View {  // swiftlint:disable:this explicit_acl
    ShiftCardContentLayout(topRowAlignment: .center) {
      // Row 1: Label (leads with purpose, matches shift card title size)
      payrollLabelContent
        .frame(maxWidth: .infinity, alignment: .leading)
    } leadingBottom: {
      // Row 2: Banknote icon + payroll date (secondary)
      if isPayrollToday {
        HStack(spacing: Spacing.xxxs) {
          Image(systemName: "banknote")  // swiftlint:disable:this accessibility_label_for_image
            .font(.tidexLabel)
            .foregroundColor(.tidexBlue)
          Text(.dashboardToday)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)
          Image(systemName: "party.popper.fill")  // swiftlint:disable:this accessibility_label_for_image
            .font(.tidexFootnote)
            .foregroundColor(.tidexBlue)
        }
      } else {
        HStack(spacing: Spacing.xxs) {
          Image(systemName: "banknote")  // swiftlint:disable:this accessibility_label_for_image
            .font(.tidexLabel)
            .foregroundColor(.tidexBlue)
          Text(dateParts.weekday)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)
          Text("·")
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextMuted)
          Text(dateParts.dayMonth)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextMuted)
            .contentTransition(.numericText())
        }
        .animation(.spring(duration: 0.8, bounce: 0), value: dateParts.dayMonth)  // swiftlint:disable:this line_length no_magic_numbers
      }
    } trailingTop: {  // swiftlint:disable:this closure_body_length
      // Right side: amount
      if showPayout {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
          CurrencyCountUpText(
            amount: primaryAmount,
            duration: 0.8,  // swiftlint:disable:this no_magic_numbers
            animateOnAppear: false,
            animateChanges: true,
            animateFrom: ShiftCardAmountAnimationFallback.animateFrom(
              previousAmount: previousPrimaryAmount,
              previousHasTrailingBottomContent: previousHasTrailingBottomContent,
              currentHasTrailingBottomContent: showBreakdown
            )
          )
          .font(.tidexTitle)

          if hasPayrollAdjustments {
            adjustmentMarker
              .font(.tidexSubheadline.weight(.semibold))
              .offset(y: -6)  // swiftlint:disable:this no_magic_numbers
              .accessibilityHidden(true)
          }
        }
        .foregroundColor(.tidexTextPrimary)
        .offset(y: shouldCenterTrailingAmount ? Self.centeredTrailingAmountOffset : 0)
      } else {
        ZStack {
          Text(verbatim: "00 000")
            .font(.tidexTitle)
            .opacity(0)

          RoundedRectangle(cornerRadius: CornerRadius.xs)
            .fill(Color.tidexTextMuted.opacity(0.3))  // swiftlint:disable:this no_magic_numbers
            .frame(width: 112, height: 24)  // swiftlint:disable:this no_magic_numbers
        }
      }
    } trailingBottom: {
      // Breakdown (gross - tax) when tax enabled
      if showPayout, showBreakdown {
        HStack(spacing: Spacing.xxs) {
          Text(formatPlainAmount(gross))
            .contentTransition(.numericText(value: gross))
          Text("−")
          Text(formatPlainAmount(tax ?? 0))
            .contentTransition(.numericText(value: tax ?? 0))
        }
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
        .animation(.spring(duration: 0.8, bounce: 0), value: gross)  // swiftlint:disable:this no_magic_numbers
        .animation(.spring(duration: 0.8, bounce: 0), value: tax)  // swiftlint:disable:this no_magic_numbers
      } else if !showPayout {
        ZStack {
          Text(verbatim: "00 000 − 00 000")
            .font(.tidexSubheadline)
            .opacity(0)

          RoundedRectangle(cornerRadius: CornerRadius.xxs)
            .fill(Color.tidexTextMuted.opacity(0.2))  // swiftlint:disable:this no_magic_numbers
            .frame(width: 84, height: 17)  // swiftlint:disable:this no_magic_numbers
        }
      }
    }
    .padding(.horizontal, Spacing.mlg)
    .padding(.vertical, ShiftCardMetrics.verticalPadding)
    .frame(minHeight: usesFixedCardHeight ? ShiftCardMetrics.regularCardMinHeight : nil)
    .background(Color.tidexSurfacePrimary)
    .overlay(alignment: .leading) {
      // Progress bar overlay - fills from left based on progress
      // Uses Rectangle instead of RoundedRectangle so small widths don't overflow
      // The clipShape on the parent handles the rounded corners
      // Always rendered (width 0 is invisible) so animatedProgress can animate to zero
      // when navigating away from the current month
      GeometryReader { geometry in
        Rectangle()
          .fill(progressFillColor)
          .frame(width: geometry.size.width * (animatedProgress / 100))
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
    .tidexCardShadow()
    .shimmer(isActive: isLoading && showsLoadingShimmer)
    .onChange(of: progress) { _, newValue in
      // Animate to new progress value
      withAnimation(.linear(duration: 1.0)) {
        animatedProgress = newValue ?? 0
      }
    }
    .onChange(of: primaryAmount) { _, newValue in
      previousPrimaryAmount = newValue
    }
    .onChange(of: showBreakdown) { _, newValue in
      previousHasTrailingBottomContent = newValue
    }
    .onAppear {
      previousPrimaryAmount = primaryAmount
      previousHasTrailingBottomContent = showBreakdown

      guard let progress, progress >= 1, progress <= 100 else {
        animatedProgress = 0
        return
      }

      // Animate from zero on appear so card re-mounts during month navigation
      // keep the same fill animation behavior as live month-to-month updates.
      withAnimation(.linear(duration: 1.0)) {
        animatedProgress = progress
      }
    }
  }

  // MARK: - Formatting

  private var dateParts: ShiftCardDateParts {
    ShiftCardFormatter.dateParts(for: payrollDate)
  }

  private func formatCurrency(_ amount: Double) -> String {  // swiftlint:disable:this type_contents_order
    CurrencyConfig.format(amount, currency: currency)
  }

  /// Format amount without currency symbol (for breakdown display)
  private func formatPlainAmount(_ amount: Double) -> String {  // swiftlint:disable:this type_contents_order
    CurrencyConfig.formatPlain(amount)
  }

  private var adjustmentMarker: Text {
    Text(verbatim: "*")
  }

  private var progressFillColor: Color {
    colorScheme == .light ? Color.tidexBlue.opacity(0.035) : Color.tidexBlue.opacity(0.1)  // swiftlint:disable:this line_length no_magic_numbers
  }

  @ViewBuilder
  private var payrollLabelContent: some View {
    if workplaceBadges.isEmpty {
      WorkplaceNameText(
        name: label,
        colorHex: labelColorHex,
        font: labelIsWorkplace ? .tidexCaptionRegular : .tidexBodyMedium,
        fallbackBadgeColor: labelIsWorkplace ? .tidexBlue : nil,
        badgeHorizontalPadding: Spacing.xs,
        badgeVerticalPadding: labelIsWorkplace ? 1 : Spacing.xxxs
      )
    } else {
      HStack(spacing: Spacing.micro) {
        ForEach(workplaceBadges) { badge in
          WorkplaceNameText(
            name: badge.title,
            colorHex: badge.colorHex,
            font: .tidexBodyMedium,
            fallbackBadgeColor: .tidexBlue,
            badgeHorizontalPadding: Spacing.xs,
            badgeVerticalPadding: 1
          )
        }
      }
      .lineLimit(1)
    }
  }

}

#Preview {
  VStack(spacing: Spacing.sm) {
    // With tax and progress bar
    PayrollCard(
      payrollDate: Date(),
      label: "Neste utbetaling",
      gross: 15_800,
      net: 12_500,
      tax: 3_300,
      taxEnabled: true,
      progress: 65
    )

    // Without tax, no progress
    PayrollCard(
      payrollDate: Date(),
      label: "Forrige utbetaling",
      gross: 22_000,
      net: nil,
      tax: nil,
      taxEnabled: false
    )

    // No earnings
    PayrollCard(
      payrollDate: Date(),
      label: "Neste utbetaling",
      gross: 0,
      net: nil,
      tax: nil,
      taxEnabled: false
    )
  }
  .padding(.horizontal, Spacing.lg)
  .background(Color.tidexBackground)
}
