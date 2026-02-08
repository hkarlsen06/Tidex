import SwiftUI

/// Toolbar label showing today's date with styled parts.
/// Weekday in primary, dot separator, and day + month in secondary.
/// Tapping navigates back to the current month.
struct TodayDateLabel: View {
  private let monthContext = SharedMonthContext.shared
  private let parts: ShiftCardDateParts = ShiftCardFormatter.dateParts(
    for: Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)),
    locale: Locale.appLocale
  )

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      Circle()
        .fill(Color.tidexBlue)
        .frame(width: 7, height: 7)
      Text(parts.dayName)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)
      Text("\u{00B7}")
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextMuted)
      Text("\(parts.dayNumber) \(parts.monthName)")
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextSecondary)
    }
    .fixedSize()
    .padding(.leading, Spacing.xxs)
    .onTapGesture {
      guard !monthContext.isCurrentMonth else { return }
      Haptics.play(.light)
      monthContext.goToCurrentMonth()
    }
  }
}
