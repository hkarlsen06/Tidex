import SwiftUI

/// Card displaying a featured shift
/// - For current month: shows next upcoming shift with countdown
/// - For other months: shows best shift (highest earnings)
/// Design matches ShiftCard from the Next.js app
struct FeaturedShiftCard: View {
  let shift: ShiftWithComputations
  let isToday: Bool
  let isBestShift: Bool  // true = showing best shift, false = showing next shift
  let countdownText: String?  // Countdown text shown below the card
  /// Progress through the shift (0-100), shows a subtle progress bar when provided (for active shifts)
  var progress: Double?
  /// When true, shows a "+" prefix and uses blue color for the amount (used in celebration overlay)
  var showIncreaseHighlight: Bool = false

  @Environment(\.userCurrency) private var currency
  @Environment(\.layoutDirection) private var layoutDirection

  /// Animated progress value for smooth entrance animation
  @State private var animatedProgress: Double = 0

  // MARK: - Computed Properties

  private var showBreakdown: Bool {
    shift.taxEnabled && shift.taxAmount > 0
  }

  private var dateParts: ShiftCardDateParts {
    ShiftCardFormatter.dateParts(for: shift.shiftDate, locale: Locale.appLocale)
  }

  /// Footer label shown below the card - "Best shift" or countdown text
  private var footerText: String? {
    if isBestShift {
      return String(localized: .dashboardBestShift)
    }
    return countdownText
  }

  /// Whether to show the progress bar (valid progress between 0-100)
  private var hasProgress: Bool {
    guard let progress = progress else { return false }
    return progress >= 0 && progress <= 100
  }

  private var isRTL: Bool {
    layoutDirection == .rightToLeft
  }

  private var timeRangeText: String {
    return ShiftCardFormatter.localizedTimeRange(
      start: shift.startTime,
      end: shift.endTime,
      locale: Locale.appLocale
    )
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: Spacing.xs) {
      // Main card content
      ShiftCardContentLayout(centerTrailing: !showBreakdown) {
        // Row 1: Day name and date
        HStack(spacing: Spacing.xxs) {
          Text(dateParts.dayName)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
          Text("·")
            .foregroundColor(.tidexTextMuted)
          HStack(spacing: Spacing.xxs) {
            Text(dateParts.dayNumber)
              .contentTransition(.numericText())
            Text(dateParts.monthName)
          }
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextMuted)
        }
        .animation(.spring(duration: 0.8, bounce: 0), value: dateParts.dayNumber)
      } leadingBottom: {
        // Row 2: Time range
        timeRangeLabel
      } trailingTop: {
        // Net/gross amount
        let displayAmount = shift.taxEnabled ? shift.netPay : shift.grossPay
        HStack(spacing: 2) {
          if showIncreaseHighlight {
            Text("+")
              .font(.tidexTitle)
              .tracking(-0.5)
              .foregroundColor(.tidexBlue)
          }
          CurrencyCountUpText(
            amount: displayAmount,
            duration: 0.8,
            animateOnAppear: true,
            animateChanges: true
          )
          .font(.tidexTitle)
          .tracking(-0.5)
          .foregroundColor(showIncreaseHighlight ? .tidexBlue : .tidexTextPrimary)
        }
      } trailingBottom: {
        // Breakdown (gross - tax) when tax enabled
        if showBreakdown {
          HStack(spacing: Spacing.xxs) {
            Text(formatPlainAmount(shift.grossPay))
              .contentTransition(.numericText(value: shift.grossPay))
            Text("−")
            Text(formatPlainAmount(shift.taxAmount))
              .contentTransition(.numericText(value: shift.taxAmount))
          }
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextMuted)
          .animation(.spring(duration: 0.8, bounce: 0), value: shift.grossPay)
          .animation(.spring(duration: 0.8, bounce: 0), value: shift.taxAmount)
        }
      }
      .padding(.horizontal, Spacing.mlg)
      .padding(.vertical, Spacing.lg)
      .background(Color.tidexSurfacePrimary)
      .overlay(alignment: .leading) {
        // Progress bar overlay - fills from left based on progress (for active shifts)
        // Uses Rectangle instead of RoundedRectangle so small widths don't overflow
        // The clipShape on the parent handles the rounded corners
        if hasProgress {
          GeometryReader { geometry in
            Rectangle()
              .fill(Color.tidexBlue.opacity(0.1))
              .frame(width: geometry.size.width * (animatedProgress / 100))
          }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 24))
      .tidexCardShadow()
      .onChange(of: progress) { _, newValue in
        // Animate to new progress value
        withAnimation(.linear(duration: 1.0)) {
          animatedProgress = newValue ?? 0
        }
      }
      .onAppear {
        // Animate from 0 to current progress on appear (matches CSS animation)
        if let progress = progress, progress >= 0, progress <= 100 {
          withAnimation(.linear(duration: 1.0)) {
            animatedProgress = progress
          }
        }
      }

      // Footer text below the card (countdown or "Best shift")
      // Uses fixed height to prevent layout shift during transitions
      Group {
        if let text = footerText {
          HStack(spacing: 6) {
            if isBestShift {
              Image(systemName: "star.fill")
                .font(.tidexCaptionRegular)
                .foregroundColor(.tidexBlue)
            } else {
              Circle()
                .fill(hasProgress ? Color.green : (isToday ? Color.blue : Color.tidexTextMuted))
                .frame(width: 7, height: 7)
            }
            Text(text)
              .font(.tidexLabel)
              .foregroundColor(.tidexTextSecondary)
          }
        } else {
          // Skeleton placeholder bar matching other empty states
          RoundedRectangle(cornerRadius: 4)
            .fill(Color.tidexTextMuted.opacity(0.3))
            .frame(width: 80, height: 14)
        }
      }
      .frame(height: 20)  // Fixed height prevents vertical jerk
    }
  }

  // MARK: - Formatting

  private func formatCurrency(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }

  /// Format amount without currency symbol (for breakdown display)
  private func formatPlainAmount(_ amount: Double) -> String {
    CurrencyConfig.formatPlain(amount)
  }

  private var timeRangeLabel: some View {
    HStack(spacing: Spacing.xxs) {
      if isRTL {
        timeRangeTextLabel
        clockIcon
      } else {
        clockIcon
        timeRangeTextLabel
      }
    }
  }

  private var timeRangeTextLabel: some View {
    Text(timeRangeText)
      .font(.tidexSubheadline)
      .foregroundColor(.tidexTextPrimary)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .environment(\.layoutDirection, .leftToRight)
  }

  private var clockIcon: some View {
    Image(systemName: "clock")
      .font(.tidexSubheadline)
      .foregroundColor(.tidexTextMuted)
  }
}

// Preview disabled - requires full app context
// #Preview {
//     VStack(spacing: Spacing.md) {
//         FeaturedShiftCard(shift: mockShift, isToday: true, isBestShift: false)
//         FeaturedShiftCard(shift: mockShift, isToday: false, isBestShift: true)
//     }
// }
