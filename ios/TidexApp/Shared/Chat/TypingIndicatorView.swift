import SwiftUI

/// Three pulsing dots indicator, similar to iMessage typing indicator.
struct TypingIndicatorView: View {
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
    .background(Color.tidexSurfacePrimary)
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
