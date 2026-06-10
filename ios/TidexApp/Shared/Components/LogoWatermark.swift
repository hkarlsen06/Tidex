// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface function_body_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable multiline_arguments_brackets no_magic_numbers prefixed_toplevel_constant
import SwiftUI

/// Logo gradient colors from short-logo-gradient.svg
private let logoGradientColors = [
  Color(red: 0, green: 212 / 255, blue: 1),  // #00D4FF - cyan (top)
  Color(red: 123 / 255, green: 97 / 255, blue: 1),  // #7B61FF - purple (middle)
  Color(red: 155 / 255, green: 77 / 255, blue: 202 / 255),  // #9B4DCA - magenta (bottom)
]

/// Tidex short logo shape - exact path from short-logo-gradient.svg
struct TidexLogoShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()

    // Original path bounds
    let pathMinX: CGFloat = 0.63993
    let pathMaxX: CGFloat = 1.2635
    let pathMinY: CGFloat = 1.7177
    let pathMaxY: CGFloat = 2.311

    let pathWidth = pathMaxX - pathMinX
    let pathHeight = pathMaxY - pathMinY

    // Use uniform scaling to preserve aspect ratio
    let scale = min(rect.width / pathWidth, rect.height / pathHeight)

    // Center the path in the rect
    let scaledWidth = pathWidth * scale
    let scaledHeight = pathHeight * scale
    let offsetX = (rect.width - scaledWidth) / 2
    let offsetY = (rect.height - scaledHeight) / 2

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(
        x: offsetX + (x - pathMinX) * scale,
        y: offsetY + (y - pathMinY) * scale
      )
    }

    path.move(to: pt(1.23732, 1.7177))
    path.addCurve(
      to: pt(0.66612, 1.7177), control1: pt(1.13775, 1.7179), control2: pt(0.76566, 1.71337))
    path.addCurve(
      to: pt(0.63993, 1.74003), control1: pt(0.65617, 1.71814), control2: pt(0.6412, 1.72111))
    path.addCurve(
      to: pt(0.63993, 1.81659), control1: pt(0.6388, 1.75702), control2: pt(0.6372, 1.79978))
    path.addCurve(
      to: pt(0.66612, 1.83892), control1: pt(0.6412, 1.82434), control2: pt(0.64969, 1.83921))
    path.addCurve(
      to: pt(0.83797, 1.83892), control1: pt(0.69934, 1.83832), control2: pt(0.80156, 1.83786))
    path.addCurve(
      to: pt(0.88052, 1.88038), control1: pt(0.85928, 1.83953), control2: pt(0.88041, 1.85613))
    path.addCurve(
      to: pt(0.88052, 2.311), control1: pt(0.88091, 1.95937), control2: pt(0.88011, 2.24337))
    path.addCurve(
      to: pt(1.02782, 2.25997), control1: pt(0.88095, 2.38083), control2: pt(1.02782, 2.32572))
    path.addCurve(
      to: pt(1.02782, 1.87719), control1: pt(1.02783, 2.18381), control2: pt(1.02715, 1.94768))
    path.addCurve(
      to: pt(1.06874, 1.83892), control1: pt(1.02797, 1.86204), control2: pt(1.04362, 1.83915))
    path.addCurve(
      to: pt(1.23568, 1.83892), control1: pt(1.10399, 1.83859), control2: pt(1.20286, 1.83973))
    path.addCurve(
      to: pt(1.2635, 1.81021), control1: pt(1.25067, 1.83854), control2: pt(1.26304, 1.83083))
    path.addCurve(
      to: pt(1.2635, 1.74482), control1: pt(1.26387, 1.79389), control2: pt(1.26396, 1.76203))
    path.addCurve(
      to: pt(1.23732, 1.7177), control1: pt(1.26317, 1.73255), control2: pt(1.25496, 1.71767))
    path.closeSubpath()

    return path
  }
}

/// Gradient-filled logo watermark with brand colors from short-logo-gradient.svg
struct LogoWatermark: View {
  var opacity: Double = 0.15

  var body: some View {
    TidexLogoShape()
      .fill(
        LinearGradient(
          colors: logoGradientColors,
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .opacity(opacity)
  }
}

#Preview {
  VStack(spacing: Spacing.mlg) {
    LogoWatermark()
      .frame(width: 64, height: 64)

    LogoWatermark(opacity: 0.5)
      .frame(width: 32, height: 32)
  }
  .padding()
}
