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
    let dayName = formatter.string(from: date).capitalized

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
      .contentShape(RoundedRectangle(cornerRadius: 24))
      .onTapGesture {
        onTap()
      }
  }

  @ViewBuilder
  private var cardContent: some View {
    ShiftCardContentLayout(centerTrailing: true) {
      // Date (left side)
      HStack(spacing: 4) {
        Text(dateParts.dayName)
          .font(.system(size: 20, weight: .medium))
          .foregroundColor(.tidexTextMuted)
        Text("·")
          .foregroundColor(.tidexTextMuted)
        Text("\(dateParts.dayNumber) \(dateParts.monthName)")
          .font(.system(size: 20, weight: .medium))
          .foregroundColor(.tidexTextMuted)
      }
      .fixedSize(horizontal: true, vertical: false)
    } leadingBottom: {
      EmptyView()
    } trailingTop: {
      // Placeholder earnings bar (right side)
      RoundedRectangle(cornerRadius: 6)
        .fill(Color.tidexTextMuted.opacity(0.3))
        .frame(width: 80, height: 20)
    } trailingBottom: {
      EmptyView()
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 20)
    .background(
      RoundedRectangle(cornerRadius: 24)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      // Blue ring to highlight as today's marker
      RoundedRectangle(cornerRadius: 24)
        .strokeBorder(Color.tidexBlue, lineWidth: 2)
    )
    .tidexCardShadow()
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: 16) {
    TodayPlaceholderCard(onTap: {
      print("Tapped!")
    })
  }
  .padding()
  .background(Color.tidexBackground)
}
