import SwiftUI

struct EventRowCard: View {
  let event: EventRow
  let coveredDateISO: String
  let onTap: (() -> Void)?

  private var dateRangeText: String {
    guard
      let startDate = Date.fromISODateString(event.start_date),
      let endDate = Date.fromISODateString(event.end_date)
    else {
      return event.start_date
    }

    let formatter = DateFormatter()
    formatter.locale = Locale.appLocale
    formatter.setLocalizedDateFormatFromTemplate("dMMM")

    if event.is_all_day {
      if event.start_date == event.end_date {
        return formatter.string(from: startDate)
      }
      return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }

    return formatter.string(from: startDate)
  }

  private var subtitleText: String {
    if event.is_all_day {
      return String(localized: .addShiftEventAllDay)
    }

    let start = event.start_time ?? "--:--"
    let end = event.end_time ?? "--:--"
    return ShiftCardFormatter.localizedTimeRange(start: start, end: end, locale: Locale.appLocale)
  }

  var body: some View {
    content
      .contentShape(RoundedRectangle(cornerRadius: CornerRadius.card))
      .onTapGesture {
        onTap?()
      }
  }

  private var content: some View {
    HStack(spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        HStack(spacing: Spacing.xxs) {
          Image(systemName: event.is_all_day ? "calendar" : "clock")
            .font(.tidexFootnote)
            .foregroundColor(.tidexBlue)
          Text(subtitleText)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)
        }

        Text(event.note)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.leading)
          .lineLimit(3)

        Text(dateRangeText)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
      }

      Spacer(minLength: Spacing.sm)

      if coveredDateISO != event.start_date {
        Text(dateRangeText)
          .font(.tidexMicro)
          .foregroundColor(.tidexTextMuted)
          .multilineTextAlignment(.trailing)
      }
    }
    .padding(.horizontal, Spacing.mlg)
    .padding(.vertical, ShiftCardMetrics.verticalPadding)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .strokeBorder(Color.tidexBlue.opacity(0.2), lineWidth: 1)
    )
    .tidexCardShadow()
  }
}
