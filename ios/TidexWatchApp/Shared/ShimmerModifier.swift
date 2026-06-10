import SwiftUI

/// A modifier that applies a shimmer animation to skeleton loading states
/// Creates a subtle left-to-right gradient sweep effect
internal struct ShimmerModifier: ViewModifier {
  internal enum Constants {
    internal static let initialPhase: CGFloat = -1
    internal static let completedPhase: CGFloat = 1
    internal static let defaultDuration: Double = 1.5
    internal static let highlightOpacity: Double = 0.3
    internal static let bandWidthMultiplier: CGFloat = 0.6
    internal static let travelWidthMultiplier: CGFloat = 1.6
  }

  @State private var phase: CGFloat = Constants.initialPhase

  /// Duration of one complete shimmer cycle
  internal let duration: Double

  /// Whether shimmer is active
  internal let isActive: Bool

  internal init(duration: Double = Constants.defaultDuration, isActive: Bool = true) {
    self.duration = duration
    self.isActive = isActive
  }

  internal func body(content: Content) -> some View {
    content
      .overlay {
        if isActive {
          GeometryReader { geometry in
            LinearGradient(
              gradient: Gradient(colors: [
                .clear,
                .white.opacity(Constants.highlightOpacity),
                .clear,
              ]),
              startPoint: .leading,
              endPoint: .trailing
            )
            .frame(width: geometry.size.width * Constants.bandWidthMultiplier)
            .offset(x: phase * geometry.size.width * Constants.travelWidthMultiplier)
            .blendMode(.overlay)
          }
          .mask(content)
        }
      }
      .onAppear {
        guard isActive else {
          return
        }
        withAnimation(
          .linear(duration: duration)
            .repeatForever(autoreverses: false)
        ) {
          phase = Constants.completedPhase
        }
      }
  }
}

// MARK: - View Extension

internal extension View {
  /// Applies a shimmer animation for loading states
  /// - Parameters:
  ///   - isActive: Whether the shimmer is active (default true)
  ///   - duration: Duration of one shimmer cycle (default 1.5s)
  func shimmer(isActive: Bool = true, duration: Double = ShimmerModifier.Constants.defaultDuration) -> some View {
    modifier(ShimmerModifier(duration: duration, isActive: isActive))
  }
}
