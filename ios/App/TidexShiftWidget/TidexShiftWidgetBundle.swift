import SwiftUI
import WidgetKit

@main
struct TidexShiftWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.2, *) {
            ShiftLiveActivity()
        }
    }
}
