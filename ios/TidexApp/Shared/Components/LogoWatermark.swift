import SwiftUI

/// Uses the same appearance-aware mark as sign-in and exported reports.
struct LogoWatermark: View {
  var opacity: Double = 0.15

  var body: some View {
    Image("TidexLogo")
      .resizable()
      .scaledToFit()
      .opacity(opacity)
      .accessibilityHidden(true)
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
