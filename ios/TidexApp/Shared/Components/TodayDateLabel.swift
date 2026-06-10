// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_trait_for_button conditional_returns_on_newline explicit_acl explicit_top_level_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_type_interface no_magic_numbers
import SwiftUI

/// Toolbar label showing today's date using system locale formatting.
/// Tapping navigates back to the current month.
struct TodayDateLabel: View {
  private let monthContext = SharedMonthContext.shared
  private var dateParts: ShiftCardDateParts { ShiftCardFormatter.dateParts(for: Date.now) }

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      Circle()
        .fill(Color.tidexBlue)
        .frame(width: 7, height: 7)
      Text(dateParts.weekday)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)
      Text("·")
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextMuted)
      Text(dateParts.dayMonth)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextSecondary)
    }
    .fixedSize()
    .padding(.leading, Spacing.xxs)
    .onTapGesture {
      guard !monthContext.isCurrentMonth else { return }
      Haptics.play(.light)
      monthContext.goToCurrentMonth()
    }
  }
}
