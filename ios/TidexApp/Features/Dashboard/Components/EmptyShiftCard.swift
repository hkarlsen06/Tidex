import SwiftUI

/// Placeholder card displayed when there are no shifts for a month
/// Shows skeleton placeholders matching the FeaturedShiftCard layout
struct EmptyShiftCard: View {
    /// When true, shows shimmer animation (for loading)
    var isLoading: Bool = false
    /// Optional action for a small footer CTA
    var onAddShift: (() -> Void)? = nil

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            // Main card content
            ShiftCardContentLayout(
                columnSpacing: 16,
                leadingSpacing: 8,
                trailingSpacing: 6
            ) {
                // Placeholder day name and date
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.tidexTextMuted.opacity(0.3))
                    .frame(width: 140, height: 16)
            } leadingBottom: {
                // Placeholder time range
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.tidexTextMuted.opacity(0.2))
                    .frame(width: 100, height: 12)
            } trailingTop: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.tidexTextMuted.opacity(0.3))
                    .frame(width: 80, height: 20)
            } trailingBottom: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.tidexTextMuted.opacity(0.2))
                    .frame(width: 60, height: 12)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.tidexSurfacePrimary)
            )
            .tidexCardShadow()
            .shimmer(isActive: isLoading)

            // Footer area below the card - fixed height to match FeaturedShiftCard
            Group {
                if isLoading {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.tidexTextMuted.opacity(0.3))
                        .frame(width: 80, height: 14)
                } else if let onAddShift {
                    Button {
                        Haptics.play(.light)
                        onAddShift()
                    } label: {
                        Text(.dashboardAddShiftButton)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.tidexBlue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                        .background(Color.tidexBlue.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.tidexTextMuted.opacity(0.3))
                        .frame(width: 80, height: 14)
                }
            }
            .frame(height: 20) // Match FeaturedShiftCard footer height
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        EmptyShiftCard(onAddShift: {})
        EmptyShiftCard(isLoading: true)
    }
    .padding(.horizontal, 24)
    .background(Color.tidexBackground)
}
