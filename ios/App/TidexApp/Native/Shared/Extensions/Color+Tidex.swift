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
    /// Light: HSL(220, 40%, 98%) - soft off-white
    /// Dark: HSL(222.2, 84%, 4.9%) - deep navy
    static var tidexBackground: Color {
        Color("TidexBackground")
    }

    /// Secondary background for nested containers
    /// Light: HSL(220, 35%, 95%)
    /// Dark: HSL(222.2, 84%, 4.9%)
    static var tidexBackgroundSecondary: Color {
        Color("TidexBackgroundSecondary")
    }

    /// Launch screen background - adapts to light/dark mode
    /// Light: HSL(220, 40%, 98%) - soft off-white (matches tidexBackground)
    /// Dark: HSL(222.2, 84%, 4.9%) - deep navy (matches tidexBackground)
    static var tidexLaunchBackground: Color {
        Color("LaunchBackground")
    }

    /// Surface primary for cards and elevated containers
    /// Light: HSL(220, 35%, 96%) - light gray
    /// Dark: HSL(220, 49%, 11%) - dark navy card
    static var tidexSurfacePrimary: Color {
        Color("TidexSurfacePrimary")
    }

    /// Surface secondary for nested elements within cards
    /// Light: HSL(221, 30%, 94%)
    /// Dark: HSL(221, 39%, 14%)
    static var tidexSurfaceSecondary: Color {
        Color("TidexSurfaceSecondary")
    }

    // MARK: - Text Colors

    /// Primary text color for headings and important content
    /// Light: HSL(222, 84%, 8%) - near black
    /// Dark: HSL(210, 40%, 98%) - near white
    static var tidexTextPrimary: Color {
        Color("TidexTextPrimary")
    }

    /// Secondary text color for body text and descriptions
    /// Light: HSL(214, 28%, 35%)
    /// Dark: HSL(214, 32%, 85%)
    static var tidexTextSecondary: Color {
        Color("TidexTextSecondary")
    }

    /// Muted text color for hints, placeholders, and disabled content
    /// Light: HSL(215, 20%, 50%)
    /// Dark: HSL(215, 20%, 70%)
    static var tidexTextMuted: Color {
        Color("TidexTextMuted")
    }

    /// Inverse text color (light on dark surfaces or vice versa)
    /// Light: HSL(210, 40%, 98%)
    /// Dark: HSL(222, 47%, 11%)
    static var tidexTextInverse: Color {
        Color("TidexTextInverse")
    }

    // MARK: - Brand Colors

    /// Tidex brand highlight color - accent blue
    /// Light: HSL(221, 83%, 53%) - vibrant blue
    /// Dark: HSL(217, 91%, 65%) - bright blue
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
    /// Light: HSL(217, 28%, 88%)
    /// Dark: HSL(220, 30%, 25%)
    static var tidexBorder: Color {
        Color("TidexBorder")
    }

    /// Subtle border for light dividers
    /// Light: HSL(217, 25%, 92%)
    /// Dark: HSL(220, 20%, 20%)
    static var tidexBorderSubtle: Color {
        Color("TidexBorderSubtle")
    }

    // MARK: - Status Colors

    /// Error/destructive color - red
    /// Light: HSL(0, 84%, 44%)
    /// Dark: HSL(0, 91%, 60%)
    static var tidexError: Color {
        Color("TidexError")
    }

    /// Success color - green
    /// Light: HSL(142, 76%, 28%)
    /// Dark: HSL(142, 71%, 50%)
    static var tidexSuccess: Color {
        Color("TidexSuccess")
    }

    /// Warning color - amber/orange
    /// Light: HSL(30, 100%, 35%)
    /// Dark: HSL(38, 100%, 55%)
    static var tidexWarning: Color {
        Color("TidexWarning")
    }

    /// Info color - blue (matches brand)
    static var tidexInfo: Color {
        tidexBlue
    }

    /// Purple color for Max tier branding
    /// HSL(258, 70%, 60%) - vibrant purple
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
    /// Light mode background - HSL(220, 40%, 98%)
    static let tidexLightBackground = Color(hue: 220 / 360, saturation: 0.40, brightness: 0.98)

    /// Dark mode background - HSL(222.2, 84%, 4.9%)
    static let tidexDarkBackgroundColor = Color(hue: 222.2 / 360, saturation: 0.84, brightness: 0.11)

    /// Light mode surface primary - HSL(220, 35%, 96%)
    static let tidexLightSurfacePrimary = Color(hue: 220 / 360, saturation: 0.35, brightness: 0.96)

    /// Dark mode surface primary - HSL(220, 49%, 11%)
    static let tidexDarkSurfacePrimary = Color(hue: 220 / 360, saturation: 0.49, brightness: 0.18)

    /// Light mode surface secondary - HSL(221, 30%, 94%)
    static let tidexLightSurfaceSecondary = Color(hue: 221 / 360, saturation: 0.30, brightness: 0.94)

    /// Dark mode surface secondary - HSL(221, 39%, 14%)
    static let tidexDarkSurfaceSecondary = Color(hue: 221 / 360, saturation: 0.40, brightness: 0.14)

    /// Light mode text primary - HSL(222, 84%, 8%)
    static let tidexLightTextPrimary = Color(hue: 222 / 360, saturation: 0.84, brightness: 0.08)

    /// Dark mode text primary - HSL(210, 40%, 98%)
    static let tidexDarkTextPrimary = Color(hue: 210 / 360, saturation: 0.40, brightness: 0.98)

    /// Light mode text secondary - HSL(214, 28%, 35%)
    static let tidexLightTextSecondary = Color(hue: 214 / 360, saturation: 0.28, brightness: 0.35)

    /// Dark mode text secondary - HSL(214, 32%, 85%)
    static let tidexDarkTextSecondary = Color(hue: 214 / 360, saturation: 0.32, brightness: 0.85)

    /// Light mode text muted - HSL(215, 20%, 50%)
    static let tidexLightTextMuted = Color(hue: 215 / 360, saturation: 0.20, brightness: 0.50)

    /// Dark mode text muted - HSL(215, 20%, 70%)
    static let tidexDarkTextMuted = Color(hue: 215 / 360, saturation: 0.20, brightness: 0.70)

    /// Light mode brand blue - HSL(221, 83%, 53%)
    static let tidexLightBlue = Color(hue: 221 / 360, saturation: 0.83, brightness: 0.53)

    /// Dark mode brand blue - HSL(217, 91%, 65%)
    static let tidexDarkBlue = Color(hue: 217 / 360, saturation: 0.91, brightness: 0.90)

    /// Light mode border - HSL(217, 28%, 88%)
    static let tidexLightBorder = Color(hue: 217 / 360, saturation: 0.28, brightness: 0.88)

    /// Dark mode border - HSL(220, 30%, 25%)
    static let tidexDarkBorder = Color(hue: 220 / 360, saturation: 0.30, brightness: 0.25)

    /// Light mode border subtle - HSL(217, 25%, 92%)
    static let tidexLightBorderSubtle = Color(hue: 217 / 360, saturation: 0.25, brightness: 0.92)

    /// Dark mode border subtle - HSL(220, 20%, 20%)
    static let tidexDarkBorderSubtle = Color(hue: 220 / 360, saturation: 0.20, brightness: 0.20)
}
