// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl file_types_order no_magic_numbers
import SwiftUI

/// Three pulsing dots indicator, similar to iMessage typing indicator.
struct TypingIndicatorView: View {
  var background: Color = .tidexSurfacePrimary
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var dotScales: [Bool] = [false, false, false]

  var body: some View {
    HStack(spacing: 5) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(Color.tidexTextMuted)
          .frame(width: 7, height: 7)
          .scaleEffect(reduceMotion || dotScales[index] ? 1.0 : 0.5)
          .opacity(reduceMotion || dotScales[index] ? 1.0 : 0.4)
      }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.msm)
    .background(background)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.bubble, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(.commonAccessibilityTyping))
    .onAppear {
      guard !reduceMotion else { return }
      for index in 0..<3 {
        withAnimation(
          .easeInOut(duration: 0.5)
            .repeatForever(autoreverses: true)
            .delay(Double(index) * 0.15)
        ) {
          dotScales[index] = true
        }
      }
    }
  }
}
