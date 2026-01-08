import SwiftUI
import WidgetKit

@main
struct TidexShiftWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Home screen widget (iOS 14+)
        ShiftHomeWidget()

        // Live Activity (iOS 16.2+)
        if #available(iOS 16.2, *) {
            ShiftLiveActivity()
        }
    }
}
