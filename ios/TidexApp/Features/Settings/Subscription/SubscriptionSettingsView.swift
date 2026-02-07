import SafariServices
import SwiftUI

/// Subscription settings view
/// Displays current subscription status, plan features, and management options
struct SubscriptionSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel = SubscriptionSettingsViewModel()

  /// URL for in-app Safari browser
  @State private var safariURL: URL?

  var body: some View {
    ScrollView {
      VStack(spacing: Spacing.lg) {
        // Error message
        if let error = viewModel.errorMessage {
          errorBanner(error)
        }

        // Grandfathered banner (early supporter)
        if viewModel.isGrandfathered && viewModel.hasPremiumAccess {
          grandfatheredBanner
        }

        // Current plan section (for subscribed users)
        if viewModel.hasPremiumAccess {
          currentPlanSection
        }

        // Features section
        featuresSection

        // Action buttons
        actionButtonsSection

        // Restore purchases
        restorePurchasesButton

        // Legal links
        legalLinks
          .padding(.top, Spacing.xs)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.lg)
    }
    .background(Color.tidexBackground)
    .navigationTitle(String(localized: .subscriptionTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadSubscriptionInfo()
    }
    .sheet(isPresented: $viewModel.showPaywall) {
      PaywallView(contextType: .upgrade)
        .onDisappear {
          // Reload subscription info after paywall closes
          Task {
            await viewModel.loadSubscriptionInfo()
          }
        }
    }
    .overlay {
      if viewModel.isLoading {
        loadingOverlay
      }
    }
    .fullScreenCover(item: $safariURL) { url in
      SubscriptionSafariView(url: url)
        .ignoresSafeArea()
    }
  }

  // MARK: - Error Banner

  @ViewBuilder
  private func errorBanner(_ error: String) -> some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "exclamationmark.circle.fill")
        .foregroundColor(.tidexError)
      Text(error)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexError)
      Spacer()
      Button {
        viewModel.errorMessage = nil
      } label: {
        Image(systemName: "xmark")
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexError)
      }
    }
    .padding(Spacing.sm)
    .background(Color.tidexError.opacity(0.1))
    .cornerRadius(CornerRadius.sm)
  }

  // MARK: - Grandfathered Banner

  private var grandfatheredBanner: some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: "star.fill")
        .font(.tidexTitle2)
        .foregroundColor(.tidexWarning)

      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(.subscriptionEarlySupporterTitle)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextPrimary)

        Text(.subscriptionEarlySupporterDescription)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }

      Spacer()
    }
    .padding(Spacing.md)
    .background(Color.tidexWarning.opacity(0.1))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.lg)
        .stroke(Color.tidexWarning.opacity(0.3), lineWidth: 1)
    )
    .cornerRadius(CornerRadius.lg)
  }

  // MARK: - Current Plan Section

  private var currentPlanSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      // Section header
      Text(.subscriptionCurrentPlanSectionTitle)
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexTextMuted)
        .textCase(.uppercase)

      // Plan card
      VStack(spacing: 0) {
        // Plan name and status
        HStack {
          VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(viewModel.tierDisplayName)
              .font(.tidexTitle2)
              .foregroundColor(.tidexTextPrimary)

            if viewModel.hasActiveSubscription {
              statusBadge(isActive: true)
            }
          }

          Spacer()

          // Tier icon
          tierIcon
        }
        .padding(Spacing.md)

        Divider()
          .background(Color.tidexBorder)

        // Price and billing
        if viewModel.hasActiveSubscription {
          HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
              Text(.subscriptionCurrentPlanPrice)
                .font(.tidexFootnote)
                .foregroundColor(.tidexTextSecondary)

              if let price = viewModel.priceDisplayText {
                Text("\(price) \(viewModel.billingPeriodText)")
                  .font(.tidexButton)
                  .foregroundColor(.tidexTextPrimary)
              } else {
                Text(viewModel.billingPeriodText.capitalized)
                  .font(.tidexButton)
                  .foregroundColor(.tidexTextPrimary)
              }
            }

            Spacer()

            // Renewal date
            if let renewalDate = viewModel.formattedRenewalDate {
              VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(.subscriptionCurrentPlanRenews)
                  .font(.tidexFootnote)
                  .foregroundColor(.tidexTextSecondary)

                Text(renewalDate)
                  .font(.tidexButton)
                  .foregroundColor(.tidexTextPrimary)
              }
            }
          }
          .padding(Spacing.md)
        }
      }
      .background(Color.tidexSurfacePrimary)
      .cornerRadius(CornerRadius.lg)
    }
  }

  @ViewBuilder
  private func statusBadge(isActive: Bool) -> some View {
    Text(
      isActive
        ? String(localized: .subscriptionStatusActive)
        : String(localized: .subscriptionStatusInactive)
    )
    .font(.tidexCaption)
    .foregroundColor(isActive ? .tidexSuccess : .tidexTextMuted)
    .padding(.horizontal, Spacing.xs)
    .padding(.vertical, Spacing.xxs)
    .background(isActive ? Color.tidexSuccess.opacity(0.15) : Color.tidexSurfaceSecondary)
    .cornerRadius(CornerRadius.xs)
  }

  @ViewBuilder
  private var tierIcon: some View {
    ZStack {
      Circle()
        .fill(tierColor.opacity(0.15))
        .frame(width: 48, height: 48)

      Image(systemName: tierIconName)
        .font(.tidexTitle)
        .foregroundColor(tierColor)
    }
  }

  private var tierColor: Color {
    switch viewModel.effectiveTier {
    case .free:
      return .tidexTextMuted
    case .pro:
      return .tidexBlue
    case .max:
      return .tidexWarning
    }
  }

  private var tierIconName: String {
    switch viewModel.effectiveTier {
    case .free:
      return "person.circle"
    case .pro:
      return "star.circle.fill"
    case .max:
      return "crown.fill"
    }
  }

  // MARK: - Features Section

  private var featuresSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      // Section header
      Text(.subscriptionFeaturesSectionTitle)
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexTextMuted)
        .textCase(.uppercase)

      // Features card
      VStack(alignment: .leading, spacing: Spacing.sm) {
        ForEach(currentFeatures, id: \.self) { feature in
          HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
              .font(.tidexHeadline)
              .foregroundColor(.tidexSuccess)

            Text(feature)
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextPrimary)

            Spacer()
          }
        }

        // Lifetime access note for grandfathered users
        if viewModel.isGrandfathered {
          HStack(spacing: Spacing.sm) {
            Image(systemName: "infinity.circle.fill")
              .font(.tidexHeadline)
              .foregroundColor(.tidexWarning)

            Text(.subscriptionFeaturesLifetimeAccess)
              .font(.tidexLabel)
              .foregroundColor(.tidexWarning)

            Spacer()
          }
        }
      }
      .padding(Spacing.md)
      .background(Color.tidexSurfacePrimary)
      .cornerRadius(CornerRadius.lg)
    }
  }

  private var currentFeatures: [String] {
    switch viewModel.effectiveTier {
    case .free:
      return [
        String(localized: .paywallFreeFeature1),
        String(localized: .paywallFreeFeature2),
      ]
    case .pro:
      return [
        String(localized: .paywallProFeature1),
        String(localized: .paywallProFeature2),
        String(localized: .paywallProFeature3),
        String(localized: .paywallProFeature4),
      ]
    case .max:
      return [
        String(localized: .paywallMaxFeature1),
        String(localized: .paywallMaxFeature2),
        String(localized: .paywallMaxFeature3),
        String(localized: .paywallMaxFeature4),
        String(localized: .paywallMaxFeature5),
      ]
    }
  }

  // MARK: - Action Buttons Section

  private var actionButtonsSection: some View {
    VStack(spacing: Spacing.sm) {
      // Manage subscription button (for users with active subscription)
      if viewModel.hasActiveSubscription {
        Button {
          viewModel.manageSubscription()
        } label: {
          HStack {
            Image(systemName: "gearshape.fill")
              .font(.tidexBody)
            Text(.subscriptionActionsManage)
              .font(.tidexButton)
          }
          .foregroundColor(.tidexBlue)
          .frame(maxWidth: .infinity)
          .frame(height: Spacing.buttonHeight)
          .background(Color.tidexBlue.opacity(0.1))
          .cornerRadius(CornerRadius.lg)
        }
      }

      // Upgrade/Subscribe button (for free users or non-active subscriptions)
      if viewModel.canUpgrade {
        Button {
          viewModel.showUpgradeOptions()
        } label: {
          HStack {
            Image(systemName: "crown.fill")
              .font(.tidexBody)
            Text(
              viewModel.effectiveTier == .free
                ? String(localized: .subscriptionActionsSubscribe)
                : String(localized: .subscriptionActionsUpgrade)
            )
            .font(.tidexButton)
          }
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: Spacing.buttonHeight)
          .background(Color.tidexBlue)
          .cornerRadius(CornerRadius.lg)
        }
      }
    }
  }

  // MARK: - Restore Purchases Button

  private var restorePurchasesButton: some View {
    Button {
      Task {
        await viewModel.restorePurchases()
      }
    } label: {
      Text(.paywallRestorePurchases)
        .font(.tidexLabel)
        .foregroundColor(.tidexBlue)
    }
    .disabled(viewModel.isLoading)
  }

  // MARK: - Legal Links

  private var termsURL: URL {
    // swiftlint:disable:next force_unwrapping
    URL(string: "https://tidex.no/\(Locale.current.urlLanguageCode)/terms")!
  }

  private var privacyURL: URL {
    // swiftlint:disable:next force_unwrapping
    URL(string: "https://tidex.no/\(Locale.current.urlLanguageCode)/privacy")!
  }

  private var legalLinks: some View {
    HStack(spacing: Spacing.md) {
      Button {
        safariURL = termsURL
      } label: {
        Text(.paywallTermsOfUse)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
      }

      Text("•")
        .foregroundColor(.tidexTextMuted)

      Button {
        safariURL = privacyURL
      } label: {
        Text(.paywallPrivacyPolicy)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
      }
    }
  }

  // MARK: - Loading Overlay

  private var loadingOverlay: some View {
    ZStack {
      Color.tidexBackground.opacity(0.8)

      VStack(spacing: Spacing.md) {
        ProgressView()
          .scaleEffect(1.2)

        Text(
          viewModel.isRestoring
            ? String(localized: .subscriptionRestoreLoading)
            : String(localized: .commonLoading)
        )
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
      }
    }
    .ignoresSafeArea()
  }
}

// MARK: - Safari View

/// Wrapper for presenting SFSafariViewController in SwiftUI
private struct SubscriptionSafariView: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    SFSafariViewController(url: url)
  }

  func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
  NavigationStack {
    SubscriptionSettingsView()
  }
}
