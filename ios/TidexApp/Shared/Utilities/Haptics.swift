import UIKit

/// Haptic feedback types for different interactions
enum HapticType {
  case success  // Successful operations (form submit, save)
  case error  // Errors and failures
  case warning  // Destructive action confirmations
  case light  // Subtle feedback (toggles, navigation)
  case medium  // Moderate feedback
  case heavy  // Strong feedback
  case selection  // Selection changes
  case hold  // Firm, pronounced feedback (like pressing down)
  case release  // Soft, gentle feedback (like releasing a press)
}

@MainActor
enum Haptics {
  // swiftlint:disable:next cyclomatic_complexity
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

    case .hold:
      UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)

    case .release:
      UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }
  }

  /// Play shift creation success feedback
  static func playShiftCreationSuccess() {
    play(.success)
  }

  /// Play shift deletion feedback
  static func playShiftDeleted() {
    play(.warning)
  }
}
