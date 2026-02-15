import SwiftUI

// MARK: - Paywall View

/// Main paywall view showing subscription plans
/// Presented as a sheet when user needs to upgrade
struct PaywallView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel = PaywallViewModel()

  /// Optional context type about why the paywall is being shown
  /// Use this for localized context headers
  var contextType: PaywallContextType?

  /// Legacy: Optional pre-built context (for backward compatibility with previews)
  var context: PaywallContext?

  /// Computed context when contextType is provided
  private var localizedContext: PaywallContext? {
    if let contextType = contextType {
      return PaywallContext(type: contextType)
    }
    return context
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.lg) {
          // Context header (if provided)
          if let context = localizedContext {
            contextHeader(context)
          }

          // Billing toggle
          BillingToggle(
            selection: $viewModel.billingPeriod,
            yearlySavingsPercent: viewModel.yearlySavingsPercent(for: .pro)
          )
          .padding(.horizontal, Spacing.lg)

          // Plan cards
          VStack(spacing: Spacing.md) {
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
          .padding(.horizontal, Spacing.lg)

          if contextType == .wageyLimit {
            bonusAlternativeSection
              .padding(.horizontal, Spacing.lg)
          }

          // Error display
          if let error = viewModel.error {
            errorView(error)
              .padding(.horizontal, Spacing.lg)
          }

          // Restore purchases button
          Button(action: {
            Task { await viewModel.restorePurchases() }
          }) {
            Text(.paywallRestorePurchases)
              .font(.tidexLabel)
              .foregroundColor(.tidexBlue)
          }
          .disabled(viewModel.isLoading)
          .padding(.top, Spacing.xs)

          // Legal links
          legalLinks
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .padding(.top, Spacing.lg)
      }
      .background(Color.tidexBackground)
      .navigationTitle(String(localized: .paywallTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
              .font(.tidexBodyMedium)
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
    VStack(spacing: Spacing.sm) {
      Image(systemName: context.icon)
        .font(.system(size: 48))
        .foregroundColor(.tidexBlue)

      Text(context.title)
        .font(.tidexTitle2)
        .foregroundColor(.tidexTextPrimary)

      Text(context.message)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, Spacing.xl)
    .padding(.bottom, Spacing.xs)
  }

  @ViewBuilder
  private func errorView(_ error: String) -> some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundColor(.tidexError)

      Text(error)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexError)

      Spacer()

      Button(action: { viewModel.clearError() }) {
        Image(systemName: "xmark.circle.fill")
          .foregroundColor(.tidexTextMuted)
      }
    }
    .padding(Spacing.sm)
    .background(Color.tidexError.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
  }

  private var bonusAlternativeSection: some View {
    VStack(spacing: Spacing.md) {
      HStack(spacing: Spacing.sm) {
        Rectangle()
          .fill(Color.tidexBorderSubtle)
          .frame(height: 1)

        Text(String(localized: "paywall.or"))
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)

        Rectangle()
          .fill(Color.tidexBorderSubtle)
          .frame(height: 1)
      }

      bonusCard
    }
  }

  private var bonusCard: some View {
    let bonusProduct = viewModel.bonusProduct

    return VStack(alignment: .leading, spacing: Spacing.md) {
      HStack(spacing: Spacing.sm) {
        Image(systemName: "sparkles")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.tidexBlue)

        Text(bonusProduct?.displayName ?? String(localized: .paywallLoading))
          .font(.tidexTitle2)
          .foregroundColor(.tidexTextPrimary)

        Spacer()
      }

      if let productDescription = bonusProduct?.description, !productDescription.isEmpty {
        Text(productDescription)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Button(action: {
        Task {
          await viewModel.purchaseBonus()
        }
      }) {
        if viewModel.isPurchasing {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            .frame(maxWidth: .infinity)
        } else {
          if let price = bonusProduct?.displayPrice {
            Text(String(localized: .paywallBonusBuyFor(price)))
              .font(.tidexButton)
              .frame(maxWidth: .infinity)
          } else {
            Text(.paywallLoadingButton)
              .font(.tidexButton)
              .frame(maxWidth: .infinity)
          }
        }
      }
      .frame(height: 48)
      .foregroundColor(.white)
      .background(viewModel.bonusProduct != nil ? Color.tidexBlue : Color.tidexTextMuted)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      .disabled(viewModel.bonusProduct == nil || viewModel.isPurchasing)
    }
    .padding(Spacing.mlg)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
    .tidexCardShadow(cornerRadius: CornerRadius.xxl)
  }

  // swiftlint:disable force_unwrapping
  private var legalLinks: some View {
    HStack(spacing: Spacing.md) {
      Link(
        String(localized: .paywallTermsOfUse), destination: URL(string: "https://tidex.no/terms")!
      )
      .font(.tidexFootnote)
      .foregroundColor(.tidexTextMuted)

      Text("•")
        .foregroundColor(.tidexTextMuted)

      Link(
        String(localized: .paywallPrivacyPolicy),
        destination: URL(string: "https://tidex.no/privacy")!
      )
      .font(.tidexFootnote)
      .foregroundColor(.tidexTextMuted)
    }
  }
  // swiftlint:enable force_unwrapping

  private var loadingOverlay: some View {
    ZStack {
      Color.tidexBackground.opacity(0.8)

      VStack(spacing: Spacing.md) {
        ProgressView()
          .scaleEffect(1.2)

        Text(.paywallLoading)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
      }
    }
    .ignoresSafeArea()
  }
}

// MARK: - Paywall Context

/// Context for why the paywall is being shown
enum PaywallContextType {
  case monthLimit
  case upgrade
  case wageyLimit

  var icon: String {
    switch self {
    case .monthLimit: return "calendar.badge.exclamationmark"
    case .upgrade: return "crown.fill"
    case .wageyLimit: return "bubble.left.and.exclamationmark.bubble.right"
    }
  }

  var title: String {
    switch self {
    case .monthLimit: return String(localized: .paywallShiftLimitTitle)
    case .upgrade: return String(localized: .paywallUpgradeTitle)
    case .wageyLimit: return String(localized: .paywallWageyLimitTitle)
    }
  }

  var message: String {
    switch self {
    case .monthLimit: return String(localized: .paywallShiftLimitMessage)
    case .upgrade: return String(localized: .paywallUpgradeMessage)
    case .wageyLimit: return String(localized: .paywallWageyLimitMessage)
    }
  }
}

/// Context for why the paywall is being shown (localized)
struct PaywallContext {
  let icon: String
  let title: String
  let message: String

  init(type: PaywallContextType) {
    self.icon = type.icon
    self.title = type.title
    self.message = type.message
  }

  /// Month limit reached context (for backward compatibility with previews)
  static let monthLimit = PaywallContext(
    icon: "calendar.badge.exclamationmark",
    title: "Upgrade to Add More Months",
    message:
      "Free plan allows shifts in one month at a time. Upgrade to track shifts across multiple months."
  )

  /// Generic upgrade context (for backward compatibility with previews)
  static let upgrade = PaywallContext(
    icon: "crown.fill",
    title: "Unlock Premium Features",
    message: "Get unlimited months, advanced statistics, Wagey AI, and more."
  )

  /// Wagey limit context (for backward compatibility with previews)
  static let wageyLimit = PaywallContext(
    icon: "bubble.left.and.exclamationmark.bubble.right",
    title: "Message Limit Reached",
    message: "You've used all your messages this month. Upgrade to continue chatting with Wagey."
  )

  private init(icon: String, title: String, message: String) {
    self.icon = icon
    self.title = title
    self.message = message
  }
}

// MARK: - Preview

#Preview {
  PaywallView(context: .monthLimit)
}

#Preview("No Context") {
  PaywallView()
}
