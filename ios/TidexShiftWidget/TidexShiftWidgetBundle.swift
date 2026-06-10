import SwiftUI
import WidgetKit

@main
internal struct TidexShiftWidgetBundle: WidgetBundle {
  internal var body: some Widget {
    ShiftHomeWidget()
    ShiftLockScreenWidget()
    ShiftLiveActivity()
    FriendShiftWidget()
    TotalCardWidget()
    FriendsWidget()
  }
}
