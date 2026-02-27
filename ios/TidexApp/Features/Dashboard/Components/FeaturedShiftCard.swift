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
  let showJobIndicator: Bool
  let jobName: String?
  let jobColorHex: String?
  /// Progress through the shift (0-100), shows a subtle progress bar when provided (for active shifts)
  var progress: Double?
  /// Remaining seconds in the final countdown window for active shifts.
  var finalCountdownSeconds: Int? = nil
  /// When true, shows a "+" prefix and uses blue color for the amount (used in celebration overlay)
  var showIncreaseHighlight: Bool = false
  /// Whether footer text/badge under the card should be shown.
  var showFooter: Bool = true

  init(
    shift: ShiftWithComputations,
    isToday: Bool,
    isBestShift: Bool,
    countdownText: String?,
    showJobIndicator: Bool = false,
    jobName: String? = nil,
    jobColorHex: String? = nil,
    progress: Double? = nil,
    showIncreaseHighlight: Bool = false,
    showFooter: Bool = true
  ) {
    self.shift = shift
    self.isToday = isToday
    self.isBestShift = isBestShift
    self.countdownText = countdownText
    self.showJobIndicator = showJobIndicator
    self.jobName = jobName
    self.jobColorHex = jobColorHex
    self.progress = progress
    self.showIncreaseHighlight = showIncreaseHighlight
    self.showFooter = showFooter
  }

  @Environment(\.userCurrency) private var currency
  @Environment(\.layoutDirection) private var layoutDirection

  /// Animated progress value for smooth entrance animation
  @State private var animatedProgress: Double = 0

  // MARK: - Computed Properties

  private var showBreakdown: Bool {
    shift.taxEnabled && shift.taxAmount > 0
  }

  private var dateParts: ShiftCardDateParts {
    ShiftCardFormatter.dateParts(for: shift.shiftDate)
  }

  private func hasProgress(_ value: Double?) -> Bool {
    guard let value else { return false }
    return value >= 0 && value <= 100
  }

  /// Footer label shown below the card - "Best shift" or countdown text.
  private func footerText(countdown: String?) -> String? {
    isBestShift ? String(localized: .dashboardBestShift) : countdown
  }

  /// Badge color status for the featured shift countdown.
  private func countdownStatus(progress: Double?, at now: Date) -> ShiftPreviewStatus {
    if hasProgress(progress) {
      return .active
    }

    if Date.hasShiftEnded(
      shiftDate: shift.shiftDate,
      startTime: shift.startTime,
      endTime: shift.endTime,
      referenceDate: now
    ) {
      return .past
    }

    return .upcoming
  }

  private var isRTL: Bool {
    layoutDirection == .rightToLeft
  }

  private var maxJobBadgeWidth: CGFloat {
    96
  }

  private var shouldRenderJobBadge: Bool {
    showJobIndicator && (jobName?.isEmpty == false)
  }

  private var hasTrailingBottomContent: Bool {
    shouldRenderJobBadge || showBreakdown
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
    let displayedProgress = progress
    let displayedFooterText = footerText(countdown: countdownText)
    let status = countdownStatus(progress: displayedProgress, at: Date())

    VStack(spacing: Spacing.sm) {
      // Main card content
      ShiftCardContentLayout(centerTrailing: !hasTrailingBottomContent) {
        // Row 1: Day name and date
        HStack(spacing: Spacing.xxs) {
          Text(dateParts.weekday)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
          Text("·")
            .foregroundColor(.tidexTextMuted)
          Text(dateParts.dayMonth)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextMuted)
            .contentTransition(.numericText())
        }
        .animation(.spring(duration: 0.8, bounce: 0), value: dateParts.dayMonth)
      } leadingBottom: {
        // Row 2: Time range
        timeRangeLabel
      } trailingTop: {
        // Net/gross amount
        let displayAmount = shift.taxEnabled ? shift.netPay : shift.grossPay
        HStack(spacing: Spacing.xxxs) {
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
        if shouldRenderJobBadge, let jobName, !jobName.isEmpty {
          WorkplaceNameText(
            name: jobName,
            colorHex: jobColorHex,
            font: .tidexCaptionRegular,
            fallbackBadgeColor: .tidexBlue,
            badgeHorizontalPadding: Spacing.xs,
            badgeVerticalPadding: 2
          )
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: maxJobBadgeWidth, alignment: .trailing)
        } else if showBreakdown {
          // Breakdown (gross - tax) when tax enabled
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
        if hasProgress(displayedProgress) {
          GeometryReader { geometry in
            Rectangle()
              .fill(Color.tidexBlue.opacity(0.1))
              .frame(width: geometry.size.width * (animatedProgress / 100))
          }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
      .tidexCardShadow()
      .onChange(of: displayedProgress) { _, newValue in
        // Animate to new progress value
        withAnimation(.linear(duration: 1.0)) {
          animatedProgress = newValue ?? 0
        }
      }
      .onAppear {
        // Animate from 0 to current progress on appear (matches CSS animation)
        if hasProgress(displayedProgress) {
          withAnimation(.linear(duration: 1.0)) {
            animatedProgress = displayedProgress ?? 0
          }
        }
      }

      // Footer text below the card (countdown or "Best shift")
      // Uses fixed height to prevent layout shift during transitions
      if showFooter {
        Group {
          if let text = displayedFooterText {
            if isBestShift {
              HStack(spacing: Spacing.xxxs) {
                Image(systemName: "star.fill")
                  .font(.tidexCaptionRegular)
                  .foregroundColor(.tidexBlue)
                Text(text)
                  .font(.tidexLabel)
                  .foregroundColor(.tidexTextSecondary)
              }
            } else {
              ShiftCountdownBadge(
                text: text,
                status: status,
                finalCountdownSeconds: finalCountdownSeconds
              )
            }
          } else {
            // Skeleton placeholder bar matching other empty states
            RoundedRectangle(cornerRadius: CornerRadius.xxs)
              .fill(Color.tidexTextMuted.opacity(0.3))
              .frame(width: 80, height: 14)
          }
        }
        .frame(height: 20)  // Fixed height prevents vertical jerk
      }
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
