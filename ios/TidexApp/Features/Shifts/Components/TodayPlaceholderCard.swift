import SwiftUI

/// Shows today's date when no shifts exist for today
/// Visually matches ShiftRowCard styling but shows a placeholder skeleton bar for earnings
/// Tapping navigates to add shift with today's date pre-selected
struct TodayPlaceholderCard: View {
  /// Callback when the card is tapped
  let onTap: () -> Void

  // MARK: - Computed Properties

  private var dateParts: (dayName: String, dayNumber: String, monthName: String) {
    let date = Date()
    let formatter = DateFormatter()

    // Get day name (full)
    formatter.dateFormat = "EEEE"
    let dayName = formatter.string(from: date).sentenceCased()

    // Get day number
    formatter.dateFormat = "d"
    let dayNumber = formatter.string(from: date) + String(localized: .commonDaySuffix)

    // Get month name (short)
    formatter.dateFormat = "MMM"
    let monthName = formatter.string(from: date).lowercased()

    return (dayName, dayNumber, monthName)
  }

  // MARK: - Body

  var body: some View {
    cardContent
      .contentShape(RoundedRectangle(cornerRadius: CornerRadius.card))
      .onTapGesture {
        onTap()
      }
  }

  @ViewBuilder
  private var cardContent: some View {
    ShiftCardContentLayout(centerTrailing: true) {
      // Date (left side)
      HStack(spacing: Spacing.xxs) {
        Text(dateParts.dayName)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextMuted)
        Text("·")
          .foregroundColor(.tidexTextMuted)
        Text("\(dateParts.dayNumber) \(dateParts.monthName)")
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
    .padding(.vertical, Spacing.mlg)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      // Blue ring to highlight as today's marker
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .strokeBorder(Color.tidexBlue, lineWidth: 2)
    )
    .tidexCardShadow()
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
