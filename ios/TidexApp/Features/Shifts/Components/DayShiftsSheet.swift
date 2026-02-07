import SwiftUI

/// A sheet showing all shifts for a specific day
/// Displayed when tapping a calendar day cell
struct DayShiftsSheet: View {
  let dateISO: String
  let shifts: [ShiftWithComputations]
  let onShiftTapped: (ShiftWithComputations) -> Void
  var excludedFromTotalIds: Set<String> = []

  @Environment(\.userCurrency) private var currency
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.dismiss) private var dismiss

  // MARK: - Computed Properties

  private var formattedDate: String {
    guard let date = Date.fromISODateString(dateISO) else {
      return dateISO
    }

    let formatter = DateFormatter()
    formatter.locale = Locale.appLocale
    formatter.dateFormat = "EEEE, d. MMMM"
    return formatter.string(from: date).capitalized
  }

  private var totalEarnings: Double {
    shifts.reduce(0) { total, shift in
      // Skip shifts excluded from totals
      guard !excludedFromTotalIds.contains(shift.id) else { return total }
      return total + (shift.taxEnabled ? shift.netPay : shift.grossPay)
    }
  }

  private var totalHours: Double {
    shifts.reduce(0) { total, shift in
      // Skip shifts excluded from totals
      guard !excludedFromTotalIds.contains(shift.id) else { return total }
      return total + shift.paidHours
    }
  }

  // MARK: - Body

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.md) {
          // Summary header
          summaryHeader

          // Shift cards
          VStack(spacing: Spacing.sm) {
            ForEach(shifts) { shift in
              shiftCard(shift)
            }
          }
        }
        .padding(Spacing.mlg)
      }
      .background(Color.tidexBackground)
      .navigationTitle(formattedDate)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(String(localized: .commonDone)) {
            dismiss()
          }
          .font(.tidexButton)
          .foregroundColor(.tidexBlue)
        }
      }
    }
  }

  // MARK: - Summary Header

  private var summaryHeader: some View {
    HStack(spacing: Spacing.lg) {
      // Total hours
      VStack(spacing: Spacing.xxs) {
        Text(formattedHours(totalHours))
          .font(.tidexLargeTitle)
          .foregroundColor(.tidexTextPrimary)
        Text(.shiftsDaySheetHours)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }

      // Divider
      Rectangle()
        .fill(Color.tidexBorder)
        .frame(width: 1, height: 40)

      // Total earnings
      VStack(spacing: Spacing.xxs) {
        Text(formatCurrency(totalEarnings))
          .font(.tidexLargeTitle)
          .foregroundColor(.tidexTextPrimary)
        Text(.shiftsDaySheetEarnings)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }

      Spacer()

      // Shift count badge
      Text("\(shifts.count)")
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexBlue)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxxs)
        .background(
          Capsule()
            .fill(Color.tidexBlue.opacity(0.1))
        )
    }
    .padding(Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xxl)
        .fill(Color.tidexSurfaceSecondary)
    )
  }

  // MARK: - Shift Card

  @ViewBuilder
  private func shiftCard(_ shift: ShiftWithComputations) -> some View {
    Button {
      onShiftTapped(shift)
    } label: {
      HStack(spacing: Spacing.sm) {
        // Time range
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(formatTimeRange(shift))
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
            .environment(\.layoutDirection, .leftToRight)

          Text(formattedHours(shift.paidHours))
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)
        }

        Spacer()

        // Earnings
        VStack(alignment: .trailing, spacing: Spacing.micro) {
          let displayAmount = shift.taxEnabled ? shift.netPay : shift.grossPay
          Text(formatCurrency(displayAmount))
            .font(.tidexHeadline)
            .foregroundColor(.tidexTextPrimary)

          if shift.taxEnabled && shift.taxAmount > 0 {
            Text("-\(formatCurrency(shift.taxAmount))")
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)
          }
        }

        // Chevron
        Image(systemName: "chevron.right")
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextMuted)
      }
      .padding(Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
    }
    .buttonStyle(.plain)
  }

  // MARK: - Formatting

  private func formatTimeRange(_ shift: ShiftWithComputations) -> String {
    ShiftCardFormatter.localizedTimeRange(
      start: shift.startTime,
      end: shift.endTime,
      locale: Locale.appLocale,
      separator: " – "
    )
  }

  private func formattedHours(_ hours: Double) -> String {
    let formatter = FormatterCache.numberFormatter(includeDecimals: true, locale: Locale.appLocale)
    return formatter.string(from: NSNumber(value: hours)) ?? String(format: "%.2f", hours)
  }

  private func formatCurrency(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }
}

// MARK: - Preview

#Preview {
  DayShiftsSheet(
    dateISO: "2025-01-17",
    shifts: [
      ShiftWithComputations(
        shift: ShiftRow(
          id: "1",
          user_id: "user-1",
          shift_date: "2025-01-17",
          start_time: "08:00",
          end_time: "12:00",
          custom_supplements: nil
        ),
        computed: ShiftComputed(
          id: "1",
          durationHours: 4.0,
          paidHours: 3.75,
          basePay: 750,
          supplementPay: 50,
          gross: 800,
          wagePeriods: [],
          originalWagePeriods: [],
          breakAudit: BreakAudit(
            method: .proportional, thresholdHours: 5.0, deductedHours: 0.25, notes: [])
        ),
        taxEnabled: false,
        taxPercentage: 0
      ),
      ShiftWithComputations(
        shift: ShiftRow(
          id: "2",
          user_id: "user-1",
          shift_date: "2025-01-17",
          start_time: "14:00",
          end_time: "22:00",
          custom_supplements: nil
        ),
        computed: ShiftComputed(
          id: "2",
          durationHours: 8.0,
          paidHours: 7.5,
          basePay: 1500,
          supplementPay: 200,
          gross: 1700,
          wagePeriods: [],
          originalWagePeriods: [],
          breakAudit: BreakAudit(
            method: .proportional, thresholdHours: 5.0, deductedHours: 0.5, notes: [])
        ),
        taxEnabled: true,
        taxPercentage: 30
      ),
    ],
    onShiftTapped: { shift in
      print("Tapped shift: \(shift.id)")
    }
  )
}
