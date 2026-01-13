import SwiftUI

/// Card displaying the next upcoming shift
/// Design matches OfflineFeaturedShiftCard from the Capacitor app
struct NextShiftCard: View {
    let shift: ShiftWithComputations
    let isToday: Bool

    @Environment(\.localization) private var localization

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
        guard let date = Date.fromISODateStringUTC(shift.shiftDate) else {
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
                        Text("\(shift.startTime)–\(shift.endTime)")
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
                // Net/gross amount
                let displayAmount = shift.taxEnabled ? shift.netPay : shift.grossPay
                Text(formatCurrency(displayAmount))
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(.tidexTextPrimary)

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
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.tidexSurfacePrimary)
        )
        .overlay(
            // Today indicator ring
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.tidexBlue, lineWidth: isToday ? 2 : 0)
        )
    }

    // MARK: - Formatting

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "NOK"
        formatter.currencySymbol = "kr "
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "nb_NO")
        return formatter.string(from: NSNumber(value: amount)) ?? "kr 0"
    }
}

// Preview disabled - requires full app context
// #Preview {
//     NextShiftCard(shift: mockShift, isToday: true)
// }
