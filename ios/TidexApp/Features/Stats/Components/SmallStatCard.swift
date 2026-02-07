import SwiftUI

/// Small stat card for displaying a single metric (hours, shifts, etc.)
/// Used in a 2-column grid layout
struct SmallStatCard: View {
  let title: String
  let value: String
  let icon: String

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      // Header row with title and icon
      HStack {
        Text(title)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        Spacer()

        Image(systemName: icon)
          .font(.tidexBody)
          .foregroundColor(.tidexTextMuted)
      }

      // Value
      Text(value)
        .font(.tidexStatSecondary)
        .foregroundColor(.tidexTextPrimary)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.mlg)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.card)
    .tidexCardShadow()
  }
}

/// Hours stat card with decimal formatting
struct HoursStatCard: View {
  let hours: Double

  var body: some View {
    SmallStatCard(
      title: String(localized: .statsHours),
      value: formatHours(hours),
      icon: "clock"
    )
  }

  private func formatHours(_ hours: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    formatter.locale = Locale(identifier: "nb_NO")
    return formatter.string(from: NSNumber(value: hours)) ?? "\(Int(hours))"
  }
}

/// Shifts count stat card
struct ShiftsStatCard: View {
  let count: Int

  var body: some View {
    SmallStatCard(
      title: String(localized: .statsShifts),
      value: "\(count)",
      icon: "calendar"
    )
  }
}

#Preview {
  HStack(spacing: Spacing.sm) {
    HoursStatCard(hours: 60.3)
    ShiftsStatCard(count: 9)
  }
  .padding()
  .background(Color.tidexBackground)
}
