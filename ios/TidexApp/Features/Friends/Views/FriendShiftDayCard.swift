import SwiftUI

/// A friend's current or next shift on a 24-hour bar, shown under their calendar. The times and
/// the bar use the clock the schedule shows, and today's bar has a line at the current time.
struct FriendShiftDayCard: View {
  let interval: SharedShiftInterval
  /// The viewer's zone, or the friend's when the schedule shows their time.
  let zone: TimeZone

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let bar = interval.dayBar(in: zone, now: context.date)
      // A shift that ended before today says nothing about the friend's day.
      if bar.now != nil || interval.status(at: context.date) != .past {
        card(bar: bar, now: context.date)
      }
    }
  }

  private func card(bar: ShiftDayBar, now: Date) -> some View {
    let isActive = interval.status(at: now) == .active
    let timing = FriendShiftTiming(start: interval.start, end: interval.end)
    let status = timing.statusText(at: now)
    let date = interval.dateLabel(in: zone, locale: .appLocale)
    let range = interval.timeRange(in: zone, locale: .appLocale)

    return VStack(alignment: .leading, spacing: Spacing.md) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .center, spacing: Spacing.sm) {
          labels(status: status, date: date, isActive: isActive)
          Spacer(minLength: 0)
          timeRange(range)
        }
        VStack(alignment: .leading, spacing: Spacing.xs) {
          labels(status: status, date: date, isActive: isActive)
          timeRange(range)
        }
      }

      FriendShiftDayBar(bar: bar, accent: isActive ? .tidexSuccess : .tidexBlue)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.top, Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      [status, interval.datedTimeRange(in: zone, locale: .appLocale)].joined(separator: ", "))
  }

  /// The date, with a green "now" badge under it during the shift and a countdown otherwise.
  private func labels(status: String, date: String, isActive: Bool) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      Text(date)
        .font(.tidexHeadline)
        .foregroundStyle(Color.tidexTextPrimary)
      if isActive {
        HStack(spacing: Spacing.xxs) {
          Circle()
            .fill(Color.tidexSuccess)
            .frame(width: 6, height: 6)
          Text(status)
            .font(.tidexCaptionStrong)
        }
        .foregroundStyle(Color.tidexSuccess)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(Capsule().fill(Color.tidexSuccess.opacity(0.15)))
      } else {
        Text(status)
          .font(.tidexFootnoteMedium)
          .foregroundStyle(Color.tidexTextSecondary)
      }
    }
  }

  private func timeRange(_ range: String) -> some View {
    Text(range)
      .font(.system(.title2, design: .rounded).weight(.bold))
      .monospacedDigit()
      .foregroundStyle(Color.tidexTextPrimary)
      .lineLimit(1)
      .environment(\.layoutDirection, .leftToRight)
  }
}

/// A 24-hour track with the shift as a filled segment and, on today's bar, a line at the
/// current time. A gap cut around the line keeps it visible on the segment in either theme.
private struct FriendShiftDayBar: View {
  let bar: ShiftDayBar
  let accent: Color

  @ScaledMetric(relativeTo: .caption) private var trackHeight: CGFloat = 6

  var body: some View {
    VStack(spacing: Spacing.xs) {
      GeometryReader { geo in
        Capsule()
          .fill(Color.tidexTextMuted.opacity(0.18))
          .overlay(alignment: .leading) {
            Capsule()
              .fill(accent)
              .frame(
                width: max(
                  trackHeight, geo.size.width * (bar.span.upperBound - bar.span.lowerBound))
              )
              .offset(x: geo.size.width * bar.span.lowerBound)
          }
          .overlay(alignment: .leading) {
            if let now = bar.now {
              nowLine.offset(x: geo.size.width * now - 3.5)
            }
          }
          .compositingGroup()
      }
      .frame(height: trackHeight)

      HStack {
        ForEach(["00", "06", "12", "18", "24"], id: \.self) { label in
          Text(verbatim: label)
            .font(.tidexMicro.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Color.tidexTextMuted)
          if label != "24" { Spacer(minLength: 0) }
        }
      }
    }
    .padding(.top, Spacing.xxs)
    .environment(\.layoutDirection, .leftToRight)
    .accessibilityHidden(true)
  }

  /// Seven points wide: the line and the gap erased on each side of it.
  private var nowLine: some View {
    ZStack {
      Capsule()
        .frame(width: 7, height: trackHeight + 14)
        .blendMode(.destinationOut)
      Capsule()
        .fill(Color.tidexTextPrimary)
        .frame(width: 3, height: trackHeight + 10)
    }
  }
}
