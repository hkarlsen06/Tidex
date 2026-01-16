import SwiftUI

/// Horizontal bar showing selected weekday anchors as dismissible chips
struct WeekdayChipBar: View {
    let selectedDays: [String: String]  // weekday "0"-"6" -> anchor ISO date
    let onRemove: (String) -> Void
    @Environment(\.localization) private var localization

    // Sorted weekdays (Monday first: 1, 2, 3, 4, 5, 6, 0)
    private var sortedWeekdays: [String] {
        let order = ["1", "2", "3", "4", "5", "6", "0"]
        return order.filter { selectedDays.keys.contains($0) }
    }

    var body: some View {
        if !selectedDays.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sortedWeekdays, id: \.self) { weekday in
                        if let anchorDate = selectedDays[weekday] {
                            WeekdayChip(
                                weekday: weekday,
                                anchorDate: anchorDate,
                                onRemove: { onRemove(weekday) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 36)
        }
    }
}

// MARK: - Weekday Chip

private struct WeekdayChip: View {
    let weekday: String
    let anchorDate: String
    let onRemove: () -> Void
    @Environment(\.localization) private var localization

    private var weekdayName: String {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: localization.currentLocale.localeIdentifier)
        let names = calendar.shortWeekdaySymbols
        guard let index = Int(weekday), index >= 0, index < 7 else { return "" }
        return names[index]
    }

    private var formattedDate: String {
        // Show abbreviated date like "Jan 15"
        guard let date = Date.fromISODateString(anchorDate) else { return anchorDate }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: localization.currentLocale.localeIdentifier)
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(weekdayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.tidexBlue)

            Text(formattedDate)
                .font(.system(size: 12))
                .foregroundColor(.tidexTextSecondary)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.tidexBlue.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    VStack {
        WeekdayChipBar(
            selectedDays: [
                "1": "2025-01-20",
                "3": "2025-01-22",
                "5": "2025-01-24"
            ],
            onRemove: { _ in }
        )

        WeekdayChipBar(
            selectedDays: [:],
            onRemove: { _ in }
        )
    }
    .padding()
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
