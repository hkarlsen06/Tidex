// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl implicit_optional_initialization no_magic_numbers
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable vertical_whitespace_between_cases
import SwiftUI

/// Shared badge style for shift countdown/status labels.
/// Used in Friends and Dashboard featured shift cards.
struct ShiftCountdownBadge: View {
  let text: String
  let status: ShiftPreviewStatus
  var finalCountdownSeconds: Int?

  var body: some View {
    if let finalCountdownSeconds, status == .active, finalCountdownSeconds > 0 {
      Text("\(finalCountdownSeconds)")
        .font(.tidexBodyMedium)
        .monospacedDigit()
        .frame(minWidth: 40)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.sm)
            .fill(Color.green.opacity(0.2))
        )
        .foregroundColor(.green)
        .contentTransition(.numericText())
        .animation(.default, value: finalCountdownSeconds)
    } else {
      Text(text)
        .font(.tidexCaption)
        .monospacedDigit()
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.sm)
            .fill(backgroundColor)
        )
        .foregroundColor(textColor)
        .contentTransition(.numericText())
        .animation(.default, value: text)
    }
  }

  private var backgroundColor: Color {
    switch status {
    case .active:
      return Color.green.opacity(0.15)

    case .upcoming:
      return Color.blue.opacity(0.15)

    case .past:
      return Color.tidexTextMuted.opacity(0.15)
    }
  }

  private var textColor: Color {
    switch status {
    case .active:
      return .green

    case .upcoming:
      return .blue

    case .past:
      return .tidexTextMuted
    }
  }
}
