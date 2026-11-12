import SwiftUI

/// The floating pill's content while Stats shows a year. It has the month picker's layout, so the
/// pill keeps its frame when the period changes. Changing year keeps the month, so switching
/// back shows the same month of the picked year.
struct StatsYearPicker: View {
  private let monthContext: SharedMonthContext = .shared
  private let navTapTargetSize: CGFloat = 44
  private let navTextSafeInset: CGFloat = 24

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.layoutDirection) private var layoutDirection
  @ScaledMetric(relativeTo: .body) private var navIconSize: CGFloat = 16

  private var year: Int { monthContext.displayYear }

  var body: some View {
    Text(verbatim: String(year))
      .font(.tidexBodyMedium)
      .monospacedDigit()
      .foregroundStyle(Color.tidexTextPrimary)
      .contentTransition(reduceMotion ? .identity : .numericText(value: Double(year)))
      .animation(reduceMotion ? nil : .snappy, value: year)
      .lineLimit(1)
      .minimumScaleFactor(0.4)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, navTextSafeInset)
      .contentShape(Rectangle())
      .highPriorityGesture(
        LongPressGesture(minimumDuration: 0.35)
          .onEnded { _ in
            guard year != Date.currentYearMonth().year else { return }
            Haptics.play(.heavy)
            goToCurrentYear()
          }
      )
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(.commonYear))
      .accessibilityValue(Text(verbatim: String(year)))
      .accessibilityAddTraits(.isHeader)
      .accessibilityAdjustableAction { direction in
        switch direction {
        case .increment: goToYear(year + 1)
        case .decrement: goToYear(year - 1)
        @unknown default: break
        }
      }
      .accessibilityAction(named: Text(.statsPeriodThisYear)) { goToCurrentYear() }
      .accessibilityIdentifier("stats.year-picker")
      .frame(maxWidth: .infinity)
      .overlay(alignment: .leading) {
        chevron(
          icon: layoutDirection == .rightToLeft ? "chevron.right" : "chevron.left",
          label: .commonPreviousYear
        ) { goToYear(year - 1) }
      }
      .overlay(alignment: .trailing) {
        chevron(
          icon: layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right",
          label: .commonNextYear
        ) { goToYear(year + 1) }
      }
      .padding(.horizontal, Spacing.xsm)
      .padding(.vertical, Spacing.sm)
      .contentShape(Rectangle())
      .gesture(swipeGesture)
      .sensoryFeedback(.impact(weight: .medium), trigger: year)
  }

  private func chevron(
    icon: String, label: LocalizedStringResource, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: min(navIconSize, Spacing.iconSize), weight: .semibold))
        .foregroundStyle(Color.tidexBlueText)
        .frame(width: navTapTargetSize, height: navTapTargetSize)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .buttonRepeatBehavior(.enabled)
    .accessibilityLabel(Text(label))
  }

  private var swipeGesture: some Gesture {
    DragGesture(minimumDistance: 30)
      .onEnded { value in
        let horizontal = value.translation.width
        guard abs(horizontal) > abs(value.translation.height) else { return }
        goToYear(horizontal > 0 ? year - 1 : year + 1)
      }
  }

  private func goToYear(_ target: Int) {
    AppearanceTracker.shared.reset()
    monthContext.navigateTo(year: target, month: monthContext.displayMonth)
  }

  private func goToCurrentYear() {
    goToYear(Date.currentYearMonth().year)
  }
}
