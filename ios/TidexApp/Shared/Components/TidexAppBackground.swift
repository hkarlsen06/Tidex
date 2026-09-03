import SwiftUI

/// Shared full-screen app canvas.
internal struct TidexAppBackground: View {
  internal var body: some View {
    Color.tidexBackground
      .ignoresSafeArea()
      .allowsHitTesting(false)
  }
}
