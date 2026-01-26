import SwiftUI
import WidgetKit

@main
struct TidexShiftWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShiftHomeWidget()
        ShiftLockScreenWidget()
        ShiftLiveActivity()
        FriendShiftWidget()
    }
}
