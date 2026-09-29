import SwiftUI

// MARK: - Day Button

struct DayButton: View {
  let day: Int
  let isSelected: Bool
  let action: () -> Void

  @ScaledMetric(relativeTo: .body) private var circleSize: CGFloat = 40

  var body: some View {
    Button(action: action) {
      Text(OnboardingWeekday.initial(for: day))
        .font(isSelected ? .tidexLabelStrong : .tidexLabel)
        .foregroundColor(isSelected ? .tidexTextOnBrand : .tidexTextSecondary)
        .frame(width: circleSize, height: circleSize)
        .background(isSelected ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary)
        .clipShape(Circle())
        .overlay(
          Circle()
            .stroke(isSelected ? Color.clear : Color.tidexBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .frame(minWidth: 44, minHeight: 44)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(verbatim: OnboardingWeekday.name(for: day)))
    .accessibilityInputLabels([OnboardingWeekday.name(for: day), OnboardingWeekday.initial(for: day)])
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

// MARK: - Quick Select Button

struct QuickSelectButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: {
      Haptics.play(.light)
      action()
    }) {
      Text(title)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexBlueText)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.tidexBlue.opacity(0.08))
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Type Button

struct TypeButton: View {
  let title: String
  let subtitle: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: Spacing.xxs) {
        Text(title)
          .font(isSelected ? .tidexLabelStrong : .tidexLabel)
          .foregroundColor(isSelected ? .tidexTextPrimary : .tidexTextSecondary)

        Text(subtitle)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.xs)
      .frame(minHeight: 64)
      .background(isSelected ? Color.tidexBrandPrimary.opacity(0.08) : Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .stroke(
            isSelected ? Color.tidexBrandPrimary : Color.tidexBorder, lineWidth: isSelected ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }
}

// MARK: - Quick Value Button

struct QuickValueButton: View {
  let value: Double
  let type: OnboardingSupplementRule.SupplementType
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(type == .fixed ? "+\(Int(value))" : "\(Int(value))%")
        .font(isSelected ? .tidexLabelStrong : .tidexLabel)
        .foregroundColor(isSelected ? .tidexTextOnBrand : .tidexTextSecondary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 44)
        .background(isSelected ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary)
        .clipShape(Capsule())
        .overlay(
          Capsule()
            .stroke(isSelected ? Color.clear : Color.tidexBorder, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
