import SwiftUI

/// Placeholder card displayed when there are no shifts for a month
/// Shows skeleton placeholders matching the FeaturedShiftCard layout
struct EmptyShiftCard: View {
  /// When true, shows shimmer animation (for loading)
  var isLoading: Bool = false
  /// Optional action for a small footer CTA
  var onAddShift: (() -> Void)? = nil

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var usesFixedCardHeight: Bool {
    !dynamicTypeSize.isAccessibilitySize
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: Spacing.sm) {
      // Main card content
      ShiftCardContentLayout(rowSpacing: 4, centerTrailing: true) {
        // Placeholder day name and date
        ZStack(alignment: .leading) {
          Text(verbatim: "Monday · 31 Dec")
            .font(.tidexBodyMedium)
            .opacity(0)

          RoundedRectangle(cornerRadius: 5)
            .fill(Color.tidexTextMuted.opacity(0.3))
            .frame(width: 140, height: 20)
        }
      } leadingBottom: {
        // Placeholder time range
        ZStack(alignment: .leading) {
          HStack(spacing: Spacing.xxs) {
            Image(systemName: "clock")
              .font(.tidexSubheadline)
              .opacity(0)
            Text(verbatim: "00:00 - 00:00")
              .font(.tidexSubheadline)
              .opacity(0)
          }

          RoundedRectangle(cornerRadius: CornerRadius.xxs)
            .fill(Color.tidexTextMuted.opacity(0.2))
            .frame(width: 100, height: 17)
        }
      } trailingTop: {
        ZStack {
          Text(verbatim: "00 000")
            .font(.tidexTitle)
            .opacity(0)

          RoundedRectangle(cornerRadius: CornerRadius.xs)
            .fill(Color.tidexTextMuted.opacity(0.3))
            .frame(width: 96, height: 24)
        }
      } trailingBottom: {
        ZStack(alignment: .trailing) {
          Text(verbatim: "00 000 − 00 000")
            .font(.tidexSubheadline)
            .opacity(0)

          RoundedRectangle(cornerRadius: CornerRadius.xxs)
            .fill(Color.tidexTextMuted.opacity(0.2))
            .frame(width: 72, height: 17)
        }
      }
      .padding(.horizontal, Spacing.mlg)
      .padding(.vertical, ShiftCardMetrics.verticalPadding)
      .frame(minHeight: usesFixedCardHeight ? ShiftCardMetrics.regularCardMinHeight : nil)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.card)
          .fill(Color.tidexSurfacePrimary)
      )
      .tidexCardShadow()
      .shimmer(isActive: isLoading)

      // Footer area below the card - fixed height to match FeaturedShiftCard
      Group {
        if isLoading {
          RoundedRectangle(cornerRadius: CornerRadius.xxs)
            .fill(Color.tidexTextMuted.opacity(0.3))
            .frame(width: 80, height: 14)
        } else if let onAddShift {
          Button {
            Haptics.play(.light)
            onAddShift()
          } label: {
            Text(.dashboardAddShiftButton)
              .font(.tidexCaptionStrong)
              .foregroundColor(.tidexBlue)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
              .padding(.horizontal, Spacing.xsm)
              .padding(.vertical, 3)
              .background(Color.tidexBlue.opacity(0.12))
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        } else {
          RoundedRectangle(cornerRadius: CornerRadius.xxs)
            .fill(Color.tidexTextMuted.opacity(0.3))
            .frame(width: 80, height: 14)
        }
      }
      .frame(height: 20)  // Match FeaturedShiftCard footer height
    }
  }
}

#Preview {
  VStack(spacing: Spacing.md) {
    EmptyShiftCard(onAddShift: {})
    EmptyShiftCard(isLoading: true)
  }
  .padding(.horizontal, Spacing.lg)
  .background(Color.tidexBackground)
}
