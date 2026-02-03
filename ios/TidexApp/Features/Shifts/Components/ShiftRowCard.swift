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

    private var formattedHours: String {
        ShiftCardFormatter.formattedHours(shift.paidHours, locale: Locale.current)
    }

    private var dateParts: ShiftCardDateParts {
        ShiftCardFormatter.dateParts(for: shift.shiftDate, locale: Locale.current)
    }

    // MARK: - Body

    var body: some View {
        // Use a simple view with tap gesture instead of Button
        // Button adds its own gesture recognizer that conflicts with SwipeableShiftCard
        cardContent
            .contentShape(RoundedRectangle(cornerRadius: 24))
            .onTapGesture {
                onTap?()
            }
    }

    /// The card's visual content (extracted for cleaner code)
    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Row 1: Date (left) and earnings amount (right) - center aligned
            HStack(alignment: .center) {
                // Day name and date
                HStack(spacing: 4) {
                    Text(dateParts.dayName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.tidexTextPrimary)
                    Text("·")
                        .foregroundColor(.tidexTextMuted)
                    Text("\(dateParts.dayNumber) \(dateParts.monthName)")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.tidexTextMuted)
                }
                .fixedSize(horizontal: true, vertical: false)

                Spacer()

                // Net/gross amount
                let displayAmount = shift.taxEnabled ? shift.netPay : shift.grossPay
                Text(formatCurrency(displayAmount))
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(excludedFromTotal ? .tidexTextMuted : .tidexTextPrimary)
                    .strikethrough(excludedFromTotal, color: .tidexTextMuted)
            }

            // Row 2: Time range (left) and breakdown (right) - center aligned
            HStack(alignment: .center) {
                // Time range and hours
                HStack(spacing: 8) {
                    // Time with clock or warning icon (warning replaces clock when conflict)
                    HStack(spacing: 4) {
                        if hasConflict {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.tidexWarning)
                        } else {
                            Image(systemName: "clock")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.tidexTextMuted)
                        }
                        Text("\(formatTime(shift.startTime))–\(formatTime(shift.endTime))")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.tidexTextPrimary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    // Arrow and hours combined
                    Text("→ \(formattedHours)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.tidexTextMuted)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer()

                // When excluded from total, show excluded label instead of breakdown
                if excludedFromTotal {
                    Text(.shiftsExcludedFromTotal)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.tidexWarning)
                } else if showBreakdown {
                    // Breakdown (gross - tax) when tax enabled
                    HStack(spacing: 4) {
                        Text(formatPlainAmount(shift.grossPay))
                        Text("−")
                        Text(formatPlainAmount(shift.taxAmount))
                    }
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.tidexTextMuted)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(hasConflict ? Color.tidexWarning.opacity(0.08) : Color.tidexSurfacePrimary)
        )
        .overlay(
            // Border: today (blue), conflict (orange), or none
            RoundedRectangle(cornerRadius: 24)
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

    /// Format time string to HH:mm (removes seconds if present)
    private func formatTime(_ time: String) -> String {
        // Handle both "HH:mm" and "HH:mm:ss" formats
        String(time.prefix(5))
    }
}

// Preview disabled - requires full app context
// #Preview {
//     ShiftRowCard(shift: mockShift, isToday: true, onTap: nil)
// }
