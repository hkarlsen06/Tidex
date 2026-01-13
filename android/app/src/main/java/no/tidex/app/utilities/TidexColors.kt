package no.tidex.app.utilities

import androidx.compose.ui.graphics.Color

/**
 * Tidex brand colors for use in native Android components.
 * Matches the color system defined in the web app's CSS variables.
 */
object TidexColors {
    // Background colors
    val DarkBackground = Color(0xFF020817)
    val SurfacePrimary = Color(0xFF0A0F1A)
    val SurfaceSecondary = Color(0xFF101729)

    // Brand colors
    val BrandBlue = Color(0xFF4D89F9)
    val BrandCyan = Color(0xFF00D4FF)
    val BrandPurple = Color(0xFF7B61FF)
    val BrandMagenta = Color(0xFF9B4DCA)

    // Text colors
    val TextPrimary = Color.White
    val TextSecondary = Color(0x99FFFFFF) // 60% white
    val TextMuted = Color(0x66FFFFFF) // 40% white

    // Status colors
    val Success = Color(0xFF22C55E)
    val Warning = Color(0xFFFACC15)
    val Error = Color(0xFFEF4444)

    // Logo gradient colors
    val LogoGradientStart = BrandCyan
    val LogoGradientMid = BrandPurple
    val LogoGradientEnd = BrandMagenta
}
