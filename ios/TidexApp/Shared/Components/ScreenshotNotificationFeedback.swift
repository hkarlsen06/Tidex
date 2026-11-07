// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface no_magic_numbers
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable required_deinit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ScreenshotNotificationFeedback {
  var showsBubble = false
  var showsNotifiedIcon = false
  var bellShakeTrigger = false

  func showBubble() {
    showsNotifiedIcon = false
    let reduceMotion = UIAccessibility.isReduceMotionEnabled
    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
      showsBubble = true
    }
  }

  func markSent() async {
    let reduceMotion = UIAccessibility.isReduceMotionEnabled
    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6)) {
      showsNotifiedIcon = true
    }
    Haptics.play(.success)
    do { try await Task.sleep(for: .seconds(0.3)) } catch { return }
    if !UIAccessibility.isReduceMotionEnabled {
      bellShakeTrigger.toggle()
    }
  }

  func dismiss() {
    withAnimation(.easeOut(duration: 0.2), completionCriteria: .removed) {
      showsBubble = false
    } completion: {
      guard !self.showsBubble else { return }
      self.showsNotifiedIcon = false
      self.bellShakeTrigger = false
    }
  }
}
