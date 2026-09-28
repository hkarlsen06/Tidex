import SwiftUI

/// Shared full-screen app canvas.
internal struct TidexAppBackground: View {
  internal var body: some View {
    Color.tidexBackground
      .ignoresSafeArea()
      .allowsHitTesting(false)
  }
}

extension View {
  /// Swaps the system grouped background of a `List` or `Form` for the app canvas.
  internal func tidexListBackground() -> some View {
    scrollContentBackground(.hidden)
      .background(TidexAppBackground())
  }
}
