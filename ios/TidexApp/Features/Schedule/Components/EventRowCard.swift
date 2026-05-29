import SwiftUI

struct EventRowCard: View {
  let event: EventRow
  let coveredDateISO: String
  let onTap: (() -> Void)?
  var showTodayHighlight: Bool = true

  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var isToday: Bool {
    coveredDateISO == todayISO()
  }

  private var dateParts: ShiftCardDateParts {
    ShiftCardFormatter.dateParts(for: coveredDateISO)
  }

  private var isContinuingFromPreviousDay: Bool {
    coveredDateISO != event.start_date
  }

  private var hasTrailingBottomContent: Bool {
    isContinuingFromPreviousDay
  }

  private var isRTL: Bool {
    layoutDirection == .rightToLeft
  }

  private var usesFixedCardHeight: Bool {
    !dynamicTypeSize.isAccessibilitySize
  }

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
    ShiftCardContentLayout(
      centerTrailing: !hasTrailingBottomContent,
      leadingLayoutPriority: 1,
      trailingLayoutPriority: 0,
      trailingFixedHorizontal: false
    ) {
      HStack(spacing: Spacing.xxs) {
        HStack(spacing: Spacing.xxs) {
          Text(dateParts.weekday)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
          Text("·")
            .foregroundColor(.tidexTextMuted)
          Text(dateParts.dayMonth)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextMuted)
        }
      }
    } leadingBottom: {
      subtitleLabel
    } trailingTop: {
      Text(event.note)
        .font(.tidexTitle)
        .tracking(-0.5)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.trailing)
        .lineLimit(2)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 170, alignment: .trailing)
    } trailingBottom: {
      if isContinuingFromPreviousDay {
        Text(dateRangeText)
          .font(.tidexMicro)
          .foregroundColor(.tidexTextMuted)
          .multilineTextAlignment(.trailing)
          .lineLimit(1)
          .frame(maxWidth: 170, alignment: .trailing)
      }
    }
    .padding(.horizontal, Spacing.mlg)
    .padding(.vertical, ShiftCardMetrics.verticalPadding)
    .frame(minHeight: usesFixedCardHeight ? ShiftCardMetrics.regularCardMinHeight : nil)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .strokeBorder(
          showTodayHighlight && isToday ? Color.tidexBlue : Color.clear,
          lineWidth: showTodayHighlight && isToday ? 2 : 0
        )
    )
    .tidexCardShadow()
  }

  private var subtitleLabel: some View {
    HStack(spacing: Spacing.xxs) {
      if isRTL {
        subtitleTextLabel
        subtitleIcon
      } else {
        subtitleIcon
        subtitleTextLabel
      }
    }
  }

  private var subtitleTextLabel: some View {
    Text(subtitleText)
      .font(.tidexSubheadline)
      .foregroundColor(.tidexTextPrimary)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .environment(\.layoutDirection, .leftToRight)
  }

  private var subtitleIcon: some View {
    Image(systemName: event.is_all_day ? "calendar" : "clock")
      .font(.tidexFootnote)
      .foregroundColor(.tidexTextMuted)
  }
}
