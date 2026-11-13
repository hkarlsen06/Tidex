import SwiftUI

/// A friend's current or next shift, shown under their calendar. The times and the bar use the
/// clock the schedule shows.
struct FriendShiftDayCard: View {
  let interval: SharedShiftInterval
  /// The viewer's zone, or the friend's when the schedule shows their time.
  let zone: TimeZone

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      // A shift that ended before today says nothing about the friend's day.
      if interval.dayBar(in: zone, now: context.date).now != nil
        || interval.status(at: context.date) != .past
      {
        ShiftDayCard(interval: interval, zone: zone, now: context.date)
      }
    }
  }
}
