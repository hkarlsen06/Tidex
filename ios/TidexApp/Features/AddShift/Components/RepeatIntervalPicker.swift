import SwiftUI

/// Picker for selecting the repeat interval of a recurring shift
/// Shows "Repeat every [X] week(s)" format
struct RepeatIntervalPicker: View {
  @Binding var interval: Int  // 0-8 (0 = weekly, 1 = biweekly, etc.)

  // Get localized ordinal label for interval
  private func ordinalLabel(_ index: Int) -> String {
    let weeks = index + 1
    if weeks == 1 {
      return String(localized: .addShiftEveryWeek)
    }
    return String(localized: .addShiftEveryNWeeks(weeks))
  }

  var body: some View {
    HStack(spacing: Spacing.xs) {
      Text(.addShiftRepeat)
        .font(.tidexBody)
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
        HStack(spacing: Spacing.xxs) {
          Text(ordinalLabel(interval))
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexBlue)

          Image(systemName: "chevron.up.chevron.down")
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexBlue)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
      }

      Spacer()
    }
    .padding(.vertical, Spacing.xs)
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.mlg) {
    RepeatIntervalPicker(interval: .constant(0))
    RepeatIntervalPicker(interval: .constant(1))
    RepeatIntervalPicker(interval: .constant(3))
  }
  .padding()
  .background(Color.tidexBackground)
}
