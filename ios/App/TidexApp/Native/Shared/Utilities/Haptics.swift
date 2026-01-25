import UIKit

/// Haptic feedback types for different interactions
enum HapticType {
    case success     // Successful operations (form submit, save)
    case error       // Errors and failures
    case warning     // Destructive action confirmations
    case light       // Subtle feedback (toggles, navigation)
    case medium      // Moderate feedback
    case heavy       // Strong feedback
    case selection   // Selection changes
}

/// Centralized haptic feedback manager
/// Provides consistent haptic feedback across the app
enum Haptics {
    /// Play haptic feedback of the specified type
    static func play(_ type: HapticType) {
        switch type {
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}
