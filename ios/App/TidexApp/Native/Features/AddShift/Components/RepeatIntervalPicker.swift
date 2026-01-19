import SwiftUI

/// Picker for selecting the repeat interval of a recurring shift
/// Shows "Repeat every [X] week(s)" format
struct RepeatIntervalPicker: View {
    @Binding var interval: Int  // 0-8 (0 = weekly, 1 = biweekly, etc.)
    @Environment(\.localization) private var localization

    // Get localized ordinal label for interval
    private func ordinalLabel(_ index: Int) -> String {
        let weeks = index + 1
        if weeks == 1 {
            return localization.string("addShift.everyWeek")
        } else {
            return localization.string("addShift.everyNWeeks")
                .replacingOccurrences(of: "{n}", with: "\(weeks)")
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(localization.string("addShift.repeat"))
                .font(.system(size: 16))
                .foregroundColor(.tidexTextPrimary)

            Menu {
                ForEach(0..<9) { i in
                    Button(action: {
                        interval = i
                        // Haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }) {
                        Text(ordinalLabel(i))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(ordinalLabel(interval))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.tidexBlue)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.tidexBlue)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.tidexSurfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        RepeatIntervalPicker(interval: .constant(0))
        RepeatIntervalPicker(interval: .constant(1))
        RepeatIntervalPicker(interval: .constant(3))
    }
    .padding()
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
