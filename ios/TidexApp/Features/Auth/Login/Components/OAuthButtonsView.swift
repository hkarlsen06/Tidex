import SwiftUI

/// OAuth sign-in buttons for Google and Apple
struct OAuthButtonsView: View {
  let onGoogleTap: () -> Void
  let onAppleTap: () -> Void
  var isLoading: Bool = false

  var body: some View {
    VStack(spacing: Spacing.sm) {
      OAuthProviderButton(
        title: String(localized: .oauthContinueWithApple),
        action: onAppleTap,
        isLoading: isLoading
      ) {
        Image(systemName: "apple.logo")
          .font(.system(size: 19, weight: .medium))
      }

      OAuthProviderButton(
        title: String(localized: .oauthContinueWithGoogle),
        action: onGoogleTap,
        isLoading: isLoading
      ) {
        GoogleLogo()
      }
    }
  }
}

// MARK: - OAuth Provider Button

private struct OAuthProviderButton<Icon: View>: View {
  let title: String
  let action: () -> Void
  let isLoading: Bool
  @ViewBuilder let icon: () -> Icon

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button {
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      action()
    } label: {
      HStack(spacing: Spacing.sm) {
        icon()
          .frame(width: 19, height: 19)

        Text(title)
          .font(.system(size: 18, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.9)
      }
      .foregroundColor(colorScheme == .dark ? .black : .white)
      .padding(.leading, 64)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: 50)
      .background(colorScheme == .dark ? Color.white : Color.black)
      .overlay {
        RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous)
          .stroke(colorScheme == .dark ? Color.clear : Color.black.opacity(0.16), lineWidth: 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous))
    }
    .buttonStyle(SnappyButtonStyle())
    .disabled(isLoading)
    .opacity(isLoading ? 0.6 : 1)
  }
}

// MARK: - Google Logo

/// Official Google "G" logo with brand colors
/// Paths extracted from official Google SVG
private struct GoogleLogo: View {
  // Google brand colors
  private let googleBlue = Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255)
  private let googleGreen = Color(red: 52 / 255, green: 168 / 255, blue: 83 / 255)
  private let googleYellow = Color(red: 251 / 255, green: 188 / 255, blue: 5 / 255)
  private let googleRed = Color(red: 235 / 255, green: 67 / 255, blue: 53 / 255)

  var body: some View {
    ZStack {
      // Blue path (right side with horizontal bar)
      GoogleBluePath()
        .fill(googleBlue)

      // Green path (bottom right)
      GoogleGreenPath()
        .fill(googleGreen)

      // Yellow path (bottom left)
      GoogleYellowPath()
        .fill(googleYellow)

      // Red path (top)
      GoogleRedPath()
        .fill(googleRed)
    }
    .aspectRatio(1, contentMode: .fit)
  }
}

// MARK: - Google Logo Path Shapes

private struct GoogleBluePath: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let w = rect.width
    let h = rect.height
    path.move(to: CGPoint(x: 0.97663 * w, y: 0.50935 * h))
    path.addCurve(
      to: CGPoint(x: 0.96611 * w, y: 0.40748 * h),
      control1: CGPoint(x: 0.97663 * w, y: 0.46839 * h),
      control2: CGPoint(x: 0.97331 * w, y: 0.43849 * h)
    )
    path.addLine(to: CGPoint(x: 0.49828 * w, y: 0.40748 * h))
    path.addLine(to: CGPoint(x: 0.49828 * w, y: 0.5924 * h))
    path.addLine(to: CGPoint(x: 0.77289 * w, y: 0.5924 * h))
    path.addCurve(
      to: CGPoint(x: 0.67102 * w, y: 0.75406 * h),
      control1: CGPoint(x: 0.76735 * w, y: 0.63835 * h),
      control2: CGPoint(x: 0.73746 * w, y: 0.70756 * h)
    )
    path.addLine(to: CGPoint(x: 0.67009 * w, y: 0.76026 * h))
    path.addLine(to: CGPoint(x: 0.81801 * w, y: 0.87485 * h))
    path.addLine(to: CGPoint(x: 0.82826 * w, y: 0.87587 * h))
    path.addCurve(
      to: CGPoint(x: 0.97663 * w, y: 0.50935 * h),
      control1: CGPoint(x: 0.92237 * w, y: 0.78895 * h),
      control2: CGPoint(x: 0.97663 * w, y: 0.66105 * h)
    )
    return path
  }
}

private struct GoogleGreenPath: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let w = rect.width
    let h = rect.height
    path.move(to: CGPoint(x: 0.49828 * w, y: 0.99656 * h))
    path.addCurve(
      to: CGPoint(x: 0.82826 * w, y: 0.87587 * h),
      control1: CGPoint(x: 0.63282 * w, y: 0.99656 * h),
      control2: CGPoint(x: 0.74576 * w, y: 0.95227 * h)
    )
    path.addLine(to: CGPoint(x: 0.67102 * w, y: 0.75406 * h))
    path.addCurve(
      to: CGPoint(x: 0.49828 * w, y: 0.80389 * h),
      control1: CGPoint(x: 0.62894 * w, y: 0.78341 * h),
      control2: CGPoint(x: 0.57247 * w, y: 0.80389 * h)
    )
    path.addCurve(
      to: CGPoint(x: 0.21481 * w, y: 0.59683 * h),
      control1: CGPoint(x: 0.36652 * w, y: 0.80389 * h),
      control2: CGPoint(x: 0.25468 * w, y: 0.71697 * h)
    )
    path.addLine(to: CGPoint(x: 0.20897 * w, y: 0.59733 * h))
    path.addLine(to: CGPoint(x: 0.05516 * w, y: 0.71636 * h))
    path.addLine(to: CGPoint(x: 0.05315 * w, y: 0.72195 * h))
    path.addCurve(
      to: CGPoint(x: 0.49828 * w, y: 0.99656 * h),
      control1: CGPoint(x: 0.13509 * w, y: 0.88473 * h),
      control2: CGPoint(x: 0.3034 * w, y: 0.99656 * h)
    )
    return path
  }
}

private struct GoogleYellowPath: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let w = rect.width
    let h = rect.height
    path.move(to: CGPoint(x: 0.21481 * w, y: 0.59683 * h))
    path.addCurve(
      to: CGPoint(x: 0.19821 * w, y: 0.49828 * h),
      control1: CGPoint(x: 0.20429 * w, y: 0.56583 * h),
      control2: CGPoint(x: 0.19821 * w, y: 0.53261 * h)
    )
    path.addCurve(
      to: CGPoint(x: 0.21426 * w, y: 0.39973 * h),
      control1: CGPoint(x: 0.19821 * w, y: 0.46395 * h),
      control2: CGPoint(x: 0.20429 * w, y: 0.43074 * h)
    )
    path.addLine(to: CGPoint(x: 0.21398 * w, y: 0.39313 * h))
    path.addLine(to: CGPoint(x: 0.05824 * w, y: 0.27218 * h))
    path.addLine(to: CGPoint(x: 0.05315 * w, y: 0.27461 * h))
    path.addCurve(
      to: CGPoint(x: 0, y: 0.49828 * h),
      control1: CGPoint(x: 0.01938 * w, y: 0.34215 * h),
      control2: CGPoint(x: 0, y: 0.418 * h)
    )
    path.addCurve(
      to: CGPoint(x: 0.05315 * w, y: 0.72195 * h),
      control1: CGPoint(x: 0, y: 0.57856 * h),
      control2: CGPoint(x: 0.01938 * w, y: 0.65441 * h)
    )
    path.addLine(to: CGPoint(x: 0.21481 * w, y: 0.59683 * h))
    return path
  }
}

private struct GoogleRedPath: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let w = rect.width
    let h = rect.height
    path.move(to: CGPoint(x: 0.49828 * w, y: 0.19267 * h))
    path.addCurve(
      to: CGPoint(x: 0.69095 * w, y: 0.26686 * h),
      control1: CGPoint(x: 0.59185 * w, y: 0.19267 * h),
      control2: CGPoint(x: 0.65496 * w, y: 0.23308 * h)
    )
    path.addLine(to: CGPoint(x: 0.83158 * w, y: 0.12955 * h))
    path.addCurve(
      to: CGPoint(x: 0.49828 * w, y: 0),
      control1: CGPoint(x: 0.74521 * w, y: 0.04927 * h),
      control2: CGPoint(x: 0.63282 * w, y: 0)
    )
    path.addCurve(
      to: CGPoint(x: 0.05315 * w, y: 0.27461 * h),
      control1: CGPoint(x: 0.3034 * w, y: 0),
      control2: CGPoint(x: 0.13509 * w, y: 0.11184 * h)
    )
    path.addLine(to: CGPoint(x: 0.21426 * w, y: 0.39973 * h))
    path.addCurve(
      to: CGPoint(x: 0.49828 * w, y: 0.19267 * h),
      control1: CGPoint(x: 0.25468 * w, y: 0.27959 * h),
      control2: CGPoint(x: 0.36652 * w, y: 0.19267 * h)
    )
    return path
  }
}

#Preview {
  VStack(spacing: Spacing.mlg) {
    OAuthButtonsView(
      onGoogleTap: {},
      onAppleTap: {}
    )

    // Show Google logo standalone for verification
    HStack(spacing: Spacing.mlg) {
      GoogleLogo()
        .frame(width: 24, height: 24)

      GoogleLogo()
        .frame(width: 40, height: 40)

      GoogleLogo()
        .frame(width: 60, height: 60)
    }
    .padding()
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.lg)
  }
  .padding()
  .background(Color.tidexBackground)
}
