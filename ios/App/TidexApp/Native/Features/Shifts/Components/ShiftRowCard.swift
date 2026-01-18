import SwiftUI

/// Card displaying a single shift in the shifts list
/// Design matches NextShiftCard from the Dashboard
struct ShiftRowCard: View {
    let shift: ShiftWithComputations
    let isToday: Bool
    let hasConflict: Bool
    let excludedFromTotal: Bool
    let onTap: (() -> Void)?

    @Environment(\.localization) private var localization
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
        let hoursLabel = localization.currentLocale == .norwegian ? "t" : "h"
        if shift.paidHours == floor(shift.paidHours) {
            return String(format: "%.0f %@", shift.paidHours, hoursLabel)
        }
        return String(format: "%.1f %@", shift.paidHours, hoursLabel)
    }

    private var dateParts: (dayName: String, dayNumber: String, monthName: String) {
        guard let date = Date.fromISODateString(shift.shiftDate) else {
            return ("", "", "")
        }

        let formatter = DateFormatter()
        let isNorwegian = localization.currentLocale == .norwegian
        formatter.locale = Locale(identifier: isNorwegian ? "nb_NO" : "en_US")

        // Get day name (full)
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: date).capitalized

        // Get day number
        formatter.dateFormat = "d"
        let dayNumber = formatter.string(from: date)

        // Get month name (short)
        formatter.dateFormat = "MMM"
        let monthName = formatter.string(from: date).lowercased()

        return (dayName, dayNumber, monthName)
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
        HStack(alignment: showBreakdown ? .top : .center, spacing: 16) {
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
                    // Time with clock icon
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.tidexTextMuted)
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
            }

            Spacer()

            // Right side: earnings
            VStack(alignment: .trailing, spacing: 2) {
                // Conflict indicator + amount
                HStack(spacing: 6) {
                    // Conflict warning icon
                    if hasConflict {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.tidexWarning)
                    }

                    // Net/gross amount
                    let displayAmount = shift.taxEnabled ? shift.netPay : shift.grossPay
                    Text(formatCurrency(displayAmount))
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundColor(excludedFromTotal ? .tidexTextMuted : .tidexTextPrimary)
                        .strikethrough(excludedFromTotal, color: .tidexTextMuted)
                }

                // Breakdown (gross - tax) when tax enabled
                if showBreakdown {
                    HStack(spacing: 4) {
                        Text(formatCurrency(shift.grossPay))
                        Text("−")
                        Text(formatCurrency(shift.taxAmount))
                    }
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.tidexTextMuted)
                }

                // Excluded from total label
                if excludedFromTotal {
                    Text(localization.string("shifts.excludedFromTotal"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.tidexWarning)
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
    }

    // MARK: - Formatting

    private func formatCurrency(_ amount: Double) -> String {
        CurrencyConfig.format(amount, currency: currency)
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
