import SwiftUI

/// Tidex brand colors as SwiftUI Color extensions
/// These mirror the existing TidexBrandColors.swift values for consistency
extension Color {
    // MARK: - Background Colors

    /// Dark background color matching --background: 222.2 84% 4.9%
    static let tidexDarkBackground = Color(hue: 222.2 / 360, saturation: 0.84, brightness: 0.11)

    /// Launch screen background - exact match for LaunchScreen.storyboard LaunchBackground color
    /// RGB: 0.008, 0.032, 0.090 in sRGB
    static let tidexLaunchBackground = Color(red: 0.008, green: 0.032, blue: 0.090)

    /// Surface primary for cards - matches --surface-primary: 220 49% 11%
    static let tidexSurfacePrimary = Color(hue: 220 / 360, saturation: 0.49, brightness: 0.18)

    /// Surface secondary for nested elements
    static let tidexSurfaceSecondary = Color(hue: 220 / 360, saturation: 0.40, brightness: 0.14)

    // MARK: - Text Colors

    /// Text primary color - matches --text-primary: 210 40% 98%
    static let tidexTextPrimary = Color(hue: 210 / 360, saturation: 0.40, brightness: 0.98)

    /// Text secondary color - matches --text-secondary: 214 32% 85%
    static let tidexTextSecondary = Color(hue: 214 / 360, saturation: 0.32, brightness: 0.85)

    /// Text muted color - matches --text-muted: 215 20% 70%
    static let tidexTextMuted = Color(hue: 215 / 360, saturation: 0.20, brightness: 0.70)

    // MARK: - Brand Colors

    /// Tidex brand highlight color - matches --brand-highlight: 217 91% 65%
    static let tidexBlue = Color(hue: 217 / 360, saturation: 0.91, brightness: 0.90)

    /// Brand primary for buttons and accents
    static let tidexBrandPrimary = Color(hue: 217 / 360, saturation: 0.85, brightness: 0.85)

    // MARK: - Border Colors

    /// Border color for inputs and cards
    static let tidexBorder = Color(hue: 220 / 360, saturation: 0.30, brightness: 0.25)

    /// Subtle border for dividers
    static let tidexBorderSubtle = Color(hue: 220 / 360, saturation: 0.20, brightness: 0.20)

    // MARK: - Status Colors

    /// Error/destructive color
    static let tidexError = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)

    /// Success color
    static let tidexSuccess = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)

    /// Warning color
    static let tidexWarning = Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)

    // MARK: - Gradient Colors

    /// Logo gradient colors from short-logo-gradient.svg
    static let logoGradientColors = [
        Color(red: 0, green: 212 / 255, blue: 1),              // #00D4FF - cyan (top)
        Color(red: 123 / 255, green: 97 / 255, blue: 1),       // #7B61FF - purple (middle)
        Color(red: 155 / 255, green: 77 / 255, blue: 202 / 255) // #9B4DCA - magenta (bottom)
    ]
}
