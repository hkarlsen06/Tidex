import SwiftUI

/// A modifier that applies a shimmer animation to skeleton loading states
/// Creates a subtle left-to-right gradient sweep effect
struct ShimmerModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    let shouldAnimate = isActive && !reduceMotion
    content
      .overlay {
        if shouldAnimate {
          GeometryReader { geometry in
            LinearGradient(
              gradient: Gradient(colors: [
                .clear,
                .white.opacity(0.4),
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
        guard shouldAnimate else { return }
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

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.md) {
    // Skeleton card with shimmer
    VStack(spacing: Spacing.xs) {
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.tidexTextMuted.opacity(0.3))
        .frame(width: 200, height: 56)

      RoundedRectangle(cornerRadius: 6)
        .fill(Color.tidexTextMuted.opacity(0.3))
        .frame(width: 120, height: 16)
    }
    .padding(Spacing.lg)
    .background(
      RoundedRectangle(cornerRadius: 24)
        .fill(Color.tidexSurfacePrimary)
    )
    .shimmer()

    // Without shimmer for comparison
    VStack(spacing: Spacing.xs) {
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.tidexTextMuted.opacity(0.3))
        .frame(width: 200, height: 56)

      RoundedRectangle(cornerRadius: 6)
        .fill(Color.tidexTextMuted.opacity(0.3))
        .frame(width: 120, height: 16)
    }
    .padding(Spacing.lg)
    .background(
      RoundedRectangle(cornerRadius: 24)
        .fill(Color.tidexSurfacePrimary)
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
