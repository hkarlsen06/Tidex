import SwiftUI

/// Dot indicators for onboarding page progress
internal struct PageIndicator: View {
  private static let inactiveOpacity: Double = 0.4
  private static let dotSize: CGFloat = 8
  private static let selectedScale: CGFloat = 1.2
  private static let animationResponse: Double = 0.3
  private static let animationDampingFraction: Double = 0.7

  internal let totalPages: Int
  internal let currentPage: Int

  internal var body: some View {
    HStack(spacing: Spacing.xs) {
      ForEach(0..<totalPages, id: \.self) { index in
        Circle()
          .fill(
            index == currentPage
              ? Color.tidexBlue
              : Color.tidexTextMuted.opacity(Self.inactiveOpacity)
          )
          .frame(width: Self.dotSize, height: Self.dotSize)
          .scaleEffect(index == currentPage ? Self.selectedScale : 1.0)
          .animation(
            .spring(
              response: Self.animationResponse,
              dampingFraction: Self.animationDampingFraction
            ),
            value: currentPage
          )
      }
    }
  }
}

#Preview {
  VStack(spacing: Spacing.lg) {
    PageIndicator(totalPages: 4, currentPage: 0)
    PageIndicator(totalPages: 4, currentPage: 1)
    PageIndicator(totalPages: 4, currentPage: 2)
    PageIndicator(totalPages: 4, currentPage: 3)
  }
  .padding()
  .background(Color.tidexBackground)
}
