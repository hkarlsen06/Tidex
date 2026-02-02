import SwiftUI

// MARK: - Tidex Adaptive Color System
//
// This color system automatically adapts to iOS system appearance (light/dark mode).
// Colors are organized into semantic categories that match the web app's CSS tokens
// defined in globals.css.
//
// Usage: Always use these semantic colors in views (e.g., Color.tidexBackground)
// rather than hardcoded values. This ensures consistent theming across the app.

extension Color {
    // MARK: - Background Colors

    /// Main app background - adapts to light/dark mode
    /// Light: HSlocalized(220, 40%, 98%) - soft off-white
    /// Dark: HSlocalized(222.2, 84%, 4.9%) - deep navy
    static var tidexBackground: Color {
        Color("TidexBackground")
    }

    /// Secondary background for nested containers
    /// Light: HSlocalized(220, 35%, 95%)
    /// Dark: HSlocalized(222.2, 84%, 4.9%)
    static var tidexBackgroundSecondary: Color {
        Color("TidexBackgroundSecondary")
    }

    /// Launch screen background - adapts to light/dark mode
    /// Light: HSlocalized(220, 40%, 98%) - soft off-white (matches tidexBackground)
    /// Dark: HSlocalized(222.2, 84%, 4.9%) - deep navy (matches tidexBackground)
    static var tidexLaunchBackground: Color {
        Color("LaunchBackground")
    }

    /// Surface primary for cards and elevated containers
    /// Light: Pure white (#FFFFFF) - maximum contrast against blue-tinted background
    /// Dark: #142133 - lighter navy for better card separation
    static var tidexSurfacePrimary: Color {
        Color("TidexSurfacePrimary")
    }

    /// Surface secondary for nested elements within cards
    /// Light: Very light gray (#F7F8F8) - subtle distinction from primary
    /// Dark: #1C2A3D - lighter for better contrast
    static var tidexSurfaceSecondary: Color {
        Color("TidexSurfaceSecondary")
    }

    // MARK: - Text Colors

    /// Primary text color for headings and important content
    /// Light: HSlocalized(222, 84%, 8%) - near black
    /// Dark: HSlocalized(210, 40%, 98%) - near white
    static var tidexTextPrimary: Color {
        Color("TidexTextPrimary")
    }

    /// Secondary text color for body text and descriptions
    /// Light: HSlocalized(214, 28%, 35%)
    /// Dark: HSlocalized(214, 32%, 85%)
    static var tidexTextSecondary: Color {
        Color("TidexTextSecondary")
    }

    /// Muted text color for hints, placeholders, and disabled content
    /// Light: #596B80 - darker for better contrast (WCAG AA compliant)
    /// Dark: HSlocalized(215, 20%, 70%)
    static var tidexTextMuted: Color {
        Color("TidexTextMuted")
    }

    /// Inverse text color (light on dark surfaces or vice versa)
    /// Light: HSlocalized(210, 40%, 98%)
    /// Dark: HSlocalized(222, 47%, 11%)
    static var tidexTextInverse: Color {
        Color("TidexTextInverse")
    }

    // MARK: - Brand Colors

    /// Tidex brand highlight color - accent blue
    /// Light: HSlocalized(221, 83%, 53%) - vibrant blue
    /// Dark: HSlocalized(217, 91%, 65%) - bright blue
    static var tidexBlue: Color {
        Color("TidexBlue")
    }

    /// Brand primary for buttons and primary actions
    /// Slightly desaturated version of brand blue for better contrast
    static var tidexBrandPrimary: Color {
        Color("TidexBrandPrimary")
    }

    // MARK: - Border Colors

    /// Border color for inputs, cards, and dividers
    /// Light: #C7D1DB - darker for better visibility
    /// Dark: #384761 - lighter for better visibility
    static var tidexBorder: Color {
        Color("TidexBorder")
    }

    /// Subtle border for light dividers
    /// Light: #D9E0E8 - darker for better visibility
    /// Dark: #303D52 - lighter for better visibility
    static var tidexBorderSubtle: Color {
        Color("TidexBorderSubtle")
    }

    // MARK: - Status Colors

    /// Error/destructive color - red
    /// Light: HSlocalized(0, 84%, 44%)
    /// Dark: HSlocalized(0, 91%, 60%)
    static var tidexError: Color {
        Color("TidexError")
    }

    /// Success color - green
    /// Light: HSlocalized(142, 76%, 28%)
    /// Dark: HSlocalized(142, 71%, 50%)
    static var tidexSuccess: Color {
        Color("TidexSuccess")
    }

    /// Warning color - amber/orange
    /// Light: HSlocalized(30, 100%, 35%)
    /// Dark: HSlocalized(38, 100%, 55%)
    static var tidexWarning: Color {
        Color("TidexWarning")
    }

    /// Info color - blue (matches brand)
    static var tidexInfo: Color {
        tidexBlue
    }

    /// Purple color for Max tier branding
    /// HSlocalized(258, 70%, 60%) - vibrant purple
    static var tidexPurple: Color {
        Color(hue: 258 / 360, saturation: 0.70, brightness: 0.75)
    }

    // MARK: - Gradient Colors

    /// Logo gradient colors from short-logo-gradient.svg
    /// These remain constant regardless of appearance mode
    static let logoGradientColors = [
        Color(red: 0, green: 212 / 255, blue: 1),              // #00D4FF - cyan (top)
        Color(red: 123 / 255, green: 97 / 255, blue: 1),       // #7B61FF - purple (middle)
        Color(red: 155 / 255, green: 77 / 255, blue: 202 / 255) // #9B4DCA - magenta (bottom)
    ]

}

// MARK: - Programmatic Adaptive Colors
//
// These are used as fallbacks and for the widget (which can't access main app assets)

extension Color {
    /// Light mode background - HSlocalized(220, 40%, 98%)
    static let tidexLightBackground = Color(hue: 220 / 360, saturation: 0.40, brightness: 0.98)

    /// Dark mode background - HSlocalized(222.2, 84%, 4.9%)
    static let tidexDarkBackgroundColor = Color(hue: 222.2 / 360, saturation: 0.84, brightness: 0.11)

    /// Light mode surface primary - Pure white for maximum contrast against blue-tinted background
    static let tidexLightSurfacePrimary = Color.white

    /// Dark mode surface primary - Lighter for better card separation (#142133)
    static let tidexDarkSurfacePrimary = Color(red: 0.08, green: 0.13, blue: 0.20)

    /// Light mode surface secondary - Very light gray (#F7F8F8)
    static let tidexLightSurfaceSecondary = Color(red: 0.965, green: 0.969, blue: 0.973)

    /// Dark mode surface secondary - Lighter for better contrast (#1C2A3D)
    static let tidexDarkSurfaceSecondary = Color(red: 0.11, green: 0.165, blue: 0.24)

    /// Light mode text primary - HSlocalized(222, 84%, 8%)
    static let tidexLightTextPrimary = Color(hue: 222 / 360, saturation: 0.84, brightness: 0.08)

    /// Dark mode text primary - HSlocalized(210, 40%, 98%)
    static let tidexDarkTextPrimary = Color(hue: 210 / 360, saturation: 0.40, brightness: 0.98)

    /// Light mode text secondary - HSlocalized(214, 28%, 35%)
    static let tidexLightTextSecondary = Color(hue: 214 / 360, saturation: 0.28, brightness: 0.35)

    /// Dark mode text secondary - HSlocalized(214, 32%, 85%)
    static let tidexDarkTextSecondary = Color(hue: 214 / 360, saturation: 0.32, brightness: 0.85)

    /// Light mode text muted - Darker for better contrast (#596B80)
    static let tidexLightTextMuted = Color(red: 0.35, green: 0.42, blue: 0.50)

    /// Dark mode text muted - HSlocalized(215, 20%, 70%)
    static let tidexDarkTextMuted = Color(hue: 215 / 360, saturation: 0.20, brightness: 0.70)

    /// Light mode brand blue - HSlocalized(221, 83%, 53%)
    static let tidexLightBlue = Color(hue: 221 / 360, saturation: 0.83, brightness: 0.53)

    /// Dark mode brand blue - HSlocalized(217, 91%, 65%)
    static let tidexDarkBlue = Color(hue: 217 / 360, saturation: 0.91, brightness: 0.90)

    /// Light mode border - Darker for better visibility (#C7D1DB)
    static let tidexLightBorder = Color(red: 0.78, green: 0.82, blue: 0.86)

    /// Dark mode border - Lighter for better visibility (#384761)
    static let tidexDarkBorder = Color(red: 0.22, green: 0.28, blue: 0.38)

    /// Light mode border subtle - Darker (#D9E0E8)
    static let tidexLightBorderSubtle = Color(red: 0.85, green: 0.88, blue: 0.91)

    /// Dark mode border subtle - Lighter for better visibility (#303D52)
    static let tidexDarkBorderSubtle = Color(red: 0.19, green: 0.24, blue: 0.32)
}

// MARK: - Card Shadow Colors
//
// Subtle shadows for elevated card surfaces in light mode
// iOS-native approach to add depth and visual separation

extension Color {
    /// Light mode card shadow - subtle blue-gray shadow
    static let tidexCardShadowLight = Color(red: 0.4, green: 0.45, blue: 0.55).opacity(0.12)

    /// Dark mode card shadow - deeper shadow for contrast
    static let tidexCardShadowDark = Color.black.opacity(0.4)
}

// MARK: - Card Shadow View Modifiers
//
// iOS-native shadow styles for elevated surfaces
// Automatically adapts to light/dark mode:
// - Light mode: Subtle drop shadows for depth
// - Dark mode: Inner glow/rim effect + subtle shadow for definition

/// Shadow elevation levels for cards
enum TidexShadowLevel {
    /// Subtle shadow for standard cards (shift cards, settings rows)
    case card
    /// Medium shadow for modals and popovers
    case elevated
    /// Strong shadow for floating action buttons
    case floating
}

/// View modifier that applies an adaptive card shadow with dark mode glow
struct TidexCardShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let level: TidexShadowLevel
    let customCornerRadius: CGFloat?

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            // Dark mode: Add subtle inner glow overlay + shadow
            content
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(glowOpacity),
                                    Color.white.opacity(glowOpacity * 0.3),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: shadowColor,
                    radius: shadowRadius,
                    x: 0,
                    y: shadowY
                )
        } else {
            // Light mode: Just shadow
            content
                .shadow(
                    color: shadowColor,
                    radius: shadowRadius,
                    x: 0,
                    y: shadowY
                )
        }
    }

    /// Corner radius for the glow overlay
    private var cornerRadius: CGFloat {
        if let custom = customCornerRadius {
            return custom
        }
        switch level {
        case .card:
            return 24
        case .elevated:
            return 20
        case .floating:
            return 16
        }
    }

    /// Glow opacity for dark mode rim effect
    private var glowOpacity: Double {
        switch level {
        case .card:
            return 0.08
        case .elevated:
            return 0.12
        case .floating:
            return 0.15
        }
    }

    private var shadowColor: Color {
        switch colorScheme {
        case .light:
            switch level {
            case .card:
                return Color(red: 0.4, green: 0.45, blue: 0.55).opacity(0.10)
            case .elevated:
                return Color(red: 0.4, green: 0.45, blue: 0.55).opacity(0.15)
            case .floating:
                return Color(red: 0.4, green: 0.45, blue: 0.55).opacity(0.20)
            }
        case .dark:
            switch level {
            case .card:
                return Color.black.opacity(0.30)
            case .elevated:
                return Color.black.opacity(0.40)
            case .floating:
                return Color.black.opacity(0.50)
            }
        @unknown default:
            return Color.black.opacity(0.1)
        }
    }

    private var shadowRadius: CGFloat {
        switch level {
        case .card:
            return colorScheme == .light ? 8 : 6
        case .elevated:
            return colorScheme == .light ? 16 : 10
        case .floating:
            return colorScheme == .light ? 24 : 14
        }
    }

    private var shadowY: CGFloat {
        switch level {
        case .card:
            return colorScheme == .light ? 2 : 2
        case .elevated:
            return colorScheme == .light ? 4 : 3
        case .floating:
            return colorScheme == .light ? 8 : 5
        }
    }
}

extension View {
    /// Applies a subtle card shadow that adapts to light/dark mode
    /// - Light mode: Drop shadow for depth
    /// - Dark mode: Subtle top-edge glow + shadow for definition
    /// Use on cards, list rows, and other elevated surfaces
    /// - Parameters:
    ///   - level: Shadow intensity level (default: .card)
    ///   - cornerRadius: Custom corner radius for the glow overlay. If nil, uses default for the level.
    func tidexCardShadow(_ level: TidexShadowLevel = .card, cornerRadius: CGFloat? = nil) -> some View {
        modifier(TidexCardShadowModifier(level: level, customCornerRadius: cornerRadius))
    }

    /// Applies a subtle shadow for small chips and status badges
    /// Creates consistent 3D appearance across all chip styles
    func tidexChipShadow() -> some View {
        modifier(TidexChipShadowModifier())
    }
}

/// View modifier for subtle chip/badge shadows
/// Lighter than card shadows, suitable for small UI elements
struct TidexChipShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
    }

    private var shadowColor: Color {
        colorScheme == .light
            ? Color(red: 0.4, green: 0.45, blue: 0.55).opacity(0.15)
            : Color.black.opacity(0.35)
    }

    private var shadowRadius: CGFloat {
        colorScheme == .light ? 3 : 2
    }

    private var shadowY: CGFloat {
        1
    }
}
