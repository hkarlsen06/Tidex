import SwiftUI

/// A row displaying a shared shift (read-only, may have hidden earnings)
struct SharedShiftRow: View {
  let shift: ShiftWithComputations
  let isToday: Bool
  let showEarnings: Bool
  let currency: String

  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var isStacked: Bool {
    dynamicTypeSize.isAccessibilitySize
  }

  // MARK: - Computed Properties

  private var formattedHours: String {
    ShiftCardFormatter.formattedHours(shift.paidHours, locale: Locale.appLocale)
  }

  private var dateParts: ShiftCardDateParts {
    ShiftCardFormatter.dateParts(for: shift.shiftDate)
  }

  // MARK: - Body

  var body: some View {
    // Date, times and amount stack at accessibility sizes, where fixed-width rows would clip.
    let layout =
      isStacked
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
      : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.md))

    layout {
      // Left side: date and time info
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        // Day name and date
        HStack(spacing: Spacing.xxs) {
          Text(dateParts.weekday)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
          Text("·")
            .foregroundColor(.tidexTextMuted)
            .accessibilityHidden(true)
          Text(dateParts.dayMonth)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextMuted)
        }
        .fixedSize(horizontal: !isStacked, vertical: false)

        // Time range and hours
        HStack(spacing: Spacing.xs) {
          if isRTL {
            timeRangeLabel
          } else {
            timeRangeLabel
          }
        }
        .environment(\.layoutDirection, .leftToRight)
      }

      if !isStacked {
        Spacer()
      }

      // Right side: earnings or hidden indicator
      if showEarnings {
        earningsView
      } else {
        hiddenEarningsIndicator
      }
    }
    .padding(.horizontal, Spacing.mlg)
    .padding(.vertical, Spacing.mlg)
    .accessibilityElement(children: .combine)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .strokeBorder(
          isToday ? Color.tidexBlue : Color.clear,
          lineWidth: isToday ? 2 : 0
        )
    )
  }

  @ViewBuilder
  private var earningsView: some View {
    VStack(alignment: isStacked ? .leading : .trailing, spacing: Spacing.micro) {
      let displayAmount = shift.taxEnabled ? shift.netPay : shift.grossPay
      Text(formatCurrency(displayAmount))
        .font(.tidexTitle)
        .tracking(-0.5)
        .foregroundColor(.tidexTextPrimary)
        .lineLimit(isStacked ? nil : 1)
        .fixedSize(horizontal: !isStacked, vertical: false)

      // Show gross - tax breakdown if tax enabled
      if shift.taxEnabled, shift.taxAmount > 0 {
        HStack(spacing: Spacing.xxs) {
          Text(formatPlainAmount(shift.grossPay))
          Text("−")
          Text(formatPlainAmount(shift.taxAmount))
        }
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextMuted)
        .lineLimit(isStacked ? nil : 1)
        .fixedSize(horizontal: !isStacked, vertical: false)
      }
    }
    .fixedSize(horizontal: !isStacked, vertical: false)
    .layoutPriority(2)
  }

  private var hiddenEarningsIndicator: some View {
    HStack(spacing: Spacing.xxxs) {
      Image(systemName: "eye.slash.fill")
        .font(.tidexSubheadline)
        .accessibilityHidden(true)
      Text(.sharingHidden)
        .font(.tidexLabel)
    }
    .foregroundColor(.tidexTextMuted)
  }

  // MARK: - Formatting

  private func formatCurrency(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }

  private func formatPlainAmount(_ amount: Double) -> String {
    CurrencyConfig.formatPlain(amount)
  }

  private var isRTL: Bool {
    layoutDirection == .rightToLeft
  }

  private var timeRangeText: String {
    ShiftCardFormatter.localizedTimeRange(
      start: shift.startTime,
      end: shift.endTime,
      locale: Locale.appLocale
    )
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
      .lineLimit(isStacked ? nil : 1)
      .minimumScaleFactor(isStacked ? 1 : 0.85)
      .environment(\.layoutDirection, .leftToRight)
  }

  private var clockIcon: some View {
    Image(systemName: "clock")
      .font(.tidexFootnote)
      .foregroundColor(.tidexTextMuted)
      .accessibilityHidden(true)
  }

}

private func previewShift(
  id: String,
  date: String,
  times: (start: String, end: String),
  paidHours: Double,
  supplementPay: Double
) -> ShiftWithComputations {
  let basePay = paidHours * 200
  return ShiftWithComputations(
    shift: ShiftRow(
      id: id,
      user_id: "owner",
      shift_date: date,
      start_time: times.start,
      end_time: times.end,
      custom_supplements: nil
    ),
    computed: ShiftComputed(
      id: id,
      durationHours: 8,
      paidHours: paidHours,
      basePay: basePay,
      supplementPay: supplementPay,
      gross: basePay + supplementPay,
      wagePeriods: [],
      originalWagePeriods: [],
      breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
    ),
    taxEnabled: false,
    taxPercentage: 0
  )
}

#Preview {
  VStack(spacing: Spacing.sm) {
    // With earnings visible
    SharedShiftRow(
      shift: previewShift(
        id: "1", date: "2025-01-18", times: ("09:00", "17:00"), paidHours: 7.5, supplementPay: 200),
      isToday: true,
      showEarnings: true,
      currency: "kr"
    )

    // With earnings hidden
    SharedShiftRow(
      shift: previewShift(
        id: "2", date: "2025-01-19", times: ("08:00", "16:00"), paidHours: 8, supplementPay: 0),
      isToday: false,
      showEarnings: false,
      currency: "kr"
    )
  }
  .padding()
  .background(Color.tidexBackground)
  .environment(\.userCurrency, "kr")
}
