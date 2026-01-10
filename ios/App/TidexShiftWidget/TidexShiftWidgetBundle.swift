import SwiftUI
import WidgetKit

@main
struct TidexShiftWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Home screen widget (iOS 14+)
        ShiftHomeWidget()

        // Lock screen widget (iOS 16+)
        if #available(iOS 16.0, *) {
            ShiftLockScreenWidget()
        }

        // Live Activity (iOS 16.2+)
        if #available(iOS 16.2, *) {
            ShiftLiveActivity()
        }
    }
}
