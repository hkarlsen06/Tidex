import SwiftUI

struct EventRowCard: View {
  let event: EventRow
  let coveredDateISO: String
  let onTap: (() -> Void)?
  var showTodayHighlight: Bool = true
  var isElevated: Bool = true

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
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(verbatim: accessibilityDescription))
      .accessibilityAddTraits(.isButton)
      .accessibilityAction(.default) {
        onTap?()
      }
  }

  /// One spoken summary instead of a fragment per text label.
  private var accessibilityDescription: String {
    var parts = ["\(dateParts.weekday) \(dateParts.dayMonth)"]
    if showTodayHighlight, isToday {
      parts.append(String(localized: .commonToday))
    }
    parts.append(event.note)
    parts.append(subtitleText)
    if isContinuingFromPreviousDay {
      parts.append(dateRangeText)
    }
    return parts.joined(separator: ", ")
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
        .lineLimit(usesFixedCardHeight ? 2 : nil)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: usesFixedCardHeight ? 170 : .infinity, alignment: .trailing)
    } trailingBottom: {
      if isContinuingFromPreviousDay {
        Text(dateRangeText)
          .font(.tidexMicro)
          .foregroundColor(.tidexTextMuted)
          .multilineTextAlignment(.trailing)
          .lineLimit(usesFixedCardHeight ? 1 : nil)
          .frame(maxWidth: usesFixedCardHeight ? 170 : .infinity, alignment: .trailing)
      }
    }
    .padding(.horizontal, isElevated ? Spacing.mlg : 0)
    .padding(.vertical, ShiftCardMetrics.verticalPadding)
    .frame(minHeight: usesFixedCardHeight ? ShiftCardMetrics.regularCardMinHeight : nil)
    .tidexRowSurface(
      cornerRadius: CornerRadius.card,
      fillColor: isElevated ? .tidexSurfacePrimary : .clear
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .strokeBorder(
          showTodayHighlight && isToday ? Color.tidexBlue : Color.clear,
          lineWidth: showTodayHighlight && isToday ? 2 : 0
        )
    )
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
