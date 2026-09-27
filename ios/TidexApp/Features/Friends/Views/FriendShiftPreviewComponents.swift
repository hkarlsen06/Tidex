import SwiftUI

enum FriendCardMessagePreviewTimestampFormatter {
  static func relativeTimestamp(
    messageDate: Date,
    referenceDate: Date,
    nowText: String = String(localized: .commonNow)
  ) -> String {
    let elapsed = referenceDate.timeIntervalSince(messageDate)
    guard elapsed >= 60 else {
      return nowText
    }

    let unit = largestNonZeroUnit(from: messageDate, to: referenceDate)
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [unit]
    formatter.unitsStyle = unit == .month ? .short : .abbreviated
    formatter.maximumUnitCount = 1
    formatter.zeroFormattingBehavior = .dropAll

    guard let timestamp = formatter.string(from: elapsed) else {
      return "1m"
    }

    let compactTimestamp = String(
      timestamp.unicodeScalars.filter {
        !CharacterSet.whitespacesAndNewlines.contains($0)
      }
    )
    return unit == .month
      ? compactTimestamp.replacingOccurrences(of: ".", with: "") : compactTimestamp
  }

  private static func largestNonZeroUnit(from messageDate: Date, to referenceDate: Date)
    -> NSCalendar.Unit
  {
    let calendarComponents = Calendar.current.dateComponents(
      [.year, .month, .weekOfMonth, .day, .hour, .minute],
      from: messageDate,
      to: referenceDate
    )

    if (calendarComponents.year ?? 0) > 0 { return .year }
    if (calendarComponents.month ?? 0) > 0 { return .month }
    if (calendarComponents.weekOfMonth ?? 0) > 0 { return .weekOfMonth }
    if (calendarComponents.day ?? 0) > 0 { return .day }
    if (calendarComponents.hour ?? 0) > 0 { return .hour }
    return .minute
  }
}

struct CompactFriendShiftPreviewHeader: View {
  let preview: SharerShiftPreview

  var body: some View {
    if let shift = preview.shift, let status = preview.status {
      CompactFriendShiftPreviewTextRow(
        shift: shift,
        status: status,
        showEarnings: preview.showEarnings,
        currency: preview.currency
      )
    }
  }
}

/// Start and end of a shared shift, with the end moved to the next day for overnight shifts.
struct FriendShiftTiming: Equatable {
  let start: Date
  let end: Date

  init(start: Date, end: Date) {
    self.start = start
    self.end = end
  }

  init?(shift: SharedShiftData, calendar: Calendar = .current) {
    guard let shiftDate = Date.fromISODateString(shift.shift_date) else { return nil }

    let startComponents = shift.start_time.split(separator: ":").compactMap { Int($0) }
    let endComponents = shift.end_time.split(separator: ":").compactMap { Int($0) }
    guard startComponents.count >= 2, endComponents.count >= 2,
      let start = calendar.date(
        bySettingHour: startComponents[0], minute: startComponents[1], second: 0, of: shiftDate),
      var end = calendar.date(
        bySettingHour: endComponents[0], minute: endComponents[1], second: 0, of: shiftDate)
    else { return nil }

    if end <= start {
      end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
    }
    self.init(start: start, end: end)
  }

  func status(at now: Date) -> ShiftPreviewStatus {
    if now < start { return .upcoming }
    return now <= end ? .active : .past
  }

  /// Fraction of the shift that has elapsed, clamped to 0...1.
  func progress(at now: Date) -> Double {
    let duration = end.timeIntervalSince(start)
    guard duration > 0 else { return 0 }
    return min(1, max(0, now.timeIntervalSince(start) / duration))
  }

  /// "Pågår nå" while active, otherwise a countdown to the start or time since the end.
  func statusText(at now: Date) -> String {
    if status(at: now) == .active {
      return String(localized: .sharingStatusActive)
    }
    return CountdownFormatter.formatRelativeCountdown(
      referenceDate: now > end ? end : start,
      dayBoundaryReferenceDate: start,
      now: now
    )
  }
}

private struct CompactFriendShiftPreviewTextRow: View {
  let shift: SharedShiftData
  let status: ShiftPreviewStatus
  let showEarnings: Bool
  let currency: String?

  private var formattedDate: String {
    guard let date = Date.fromISODateString(shift.shift_date) else { return "" }
    return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).sentenceCased()
  }

  private var formattedTimeRange: String {
    ShiftCardFormatter.localizedTimeRange(
      start: shift.start_time,
      end: shift.end_time,
      locale: Locale.appLocale,
      separator: " – "
    )
  }

  private var formattedEarnings: String {
    CurrencyConfig.format(shift.computed.gross, currency: currency ?? "kr")
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      HStack(alignment: .top, spacing: Spacing.md) {
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(formattedDate)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
            .lineLimit(1)

          Text(formattedTimeRange)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
            .lineLimit(1)
            .environment(\.layoutDirection, .leftToRight)
        }

        Spacer(minLength: Spacing.xs)

        VStack(alignment: .trailing, spacing: Spacing.micro) {
          Text(statusText(at: context.date))
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

          if showEarnings {
            Text(formattedEarnings)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)
              .lineLimit(1)
              .fixedSize(horizontal: true, vertical: false)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, Spacing.xxs)
    }
  }

  private func statusText(at now: Date) -> String {
    if let timing = FriendShiftTiming(shift: shift) {
      return timing.statusText(at: now)
    }
    return status == .active ? String(localized: .sharingStatusActive) : ""
  }
}
