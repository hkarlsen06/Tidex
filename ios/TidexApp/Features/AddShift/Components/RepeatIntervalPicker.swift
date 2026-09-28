import SwiftUI

/// Picker for selecting the repeat interval of a recurring shift
/// Shows "Repeat every [X] week(s)" format
internal struct RepeatIntervalPicker: View {
  private static let maxRepeatInterval: Int = 8

  @Binding internal var interval: Int  // 0-8 (0 = weekly, 1 = biweekly, etc.)

  internal var body: some View {
    HStack(spacing: Spacing.xs) {
      Text(.addShiftRepeat)
        .font(.tidexBody)
        .foregroundColor(.tidexTextPrimary)

      Menu {
        ForEach(0...Self.maxRepeatInterval, id: \.self) { intervalOption in
          Button(action: {
            interval = intervalOption
            // Haptic feedback
            let generator: UIImpactFeedbackGenerator = .init(style: .light)
            generator.impactOccurred()
          }) {
            Text(ordinalLabel(intervalOption))
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
            .accessibilityHidden(true)
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

  // Get localized ordinal label for interval
  private func ordinalLabel(_ index: Int) -> String {
    String(localized: .addShiftEveryNWeeks(index + 1))
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
