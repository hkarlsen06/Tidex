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
    clear: Bool = false,
    interactive: Bool = false,
    disabled: Bool = false,
    fallbackOpacity: Double = 0.94
  ) -> some View {
    modifier(
      TidexGlassModifier(
        shape: shape,
        tint: tint,
        clear: clear,
        interactive: interactive,
        disabled: disabled,
        fallbackOpacity: fallbackOpacity
      ))
  }
}

private struct TidexGlassModifier: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme

  let shape: TidexGlassShape
  let tint: Color?
  let clear: Bool
  let interactive: Bool
  let disabled: Bool
  let fallbackOpacity: Double

  private var glassEffect: Glass {
    var effect: Glass = clear ? .clear : .regular
    if let resolvedTint {
      effect = effect.tint(resolvedTint)
    }
    if interactive {
      effect = effect.interactive()
    }
    return effect
  }

  func body(content: Content) -> some View {
    let fallbackBase = Color.tidexGlassSurface.opacity(fallbackOpacity)
    let fallbackTint = resolvedTint?.opacity(colorScheme == .dark ? 0.24 : 0.16) ?? .clear

    if reduceTransparency || disabled {
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
        content
          .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
              .fill(glassBaseFill)
          )
          .glassEffect(glassEffect, in: .rect(cornerRadius: cornerRadius))
      case .capsule:
        content
          .background(Capsule().fill(glassBaseFill))
          .glassEffect(glassEffect, in: .capsule)
      case .circle:
        content
          .background(Circle().fill(glassBaseFill))
          .glassEffect(glassEffect, in: .circle)
      }
    }
  }

  private var resolvedTint: Color? {
    tint ?? Color.tidexGlassSurface.opacity(colorScheme == .dark ? 0.86 : 0.42)
  }

  private var glassBaseFill: Color {
    Color.tidexGlassSurface.opacity(colorScheme == .dark ? (clear ? 0.34 : 0.26) : 0.10)
  }
}
