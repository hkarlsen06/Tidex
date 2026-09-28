// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface file_types_order
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers
import SwiftUI

/// Consistent glass styling built on Liquid Glass.
enum TidexGlassShape {
  case rect(cornerRadius: CGFloat)
  case capsule
  case circle

  fileprivate var resolved: AnyShape {
    switch self {
    case .rect(let cornerRadius):
      return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

    case .capsule:
      return AnyShape(Capsule())

    case .circle:
      return AnyShape(Circle())
    }
  }
}

extension View {
  /// Applies a Liquid Glass effect, or a solid fallback when `disabled` is set.
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
  @Environment(\.colorScheme) private var colorScheme

  let shape: TidexGlassShape
  let tint: Color?
  let clear: Bool
  let interactive: Bool
  let disabled: Bool
  let fallbackOpacity: Double

  private var glassEffect: Glass {
    var effect: Glass = clear ? .clear : .regular
    if let tint {
      effect = effect.tint(tint)
    }
    if interactive {
      effect = effect.interactive()
    }
    return effect
  }

  func body(content: Content) -> some View {
    if disabled {
      let fallbackBase = Color.tidexGlassSurface.opacity(fallbackOpacity)
      let fallbackTint = tint?.opacity(colorScheme == .dark ? 0.24 : 0.16) ?? .clear
      content
        .background(
          shape.resolved
            .fill(fallbackBase)
            .overlay(shape.resolved.fill(fallbackTint))
        )
        .overlay(shape.resolved.stroke(Color.tidexBorderSubtle, lineWidth: 1))
    } else {
      content.glassEffect(glassEffect, in: shape.resolved)
    }
  }
}
