import Foundation
import StoreKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SubscriptionSettingsViewModel")

/// View model for subscription settings
/// Manages subscription state display and actions (manage, upgrade)
@MainActor
final class SubscriptionSettingsViewModel: ObservableObject {

    // MARK: - Dependencies

    private let entitlementService: EntitlementService
    private let storeKitManager: StoreKitManager
    private let repository: EntitlementRepository

    // MARK: - Published State

    /// Current effective tier (max of StoreKit and server)
    @Published private(set) var effectiveTier: SubscriptionTier = .free

    /// Whether user has an active subscription
    @Published private(set) var hasActiveSubscription = false

    /// Whether user is grandfathered (early supporter)
    @Published private(set) var isGrandfathered = false

    /// Subscription renewal/expiry date
    @Published private(set) var subscriptionEndsAt: Date?

    /// Active subscription provider (apple, stripe)
    @Published private(set) var activeProvider: String?

    /// Active product ID for determining billing period
    @Published private(set) var activeProductId: String?

    /// Current product (for price display)
    @Published private(set) var currentProduct: Product?

    /// Loading state
    @Published private(set) var isLoading = false

    /// Whether to show the paywall
    @Published var showPaywall = false

    /// Error message
    @Published var errorMessage: String?

    // MARK: - Computed Properties

    /// Display name for the current tier
    var tierDisplayName: String {
        switch effectiveTier {
        case .free:
            return AuthStrings.string("paywall.tier.free", locale: LocalizationManager.shared.currentLocale)
        case .pro:
            return AuthStrings.string("paywall.tier.pro", locale: LocalizationManager.shared.currentLocale)
        case .max:
            return AuthStrings.string("paywall.tier.max", locale: LocalizationManager.shared.currentLocale)
        }
    }

    /// Whether this is a yearly subscription
    var isYearlySubscription: Bool {
        guard let productId = activeProductId else { return false }
        // Check both internal and Apple product IDs
        return productId.contains("year") || productId.contains(".year")
    }

    /// Billing period display text
    var billingPeriodText: String {
        let locale = LocalizationManager.shared.currentLocale
        return isYearlySubscription
            ? AuthStrings.string("paywall.perYear", locale: locale)
            : AuthStrings.string("paywall.perMonth", locale: locale)
    }

    /// Price display from current product
    var priceDisplayText: String? {
        currentProduct?.displayPrice
    }

    /// Whether the subscription is from Apple (vs Stripe web)
    var isAppleSubscription: Bool {
        activeProvider == "apple"
    }

    /// Formatted renewal date
    var formattedRenewalDate: String? {
        guard let date = subscriptionEndsAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Whether user can upgrade (is on free or wants to change plan)
    var canUpgrade: Bool {
        effectiveTier == .free || !hasActiveSubscription
    }

    /// Whether user has any premium access (subscription or grandfathered)
    var hasPremiumAccess: Bool {
        effectiveTier != .free
    }

    // MARK: - Initialization

    init(
        entitlementService: EntitlementService? = nil,
        storeKitManager: StoreKitManager? = nil,
        repository: EntitlementRepository? = nil
    ) {
        self.entitlementService = entitlementService ?? EntitlementService.shared
        self.storeKitManager = storeKitManager ?? StoreKitManager.shared
        self.repository = repository ?? EntitlementRepository.shared
    }

    // MARK: - Load Subscription Info

    /// Load subscription information from entitlement service and cache
    func loadSubscriptionInfo() async {
        isLoading = true
        errorMessage = nil

        // Get current user ID
        guard let userId = try? await supabase.auth.session.normalizedUserId else {
            logger.warning("No authenticated user for subscription settings")
            isLoading = false
            return
        }

        // Update from entitlement service (already loaded on app start)
        effectiveTier = entitlementService.effectiveTier

        // Load cached entitlement for additional details
        if let cached = repository.getCached(for: userId) {
            hasActiveSubscription = cached.hasActiveSubscription
            isGrandfathered = cached.isGrandfathered
            subscriptionEndsAt = cached.subscriptionEndsAt
            activeProvider = cached.activeProvider
            activeProductId = cached.activeProductId
            logger.info("Loaded cached subscription: tier=\(cached.tier.rawValue), provider=\(cached.activeProvider ?? "none")")
        } else {
            // Try to refresh from server if no cache
            do {
                try await entitlementService.refreshFromServer(userId: userId)
                effectiveTier = entitlementService.effectiveTier

                // Re-check cache after refresh
                if let cached = repository.getCached(for: userId) {
                    hasActiveSubscription = cached.hasActiveSubscription
                    isGrandfathered = cached.isGrandfathered
                    subscriptionEndsAt = cached.subscriptionEndsAt
                    activeProvider = cached.activeProvider
                    activeProductId = cached.activeProductId
                }
            } catch {
                logger.error("Failed to refresh entitlement: \(error.localizedDescription)")
            }
        }

        // Load products for price display
        await loadCurrentProduct()

        isLoading = false
    }

    /// Load the current subscription product for price display
    private func loadCurrentProduct() async {
        // Ensure products are loaded
        if storeKitManager.products.isEmpty {
            await storeKitManager.loadProducts()
        }

        // Find the current product based on active product ID
        if let productId = activeProductId,
           let matchingProductId = ProductID(rawValue: productId) {
            currentProduct = storeKitManager.product(for: matchingProductId)
        } else if hasActiveSubscription {
            // Fallback: determine product from tier and guess billing period
            let targetProductIds: [ProductID]
            switch effectiveTier {
            case .pro:
                targetProductIds = isYearlySubscription ? [.proYearly] : [.proMonthly]
            case .max:
                targetProductIds = isYearlySubscription ? [.maxYearly] : [.maxMonthly]
            case .free:
                targetProductIds = []
            }
            currentProduct = targetProductIds.compactMap { storeKitManager.product(for: $0) }.first
        }
    }

    // MARK: - Actions

    /// Open Apple's subscription management page
    func manageSubscription() {
        // iOS deep link to subscription management
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
            logger.info("Opened Apple subscription management")
        }
    }

    /// Show paywall for upgrade
    func showUpgradeOptions() {
        showPaywall = true
    }

    /// Restore purchases
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil

        do {
            try await storeKitManager.restorePurchases()

            // Reload subscription info after restore
            await loadSubscriptionInfo()

            logger.info("Purchases restored successfully")
        } catch {
            logger.error("Failed to restore purchases: \(error.localizedDescription)")
            errorMessage = AuthStrings.string("subscription.errors.restoreFailed", locale: LocalizationManager.shared.currentLocale)
        }

        isLoading = false
    }
}
