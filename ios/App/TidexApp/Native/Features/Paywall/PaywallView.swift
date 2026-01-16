import SwiftUI

// MARK: - Paywall View

/// Main paywall view showing subscription plans
/// Presented as a sheet when user needs to upgrade
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.localization) private var localization
    @StateObject private var viewModel = PaywallViewModel()

    /// Optional context about why the paywall is being shown
    var context: PaywallContext?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Context header (if provided)
                    if let context = context {
                        contextHeader(context)
                    }

                    // Billing toggle
                    BillingToggle(
                        selection: $viewModel.billingPeriod,
                        yearlySavingsPercent: viewModel.yearlySavingsPercent(for: .pro)
                    )
                    .padding(.horizontal, 24)

                    // Plan cards
                    VStack(spacing: 16) {
                        // Pro plan
                        PlanCard(
                            tier: .pro,
                            product: viewModel.proProduct,
                            isCurrentPlan: viewModel.currentTier == .pro,
                            isPurchasing: viewModel.isPurchasing,
                            onSubscribe: {
                                Task {
                                    if let product = viewModel.proProduct {
                                        await viewModel.purchase(product)
                                    }
                                }
                            }
                        )

                        // Max plan
                        PlanCard(
                            tier: .max,
                            product: viewModel.maxProduct,
                            isCurrentPlan: viewModel.currentTier == .max,
                            isPurchasing: viewModel.isPurchasing,
                            onSubscribe: {
                                Task {
                                    if let product = viewModel.maxProduct {
                                        await viewModel.purchase(product)
                                    }
                                }
                            }
                        )
                    }
                    .padding(.horizontal, 24)

                    // Error display
                    if let error = viewModel.error {
                        errorView(error)
                            .padding(.horizontal, 24)
                    }

                    // Restore purchases button
                    Button(action: {
                        Task { await viewModel.restorePurchases() }
                    }) {
                        Text("Restore Purchases")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.tidexBlue)
                    }
                    .disabled(viewModel.isLoading)
                    .padding(.top, 8)

                    // Legal links
                    legalLinks
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                }
                .padding(.top, 24)
            }
            .background(Color.tidexBackground)
            .navigationTitle("Choose a Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.tidexTextMuted)
                    }
                }
            }
        }
        .task {
            await viewModel.loadProducts()
        }
        .onChange(of: viewModel.purchaseSucceeded) { _, succeeded in
            if succeeded {
                // Dismiss after successful purchase
                dismiss()
            }
        }
        .overlay {
            if viewModel.isLoading && !viewModel.hasProducts {
                loadingOverlay
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func contextHeader(_ context: PaywallContext) -> some View {
        VStack(spacing: 12) {
            Image(systemName: context.icon)
                .font(.system(size: 48))
                .foregroundColor(.tidexBlue)

            Text(context.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.tidexTextPrimary)

            Text(context.message)
                .font(.system(size: 15))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.tidexError)

            Text(error)
                .font(.system(size: 14))
                .foregroundColor(.tidexError)

            Spacer()

            Button(action: { viewModel.clearError() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.tidexTextMuted)
            }
        }
        .padding(12)
        .background(Color.tidexError.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var legalLinks: some View {
        HStack(spacing: 16) {
            Link("Terms of Use", destination: URL(string: "https://tidex.no/terms")!)
                .font(.system(size: 13))
                .foregroundColor(.tidexTextMuted)

            Text("•")
                .foregroundColor(.tidexTextMuted)

            Link("Privacy Policy", destination: URL(string: "https://tidex.no/privacy")!)
                .font(.system(size: 13))
                .foregroundColor(.tidexTextMuted)
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.tidexBackground.opacity(0.8)

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)

                Text("Loading plans...")
                    .font(.system(size: 15))
                    .foregroundColor(.tidexTextSecondary)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Paywall Context

/// Context for why the paywall is being shown
struct PaywallContext {
    let icon: String
    let title: String
    let message: String

    /// Month limit reached context
    static let monthLimit = PaywallContext(
        icon: "calendar.badge.exclamationmark",
        title: "Upgrade to Add More Months",
        message: "Free plan allows shifts in one month at a time. Upgrade to track shifts across multiple months."
    )

    /// Generic upgrade context
    static let upgrade = PaywallContext(
        icon: "crown.fill",
        title: "Unlock Premium Features",
        message: "Get unlimited months, advanced statistics, Wagey AI, and more."
    )
}

// MARK: - Preview

#Preview {
    PaywallView(context: .monthLimit)
}

#Preview("No Context") {
    PaywallView()
}
