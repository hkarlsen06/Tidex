import SwiftUI

/// Reusable accordion component for onboarding settings
/// Expands to show content, collapses to show summary
struct AccordionSectionView<Content: View>: View {
  let title: String
  let summary: String?
  let isExpanded: Bool
  let isComplete: Bool
  let onContinue: (() -> Void)?
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(spacing: 0) {
      header

      // Content (when expanded)
      if isExpanded {
        expandedContent
      }
    }
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .stroke(isExpanded ? Color.tidexBrandPrimary.opacity(0.3) : Color.tidexBorder, lineWidth: 1)
    )
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(title)
          .font(.tidexButton)
          .foregroundColor(.tidexTextPrimary)

        if !isExpanded, let summary {
          Text(summary)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)
        }
      }

      Spacer()

      // Status indicator
      if isComplete {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 20))
          .foregroundColor(.tidexSuccess)
      } else if isExpanded {
        Image(systemName: "chevron.up")
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)
      } else {
        Image(systemName: "chevron.down")
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)
      }
    }
    .padding(Spacing.md)
  }

  private var expandedContent: some View {
    VStack(spacing: Spacing.md) {
      content()

      if let onContinue {
        Button(action: {
          Haptics.play(.medium)
          onContinue()
        }) {
          Text(.commonContinue)
            .font(.tidexLabelStrong)
            .foregroundColor(.tidexTextOnBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: 44)
            .background(Color.tidexBrandPrimary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.bottom, Spacing.md)
    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.md) {
    AccordionSectionView(
      title: "Break Deduction",
      summary: "Enabled • 30 min for 5.5h+ shifts",
      isExpanded: true,
      isComplete: false,
      onContinue: {}
    ) {
      Toggle("Enable automatic break deduction", isOn: .constant(true))
    }

    AccordionSectionView(
      title: "Tax Deduction",
      summary: "22%",
      isExpanded: false,
      isComplete: true,
      onContinue: nil
    ) {
      Text("Content")
    }

    AccordionSectionView(
      title: "Payday",
      summary: "15th",
      isExpanded: false,
      isComplete: false,
      onContinue: nil
    ) {
      Text("Content")
    }
  }
  .padding()
  .background(Color.tidexBackground)
}
