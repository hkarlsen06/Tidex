import SwiftUI

/// Toggle between single and recurring shift modes
/// Toolbar toggle with independent glass buttons
struct ShiftModeToggle: View {
    @Binding var mode: AddShiftMode
    @Environment(\.localization) private var localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var minSegmentWidth: CGFloat = 44
    private let buttonPadding: CGFloat = Spacing.xxs
    private let buttonSpacing: CGFloat = 8
    private let toggleHaptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        HStack(spacing: buttonSpacing) {
            ForEach(AddShiftMode.allCases) { modeOption in
                let isSelected = mode == modeOption
                Button {
                    select(modeOption)
                } label: {
                    Label(localizedTitle(for: modeOption), systemImage: iconName(for: modeOption))
                        .labelStyle(.iconOnly)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .tidexTextSecondary)
                        .frame(minWidth: minSegmentWidth, minHeight: height)
                        .contentShape(Capsule())
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.clear)
                                    .glassEffect(
                                        .regular.tint(Color.tidexBlue.opacity(0.35)),
                                        in: .capsule
                                    )
                                    .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localizedTitle(for: modeOption))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(buttonPadding)
        .iPadFixedHeight(height + buttonPadding * 2)
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
            return localization.string("addShift.modeSingle")
        case .recurring:
            return localization.string("addShift.modeRecurring")
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
    VStack(spacing: 20) {
        ShiftModeToggle(mode: .constant(.single))
        ShiftModeToggle(mode: .constant(.recurring))
    }
    .padding()
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
