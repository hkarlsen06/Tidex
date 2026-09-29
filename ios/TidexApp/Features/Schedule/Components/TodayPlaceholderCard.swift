import SwiftUI

/// Shows today's date when no shifts exist for today
/// Visually matches ShiftRowCard styling but shows a placeholder skeleton bar for earnings
/// Tapping navigates to add shift with today's date pre-selected
struct TodayPlaceholderCard: View {
  /// Callback when the card is tapped
  let onTap: () -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  // MARK: - Computed Properties

  private var dateParts: ShiftCardDateParts {
    ShiftCardFormatter.dateParts(for: Date.now)
  }

  private var usesFixedCardHeight: Bool {
    !dynamicTypeSize.isAccessibilitySize
  }

  // MARK: - Body

  var body: some View {
    cardContent
      .contentShape(RoundedRectangle(cornerRadius: CornerRadius.card))
      .onTapGesture {
        onTap()
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        Text(
          verbatim:
            "\(dateParts.weekday) \(dateParts.dayMonth), \(String(localized: .commonToday))")
      )
      .accessibilityHint(Text(.shiftsAccessibilityAddShiftTodayHint))
      .accessibilityAddTraits(.isButton)
      .accessibilityAction(.default) {
        onTap()
      }
  }

  @ViewBuilder
  private var cardContent: some View {
    ShiftCardContentLayout(centerTrailing: true) {
      // Date (left side)
      HStack(spacing: Spacing.xxs) {
        Text(dateParts.weekday)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextMuted)
        Text("·")
          .foregroundColor(.tidexTextMuted)
        Text(dateParts.dayMonth)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextMuted)
      }
    } leadingBottom: {
      EmptyView()
    } trailingTop: {
      // Placeholder earnings bar (right side)
      RoundedRectangle(cornerRadius: CornerRadius.xs)
        .fill(Color.tidexTextMuted.opacity(0.3))
        .frame(width: 80, height: 20)
    } trailingBottom: {
      EmptyView()
    }
    .padding(.horizontal, Spacing.mlg)
    .padding(.vertical, ShiftCardMetrics.verticalPadding)
    .frame(minHeight: usesFixedCardHeight ? ShiftCardMetrics.regularCardMinHeight : nil)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      // Blue ring to highlight as today's marker
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .strokeBorder(Color.tidexBlue, lineWidth: 2)
    )
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.md) {
    TodayPlaceholderCard(onTap: {
      print("Tapped!")
    })
  }
  .padding()
  .background(Color.tidexBackground)
}
