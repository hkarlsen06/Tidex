import SafariServices
import SwiftUI

/// Subscription settings view
/// Displays current subscription status, plan features, and management options
struct SubscriptionSettingsView: View {
    @Environment(\.localization) private var localization
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SubscriptionSettingsViewModel()

    /// URL for in-app Safari browser
    @State private var safariURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

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
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color.tidexBackground)
        .navigationTitle(localization.string("subscription.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.tidexBackground, for: .navigationBar)
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

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.hasPremiumAccess
                 ? localization.string("subscription.title")
                 : localization.string("subscription.choosePlan.title"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.tidexTextPrimary)

            Text(viewModel.hasPremiumAccess
                 ? localization.string("subscription.subtitle")
                 : localization.string("subscription.choosePlan.subtitle"))
                .font(.subheadline)
                .foregroundColor(.tidexTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Grandfathered Banner

    private var grandfatheredBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 20))
                .foregroundColor(.tidexWarning)

            VStack(alignment: .leading, spacing: 2) {
                Text(localization.string("subscription.earlySupporter.title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Text(localization.string("subscription.earlySupporter.description"))
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
            Text(localization.string("subscription.currentPlan.sectionTitle"))
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
                            Text(localization.string("subscription.currentPlan.price"))
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
                                Text(localization.string("subscription.currentPlan.renews"))
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
        Text(isActive
             ? localization.string("subscription.status.active")
             : localization.string("subscription.status.inactive"))
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
            Text(localization.string("subscription.features.sectionTitle"))
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

                        Text(localization.string("subscription.features.lifetimeAccess"))
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
        let locale = localization.currentLocale
        switch viewModel.effectiveTier {
        case .free:
            return [
                AuthStrings.string("paywall.free.feature1", locale: locale),
                AuthStrings.string("paywall.free.feature2", locale: locale)
            ]
        case .pro:
            return [
                AuthStrings.string("paywall.pro.feature1", locale: locale),
                AuthStrings.string("paywall.pro.feature2", locale: locale),
                AuthStrings.string("paywall.pro.feature3", locale: locale),
                AuthStrings.string("paywall.pro.feature4", locale: locale)
            ]
        case .max:
            return [
                AuthStrings.string("paywall.max.feature1", locale: locale),
                AuthStrings.string("paywall.max.feature2", locale: locale),
                AuthStrings.string("paywall.max.feature3", locale: locale),
                AuthStrings.string("paywall.max.feature4", locale: locale),
                AuthStrings.string("paywall.max.feature5", locale: locale)
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
                        Text(localization.string("subscription.actions.manage"))
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
                        Text(viewModel.effectiveTier == .free
                             ? localization.string("subscription.actions.subscribe")
                             : localization.string("subscription.actions.upgrade"))
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
            Text(localization.string("paywall.restorePurchases"))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.tidexBlue)
        }
        .disabled(viewModel.isLoading)
    }

    // MARK: - Legal Links

    private var termsURL: URL {
        URL(string: "https://tidex.no/\(localization.currentLocale.rawValue)/terms")!
    }

    private var privacyURL: URL {
        URL(string: "https://tidex.no/\(localization.currentLocale.rawValue)/privacy")!
    }

    private var legalLinks: some View {
        HStack(spacing: 16) {
            Button {
                safariURL = termsURL
            } label: {
                Text(localization.string("paywall.termsOfUse"))
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextMuted)
            }

            Text("•")
                .foregroundColor(.tidexTextMuted)

            Button {
                safariURL = privacyURL
            } label: {
                Text(localization.string("paywall.privacyPolicy"))
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

                Text(localization.string("common.loading"))
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
    .environment(\.localization, LocalizationManager.shared)
}
