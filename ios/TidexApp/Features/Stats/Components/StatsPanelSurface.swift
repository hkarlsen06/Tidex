import SwiftUI  // swiftlint:disable:this file_name

struct StatsPanelSurfaceModifier: ViewModifier {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let padding: CGFloat  // swiftlint:disable:this explicit_acl
  let cornerRadius: CGFloat  // swiftlint:disable:this explicit_acl
  let shadowLevel: TidexShadowLevel  // swiftlint:disable:this explicit_acl

  func body(content: Content) -> some View {  // swiftlint:disable:this explicit_acl
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)  // swiftlint:disable:this explicit_type_interface line_length

    content
      .padding(padding)
      .background(shape.fill(Color.tidexSurfacePrimary))
      .clipShape(shape)
      .overlay(
        shape.strokeBorder(Color.tidexBorderSubtle.opacity(0.42), lineWidth: 1)  // swiftlint:disable:this line_length no_magic_numbers
      )
      .tidexCardShadow(shadowLevel, cornerRadius: cornerRadius)
  }
}

extension View {
  func statsPanelSurface(  // swiftlint:disable:this explicit_acl
    padding: CGFloat = Spacing.mlg,
    cornerRadius: CGFloat = CornerRadius.xxl,
    shadowLevel: TidexShadowLevel = .subtle
  ) -> some View {
    modifier(
      StatsPanelSurfaceModifier(
        padding: padding,
        cornerRadius: cornerRadius,
        shadowLevel: shadowLevel
      ))  // swiftlint:disable:this multiline_arguments_brackets
  }
}
