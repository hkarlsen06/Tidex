import SwiftUI

/// Card displaying previous month's earnings and payroll information
/// Design matches NextPayrollCard from the Next.js app
struct PayrollCard: View {
  let payrollDate: Date
  let label: String
  let gross: Double
  let net: Double?
  let tax: Double?
  let taxEnabled: Bool
  /// Progress through the month until payroll (0-100), shows a subtle progress bar when provided
  var progress: Double?
  /// When true, shows skeleton state with shimmer animation (for loading)
  var isLoading: Bool = false

  @Environment(\.userCurrency) private var currency

  /// Animated progress value for smooth entrance animation
  @State private var animatedProgress: Double = 0

  // MARK: - Computed Properties

  private var isPayrollToday: Bool {
    Calendar.current.isDateInToday(payrollDate)
  }

  private var showBreakdown: Bool {
    taxEnabled && (tax ?? 0) > 0
  }

  private var hasPayout: Bool {
    !isLoading && gross > 0
  }

  // MARK: - Body

  /// Whether to show the progress bar (valid progress between 1-100)
  private var hasProgress: Bool {
    guard let progress = progress else { return false }
    return progress >= 1 && progress <= 100
  }

  var body: some View {
    ShiftCardContentLayout(centerTrailing: hasPayout && !showBreakdown) {
      // Row 1: Label (leads with purpose, matches shift card title size)
      Text(label)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)
    } leadingBottom: {
      // Row 2: Banknote icon + payroll date (secondary)
      if isPayrollToday {
        HStack(spacing: Spacing.xxxs) {
          Image(systemName: "banknote")
            .font(.tidexLabel)
            .foregroundColor(.tidexBlue)
          Text(.dashboardToday)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)
          Image(systemName: "party.popper.fill")
            .font(.tidexFootnote)
            .foregroundColor(.tidexBlue)
        }
      } else {
        HStack(spacing: Spacing.xxs) {
          Image(systemName: "banknote")
            .font(.tidexLabel)
            .foregroundColor(.tidexBlue)
          Text(dateParts.dayName)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)
          Text("·")
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextMuted)
          HStack(spacing: 0) {
            Text(dateParts.dayNumber)
              .contentTransition(.numericText())
            Text(" ")
            Text(dateParts.monthName)
          }
          .font(.tidexLabel)
          .foregroundColor(.tidexTextMuted)
        }
        .animation(.spring(duration: 0.8, bounce: 0), value: dateParts.dayNumber)
      }
    } trailingTop: {
      // Right side: amount
      if hasPayout {
        let primaryAmount = taxEnabled ? (net ?? gross) : gross
        CurrencyCountUpText(
          amount: primaryAmount,
          duration: 0.8,
          animateOnAppear: true,
          animateChanges: true
        )
        .font(.tidexTitle)
        .tracking(-0.5)
        .foregroundColor(.tidexTextPrimary)
      } else {
        RoundedRectangle(cornerRadius: CornerRadius.xs)
          .fill(Color.tidexTextMuted.opacity(0.3))
          .frame(width: 100, height: 20)
      }
    } trailingBottom: {
      // Breakdown (gross - tax) when tax enabled
      if hasPayout && showBreakdown {
        HStack(spacing: Spacing.xxs) {
          Text(formatPlainAmount(gross))
            .contentTransition(.numericText(value: gross))
          Text("−")
          Text(formatPlainAmount(tax ?? 0))
            .contentTransition(.numericText(value: tax ?? 0))
        }
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
        .animation(.spring(duration: 0.8, bounce: 0), value: gross)
        .animation(.spring(duration: 0.8, bounce: 0), value: tax)
      } else if !hasPayout {
        RoundedRectangle(cornerRadius: CornerRadius.xxs)
          .fill(Color.tidexTextMuted.opacity(0.2))
          .frame(width: 70, height: 12)
      }
    }
    .padding(.horizontal, Spacing.mlg)
    .padding(.vertical, Spacing.lg)
    .background(Color.tidexSurfacePrimary)
    .overlay(alignment: .leading) {
      // Progress bar overlay - fills from left based on progress
      // Uses Rectangle instead of RoundedRectangle so small widths don't overflow
      // The clipShape on the parent handles the rounded corners
      // Always rendered (width 0 is invisible) so animatedProgress can animate to zero
      // when navigating away from the current month
      GeometryReader { geometry in
        Rectangle()
          .fill(Color.tidexBlue.opacity(0.1))
          .frame(width: geometry.size.width * (animatedProgress / 100))
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
    .tidexCardShadow()
    .shimmer(isActive: isLoading)
    .onChange(of: progress) { _, newValue in
      // Animate to new progress value
      withAnimation(.linear(duration: 1.0)) {
        animatedProgress = newValue ?? 0
      }
    }
    .onAppear {
      // Animate from 0 to current progress on appear (matches CSS animation)
      if let progress = progress, progress >= 1, progress <= 100 {
        withAnimation(.linear(duration: 1.0)) {
          animatedProgress = progress
        }
      }
    }
  }

  // MARK: - Formatting

  private var dateParts: ShiftCardDateParts {
    ShiftCardFormatter.dateParts(
      for: payrollDate.toISODateString(),
      locale: Locale.appLocale
    )
  }

  private func formatCurrency(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }

  /// Format amount without currency symbol (for breakdown display)
  private func formatPlainAmount(_ amount: Double) -> String {
    CurrencyConfig.formatPlain(amount)
  }
}

#Preview {
  VStack(spacing: Spacing.sm) {
    // With tax and progress bar
    PayrollCard(
      payrollDate: Date(),
      label: "Neste utbetaling",
      gross: 15800,
      net: 12500,
      tax: 3300,
      taxEnabled: true,
      progress: 65
    )

    // Without tax, no progress
    PayrollCard(
      payrollDate: Date(),
      label: "Forrige utbetaling",
      gross: 22000,
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
