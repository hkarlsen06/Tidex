import SwiftUI

/// Shared layout of the add job pages. It shows a header row, an icon with a title, a stack
/// of cards, an optional validation error and a continue button pinned to the bottom.
/// Pass `isContinueHidden` while a text field has focus, so the button doesn't sit on top of
/// the keyboard and skip the cards below the field.
struct AddJobStepPage<Header: View, Cards: View>: View {
  let icon: String
  var iconTint: Color = .tidexBlueText
  let title: LocalizedStringResource
  let continueTitle: String
  let isContinueEnabled: Bool
  let validationError: String?
  var isContinueHidden = false
  let onContinue: () -> Void
  @ViewBuilder let header: Header
  @ViewBuilder let cards: Cards

  @ScaledMetric(relativeTo: .title3) private var iconBadgeSize: CGFloat = 64

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        ScrollView {
          scrollContent
        }
        .scrollDismissesKeyboard(.interactively)

        if !isContinueHidden {
          continueBar
        }
      }
    }
  }

  private var scrollContent: some View {
    VStack(spacing: 0) {
      header
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .adaptiveContentWidth()

      Spacer()
        .frame(height: 24)

      titleBlock

      Spacer()
        .frame(height: 28)

      VStack(spacing: Spacing.sm) {
        cards
      }
      .padding(.horizontal, Spacing.lg)
      .adaptiveContentWidth()

      if let validationError {
        Text(validationError)
          .font(.tidexFootnote)
          .foregroundColor(.tidexError)
          .padding(.horizontal, Spacing.lg)
          .padding(.top, Spacing.sm)
          .frame(maxWidth: .infinity, alignment: .leading)
          .adaptiveContentWidth()
          .announcesToVoiceOver(validationError)
      }

      Spacer()
        .frame(height: 120)
    }
  }

  private var titleBlock: some View {
    VStack(spacing: Spacing.sm) {
      Image(systemName: icon)
        .font(.tidexTitle)
        .foregroundColor(iconTint)
        .frame(width: iconBadgeSize, height: iconBadgeSize)
        .background(iconTint.opacity(0.16), in: Circle())
        .accessibilityHidden(true)
      Text(title)
        .font(.tidexScreenTitle)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
    }
    .padding(.horizontal, Spacing.xl)
    .adaptiveContentWidth()
  }

  private var continueBar: some View {
    VStack(spacing: 0) {
      LinearGradient(
        colors: [Color.tidexBackground.opacity(0), Color.tidexBackground],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: 24)

      OnboardingButton(
        title: continueTitle,
        isEnabled: isContinueEnabled,
        action: onContinue
      )
      .padding(.horizontal, Spacing.lg)
      .padding(.bottom, Spacing.xl)
      .adaptiveContentWidth()
      .background(Color.tidexBackground)
    }
  }
}

/// Dims the page and shows a spinner while the job is being saved.
struct AddJobSavingOverlay: View {
  var body: some View {
    ZStack {
      Color.black.opacity(0.35)
        .ignoresSafeArea()

      VStack(spacing: Spacing.sm) {
        ProgressView()
        Text(.commonLoading)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextPrimary)
      }
      .padding(Spacing.md)
      .background(Color.tidexSurfacePrimary.opacity(0.9))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
    }
    // Keeps VoiceOver on the saving message instead of the controls behind it.
    .accessibilityAddTraits(.isModal)
  }
}
