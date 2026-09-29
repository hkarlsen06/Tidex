// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image explicit_acl explicit_top_level_acl file_types_order
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers
import SwiftUI

struct ScreenshotNotificationBubble: View {
  /// First name of the person who gets the screenshot notification.
  let notifiedName: String
  let showNotifiedIcon: Bool
  let bellShakeTrigger: Bool

  var body: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "camera.viewfinder")
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)
        .accessibilityHidden(true)

      Text(.sharingScreenshotTaken)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexTextSecondary)

      if showNotifiedIcon {
        notifiedBell

        Text(.sharingScreenshotNotified(notifiedName))
          .font(.tidexFootnoteMedium)
          .foregroundColor(.tidexTextSecondary)
          .lineLimit(1)
          .transition(.opacity)
      }
    }
    .accessibilityElement(children: .combine)
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xs)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.xxxl)
    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
  }

  private var notifiedBell: some View {
    Image(systemName: "bell.and.waves.left.and.right")
      .font(.tidexCaption)
      .foregroundColor(.tidexBlue)
      .keyframeAnimator(initialValue: BellShake(), trigger: bellShakeTrigger) {
        content, value in
        content.rotationEffect(.degrees(value.angle), anchor: .top)
      } keyframes: { _ in
        KeyframeTrack(\.angle) {
          SpringKeyframe(15, duration: 0.1, spring: .bouncy)
          SpringKeyframe(-12, duration: 0.1, spring: .bouncy)
          SpringKeyframe(8, duration: 0.1, spring: .bouncy)
          SpringKeyframe(-5, duration: 0.1, spring: .bouncy)
          SpringKeyframe(2, duration: 0.1, spring: .bouncy)
          SpringKeyframe(0, duration: 0.15, spring: .bouncy)
        }
      }
      .transition(.scale.combined(with: .opacity))
      .accessibilityHidden(true)
  }
}

private struct BellShake {
  var angle: Double = 0
}
