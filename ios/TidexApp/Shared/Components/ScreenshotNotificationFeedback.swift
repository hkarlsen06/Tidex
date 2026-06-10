// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface no_magic_numbers
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable required_deinit
import Foundation
import SwiftUI

@MainActor
final class ScreenshotNotificationFeedback: ObservableObject {
  @Published var showsBubble = false
  @Published var showsNotifiedIcon = false
  @Published var bellShakeTrigger = false

  func showBubble() {
    showsNotifiedIcon = false
    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
      showsBubble = true
    }
  }

  func markSent() async {
    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
      showsNotifiedIcon = true
    }
    Haptics.play(.success)
    try? await Task.sleep(for: .seconds(0.3))
    bellShakeTrigger.toggle()
  }

  func dismiss() {
    withAnimation(.easeOut(duration: 0.2)) {
      showsBubble = false
    }

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(0.3))
      self.showsNotifiedIcon = false
      self.bellShakeTrigger = false
    }
  }
}
