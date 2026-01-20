import SwiftUI

/// Toggle between single and recurring shift modes
/// Rounded segmented control with liquid glass styling
struct ShiftModeToggle: View {
    @Binding var mode: AddShiftMode
    @Environment(\.localization) private var localization

    private let cornerRadius: CGFloat = 22

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AddShiftMode.allCases) { modeOption in
                ModeButton(
                    title: localizedTitle(for: modeOption),
                    isSelected: mode == modeOption,
                    cornerRadius: cornerRadius - 4
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
    let cornerRadius: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? .white : .tidexTextSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.tidexBlue : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
