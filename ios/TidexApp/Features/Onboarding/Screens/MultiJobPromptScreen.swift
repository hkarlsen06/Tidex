import SwiftUI
import UIKit

/// Optional post-auth onboarding step for setting up an additional workplace/job.
struct MultiJobPromptScreen: View {
  var isLoading: Bool = false
  var didAddJob: Bool = false
  var jobs: [Job] = []
  let onAddNow: () -> Void
  let onContinueLater: () -> Void
  let onBack: () -> Void
  var errorMessage: String?

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        HStack {
          Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onBack()
          }) {
            HStack(spacing: Spacing.xxs) {
              Image(systemName: "chevron.left")
                .font(.tidexButton)
              Text(.commonBack)
                .font(.tidexBody)
            }
            .foregroundColor(.tidexBlue)
          }
          .buttonStyle(.plain)

          Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .adaptiveContentWidth()

        Spacer()

        ZStack {
          Circle()
            .fill(Color.tidexBlue.opacity(0.1))
            .frame(width: 120, height: 120)

          Image(systemName: "building.2")
            .font(.system(size: 52))
            .foregroundColor(.tidexBlue)
        }
        .padding(.bottom, Spacing.xl)

        VStack(spacing: Spacing.sm) {
          Text(.onboardingMultiJobTitle)
            .font(.tidexScreenTitle)
            .foregroundColor(.tidexTextPrimary)
            .multilineTextAlignment(.center)

          Text(.settingsPayAddJobSetupSubtitle)
            .font(.tidexBody)
            .foregroundColor(.tidexTextSecondary)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)

          Text(.onboardingMultiJobLaterHint)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.xl)
        .adaptiveContentWidth()

        if !jobs.isEmpty {
          addedJobsSummary
            .padding(.top, Spacing.md)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }

        if let errorMessage, !errorMessage.isEmpty {
          Text(errorMessage)
            .font(.tidexFootnote)
            .foregroundColor(.tidexError)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)
            .adaptiveContentWidth()
        }

        Spacer()

        VStack(spacing: Spacing.lg) {
          OnboardingButton(
            title: String(localized: .settingsPayAddJobCta),
            action: {
              UINotificationFeedbackGenerator().notificationOccurred(.success)
              onAddNow()
            }
          )
          .disabled(isLoading)

          Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onContinueLater()
          }) {
            Text(!jobs.isEmpty ? .commonContinue : .onboardingMfaSkip)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextSecondary)
          }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.xl)
        .adaptiveContentWidth()
      }
    }
  }

  @ViewBuilder
  private var addedJobsSummary: some View {
    OnboardingJobBadgeFlowLayout(spacing: Spacing.sm) {
      ForEach(jobs) { job in
        addedJobBadge(job)
      }
    }
    .padding(.horizontal, Spacing.xl)
    .adaptiveContentWidth()
  }

  private func addedJobBadge(_ job: Job) -> some View {
    ZStack(alignment: .trailing) {
      WorkplaceNameText(
        name: job.name,
        colorHex: job.color,
        font: .tidexBodyMedium,
        fallbackBadgeColor: .tidexBlue,
        lineLimit: 1
      )
      .padding(.trailing, Spacing.lg)

      Image(systemName: "checkmark.circle.fill")
        .font(.tidexSubheadline)
        .foregroundColor(.tidexSuccess)
        .background(Color.tidexBackground, in: Circle())
        .accessibilityHidden(true)
    }
    .fixedSize(horizontal: true, vertical: false)
  }
}

private struct OnboardingJobBadgeFlowLayout: Layout {
  var spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    computeLayout(proposal: proposal, subviews: subviews).size
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    let layout = computeLayout(proposal: proposal, subviews: subviews)
    for (index, position) in layout.positions.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
        proposal: .unspecified
      )
    }
  }

  private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (
    size: CGSize,
    positions: [CGPoint]
  ) {
    let maxWidth = proposal.width ?? 0
    var positions: [CGPoint] = []
    var currentX: CGFloat = 0
    var currentY: CGFloat = 0
    var lineHeight: CGFloat = 0
    var contentWidth: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      let shouldWrap = maxWidth > 0 && currentX > 0 && currentX + size.width > maxWidth

      if shouldWrap {
        currentX = 0
        currentY += lineHeight + spacing
        lineHeight = 0
      }

      positions.append(CGPoint(x: currentX, y: currentY))
      lineHeight = max(lineHeight, size.height)
      contentWidth = max(contentWidth, currentX + size.width)
      currentX += size.width + spacing
    }

    return (
      CGSize(width: maxWidth > 0 ? maxWidth : contentWidth, height: currentY + lineHeight),
      positions
    )
  }
}

#Preview {
  MultiJobPromptScreen(
    onAddNow: {},
    onContinueLater: {},
    onBack: {},
    errorMessage: nil
  )
}
