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
                VStack(spacing: 16) {
                    // Summary header
                    summaryHeader

                    // Shift cards
                    VStack(spacing: 12) {
                        ForEach(shifts) { shift in
                            shiftCard(shift)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.tidexBackground)
            .navigationTitle(formattedDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: .commonDone)) {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexBlue)
                }
            }
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        HStack(spacing: 24) {
            // Total hours
            VStack(spacing: 4) {
                Text(formattedHours(totalHours))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)
                Text(.shiftsDaySheetHours)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextSecondary)
            }

            // Divider
            Rectangle()
                .fill(Color.tidexBorder)
                .frame(width: 1, height: 40)

            // Total earnings
            VStack(spacing: 4) {
                Text(formatCurrency(totalEarnings))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)
                Text(.shiftsDaySheetEarnings)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextSecondary)
            }

            Spacer()

            // Shift count badge
            Text("\(shifts.count)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.tidexBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.tidexBlue.opacity(0.1))
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tidexSurfaceSecondary)
        )
    }

    // MARK: - Shift Card

    @ViewBuilder
    private func shiftCard(_ shift: ShiftWithComputations) -> some View {
        Button {
            onShiftTapped(shift)
        } label: {
            HStack(spacing: 12) {
                // Time range
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatTimeRange(shift))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.tidexTextPrimary)
                        .environment(\.layoutDirection, .leftToRight)

                    Text(formattedHours(shift.paidHours))
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextSecondary)
                }

                Spacer()

                // Earnings
                VStack(alignment: .trailing, spacing: 2) {
                    let displayAmount = shift.taxEnabled ? shift.netPay : shift.grossPay
                    Text(formatCurrency(displayAmount))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.tidexTextPrimary)

                    if shift.taxEnabled && shift.taxAmount > 0 {
                        Text("-\(formatCurrency(shift.taxAmount))")
                            .font(.system(size: 13))
                            .foregroundColor(.tidexTextMuted)
                    }
                }

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextMuted)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
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
                    breakAudit: BreakAudit(method: .proportional, thresholdHours: 5.0, deductedHours: 0.25, notes: [])
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
                    breakAudit: BreakAudit(method: .proportional, thresholdHours: 5.0, deductedHours: 0.5, notes: [])
                ),
                taxEnabled: true,
                taxPercentage: 30
            )
        ],
        onShiftTapped: { shift in
            print("Tapped shift: \(shift.id)")
        }
    )
}
