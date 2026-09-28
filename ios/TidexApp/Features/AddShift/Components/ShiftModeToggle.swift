import SwiftUI

/// Toggle between Add tab modes.
/// Toolbar toggle with independent glass buttons
struct ShiftModeToggle: View {
  enum Style {
    case toolbar
    case standard
  }

  private struct ModeButtonMetrics {
    let iconFontSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let shadowRadius: CGFloat
    let shadowOpacity: Double
  }

  private static let toolbarIconFontSize: CGFloat = 14
  private static let toolbarHorizontalPadding: CGFloat = 10
  private static let toolbarVerticalPadding: CGFloat = 6
  private static let toolbarOuterPadding: CGFloat = 2
  private static let standardShadowRadius: CGFloat = 4
  private static let standardShadowOpacity: Double = 0.18
  private static let selectedStandardTintOpacity: Double = 0.35
  private static let selectedShadowYOffset: CGFloat = 2

  @Binding var mode: AddShiftMode
  let style: Style
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var namespace
  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 16
  private let buttonSpacing: CGFloat = 8

  init(mode: Binding<AddShiftMode>, style: Style = .toolbar) {
    self._mode = mode
    self.style = style
  }

  var body: some View {
    let metrics: ModeButtonMetrics = modeButtonMetrics
    let outerPadding: CGFloat = style == .toolbar ? Self.toolbarOuterPadding : Spacing.xxs

    HStack(spacing: buttonSpacing) {
      ForEach(AddShiftMode.displayOrder) { modeOption in
        modeButton(for: modeOption, metrics: metrics)
      }
    }
    .padding(outerPadding)
    .sensoryFeedback(.impact(weight: .light), trigger: mode)
  }

  private var modeButtonMetrics: ModeButtonMetrics {
    ModeButtonMetrics(
      iconFontSize: style == .toolbar ? Self.toolbarIconFontSize : iconSize,
      horizontalPadding: style == .toolbar ? Self.toolbarHorizontalPadding : Spacing.md,
      verticalPadding: style == .toolbar ? Self.toolbarVerticalPadding : Spacing.sm,
      shadowRadius: style == .toolbar ? 0 : Self.standardShadowRadius,
      shadowOpacity: style == .toolbar ? 0 : Self.standardShadowOpacity
    )
  }

  private func modeButton(
    for modeOption: AddShiftMode,
    metrics: ModeButtonMetrics
  ) -> some View {
    let isSelected: Bool = mode == modeOption

    return Button {
      select(modeOption)
    } label: {
      modeButtonLabel(
        for: modeOption,
        isSelected: isSelected,
        metrics: metrics
      )
    }
    .buttonStyle(.plain)
    .accessibilityLabel(localizedTitle(for: modeOption))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier("add-shift.mode.\(modeOption.rawValue)")
  }

  @ViewBuilder
  private func modeButtonLabel(
    for modeOption: AddShiftMode,
    isSelected: Bool,
    metrics: ModeButtonMetrics
  ) -> some View {
    if isSelected, style == .standard {
      baseLabel(for: modeOption, isSelected: isSelected, metrics: metrics)
        .tidexGlass(
          shape: .capsule,
          tint: Color.tidexBlue.opacity(Self.selectedStandardTintOpacity),
          interactive: true
        )
        .shadow(
          color: Color.black.opacity(metrics.shadowOpacity),
          radius: metrics.shadowRadius,
          x: 0,
          y: Self.selectedShadowYOffset
        )
        .matchedGeometryEffect(id: "selection", in: namespace)
    } else {
      baseLabel(for: modeOption, isSelected: isSelected, metrics: metrics)
    }
  }

  private func baseLabel(
    for modeOption: AddShiftMode,
    isSelected: Bool,
    metrics: ModeButtonMetrics
  ) -> some View {
    let selectedForeground: Color = style == .toolbar ? .tidexBlue : .white

    // Show the selected mode's name next to its icon.
    return HStack(spacing: Spacing.xxs) {
      Image(systemName: iconName(for: modeOption))
      if isSelected {
        Text(localizedTitle(for: modeOption))
          .lineLimit(1)
      }
    }
    .font(.system(size: metrics.iconFontSize, weight: .semibold))
    .foregroundStyle(isSelected ? selectedForeground : .tidexTextSecondary)
    .padding(.horizontal, metrics.horizontalPadding)
    .padding(.vertical, metrics.verticalPadding)
    .contentShape(Capsule())
  }

  private func iconName(for mode: AddShiftMode) -> String {
    switch mode {
    case .single:
      return "1.calendar"

    case .recurring:
      return "repeat"

    case .events:
      return "calendar.and.person"
    }
  }

  private func localizedTitle(for mode: AddShiftMode) -> String {
    switch mode {
    case .single:
      return String(localized: .addShiftModeSingle)

    case .recurring:
      return String(localized: .addShiftModeRecurring)

    case .events:
      return String(localized: .addShiftModeEvents)
    }
  }

  private func select(_ modeOption: AddShiftMode) {
    guard mode != modeOption else { return }
    if reduceMotion {
      mode = modeOption
    } else {
      withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
        mode = modeOption
      }
    }
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.mlg) {
    ShiftModeToggle(mode: .constant(.single))
    ShiftModeToggle(mode: .constant(.recurring))
    ShiftModeToggle(mode: .constant(.events))
  }
  .padding()
  .background(Color.tidexBackground)
}
