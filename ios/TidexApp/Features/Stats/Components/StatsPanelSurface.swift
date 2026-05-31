import SwiftUI

struct StatsPanelSurfaceModifier: ViewModifier {
  let padding: CGFloat
  let cornerRadius: CGFloat
  let shadowLevel: TidexShadowLevel

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    content
      .padding(padding)
      .background(shape.fill(Color.tidexSurfacePrimary))
      .clipShape(shape)
      .overlay(
        shape.strokeBorder(Color.tidexBorderSubtle.opacity(0.42), lineWidth: 1)
      )
      .tidexCardShadow(shadowLevel, cornerRadius: cornerRadius)
  }
}

extension View {
  func statsPanelSurface(
    padding: CGFloat = Spacing.mlg,
    cornerRadius: CGFloat = CornerRadius.xxl,
    shadowLevel: TidexShadowLevel = .subtle
  ) -> some View {
    modifier(
      StatsPanelSurfaceModifier(
        padding: padding,
        cornerRadius: cornerRadius,
        shadowLevel: shadowLevel
      ))
  }
}
