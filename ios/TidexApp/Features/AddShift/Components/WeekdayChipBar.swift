import SwiftUI

/// Horizontal bar showing selected weekday anchors as dismissible chips
/// Always reserves space to prevent layout shifts when chips are added/removed
struct WeekdayChipBar: View {
  let selectedDays: [String: String]  // weekday "0"-"6" -> anchor ISO date
  let onRemove: (String) -> Void

  /// Fixed height for the chip bar area to prevent layout shifts. Scales with text size.
  @ScaledMetric(relativeTo: .footnote) private var chipBarHeight: CGFloat = 44

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
            .foregroundColor(.tidexTextMuted)
            .accessibilityHidden(true)
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
    var calendar = Calendar.gregorianCurrent
    calendar.locale = Locale(identifier: Locale.current.identifier)
    let names = calendar.shortWeekdaySymbols
    guard let index = Int(weekday), index >= 0, index < 7 else { return "" }
    return names[index]
  }

  private var formattedDate: String {
    // Show abbreviated date like "Jan 15"
    guard let date = Date.fromISODateString(anchorDate) else { return anchorDate }
    return FormatterCache.abbreviatedMonthDayFormatter(locale: .current).string(from: date)
  }

  var body: some View {
    HStack(spacing: Spacing.xxxs) {
      Text(weekdayName)
        .font(.tidexFootnoteStrong)
        .foregroundColor(.tidexBlueText)

      Text(formattedDate)
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextSecondary)

      Button(action: onRemove) {
        Image(systemName: "xmark.circle.fill")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextMuted)
          // Grows the touch target to about 44pt without changing the chip.
          .padding(Spacing.xs)
          .contentShape(Rectangle())
          .padding(-Spacing.xs)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(.shiftsAccessibilityRemoveItem(weekdayName)))
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
