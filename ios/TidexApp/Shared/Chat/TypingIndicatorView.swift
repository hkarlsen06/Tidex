// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl file_types_order no_magic_numbers
import SwiftUI

/// Three pulsing dots indicator, similar to iMessage typing indicator.
struct TypingIndicatorView: View {
  var background: Color = .tidexSurfacePrimary
  @State private var dotScales: [Bool] = [false, false, false]

  var body: some View {
    HStack(spacing: 5) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(Color.tidexTextMuted)
          .frame(width: 7, height: 7)
          .scaleEffect(dotScales[index] ? 1.0 : 0.5)
          .opacity(dotScales[index] ? 1.0 : 0.4)
      }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.msm)
    .background(background)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.bubble, style: .continuous))
    .onAppear {
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

/// Inline jumping dot sequence used in the explicit thinking bubble.
struct InlineJumpingDotsView: View {
  @State private var dotOffsets: [Bool] = [false, false, false]

  var body: some View {
    HStack(spacing: 1) {
      ForEach(0..<3, id: \.self) { index in
        Text(".")
          .font(.tidexFootnoteMedium)
          .foregroundColor(.tidexTextMuted)
          .offset(y: dotOffsets[index] ? -2 : 1)
          .opacity(dotOffsets[index] ? 1.0 : 0.45)
      }
    }
    .onAppear {
      for index in 0..<3 {
        withAnimation(
          .easeInOut(duration: 0.38)
            .repeatForever(autoreverses: true)
            .delay(Double(index) * 0.15)
        ) {
          dotOffsets[index] = true
        }
      }
    }
  }
}
