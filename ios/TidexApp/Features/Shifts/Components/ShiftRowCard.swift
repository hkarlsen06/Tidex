import SwiftUI

/// Card displaying a single shift in the shifts list
/// Design matches FeaturedShiftCard from the Dashboard
struct ShiftRowCard: View {
  let shift: ShiftWithComputations
  let isToday: Bool
  let hasConflict: Bool
  let excludedFromTotal: Bool
  let onTap: (() -> Void)?

  @Environment(\.userCurrency) private var currency
  @Environment(\.layoutDirection) private var layoutDirection

  // Convenience initializer without conflict props
  init(
    shift: ShiftWithComputations,
    isToday: Bool,
    hasConflict: Bool = false,
    excludedFromTotal: Bool = false,
    onTap: (() -> Void)? = nil
  ) {
    self.shift = shift
    self.isToday = isToday
    self.hasConflict = hasConflict
    self.excludedFromTotal = excludedFromTotal
    self.onTap = onTap
  }

  // MARK: - Computed Properties

  private var showBreakdown: Bool {
    shift.taxEnabled && shift.taxAmount > 0
  }

  private var dateParts: ShiftCardDateParts {
    ShiftCardFormatter.dateParts(for: shift.shiftDate)
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
    ShiftCardContentLayout(centerTrailing: !showBreakdown && !excludedFromTotal) {
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
      }
    } leadingBottom: {
      // Row 2: Time range
      timeRangeLabel
    } trailingTop: {
      // Net/gross amount
      let displayAmount = shift.taxEnabled ? shift.netPay : shift.grossPay
      Text(formatCurrency(displayAmount))
        .font(.tidexTitle)
        .tracking(-0.5)
        .foregroundColor(excludedFromTotal ? .tidexTextMuted : .tidexTextPrimary)
        .strikethrough(excludedFromTotal, color: .tidexTextMuted)
    } trailingBottom: {
      // When excluded from total, show excluded label instead of breakdown
      if excludedFromTotal {
        Text(.shiftsExcludedFromTotal)
          .font(.tidexMicro)
          .foregroundColor(.tidexWarning)
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
    .padding(.vertical, Spacing.mlg)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .fill(hasConflict ? Color.tidexWarning.opacity(0.08) : Color.tidexSurfacePrimary)
    )
    .overlay(
      // Border: today (blue), conflict (orange), or none
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .strokeBorder(
          isToday ? Color.tidexBlue : (hasConflict ? Color.tidexWarning.opacity(0.5) : Color.clear),
          lineWidth: isToday ? 2 : (hasConflict ? 1 : 0)
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
}

// Preview disabled - requires full app context
// #Preview {
//     ShiftRowCard(shift: mockShift, isToday: true, onTap: nil)
// }
