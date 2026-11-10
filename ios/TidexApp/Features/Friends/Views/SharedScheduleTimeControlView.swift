import SwiftUI

/// The clock choice in a friend's schedule. It shows nothing when the schedule's clock matches
/// the viewer's.
struct SharedScheduleTimeControlView: View {
  let control: SharedScheduleTimeControl
  let friendName: String
  @Binding var display: SharedScheduleTimeDisplay

  var body: some View {
    switch control {
    case .none:
      EmptyView()

    case .choice:
      AdaptiveCalendarPicker(
        selection: $display,
        options: [
          CalendarPickerOption(value: .viewer, title: .sharingTimeYourTime),
          CalendarPickerOption(value: .schedule, title: .friendTime(friendName)),
        ])

    case .unknownZone:
      Text(.sharingTimeUnknown)
        .font(.tidexCaption)
        .foregroundStyle(Color.tidexTextSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxs)
    }
  }

}
