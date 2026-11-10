import SwiftUI

struct CalendarPickerOption<Value: Hashable> {
  let value: Value
  let title: LocalizedStringResource
}

/// Uses the native segmented picker when its titles fit, or full-width choices otherwise.
struct AdaptiveCalendarPicker<Value: Hashable>: View {
  @Binding var selection: Value
  let options: [CalendarPickerOption<Value>]

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(selection: Binding<Value>, options: [CalendarPickerOption<Value>]) {
    self._selection = selection
    self.options = options
    _ = CalendarPickerAppearance.apply
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      Picker(selection: animatedSelection) {
        ForEach(options, id: \.value) { option in
          Text(option.title).tag(option.value)
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.segmented)
      .controlSize(.large)

      VStack(spacing: Spacing.xxs) {
        ForEach(options, id: \.value) { option in
          stackedOption(option)
        }
      }
      .padding(Spacing.xxs)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl).fill(Color.tidexSurfaceSecondary))
    }
  }

  private var animatedSelection: Binding<Value> {
    $selection.animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8))
  }

  private func stackedOption(_ option: CalendarPickerOption<Value>) -> some View {
    let isSelected = selection == option.value
    return Button {
      animatedSelection.wrappedValue = option.value
    } label: {
      Text(option.title)
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

@MainActor
private enum CalendarPickerAppearance {
  static let apply: Void = {
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
}
