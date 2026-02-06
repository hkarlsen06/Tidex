import SwiftUI

/// A modifier that applies a shimmer animation to skeleton loading states
/// Creates a subtle left-to-right gradient sweep effect
struct ShimmerModifier: ViewModifier {
  @State private var phase: CGFloat = -1

  /// Duration of one complete shimmer cycle
  let duration: Double

  /// Whether shimmer is active
  let isActive: Bool

  init(duration: Double = 1.5, isActive: Bool = true) {
    self.duration = duration
    self.isActive = isActive
  }

  func body(content: Content) -> some View {
    content
      .overlay {
        if isActive {
          GeometryReader { geometry in
            LinearGradient(
              gradient: Gradient(colors: [
                .clear,
                .white.opacity(0.3),
                .clear,
              ]),
              startPoint: .leading,
              endPoint: .trailing
            )
            .frame(width: geometry.size.width * 0.6)
            .offset(x: phase * geometry.size.width * 1.6)
            .blendMode(.overlay)
          }
          .mask(content)
        }
      }
      .onAppear {
        guard isActive else { return }
        withAnimation(
          .linear(duration: duration)
            .repeatForever(autoreverses: false)
        ) {
          phase = 1
        }
      }
  }
}

// MARK: - View Extension

extension View {
  /// Applies a shimmer animation for loading states
  /// - Parameters:
  ///   - isActive: Whether the shimmer is active (default true)
  ///   - duration: Duration of one shimmer cycle (default 1.5s)
  func shimmer(isActive: Bool = true, duration: Double = 1.5) -> some View {
    modifier(ShimmerModifier(duration: duration, isActive: isActive))
  }
}
