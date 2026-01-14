import SwiftUI

/// Add Shift tab view - form for creating new shifts
/// Currently a placeholder, will be implemented with shift creation form
struct AddShiftView: View {
    @Environment(\.localization) private var localization

    var body: some View {
        TabScreenContainer(title: localization.string(AppTab.add.titleKey)) {
            ScrollView {
                TabPlaceholder(tab: .add)
            }
        }
    }
}

#Preview {
    AddShiftView()
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
