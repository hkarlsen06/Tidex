import Foundation

/// Mode for the Add Shift view
/// - single: Add one or more individual shifts on specific dates
/// - recurring: Create a recurring shift pattern
enum AddShiftMode: String, CaseIterable, Identifiable {
    case single
    case recurring

    var id: String { rawValue }

    /// Localization key for the mode title
    var titleKey: String {
        switch self {
        case .single:
            return "addShift.modeSingle"
        case .recurring:
            return "addShift.modeRecurring"
        }
    }
}
