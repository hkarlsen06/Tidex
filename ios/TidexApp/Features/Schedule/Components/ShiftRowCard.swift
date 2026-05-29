import SwiftUI

/// Card displaying a single shift in the shifts list
/// Design matches FeaturedShiftCard from the Dashboard
struct ShiftRowCard: View {
  let shift: ShiftWithComputations
  let isToday: Bool
  let hasConflict: Bool
  let excludedFromTotal: Bool
  let isDeepLinkHighlighted: Bool
  let showJobIndicator: Bool
  let jobName: String?
  let jobColorHex: String?
  let amountTextOverride: String?
  let onTap: (() -> Void)?

  @Environment(\.userCurrency) private var currency
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  // Convenience initializer without conflict props
  init(
    shift: ShiftWithComputations,
    isToday: Bool,
    hasConflict: Bool = false,
    excludedFromTotal: Bool = false,
    isDeepLinkHighlighted: Bool = false,
    showJobIndicator: Bool = false,
    jobName: String? = nil,
    jobColorHex: String? = nil,
    amountTextOverride: String? = nil,
    onTap: (() -> Void)? = nil
  ) {
    self.shift = shift
    self.isToday = isToday
    self.hasConflict = hasConflict
    self.excludedFromTotal = excludedFromTotal
    self.isDeepLinkHighlighted = isDeepLinkHighlighted
    self.showJobIndicator = showJobIndicator
    self.jobName = jobName
    self.jobColorHex = jobColorHex
    self.amountTextOverride = amountTextOverride
    self.onTap = onTap
  }

  // MARK: - Computed Properties

  private var showBreakdown: Bool {
    shift.taxEnabled && shift.taxAmount > 0
  }

  private var shouldRenderJobBadge: Bool {
    showJobIndicator && (jobName?.isEmpty == false)
  }

  private var hasTrailingBottomContent: Bool {
    excludedFromTotal || shouldRenderJobBadge || showBreakdown
  }

  private var dateParts: ShiftCardDateParts {
    ShiftCardFormatter.dateParts(for: shift.shiftDate)
  }

  private var isRTL: Bool {
    layoutDirection == .rightToLeft
  }

  private var maxJobBadgeWidth: CGFloat {
    96
  }

  private var timeRangeText: String {
    return ShiftCardFormatter.localizedTimeRange(
      start: shift.startTime,
      end: shift.endTime,
      locale: Locale.appLocale
    )
  }

  private var usesFixedCardHeight: Bool {
    !dynamicTypeSize.isAccessibilitySize
  }

  // MARK: - Body

  var body: some View {
    // Use a simple view with tap gesture instead of Button
    // Button adds its own gesture recognizer that conflicts with SwipeableShiftCard
    cardContent
      .contentShape(RoundedRectangle(cornerRadius: CornerRadius.card))
      .onTapGesture {
        onTap?()
      }
  }

  /// The card's visual content (extracted for cleaner code)
  @ViewBuilder
  private var cardContent: some View {
    ShiftCardContentLayout(centerTrailing: !hasTrailingBottomContent) {
      // Row 1: Day name and date
      HStack(spacing: Spacing.xs) {
        HStack(spacing: Spacing.xxs) {
          Text(dateParts.weekday)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
          Text("·")
            .foregroundColor(.tidexTextMuted)
          Text(dateParts.dayMonth)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextMuted)
        }

        if isToday {
          Text(.commonToday)
            .font(.tidexMicro)
            .foregroundColor(.tidexBlue)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.micro)
            .background(Color.tidexBlue.opacity(0.12))
            .clipShape(Capsule())
        }
      }
    } leadingBottom: {
      // Row 2: Time range
      timeRangeLabel
    } trailingTop: {
      // Net/gross amount
      let displayAmount = shift.taxEnabled ? shift.netPay : shift.grossPay
      Text(amountTextOverride ?? formatCurrency(displayAmount))
        .font(.tidexTitle)
        .foregroundColor(excludedFromTotal ? .tidexTextMuted : .tidexTextPrimary)
        .strikethrough(excludedFromTotal, color: .tidexTextMuted)
    } trailingBottom: {
      // When excluded from total, show excluded label instead of breakdown
      if excludedFromTotal {
        Text(.shiftsExcludedFromTotal)
          .font(.tidexMicro)
          .foregroundColor(.tidexWarning)
      } else if shouldRenderJobBadge, let jobName, !jobName.isEmpty {
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
          Text("−")
          Text(formatPlainAmount(shift.taxAmount))
        }
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
      }
    }
    .padding(.horizontal, Spacing.mlg)
    .padding(.vertical, ShiftCardMetrics.verticalPadding)
    .frame(minHeight: usesFixedCardHeight ? ShiftCardMetrics.regularCardMinHeight : nil)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .fill(
          isDeepLinkHighlighted
            ? Color.tidexPurple.opacity(0.12)
            : (hasConflict ? Color.tidexWarning.opacity(0.08) : Color.tidexSurfacePrimary)
        )
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .strokeBorder(
          rowBorderColor,
          lineWidth: rowBorderWidth
        )
    )
    .tidexCardShadow()
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
        statusIcon
      } else {
        statusIcon
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

  private var statusIcon: some View {
    Group {
      if hasConflict {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.tidexWarning)
      } else {
        Image(systemName: "clock")
          .foregroundColor(.tidexTextMuted)
      }
    }
    .font(.tidexFootnote)
  }

  private var rowBorderColor: Color {
    if isDeepLinkHighlighted { return .tidexPurple }
    if isToday { return .tidexBlue }
    if hasConflict { return .tidexWarning.opacity(0.5) }
    return .clear
  }

  private var rowBorderWidth: CGFloat {
    if isDeepLinkHighlighted { return 2.5 }
    if isToday { return 2 }
    if hasConflict { return 1 }
    return 0
  }

}

// Preview disabled - requires full app context
// #Preview {
//     ShiftRowCard(shift: mockShift, isToday: true, onTap: nil)
// }
