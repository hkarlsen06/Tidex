import SwiftUI

/// Card displaying the next upcoming shift
struct NextShiftCard: View {
    let shift: ShiftWithComputations
    let isToday: Bool

    @Environment(\.localization) private var localization

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(localization.string("dashboard.nextShift"))
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextSecondary)

                Spacer()

                if isToday {
                    Text(localization.string("dashboard.today"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.tidexBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.tidexBlue.opacity(0.15))
                        .cornerRadius(8)
                }
            }

            // Date
            Text(formattedDate)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            // Time and duration
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextMuted)
                    Text("\(shift.startTime) - \(shift.endTime)")
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextSecondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextMuted)
                    Text(String(format: "%.1f %@", shift.paidHours, localization.string("dashboard.hoursShort")))
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextSecondary)
                }
            }

            Divider()
                .background(Color.tidexBorderSubtle)

            // Earnings
            HStack {
                Text(localization.string("dashboard.earnings"))
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextSecondary)

                Spacer()

                let displayAmount = shift.taxEnabled ? shift.netPay : shift.grossPay
                Text(formatCurrency(displayAmount))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)
            }
        }
        .padding(20)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isToday ? Color.tidexBlue : Color.clear, lineWidth: 2)
        )
    }

    // MARK: - Formatting

    private var formattedDate: String {
        guard let date = Date.fromISODateStringUTC(shift.shiftDate) else {
            return shift.shiftDate
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localization.currentLocale == .norwegian ? "nb_NO" : "en_US")
        formatter.dateFormat = "EEEE d. MMMM"
        return formatter.string(from: date).capitalized
    }

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
