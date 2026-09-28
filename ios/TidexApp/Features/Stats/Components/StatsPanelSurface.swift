import SwiftUI  // swiftlint:disable:this file_name

struct StatsPanelSurfaceModifier: ViewModifier {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let padding: CGFloat  // swiftlint:disable:this explicit_acl
  let cornerRadius: CGFloat  // swiftlint:disable:this explicit_acl

  func body(content: Content) -> some View {  // swiftlint:disable:this explicit_acl
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)  // swiftlint:disable:this explicit_type_interface line_length

    content
      .padding(padding)
      .background(shape.fill(Color.tidexSurfacePrimary))
      .clipShape(shape)
  }
}

extension View {
  func statsPanelSurface(  // swiftlint:disable:this explicit_acl
    padding: CGFloat = Spacing.mlg,
    cornerRadius: CGFloat = CornerRadius.xxl
  ) -> some View {
    modifier(
      StatsPanelSurfaceModifier(
        padding: padding,
        cornerRadius: cornerRadius
      ))  // swiftlint:disable:this multiline_arguments_brackets
  }
}
