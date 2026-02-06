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
      VStack(spacing: 24) {
        // Error message
        if let error = viewModel.errorMessage {
          errorBanner(error)
        }

        // Success/info message
        if let success = viewModel.successMessage {
          successBanner(success)
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
          .padding(.top, 8)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 24)
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
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.circle.fill")
        .foregroundColor(.tidexError)
      Text(error)
        .font(.system(size: 14))
        .foregroundColor(.tidexError)
      Spacer()
      Button {
        viewModel.errorMessage = nil
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.tidexError)
      }
    }
    .padding(12)
    .background(Color.tidexError.opacity(0.1))
    .cornerRadius(8)
  }

  // MARK: - Success Banner

  @ViewBuilder
  private func successBanner(_ message: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundColor(.tidexSuccess)
      Text(message)
        .font(.system(size: 14))
        .foregroundColor(.tidexSuccess)
      Spacer()
      Button {
        viewModel.successMessage = nil
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.tidexSuccess)
      }
    }
    .padding(12)
    .background(Color.tidexSuccess.opacity(0.1))
    .cornerRadius(8)
    .onAppear {
      // Auto-dismiss after 4 seconds
      Task {
        try? await Task.sleep(for: .seconds(4))
        await MainActor.run {
          viewModel.successMessage = nil
        }
      }
    }
  }

  // MARK: - Grandfathered Banner

  private var grandfatheredBanner: some View {
    HStack(spacing: 12) {
      Image(systemName: "star.fill")
        .font(.system(size: 20))
        .foregroundColor(.tidexWarning)

      VStack(alignment: .leading, spacing: 2) {
        Text(.subscriptionEarlySupporterTitle)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.tidexTextPrimary)

        Text(.subscriptionEarlySupporterDescription)
          .font(.system(size: 13))
          .foregroundColor(.tidexTextSecondary)
      }

      Spacer()
    }
    .padding(16)
    .background(Color.tidexWarning.opacity(0.1))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.tidexWarning.opacity(0.3), lineWidth: 1)
    )
    .cornerRadius(12)
  }

  // MARK: - Current Plan Section

  private var currentPlanSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Section header
      Text(.subscriptionCurrentPlanSectionTitle)
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.tidexTextMuted)
        .textCase(.uppercase)

      // Plan card
      VStack(spacing: 0) {
        // Plan name and status
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.tierDisplayName)
              .font(.system(size: 20, weight: .bold))
              .foregroundColor(.tidexTextPrimary)

            if viewModel.hasActiveSubscription {
              statusBadge(isActive: true)
            }
          }

          Spacer()

          // Tier icon
          tierIcon
        }
        .padding(16)

        Divider()
          .background(Color.tidexBorder)

        // Price and billing
        if viewModel.hasActiveSubscription {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(.subscriptionCurrentPlanPrice)
                .font(.system(size: 13))
                .foregroundColor(.tidexTextSecondary)

              if let price = viewModel.priceDisplayText {
                Text("\(price) \(viewModel.billingPeriodText)")
                  .font(.system(size: 16, weight: .semibold))
                  .foregroundColor(.tidexTextPrimary)
              } else {
                Text(viewModel.billingPeriodText.capitalized)
                  .font(.system(size: 16, weight: .semibold))
                  .foregroundColor(.tidexTextPrimary)
              }
            }

            Spacer()

            // Renewal date
            if let renewalDate = viewModel.formattedRenewalDate {
              VStack(alignment: .trailing, spacing: 4) {
                Text(.subscriptionCurrentPlanRenews)
                  .font(.system(size: 13))
                  .foregroundColor(.tidexTextSecondary)

                Text(renewalDate)
                  .font(.system(size: 16, weight: .semibold))
                  .foregroundColor(.tidexTextPrimary)
              }
            }
          }
          .padding(16)
        }
      }
      .background(Color.tidexSurfacePrimary)
      .cornerRadius(12)
    }
  }

  @ViewBuilder
  private func statusBadge(isActive: Bool) -> some View {
    Text(
      isActive
        ? String(localized: .subscriptionStatusActive)
        : String(localized: .subscriptionStatusInactive)
    )
    .font(.system(size: 12, weight: .medium))
    .foregroundColor(isActive ? .tidexSuccess : .tidexTextMuted)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(isActive ? Color.tidexSuccess.opacity(0.15) : Color.tidexSurfaceSecondary)
    .cornerRadius(6)
  }

  @ViewBuilder
  private var tierIcon: some View {
    ZStack {
      Circle()
        .fill(tierColor.opacity(0.15))
        .frame(width: 48, height: 48)

      Image(systemName: tierIconName)
        .font(.system(size: 22))
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
    VStack(alignment: .leading, spacing: 12) {
      // Section header
      Text(.subscriptionFeaturesSectionTitle)
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.tidexTextMuted)
        .textCase(.uppercase)

      // Features card
      VStack(alignment: .leading, spacing: 12) {
        ForEach(currentFeatures, id: \.self) { feature in
          HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 18))
              .foregroundColor(.tidexSuccess)

            Text(feature)
              .font(.system(size: 15))
              .foregroundColor(.tidexTextPrimary)

            Spacer()
          }
        }

        // Lifetime access note for grandfathered users
        if viewModel.isGrandfathered {
          HStack(spacing: 12) {
            Image(systemName: "infinity.circle.fill")
              .font(.system(size: 18))
              .foregroundColor(.tidexWarning)

            Text(.subscriptionFeaturesLifetimeAccess)
              .font(.system(size: 15, weight: .medium))
              .foregroundColor(.tidexWarning)

            Spacer()
          }
        }
      }
      .padding(16)
      .background(Color.tidexSurfacePrimary)
      .cornerRadius(12)
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
    VStack(spacing: 12) {
      // Manage subscription button (for users with active subscription)
      if viewModel.hasActiveSubscription {
        Button {
          viewModel.manageSubscription()
        } label: {
          HStack {
            Image(systemName: "gearshape.fill")
              .font(.system(size: 16))
            Text(.subscriptionActionsManage)
              .font(.system(size: 16, weight: .semibold))
          }
          .foregroundColor(.tidexBlue)
          .frame(maxWidth: .infinity)
          .frame(height: Spacing.buttonHeight)
          .background(Color.tidexBlue.opacity(0.1))
          .cornerRadius(12)
        }
      }

      // Upgrade/Subscribe button (for free users or non-active subscriptions)
      if viewModel.canUpgrade {
        Button {
          viewModel.showUpgradeOptions()
        } label: {
          HStack {
            Image(systemName: "crown.fill")
              .font(.system(size: 16))
            Text(
              viewModel.effectiveTier == .free
                ? String(localized: .subscriptionActionsSubscribe)
                : String(localized: .subscriptionActionsUpgrade)
            )
            .font(.system(size: 16, weight: .semibold))
          }
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: Spacing.buttonHeight)
          .background(Color.tidexBlue)
          .cornerRadius(12)
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
        .font(.system(size: 15, weight: .medium))
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
    HStack(spacing: 16) {
      Button {
        safariURL = termsURL
      } label: {
        Text(.paywallTermsOfUse)
          .font(.system(size: 13))
          .foregroundColor(.tidexTextMuted)
      }

      Text("•")
        .foregroundColor(.tidexTextMuted)

      Button {
        safariURL = privacyURL
      } label: {
        Text(.paywallPrivacyPolicy)
          .font(.system(size: 13))
          .foregroundColor(.tidexTextMuted)
      }
    }
  }

  // MARK: - Loading Overlay

  private var loadingOverlay: some View {
    ZStack {
      Color.tidexBackground.opacity(0.8)

      VStack(spacing: 16) {
        ProgressView()
          .scaleEffect(1.2)

        Text(
          viewModel.isRestoring
            ? String(localized: .subscriptionRestoreLoading)
            : String(localized: .commonLoading)
        )
        .font(.system(size: 15))
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
