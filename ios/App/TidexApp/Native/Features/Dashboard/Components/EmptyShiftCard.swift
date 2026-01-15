import SwiftUI

/// Placeholder card displayed when there are no shifts for a month
/// Shows dashed placeholders matching the FeaturedShiftCard layout
struct EmptyShiftCard: View {
    let isBestShift: Bool  // true = other month (no best shift), false = current month (no next shift)

    @Environment(\.localization) private var localization

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            // Main card content
            HStack(alignment: .center, spacing: 16) {
                // Left side: placeholder date and time
                VStack(alignment: .leading, spacing: 4) {
                    // Placeholder day name and date
                    Text("———")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.tidexTextMuted)

                    // Placeholder time range
                    Text("———")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.tidexTextMuted)
                }

                Spacer()

                // Right side: placeholder earnings
                Text("—— kr")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(.tidexTextMuted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.tidexSurfacePrimary)
            )

            // Footer text below the card - fixed height to match FeaturedShiftCard
            Text(localization.string(isBestShift ? "dashboard.noShiftsMonth" : "dashboard.noNextShift"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextMuted)
                .frame(height: 20) // Match FeaturedShiftCard footer height
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        EmptyShiftCard(isBestShift: true)
        EmptyShiftCard(isBestShift: false)
    }
    .padding(.horizontal, 24)
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
