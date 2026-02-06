import SwiftUI

/// A row displaying a shared shift (read-only, may have hidden earnings)
struct SharedShiftRow: View {
  let shift: ShiftWithComputations
  let isToday: Bool
  let showEarnings: Bool

  @Environment(\.userCurrency) private var currency
  @Environment(\.layoutDirection) private var layoutDirection

  // MARK: - Computed Properties

  private var formattedHours: String {
    ShiftCardFormatter.formattedHours(shift.paidHours, locale: Locale.appLocale)
  }

  private var dateParts: (dayName: String, dayNumber: String, monthName: String) {
    guard let date = Date.fromISODateString(shift.shiftDate) else {
      return ("", "", "")
    }

    let locale = Locale.appLocale

    let dayName = FormatterCache.weekdayFormatter(locale: locale)
      .string(from: date)
      .capitalized

    let dayNumber = FormatterCache.dayFormatter(locale: locale)
      .string(from: date)

    let monthName = FormatterCache.shortMonthFormatter(locale: locale)
      .string(from: date)
      .lowercased()

    return (dayName, dayNumber, monthName)
  }

  // MARK: - Body

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      // Left side: date and time info
      VStack(alignment: .leading, spacing: 4) {
        // Day name and date
        HStack(spacing: 4) {
          Text(dateParts.dayName)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.tidexTextPrimary)
          Text("·")
            .foregroundColor(.tidexTextMuted)
          Text("\(dateParts.dayNumber) \(dateParts.monthName)")
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.tidexTextMuted)
        }
        .fixedSize(horizontal: true, vertical: false)

        // Time range and hours
        HStack(spacing: 8) {
          if isRTL {
            hoursLabel
            arrowLabel
            timeRangeLabel
          } else {
            timeRangeLabel
            arrowLabel
            hoursLabel
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
    .padding(.horizontal, 20)
    .padding(.vertical, 20)
    .background(
      RoundedRectangle(cornerRadius: 24)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 24)
        .strokeBorder(
          isToday ? Color.tidexBlue : Color.clear,
          lineWidth: isToday ? 2 : 0
        )
    )
    .tidexCardShadow()
  }

  @ViewBuilder
  private var earningsView: some View {
    VStack(alignment: .trailing, spacing: 2) {
      let displayAmount = shift.taxEnabled ? shift.netPay : shift.grossPay
      Text(formatCurrency(displayAmount))
        .font(.system(size: 22, weight: .semibold))
        .tracking(-0.5)
        .foregroundColor(.tidexTextPrimary)

      // Show gross - tax breakdown if tax enabled
      if shift.taxEnabled && shift.taxAmount > 0 {
        HStack(spacing: 4) {
          Text(formatCurrency(shift.grossPay))
          Text("−")
          Text(formatCurrency(shift.taxAmount))
        }
        .font(.system(size: 13, weight: .regular))
        .foregroundColor(.tidexTextMuted)
      }
    }
  }

  private var hiddenEarningsIndicator: some View {
    HStack(spacing: 6) {
      Image(systemName: "eye.slash.fill")
        .font(.system(size: 14))
      Text(.sharingHidden)
        .font(.system(size: 14, weight: .medium))
    }
    .foregroundColor(.tidexTextMuted)
  }

  // MARK: - Formatting

  private func formatCurrency(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
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
    HStack(spacing: 4) {
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
      .font(.system(size: 14, weight: .regular))
      .foregroundColor(.tidexTextPrimary)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .environment(\.layoutDirection, .leftToRight)
  }

  private var clockIcon: some View {
    Image(systemName: "clock")
      .font(.system(size: 13, weight: .regular))
      .foregroundColor(.tidexTextMuted)
  }

  private var hoursLabel: some View {
    Text(formattedHours)
      .font(.system(size: 14, weight: .medium))
      .foregroundColor(.tidexTextMuted)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
  }

  private var arrowLabel: some View {
    Text(isRTL ? "←" : "→")
      .font(.system(size: 14, weight: .medium))
      .foregroundColor(.tidexTextMuted)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
  }
}

#Preview {
  VStack(spacing: 12) {
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
          basePay: 1500,
          supplementPay: 200,
          gross: 1700,
          wagePeriods: [],
          originalWagePeriods: [],
          breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
        ),
        taxEnabled: false,
        taxPercentage: 0
      ),
      isToday: true,
      showEarnings: true
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
          basePay: 1600,
          supplementPay: 0,
          gross: 1600,
          wagePeriods: [],
          originalWagePeriods: [],
          breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
        ),
        taxEnabled: false,
        taxPercentage: 0
      ),
      isToday: false,
      showEarnings: false
    )
  }
  .padding()
  .background(Color.tidexBackground)
  .environment(\.userCurrency, "kr")
}
