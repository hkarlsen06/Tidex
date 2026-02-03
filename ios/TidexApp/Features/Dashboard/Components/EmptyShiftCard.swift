import SwiftUI

/// Placeholder card displayed when there are no shifts for a month
/// Shows dashed placeholders matching the FeaturedShiftCard layout
struct EmptyShiftCard: View {
    /// When true, shows shimmer animation (for loading)
    var isLoading: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            // Main card content
            HStack(alignment: .center, spacing: 16) {
                // Left side: skeleton lines for date and time
                VStack(alignment: .leading, spacing: 8) {
                    // Placeholder day name and date
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.tidexTextMuted.opacity(0.3))
                        .frame(width: 140, height: 16)

                    // Placeholder time range
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.tidexTextMuted.opacity(0.2))
                        .frame(width: 100, height: 12)
                }

                Spacer()

                // Right side: skeleton lines for earnings
                VStack(alignment: .trailing, spacing: 6) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.tidexTextMuted.opacity(0.3))
                        .frame(width: 80, height: 20)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.tidexTextMuted.opacity(0.2))
                        .frame(width: 60, height: 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.tidexSurfacePrimary)
            )
            .tidexCardShadow()
            .shimmer(isActive: isLoading)

            // Footer skeleton bar below the card - fixed height to match FeaturedShiftCard
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.tidexTextMuted.opacity(0.3))
                .frame(width: 80, height: 14)
                .frame(height: 20) // Match FeaturedShiftCard footer height
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        EmptyShiftCard()
        EmptyShiftCard(isLoading: true)
    }
    .padding(.horizontal, 24)
    .background(Color.tidexBackground)
}
