import SwiftUI

/// A row displaying a shared shift (read-only, may have hidden earnings)
struct SharedShiftRow: View {
  let shift: ShiftWithComputations
  let isToday: Bool
  let showEarnings: Bool
  let currency: String

  @Environment(\.layoutDirection) private var layoutDirection

  // MARK: - Computed Properties

  private var formattedHours: String {
    ShiftCardFormatter.formattedHours(shift.paidHours, locale: Locale.appLocale)
  }

  private var dateParts: ShiftCardDateParts {
    ShiftCardFormatter.dateParts(for: shift.shiftDate)
  }

  // MARK: - Body

  var body: some View {
    HStack(alignment: .center, spacing: Spacing.md) {
      // Left side: date and time info
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        // Day name and date
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
        .fixedSize(horizontal: true, vertical: false)

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

      Spacer()

      // Right side: earnings or hidden indicator
      if showEarnings {
        earningsView
      } else {
        hiddenEarningsIndicator
      }
    }
    .padding(.horizontal, Spacing.mlg)
    .padding(.vertical, Spacing.mlg)
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
    .tidexCardShadow()
  }

  @ViewBuilder
  private var earningsView: some View {
    VStack(alignment: .trailing, spacing: Spacing.micro) {
      let displayAmount = shift.taxEnabled ? shift.netPay : shift.grossPay
      Text(formatCurrency(displayAmount))
        .font(.tidexTitle)
        .tracking(-0.5)
        .foregroundColor(.tidexTextPrimary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)

      // Show gross - tax breakdown if tax enabled
      if shift.taxEnabled, shift.taxAmount > 0 {
        HStack(spacing: Spacing.xxs) {
          Text(formatPlainAmount(shift.grossPay))
          Text("−")
          Text(formatPlainAmount(shift.taxAmount))
        }
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextMuted)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
      }
    }
    .fixedSize(horizontal: true, vertical: false)
    .layoutPriority(2)
  }

  private var hiddenEarningsIndicator: some View {
    HStack(spacing: Spacing.xxxs) {
      Image(systemName: "eye.slash.fill")
        .font(.tidexSubheadline)
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
      .lineLimit(1)
      .minimumScaleFactor(0.85)
      .environment(\.layoutDirection, .leftToRight)
  }

  private var clockIcon: some View {
    Image(systemName: "clock")
      .font(.tidexFootnote)
      .foregroundColor(.tidexTextMuted)
  }

}

#Preview {
  VStack(spacing: Spacing.sm) {
    // With earnings visible
    SharedShiftRow(
      shift: ShiftWithComputations(
        shift: ShiftRow(
          id: "1",
          user_id: "owner",
          shift_date: "2025-01-18",
          start_time: "09:00",
          end_time: "17:00",
          custom_supplements: nil
        ),
        computed: ShiftComputed(
          id: "1",
          durationHours: 8,
          paidHours: 7.5,
          basePay: 1_500,
          supplementPay: 200,
          gross: 1_700,
          wagePeriods: [],
          originalWagePeriods: [],
          breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
        ),
        taxEnabled: false,
        taxPercentage: 0
      ),
      isToday: true,
      showEarnings: true,
      currency: "kr"
    )

    // With earnings hidden
    SharedShiftRow(
      shift: ShiftWithComputations(
        shift: ShiftRow(
          id: "2",
          user_id: "owner",
          shift_date: "2025-01-19",
          start_time: "08:00",
          end_time: "16:00",
          custom_supplements: nil
        ),
        computed: ShiftComputed(
          id: "2",
          durationHours: 8,
          paidHours: 8,
          basePay: 1_600,
          supplementPay: 0,
          gross: 1_600,
          wagePeriods: [],
          originalWagePeriods: [],
          breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
        ),
        taxEnabled: false,
        taxPercentage: 0
      ),
      isToday: false,
      showEarnings: false,
      currency: "kr"
    )
  }
  .padding()
  .background(Color.tidexBackground)
  .environment(\.userCurrency, "kr")
}
