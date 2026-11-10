import SwiftUI

/// The clock choice in a friend's schedule. It shows nothing when the schedule's clock matches
/// the viewer's.
struct SharedScheduleTimeControlView: View {
  let control: SharedScheduleTimeControl
  @Binding var display: SharedScheduleTimeDisplay

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(control: SharedScheduleTimeControl, display: Binding<SharedScheduleTimeDisplay>) {
    self.control = control
    self._display = display
    _ = CalendarViewModeToggle.applyTidexAppearance
  }

  var body: some View {
    switch control {
    case .none:
      EmptyView()

    case .choice:
      // The segmented control truncates a title that outgrows its half, so large text and
      // long translations get the two options as full-width rows.
      ViewThatFits(in: .horizontal) {
        segmentedChoice
        stackedChoice
      }

    case .unknownZone:
      Text(.sharingTimeUnknown)
        .font(.tidexCaption)
        .foregroundStyle(Color.tidexTextSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxs)
    }
  }

  private var selection: Binding<SharedScheduleTimeDisplay> {
    $display.animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8))
  }

  private var segmentedChoice: some View {
    Picker(selection: selection) {
      Text(.sharingTimeYourTime).tag(SharedScheduleTimeDisplay.viewer)
      Text(.sharingTimeTheirTime).tag(SharedScheduleTimeDisplay.schedule)
    } label: {
      EmptyView()
    }
    .pickerStyle(.segmented)
    .controlSize(.large)
  }

  private var stackedChoice: some View {
    VStack(spacing: Spacing.xxs) {
      stackedOption(.viewer, title: .sharingTimeYourTime)
      stackedOption(.schedule, title: .sharingTimeTheirTime)
    }
    .padding(Spacing.xxs)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xxl).fill(Color.tidexSurfaceSecondary))
  }

  private func stackedOption(_ option: SharedScheduleTimeDisplay, title: LocalizedStringResource)
    -> some View
  {
    let isSelected = display == option
    return Button {
      selection.wrappedValue = option
    } label: {
      Text(title)
        .font(.tidexSubheadline.weight(.semibold))
        .foregroundStyle(isSelected ? Color.tidexTextPrimary : Color.tidexTextMuted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, Spacing.sm)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.lg)
            .fill(isSelected ? Color.tidexGlassSurface : .clear))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
