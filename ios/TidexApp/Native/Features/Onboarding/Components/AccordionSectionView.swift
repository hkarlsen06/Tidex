import SwiftUI
import UIKit

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
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.tidexTextPrimary)

                    if !isExpanded, let summary = summary {
                        Text(summary)
                            .font(.system(size: 14))
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.tidexTextSecondary)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.tidexTextSecondary)
                }
            }
            .padding(16)

            // Content (when expanded)
            if isExpanded {
                VStack(spacing: 16) {
                    content()

                    if let onContinue = onContinue {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onContinue()
                        }) {
                            Text(.commonContinue)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.tidexBrandPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isExpanded ? Color.tidexBrandPrimary.opacity(0.3) : Color.tidexBorder, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
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
