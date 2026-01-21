import SwiftUI

/// Shows today's date when no shifts exist for today
/// Visually matches ShiftRowCard styling but shows placeholder dashes for earnings
/// Tapping navigates to add shift with today's date pre-selected
struct TodayPlaceholderCard: View {
    /// Callback when the card is tapped
    let onTap: () -> Void

    @Environment(\.localization) private var localization
    @Environment(\.userCurrency) private var currency

    // MARK: - Computed Properties

    private var dateParts: (dayName: String, dayNumber: String, monthName: String) {
        let date = Date()
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

    /// Placeholder earnings text with currency symbol
    private var placeholderEarnings: String {
        let currencyOption = CurrencyConfig.get(currency)
        if currencyOption.display == .prefix {
            return "\(currencyOption.value)——"
        } else {
            return "—— \(currencyOption.value)"
        }
    }

    // MARK: - Body

    var body: some View {
        cardContent
            .contentShape(RoundedRectangle(cornerRadius: 24))
            .onTapGesture {
                onTap()
            }
    }

    @ViewBuilder
    private var cardContent: some View {
        HStack(alignment: .center) {
            // Date (left side)
            HStack(spacing: 4) {
                Text(dateParts.dayName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
                Text("·")
                    .foregroundColor(.tidexTextMuted)
                Text("\(dateParts.dayNumber) \(dateParts.monthName)")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer()

            // Placeholder earnings (right side)
            Text(placeholderEarnings)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.5)
                .foregroundColor(.tidexTextMuted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.tidexSurfacePrimary)
        )
        .overlay(
            // Blue ring to highlight as today's marker
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.tidexBlue, lineWidth: 2)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        TodayPlaceholderCard(onTap: {
            print("Tapped!")
        })
    }
    .padding()
    .background(Color.tidexBackground)
}
