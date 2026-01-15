import SwiftUI

/// OAuth sign-in buttons for Google and Apple
struct OAuthButtonsView: View {
    let onGoogleTap: () -> Void
    let onAppleTap: () -> Void
    var isLoading: Bool = false

    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 12) {
            // Apple Sign-In Button
            AppleSignInButton(
                title: localization.string("oauth.continueWithApple"),
                action: onAppleTap,
                isLoading: isLoading
            )

            // Google Sign-In Button
            GoogleSignInButton(
                title: localization.string("oauth.continueWithGoogle"),
                action: onGoogleTap,
                isLoading: isLoading
            )
        }
    }
}

// MARK: - Apple Sign-In Button

private struct AppleSignInButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .semibold))

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundColor(.white)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(SnappyButtonStyle())
        .disabled(isLoading)
        .opacity(isLoading ? 0.6 : 1)
    }
}

// MARK: - Google Sign-In Button

private struct GoogleSignInButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                GoogleLogo()
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.tidexBorder, lineWidth: 1)
            )
        }
        .buttonStyle(SnappyButtonStyle())
        .disabled(isLoading)
        .opacity(isLoading ? 0.6 : 1)
    }
}

// MARK: - Google Logo

/// Google "G" logo using SwiftUI shapes with brand colors
private struct GoogleLogo: View {
    // Google brand colors
    private let googleBlue = Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255)
    private let googleRed = Color(red: 219 / 255, green: 68 / 255, blue: 55 / 255)
    private let googleYellow = Color(red: 244 / 255, green: 180 / 255, blue: 0 / 255)
    private let googleGreen = Color(red: 15 / 255, green: 157 / 255, blue: 88 / 255)

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let outerRadius = size / 2
            let strokeWidth = size * 0.22

            ZStack {
                // Blue arc (right side, top-right quadrant)
                Arc(startAngle: .degrees(-45), endAngle: .degrees(45), clockwise: false)
                    .stroke(googleBlue, lineWidth: strokeWidth)
                    .frame(width: outerRadius * 2 - strokeWidth, height: outerRadius * 2 - strokeWidth)

                // Green arc (bottom-right quadrant)
                Arc(startAngle: .degrees(45), endAngle: .degrees(135), clockwise: false)
                    .stroke(googleGreen, lineWidth: strokeWidth)
                    .frame(width: outerRadius * 2 - strokeWidth, height: outerRadius * 2 - strokeWidth)

                // Yellow arc (bottom-left quadrant)
                Arc(startAngle: .degrees(135), endAngle: .degrees(195), clockwise: false)
                    .stroke(googleYellow, lineWidth: strokeWidth)
                    .frame(width: outerRadius * 2 - strokeWidth, height: outerRadius * 2 - strokeWidth)

                // Red arc (top-left and top quadrant)
                Arc(startAngle: .degrees(195), endAngle: .degrees(315), clockwise: false)
                    .stroke(googleRed, lineWidth: strokeWidth)
                    .frame(width: outerRadius * 2 - strokeWidth, height: outerRadius * 2 - strokeWidth)

                // Blue horizontal bar (the "crossbar" of the G)
                Rectangle()
                    .fill(googleBlue)
                    .frame(width: size * 0.45, height: strokeWidth)
                    .offset(x: size * 0.1, y: 0)
            }
            .frame(width: size, height: size)
            .position(center)
        }
    }
}

// MARK: - Arc Shape

private struct Arc: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var clockwise: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
        return path
    }
}

// MARK: - Snappy Button Style

/// Button style with immediate press feedback - feels snappy and responsive
private struct SnappyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 20) {
        OAuthButtonsView(
            onGoogleTap: {},
            onAppleTap: {}
        )

        // Show Google logo standalone for verification
        HStack(spacing: 20) {
            GoogleLogo()
                .frame(width: 24, height: 24)

            GoogleLogo()
                .frame(width: 40, height: 40)

            GoogleLogo()
                .frame(width: 60, height: 60)
        }
        .padding()
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(12)
    }
    .padding()
    .background(Color.tidexDarkBackground)
}
