import Foundation

/// Mode for the Add Shift view
/// - single: Add one or more individual shifts on specific dates
/// - recurring: Create a recurring shift pattern
enum AddShiftMode: String, CaseIterable, Identifiable, Codable {
    case single
    case recurring

    var id: String { rawValue }

    /// Localization key for the mode title
    var titleKey: LocalizedStringResource {
        switch self {
        case .single:
            return .addShiftModeSingle
        case .recurring:
            return .addShiftModeRecurring
        }
    }
}
