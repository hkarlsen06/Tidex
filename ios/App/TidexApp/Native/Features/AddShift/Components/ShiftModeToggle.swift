import SwiftUI

/// Toggle between single and recurring shift modes
/// Pill-shaped segmented control matching the web design
struct ShiftModeToggle: View {
    @Binding var mode: AddShiftMode
    @Environment(\.localization) private var localization

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AddShiftMode.allCases) { modeOption in
                ModeButton(
                    title: localizedTitle(for: modeOption),
                    isSelected: mode == modeOption
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        mode = modeOption
                    }
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
            }
        }
        .padding(4)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(Capsule())
    }

    private func localizedTitle(for mode: AddShiftMode) -> String {
        switch mode {
        case .single:
            return localization.string("addShift.modeSingle")
        case .recurring:
            return localization.string("addShift.modeRecurring")
        }
    }
}

// MARK: - Mode Button

private struct ModeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? .white : .tidexTextSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    isSelected ? Color.tidexBlue : Color.clear
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
