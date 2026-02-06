import SwiftUI

/// Consistent glass styling that respects Reduce Transparency.
enum TidexGlassShape {
  case rect(cornerRadius: CGFloat)
  case capsule
  case circle
}

extension View {
  /// Applies glass effect when available, or a solid fallback when Reduce Transparency is enabled.
  func tidexGlass(
    shape: TidexGlassShape,
    tint: Color? = nil,
    interactive: Bool = false,
    fallbackOpacity: Double = 0.94
  ) -> some View {
    modifier(
      TidexGlassModifier(
        shape: shape, tint: tint, interactive: interactive, fallbackOpacity: fallbackOpacity))
  }
}

private struct TidexGlassModifier: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  let shape: TidexGlassShape
  let tint: Color?
  let interactive: Bool
  let fallbackOpacity: Double

  private var glassEffect: Glass {
    var effect = Glass.regular
    if let tint {
      effect = effect.tint(tint)
    }
    if interactive {
      effect = effect.interactive()
    }
    return effect
  }

  func body(content: Content) -> some View {
    let fallbackBase = Color.tidexSurfacePrimary.opacity(fallbackOpacity)
    let fallbackTint = tint?.opacity(0.18) ?? .clear

    if reduceTransparency {
      switch shape {
      case .rect(let cornerRadius):
        content
          .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
              .fill(fallbackBase)
              .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                  .fill(fallbackTint)
              )
          )
          .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
              .stroke(Color.tidexBorderSubtle, lineWidth: 1)
          )
      case .capsule:
        content
          .background(
            Capsule()
              .fill(fallbackBase)
              .overlay(
                Capsule()
                  .fill(fallbackTint)
              )
          )
          .overlay(
            Capsule()
              .stroke(Color.tidexBorderSubtle, lineWidth: 1)
          )
      case .circle:
        content
          .background(
            Circle()
              .fill(fallbackBase)
              .overlay(
                Circle()
                  .fill(fallbackTint)
              )
          )
          .overlay(
            Circle()
              .stroke(Color.tidexBorderSubtle, lineWidth: 1)
          )
      }
    } else {
      switch shape {
      case .rect(let cornerRadius):
        content.glassEffect(glassEffect, in: .rect(cornerRadius: cornerRadius))
      case .capsule:
        content.glassEffect(glassEffect, in: .capsule)
      case .circle:
        content.glassEffect(glassEffect, in: .circle)
      }
    }
  }
}
