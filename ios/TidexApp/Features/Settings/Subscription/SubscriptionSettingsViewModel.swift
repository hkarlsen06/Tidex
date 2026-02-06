import Foundation
import StoreKit
import SwiftUI
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

  /// Whether user has an active StoreKit subscription (independent of server cache)
  private var hasStoreKitSubscription: Bool {
    storeKitManager.currentTier != .free
  }

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

  /// Whether a restore operation is in progress (for contextual loading text)
  @Published private(set) var isRestoring = false

  /// Whether to show the paywall
  @Published var showPaywall = false

  /// Error message
  @Published var errorMessage: String?

  /// Success/info message (for restore feedback)
  @Published var successMessage: String?

  // MARK: - Computed Properties

  /// Display name for the current tier
  var tierDisplayName: String {
    switch effectiveTier {
    case .free:
      return String(localized: .paywallTierFree)
    case .pro:
      return String(localized: .paywallTierPro)
    case .max:
      return String(localized: .paywallTierMax)
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
    return isYearlySubscription
      ? String(localized: .paywallPerYear)
      : String(localized: .paywallPerMonth)
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
    guard let userId = await AuthSessionManager.shared.getUserIdIfAvailable() else {
      logger.warning("No authenticated user for subscription settings")
      isLoading = false
      return
    }

    // Update from entitlement service (already loaded on app start)
    effectiveTier = entitlementService.effectiveTier

    // Load cached entitlement for additional details
    if let cached = repository.getCached(for: userId) {
      // hasActiveSubscription = true if server cache says so OR StoreKit has active entitlement
      // This handles the case where StoreKit has an active subscription but server cache is stale
      hasActiveSubscription = cached.hasActiveSubscription || hasStoreKitSubscription
      isGrandfathered = cached.isGrandfathered
      subscriptionEndsAt = cached.subscriptionEndsAt
      activeProvider = cached.activeProvider ?? (hasStoreKitSubscription ? "apple" : nil)
      // Use cached product ID, or fall back to StoreKit's current product ID
      activeProductId = cached.activeProductId ?? storeKitManager.currentProductId
      logger.info(
        "Loaded cached subscription: tier=\(cached.tier.rawValue), provider=\(self.activeProvider ?? "none"), storeKit=\(self.hasStoreKitSubscription)"
      )
    } else {
      // No cache - try to refresh from server
      do {
        try await entitlementService.refreshFromServer(userId: userId)
        effectiveTier = entitlementService.effectiveTier

        // Re-check cache after refresh
        if let cached = repository.getCached(for: userId) {
          hasActiveSubscription = cached.hasActiveSubscription || hasStoreKitSubscription
          isGrandfathered = cached.isGrandfathered
          subscriptionEndsAt = cached.subscriptionEndsAt
          activeProvider = cached.activeProvider ?? (hasStoreKitSubscription ? "apple" : nil)
          activeProductId = cached.activeProductId ?? storeKitManager.currentProductId
        } else if hasStoreKitSubscription {
          // StoreKit has subscription but server doesn't - still show as active
          hasActiveSubscription = true
          activeProvider = "apple"
          activeProductId = storeKitManager.currentProductId
          logger.info("StoreKit subscription active but no server cache")
        }
      } catch {
        logger.error("Failed to refresh entitlement: \(error.localizedDescription)")
        // Even if server refresh fails, check StoreKit
        if hasStoreKitSubscription {
          hasActiveSubscription = true
          activeProvider = "apple"
          activeProductId = storeKitManager.currentProductId
          logger.info("Server refresh failed but StoreKit subscription active")
        }
      }
    }

    // Load products for price display
    await loadCurrentProduct()

    // Log final subscription state for debugging
    logger.info(
      "Subscription state loaded: tier=\(self.effectiveTier.rawValue), active=\(self.hasActiveSubscription), provider=\(self.activeProvider ?? "none"), productId=\(self.activeProductId ?? "none"), storeKitTier=\(self.storeKitManager.currentTier.rawValue)"
    )

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
      let matchingProductId = ProductID(rawValue: productId)
    {
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
    isRestoring = true
    errorMessage = nil
    successMessage = nil

    // Track StoreKit tier before restore (not effectiveTier which includes server cache)
    let storeKitTierBefore = storeKitManager.currentTier

    do {
      try await storeKitManager.restorePurchases()

      // Check StoreKit tier after restore (this is purely from Apple, not server)
      let storeKitTierAfter = storeKitManager.currentTier

      // Reload subscription info after restore
      await loadSubscriptionInfo()

      // Determine feedback based on what StoreKit actually found
      if storeKitTierAfter != .free && storeKitTierAfter != storeKitTierBefore {
        // StoreKit found a new subscription
        logger.info("Purchases restored from Apple, StoreKit tier: \(storeKitTierAfter.rawValue)")
        successMessage = String(localized: .subscriptionRestoreSuccess)
        Haptics.playSubscriptionSuccess()
      } else if storeKitTierAfter != .free {
        // StoreKit already had this subscription (re-synced)
        logger.info("Purchases synced, StoreKit tier unchanged: \(storeKitTierAfter.rawValue)")
        successMessage = String(localized: .subscriptionRestoreSuccess)
        Haptics.play(.success)
      } else {
        // No Apple purchases found in StoreKit
        logger.info("No Apple purchases to restore (StoreKit tier: free)")
        successMessage = String(localized: .subscriptionRestoreNoPurchases)
      }
    } catch {
      logger.error("Failed to restore purchases: \(error.localizedDescription)")
      errorMessage = String(localized: .subscriptionErrorsRestoreFailed)
      isLoading = false
    }

    isRestoring = false
  }
}
