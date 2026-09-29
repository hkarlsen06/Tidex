import SwiftUI

/// Card displaying previous month's earnings and payroll information
/// Design matches NextPayrollCard from the Next.js app
struct PayrollCard: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl type_body_length
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
  var isElevated: Bool = true  // swiftlint:disable:this explicit_acl
  /// Payday only: whether the user has marked this payout as received.
  var isMarkedReceived: Bool = false  // swiftlint:disable:this explicit_acl
  /// Payday only: toggles the received state. The button is hidden when nil.
  var onToggleReceived: (() -> Void)?  // swiftlint:disable:this explicit_acl

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface
  @Environment(\.colorScheme) private var colorScheme  // swiftlint:disable:this explicit_type_interface
  @Environment(\.accessibilityReduceMotion) private var reduceMotion  // swiftlint:disable:this explicit_type_interface

  /// Animated progress value for smooth entrance animation
  @State private var animatedProgress: Double = 0
  @State private var previousPrimaryAmount: Double?
  @State private var previousHasTrailingBottomContent: Bool?  // swiftlint:disable:this discouraged_optional_boolean

  // MARK: - Computed Properties

  private var isPayrollToday: Bool {
    Calendar.gregorianCurrent.isDateInToday(payrollDate)
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

  // MARK: - Body

  /// Whether to show the progress bar (valid progress between 1-100)
  private var hasProgress: Bool {
    guard let progress else { return false }  // swiftlint:disable:this conditional_returns_on_newline
    return progress >= 1 && progress <= 100
  }

  var body: some View {  // swiftlint:disable:this explicit_acl
    ShiftCardContentLayout(topRowAlignment: .center) {
      // Row 1: Label (leads with purpose, matches shift card title size)
      if isLoading {
        loadingLabelPlaceholder
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        payrollLabelContent
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    } leadingBottom: {  // swiftlint:disable:this closure_body_length
      // Row 2: Banknote icon + payroll date (secondary)
      if isLoading {
        loadingDatePlaceholder
      } else if isPayrollToday {
        HStack(spacing: Spacing.xxxs) {
          Image(systemName: "banknote")
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)
            .accessibilityHidden(true)
          Text(.dashboardToday)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)
          Image(systemName: "party.popper.fill")
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
            .accessibilityHidden(true)
        }
      } else {
        HStack(spacing: Spacing.xxs) {
          Image(systemName: "banknote")
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)
            .accessibilityHidden(true)
          Text(dateParts.weekday)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)
          Text("·")
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextMuted)
            .accessibilityHidden(true)
          Text(dateParts.dayMonth)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextMuted)
            .contentTransition(reduceMotion ? .identity : .numericText())
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0), value: dateParts.dayMonth)  // swiftlint:disable:this line_length no_magic_numbers
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
              currentHasTrailingBottomContent: showPayout
            )
          )
          .font(.tidexTitle)

          if hasPayrollAdjustments {
            Image(systemName: "plus.forwardslash.minus")
              .font(.tidexCaption)
              .foregroundColor(.tidexTextSecondary)
              .padding(.leading, Spacing.xxxs)
              .accessibilityLabel(Text(.dashboardPayrollCardIncludesAdjustments))
          }
        }
        .foregroundColor(.tidexTextPrimary)
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
      if showPayout, let onToggleReceived {
        receivedButton(action: onToggleReceived)
      } else if showPayout {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          Text(payrollCountdownText(at: context.date))
            .contentTransition(reduceMotion ? .identity : .numericText())
        }
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
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
    .padding(.horizontal, isElevated ? Spacing.mlg : 0)
    .padding(.vertical, ShiftCardMetrics.verticalPadding)
    .frame(minHeight: usesFixedCardHeight ? ShiftCardMetrics.regularCardMinHeight : nil)
    .overlay(alignment: .leading) {
      // Progress bar overlay - fills from left based on progress
      // Uses Rectangle instead of RoundedRectangle so small widths don't overflow
      // The clipShape on the parent handles the rounded corners
      if isElevated {
        GeometryReader { geometry in
          Rectangle()
            .fill(progressFillColor)
            .frame(width: geometry.size.width * (animatedProgress / 100))
        }
      }
    }
    .tidexRowSurface(
      cornerRadius: CornerRadius.card,
      fillColor: isElevated ? .tidexSurfacePrimary : .clear
    )
    .overlay(alignment: .bottomLeading) {
      if !isElevated, !isLoading, hasProgress {
        GeometryReader { geometry in
          Rectangle()
            .fill(Color.tidexBlue)
            .frame(
              width: geometry.size.width * (animatedProgress / 100),
              height: 3  // swiftlint:disable:this no_magic_numbers
            )
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
      }
    }
    .shimmer(isActive: isLoading && showsLoadingShimmer)
    .onChange(of: progress) { _, newValue in
      guard !isLoading else {
        animatedProgress = 0
        return
      }
      // Animate to new progress value
      withAnimation(reduceMotion ? nil : .linear(duration: 1.0)) {
        animatedProgress = newValue ?? 0
      }
    }
    .onChange(of: isLoading) { _, newValue in
      if newValue {
        animatedProgress = 0
      } else {
        withAnimation(reduceMotion ? nil : .linear(duration: 1.0)) {
          animatedProgress = progress ?? 0
        }
      }
    }
    .onChange(of: primaryAmount) { _, newValue in
      previousPrimaryAmount = newValue
    }
    .onChange(of: showPayout) { _, newValue in
      previousHasTrailingBottomContent = newValue
    }
    .onAppear {
      previousPrimaryAmount = primaryAmount
      previousHasTrailingBottomContent = showPayout

      guard !isLoading, let progress, progress >= 1, progress <= 100 else {
        animatedProgress = 0
        return
      }

      // Animate from zero on appear so card re-mounts during month navigation
      // keep the same fill animation behavior as live month-to-month updates.
      withAnimation(reduceMotion ? nil : .linear(duration: 1.0)) {
        animatedProgress = progress
      }
    }
  }

  // MARK: - Formatting

  private var dateParts: ShiftCardDateParts {
    ShiftCardFormatter.dateParts(for: payrollDate)
  }

  private func payrollCountdownText(at now: Date) -> String {  // swiftlint:disable:this type_contents_order
    Calendar.gregorianCurrent.isDate(payrollDate, inSameDayAs: now)
      ? String(localized: .commonToday)
      : CountdownFormatter.formatRelativeCountdown(referenceDate: payrollDate, now: now)
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
        lineLimit: dynamicTypeSize.isAccessibilitySize ? nil : 1,
        badgeHorizontalPadding: Spacing.xs,
        badgeVerticalPadding: labelIsWorkplace ? 1 : Spacing.xxxs
      )
    } else {
      let badgeLayout =  // swiftlint:disable:this explicit_type_interface
        dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.micro))
        : AnyLayout(HStackLayout(spacing: Spacing.micro))
      badgeLayout {
        ForEach(workplaceBadges) { badge in
          WorkplaceNameText(
            name: badge.title,
            colorHex: badge.colorHex,
            font: .tidexBodyMedium,
            fallbackBadgeColor: .tidexBlue,
            lineLimit: dynamicTypeSize.isAccessibilitySize ? nil : 1,
            badgeHorizontalPadding: Spacing.xs,
            badgeVerticalPadding: 1
          )
        }
      }
      .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    }
  }

}

extension PayrollCard {
  // Placeholder bars match EmptyShiftCard's loading layout
  fileprivate var loadingLabelPlaceholder: some View {
    ZStack(alignment: .leading) {
      Text(verbatim: "Monday · 31 Dec")
        .font(.tidexBodyMedium)
        .opacity(0)

      RoundedRectangle(cornerRadius: 5)  // swiftlint:disable:this no_magic_numbers
        .fill(Color.tidexTextMuted.opacity(0.3))  // swiftlint:disable:this no_magic_numbers
        .frame(width: 140, height: 20)  // swiftlint:disable:this no_magic_numbers
    }
  }

  fileprivate var loadingDatePlaceholder: some View {
    ZStack(alignment: .leading) {
      Text(verbatim: "Mon · 31 Dec")
        .font(.tidexLabel)
        .opacity(0)

      RoundedRectangle(cornerRadius: CornerRadius.xxs)
        .fill(Color.tidexTextMuted.opacity(0.2))  // swiftlint:disable:this no_magic_numbers
        .frame(width: 100, height: 17)  // swiftlint:disable:this no_magic_numbers
    }
  }

  fileprivate func receivedButton(action: @escaping () -> Void) -> some View {
    let tint: Color = isMarkedReceived ? .tidexSuccess : .tidexBlue  // swiftlint:disable:this explicit_type_interface
    let textTint: Color = isMarkedReceived ? .tidexSuccess : .tidexBlueText  // swiftlint:disable:this explicit_type_interface line_length
    return Button(action: action) {
      Label(
        isMarkedReceived
          ? String(localized: .dashboardPayrollMarkedReceived)
          : String(localized: .dashboardPayrollMarkReceived),
        systemImage: isMarkedReceived ? "checkmark.circle.fill" : "circle"
      )
      .font(.tidexLabel)
      .foregroundColor(textTint)
      .padding(.horizontal, Spacing.xs)
      .padding(.vertical, Spacing.xxxs)
      .background(Capsule(style: .continuous).fill(tint.opacity(0.12)))  // swiftlint:disable:this no_magic_numbers
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
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
