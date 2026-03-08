import SwiftUI

struct ScreenshotNotificationBubble: View {
  let showNotifiedIcon: Bool
  let bellShakeTrigger: Bool

  var body: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "camera.viewfinder")
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      Text(.sharingScreenshotTaken)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexTextSecondary)

      if showNotifiedIcon {
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
      }
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xs)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.xxxl)
    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
  }
}

private struct BellShake {
  var angle: Double = 0
}
