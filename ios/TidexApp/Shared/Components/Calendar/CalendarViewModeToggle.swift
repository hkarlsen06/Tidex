// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image closure_body_length conditional_returns_on_newline explicit_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_top_level_acl explicit_type_interface no_magic_numbers type_contents_order
import SwiftUI

// MARK: - Calendar View Mode Toggle

/// Reusable hours/money toggle for calendar views.
/// Native segmented picker, so the Liquid Glass thumb can be dragged between segments.
struct CalendarViewModeToggle: View {
  @Binding var viewMode: CalendarViewMode
  let currency: String
  let showMoneyOption: Bool

  init(
    viewMode: Binding<CalendarViewMode>,
    currency: String,
    showMoneyOption: Bool = true
  ) {
    self._viewMode = viewMode
    self.currency = currency
    self.showMoneyOption = showMoneyOption
  }

  var body: some View {
    AdaptiveCalendarPicker(selection: $viewMode, options: options)
      .onChange(of: viewMode) { viewMode.save() }
  }

  private var options: [CalendarPickerOption<CalendarViewMode>] {
    var result = [
      CalendarPickerOption(value: CalendarViewMode.hours, title: .shiftsCalendarToggleHours)
    ]
    if showMoneyOption {
      result.append(CalendarPickerOption(value: .money, title: .shiftsCalendarToggleEarnings))
    }
    return result
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.mlg) {
    CalendarViewModeToggle(
      viewMode: .constant(.hours),
      currency: "kr"
    )

    CalendarViewModeToggle(
      viewMode: .constant(.money),
      currency: "kr"
    )

    CalendarViewModeToggle(
      viewMode: .constant(.hours),
      currency: "kr",
      showMoneyOption: false
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
