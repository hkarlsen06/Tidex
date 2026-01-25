import SwiftUI

// MARK: - Calendar Weekday Header

/// Reusable weekday header row for calendar grids
/// Displays localized two-letter abbreviations (MA/TI/ON... or MO/TU/WE...)
struct CalendarWeekdayHeader: View {
    @Environment(\.localization) private var localization

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols.indices, id: \.self) { index in
                Text(weekdaySymbols[index])
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekdaySymbols: [String] {
        CalendarGridHelper.weekdaySymbols(isNorwegian: localization.currentLocale == .norwegian)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        CalendarWeekdayHeader()
            .padding()
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
