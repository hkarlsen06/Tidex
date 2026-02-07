import SwiftUI

/// Toggle between single and recurring shift modes
/// Toolbar toggle with independent glass buttons
struct ShiftModeToggle: View {
  enum Style {
    case toolbar
    case standard
  }

  @Binding var mode: AddShiftMode
  let style: Style
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var namespace
  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 16
  private let buttonSpacing: CGFloat = 8
  private let toggleHaptic = UIImpactFeedbackGenerator(style: .light)

  init(mode: Binding<AddShiftMode>, style: Style = .toolbar) {
    self._mode = mode
    self.style = style
  }

  var body: some View {
    let verticalPadding: CGFloat = style == .toolbar ? 6 : Spacing.sm
    let horizontalPadding: CGFloat = style == .toolbar ? 10 : Spacing.md
    let outerPadding: CGFloat = style == .toolbar ? 2 : Spacing.xxs
    let iconFontSize: CGFloat = style == .toolbar ? 14 : iconSize
    let shadowRadius: CGFloat = style == .toolbar ? 0 : 4
    let shadowOpacity: Double = style == .toolbar ? 0 : 0.18

    HStack(spacing: buttonSpacing) {
      ForEach(AddShiftMode.allCases) { modeOption in
        let isSelected = mode == modeOption
        Button {
          select(modeOption)
        } label: {
          Label(localizedTitle(for: modeOption), systemImage: iconName(for: modeOption))
            .labelStyle(.iconOnly)
            .font(.system(size: iconFontSize, weight: .semibold))
            .foregroundStyle(isSelected ? .white : .tidexTextSecondary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
              if isSelected {
                Capsule()
                  .tidexGlass(
                    shape: .capsule,
                    tint: Color.tidexBlue.opacity(0.35)
                  )
                  .shadow(
                    color: Color.black.opacity(shadowOpacity),
                    radius: shadowRadius,
                    x: 0,
                    y: 2
                  )
                  .matchedGeometryEffect(id: "selection", in: namespace)
              }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localizedTitle(for: modeOption))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .padding(outerPadding)
    .onAppear {
      toggleHaptic.prepare()
    }
  }

  private func iconName(for mode: AddShiftMode) -> String {
    switch mode {
    case .single:
      return "calendar.badge.plus"
    case .recurring:
      return "repeat"
    }
  }

  private func localizedTitle(for mode: AddShiftMode) -> String {
    switch mode {
    case .single:
      return String(localized: .addShiftModeSingle)
    case .recurring:
      return String(localized: .addShiftModeRecurring)
    }
  }

  private func select(_ modeOption: AddShiftMode) {
    guard mode != modeOption else { return }
    toggleHaptic.impactOccurred()
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
  }
  .padding()
  .background(Color.tidexBackground)
}
