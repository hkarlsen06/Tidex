import SwiftUI

/// The user's shift in progress, or else their next one, under the Schedule calendar. It takes
/// only the height it is offered, so it never pushes the controls under the month picker.
struct NextShiftDayCard: View {
  let onTap: (ShiftWithComputations) -> Void

  /// Shifts in start order, read when the calendar renders rather than on every tick.
  private let shifts: [(shift: ShiftWithComputations, interval: SharedShiftInterval)]

  init(shifts: [ShiftWithComputations], onTap: @escaping (ShiftWithComputations) -> Void) {
    self.onTap = onTap
    let zone = TimeZone.current.identifier
    self.shifts =
      shifts
      .compactMap { shift in
        SharedShiftInterval(
          date: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime,
          timeZoneIdentifier: zone
        ).map { (shift, $0) }
      }
      .sorted { $0.interval.start < $1.interval.start }
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      if let next = shifts.first(where: { $0.interval.end > context.date }) {
        ViewThatFits(in: .vertical) {
          card(next, now: context.date, topPadding: Spacing.lg, showsBar: true)
          card(next, now: context.date, topPadding: Spacing.xs, showsBar: true)
          card(next, now: context.date, topPadding: Spacing.xs, showsBar: false)
          Color.clear
        }
      }
    }
  }

  private func card(
    _ next: (shift: ShiftWithComputations, interval: SharedShiftInterval),
    now: Date, topPadding: CGFloat, showsBar: Bool
  ) -> some View {
    Button {
      Haptics.play(.selection)
      onTap(next.shift)
    } label: {
      ShiftDayCard(
        interval: next.interval, zone: .current, now: now, topPadding: topPadding,
        showsBar: showsBar)
    }
    .buttonStyle(.plain)
  }
}
