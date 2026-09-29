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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    viewMode: Binding<CalendarViewMode>,
    currency: String,
    showMoneyOption: Bool = true
  ) {
    self._viewMode = viewMode
    self.currency = currency
    self.showMoneyOption = showMoneyOption
    _ = Self.applyTidexAppearance
  }

  /// Swaps the stock gray track and thumb for Tidex colors. The proxy is app-wide,
  /// which is fine while this is the only segmented picker in the app.
  private static let applyTidexAppearance: Void = {
    let control = UISegmentedControl.appearance()
    control.backgroundColor = UIColor(resource: .tidexSurfaceSecondary)
    control.selectedSegmentTintColor = UIColor(Color.tidexGlassSurface)
    let font = UIFont.systemFont(
      ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold)
    control.setTitleTextAttributes(
      [.foregroundColor: UIColor(resource: .tidexTextMuted), .font: font], for: .normal)
    control.setTitleTextAttributes(
      [.foregroundColor: UIColor(resource: .tidexTextPrimary), .font: font], for: .selected)
  }()

  var body: some View {
    Picker(
      selection: $viewMode.animation(
        reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8))
    ) {
      Text(.shiftsCalendarToggleHours).tag(CalendarViewMode.hours)
      if showMoneyOption {
        Text(.shiftsCalendarToggleEarnings).tag(CalendarViewMode.money)
      }
    } label: {
      EmptyView()
    }
    .pickerStyle(.segmented)
    .controlSize(.large)
    .onChange(of: viewMode) { viewMode.save() }
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
