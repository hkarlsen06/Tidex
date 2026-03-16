import SwiftUI

/// Shared app background with a subtle top-centered radial glow.
/// Keeps the existing semantic background token as the base layer while adding
/// the same brighter-at-the-top atmosphere used in the marketing phone mockup.
struct TidexAppBackground: View {
  @Environment(\.colorScheme) private var colorScheme

  private var verticalTopOpacity: Double {
    colorScheme == .dark ? 0.13 : 0.055
  }

  private var verticalMidOpacity: Double {
    colorScheme == .dark ? 0.07 : 0.025
  }

  private var glowOpacityPrimary: Double {
    colorScheme == .dark ? 0.16 : 0.06
  }

  private var glowOpacitySecondary: Double {
    colorScheme == .dark ? 0.07 : 0.025
  }

  var body: some View {
    GeometryReader { geometry in
      let maxDimension = max(geometry.size.width, geometry.size.height)

      ZStack {
        Color.tidexBackground

        LinearGradient(
          colors: [
            Color.tidexBlue.opacity(verticalTopOpacity),
            Color.tidexBrandPrimary.opacity(verticalMidOpacity),
            Color.clear,
          ],
          startPoint: .top,
          endPoint: UnitPoint(x: 0.5, y: 0.8)
        )
        .ignoresSafeArea()

        RadialGradient(
          colors: [
            Color.tidexBlue.opacity(glowOpacityPrimary),
            Color.tidexBrandPrimary.opacity(glowOpacitySecondary),
            Color.clear,
          ],
          center: UnitPoint(x: 0.5, y: 0.0),
          startRadius: 0,
          endRadius: maxDimension * 0.82
        )
        .ignoresSafeArea()

        RadialGradient(
          colors: [
            Color.tidexBlue.opacity(colorScheme == .dark ? 0.055 : 0.02),
            Color.clear,
          ],
          center: UnitPoint(x: 0.5, y: 0.46),
          startRadius: 0,
          endRadius: maxDimension * 0.72
        )
        .ignoresSafeArea()

        LinearGradient(
          colors: [
            Color.clear,
            Color.tidexBackground.opacity(colorScheme == .dark ? 0.10 : 0.05),
          ],
          startPoint: UnitPoint(x: 0.5, y: 0.55),
          endPoint: .bottom
        )
        .ignoresSafeArea()
      }
      .ignoresSafeArea()
    }
    .allowsHitTesting(false)
  }
}
