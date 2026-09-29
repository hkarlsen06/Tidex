// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable cyclomatic_complexity explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers sorted_enum_cases vertical_whitespace_between_cases
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
