import SwiftUI

/// Small stat card for displaying a single metric (hours, shifts, etc.)
/// Used in a 2-column grid layout
struct SmallStatCard: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order
  let title: String  // swiftlint:disable:this explicit_acl
  let value: String  // swiftlint:disable:this explicit_acl
  let icon: String  // swiftlint:disable:this explicit_acl

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(alignment: .leading, spacing: Spacing.sm) {
      // Header row with title and icon
      HStack {
        Text(title)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        Spacer()

        Image(systemName: icon)  // swiftlint:disable:this accessibility_label_for_image
          .font(.tidexBody)
          .foregroundColor(.tidexTextMuted)
      }

      // Value
      Text(value)
        .font(.tidexStatSecondary)
        .foregroundColor(.tidexTextPrimary)
        .minimumScaleFactor(0.6)  // swiftlint:disable:this no_magic_numbers
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
struct HoursStatCard: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let hours: Double  // swiftlint:disable:this explicit_acl

  var body: some View {  // swiftlint:disable:this explicit_acl
    SmallStatCard(
      title: String(localized: .statsHours),
      value: formatHours(hours),
      icon: "clock"
    )
  }

  private func formatHours(_ hours: Double) -> String {
    hours.formatted(.number.precision(.fractionLength(0...1)).locale(Locale.appLocale))
  }
}

/// Shifts count stat card
struct ShiftsStatCard: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let count: Int  // swiftlint:disable:this explicit_acl

  var body: some View {  // swiftlint:disable:this explicit_acl
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
