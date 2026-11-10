import SwiftUI

struct SharedScheduleTimeZoneCaption: View {
  let ownerTimeZone: String?

  var body: some View {
    VStack(spacing: Spacing.xxs) {
      if SharedShiftInterval.scheduleZone(ownerTimeZone) != nil {
        Text(.sharingTimeCalendar)
        if let offsetDescription { Text(offsetDescription) }
      } else {
        Text(.sharingTimeUnknown)
      }
    }
    .font(.tidexCaption)
    .foregroundStyle(Color.tidexTextSecondary)
    .multilineTextAlignment(.center)
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xs)
  }

  private var offsetDescription: LocalizedStringResource? {
    guard let zone = SharedShiftInterval.scheduleZone(ownerTimeZone) else { return nil }
    let delta = zone.secondsFromGMT() - TimeZone.current.secondsFromGMT()
    guard delta != 0 else { return nil }
    let formatter = DateComponentsFormatter()
    var calendar = Calendar.gregorianCurrent
    calendar.locale = .appLocale
    formatter.calendar = calendar
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .short
    let difference = formatter.string(from: Double(abs(delta))) ?? ""
    return delta < 0 ? .sharingTimeBehind(difference) : .sharingTimeAhead(difference)
  }
}
