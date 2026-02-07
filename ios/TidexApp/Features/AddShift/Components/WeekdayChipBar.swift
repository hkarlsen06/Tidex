import SwiftUI

/// Fixed height for the chip bar area to prevent layout shifts
private let chipBarHeight: CGFloat = 44

/// Horizontal bar showing selected weekday anchors as dismissible chips
/// Always reserves space to prevent layout shifts when chips are added/removed
struct WeekdayChipBar: View {
  let selectedDays: [String: String]  // weekday "0"-"6" -> anchor ISO date
  let onRemove: (String) -> Void

  // Sorted weekdays (Monday first: 1, 2, 3, 4, 5, 6, 0)
  private var sortedWeekdays: [String] {
    let order = ["1", "2", "3", "4", "5", "6", "0"]
    return order.filter { selectedDays.keys.contains($0) }
  }

  var body: some View {
    // Always allocate space for the chip bar to prevent layout shifts
    ZStack {
      if selectedDays.isEmpty {
        // Placeholder when no chips - shows subtle hint
        HStack(spacing: Spacing.xxxs) {
          Image(systemName: "star.fill")
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted.opacity(0.5))
          Text(.addShiftSelectAnchorDates)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
        }
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: Spacing.xs) {
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
          .padding(.horizontal, Spacing.xxs)
        }
      }
    }
    .frame(height: chipBarHeight)
    .frame(maxWidth: .infinity)
  }
}

// MARK: - Weekday Chip

private struct WeekdayChip: View {
  let weekday: String
  let anchorDate: String
  let onRemove: () -> Void

  private var weekdayName: String {
    var calendar = Calendar.current
    calendar.locale = Locale(identifier: Locale.current.identifier)
    let names = calendar.shortWeekdaySymbols
    guard let index = Int(weekday), index >= 0, index < 7 else { return "" }
    return names[index]
  }

  private var formattedDate: String {
    // Show abbreviated date like "Jan 15"
    guard let date = Date.fromISODateString(anchorDate) else { return anchorDate }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    formatter.locale = Locale(identifier: Locale.current.identifier)
    return formatter.string(from: date)
  }

  var body: some View {
    HStack(spacing: Spacing.xxxs) {
      Text(weekdayName)
        .font(.tidexFootnoteStrong)
        .foregroundColor(.tidexBlue)

      Text(formattedDate)
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextSecondary)

      Button(action: onRemove) {
        Image(systemName: "xmark.circle.fill")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextMuted)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xs)
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
        "5": "2025-01-24",
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
}
