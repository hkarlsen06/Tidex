import Combine
import Foundation
import StoreKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "PaywallViewModel")

// MARK: - Billing Period

/// Billing period selection for paywall
enum BillingPeriod: String, CaseIterable {
  case monthly
  case yearly

  var displayName: String {
    switch self {
    case .monthly: return String(localized: .paywallMonthly)
    case .yearly: return String(localized: .paywallYearly)
    }
  }
}

// MARK: - Paywall ViewModel

/// ViewModel for PaywallView
/// Handles product loading, billing period selection, and purchase flow
@MainActor
final class PaywallViewModel: ObservableObject {

  // MARK: - Published State

  @Published var billingPeriod: BillingPeriod = .monthly
  @Published private(set) var isLoading = false
  @Published private(set) var isPurchasing = false
  @Published private(set) var error: String?
  @Published private(set) var purchaseSucceeded = false
  @Published private(set) var paywallConfig = PaywallConfig.fallback

  // MARK: - Dependencies

  private let storeKitManager: StoreKitManager
  private let entitlementService: EntitlementService

  // MARK: - Initialization

  init(
    storeKitManager: StoreKitManager? = nil,
    entitlementService: EntitlementService? = nil
  ) {
    self.storeKitManager = storeKitManager ?? StoreKitManager.shared
    self.entitlementService = entitlementService ?? EntitlementService.shared
  }

  // MARK: - Computed Properties

  /// Whether products are loaded
  var hasProducts: Bool {
    !storeKitManager.products.isEmpty
  }

  /// Pro product for current billing period
  var proProduct: Product? {
    let productId: ProductID = billingPeriod == .yearly ? .proYearly : .proMonthly
    return storeKitManager.product(for: productId)
  }

  /// Max product for current billing period
  var maxProduct: Product? {
    let productId: ProductID = billingPeriod == .yearly ? .maxYearly : .maxMonthly
    return storeKitManager.product(for: productId)
  }

  /// Wagey consumable bonus product
  var bonusProduct: Product? {
    storeKitManager.consumableProduct(for: .wageyBonus20)
  }

  /// Current effective tier
  var currentTier: SubscriptionTier {
    entitlementService.effectiveTier
  }

  /// Whether the user already has an active subscription
  var hasActiveSubscription: Bool {
    currentTier != .free
  }

  var hasConfiguredTrial: Bool {
    paywallConfig.hasFreeTrial
  }

  var trialDurationDays: Int {
    paywallConfig.freeTrialDurationDays
  }

  var trialReminderDay: Int {
    paywallConfig.reminderDay
  }

  /// Calculate yearly savings percentage for a tier
  /// Returns nil if products aren't loaded
  func yearlySavingsPercent(for tier: SubscriptionTier) -> Int? {
    let monthlyId: ProductID
    let yearlyId: ProductID

    switch tier {
    case .pro:
      monthlyId = .proMonthly
      yearlyId = .proYearly

    case .max:
      monthlyId = .maxMonthly
      yearlyId = .maxYearly

    case .free:
      return nil
    }

    guard let monthly = storeKitManager.product(for: monthlyId),
      let yearly = storeKitManager.product(for: yearlyId)
    else {
      return nil
    }

    let yearlyEquivalent = monthly.price * 12
    let savings = yearlyEquivalent - yearly.price
    let savingsPercent = (savings / yearlyEquivalent) * 100

    // Convert Decimal to Double for rounding
    return Int((savingsPercent as NSDecimalNumber).doubleValue.rounded())
  }

  // MARK: - Actions

  /// Load products from App Store
  func loadProducts() async {
    isLoading = true
    error = nil

    await loadPaywallConfig()
    await storeKitManager.loadProducts()

    if storeKitManager.products.isEmpty {
      error = String(localized: .paywallErrorsLoadProductsFailed)
    }

    isLoading = false
  }

  private func loadPaywallConfig() async {
    do {
      let config: PaywallConfig =
        try await supabase
        .rpc("get_paywall_config")
        .single()
        .execute()
        .value

      paywallConfig = config.normalized
      logger.info(
        "Loaded paywall config: trialEnabled=\(config.freeTrialEnabled), durationDays=\(config.freeTrialDurationDays)"
      )
    } catch {
      paywallConfig = PaywallConfig.fallback
      logger.error("Failed to load paywall config: \(error.localizedDescription)")
    }
  }

  /// Purchase a product
  /// - Parameter product: The Product to purchase
  /// - Returns: Whether purchase succeeded
  @discardableResult
  func purchase(_ product: Product) async -> Bool {
    isPurchasing = true
    error = nil

    let tierBeforePurchase = currentTier
    logger.info(
      "Starting purchase: product=\(product.id), currentTier=\(tierBeforePurchase.rawValue), storeKitTier=\(self.storeKitManager.currentTier.rawValue)"
    )

    do {
      let transaction = try await storeKitManager.purchase(product)

      if transaction != nil {
        // Transaction succeeded - but verify entitlement was actually granted
        // Small delay to let StoreKit/EntitlementService sync
        try? await Task.sleep(for: .milliseconds(300))

        let tierAfterPurchase = entitlementService.effectiveTier
        logger.info(
          "Purchase completed for \(product.id): tierBefore=\(tierBeforePurchase.rawValue), tierAfter=\(tierAfterPurchase.rawValue)"
        )

        // Only mark as successful if tier actually changed (or was already at target tier)
        let targetTier = ProductID(rawValue: product.id)?.tier ?? .free
        if tierAfterPurchase >= targetTier || tierAfterPurchase > tierBeforePurchase {
          purchaseSucceeded = true
          isPurchasing = false
          Haptics.playSubscriptionSuccess()
          return true
        }
        // Transaction completed but entitlement not granted yet
        // This can happen in sandbox - don't auto-dismiss
        logger.warning(
          "Transaction completed but tier unchanged: expected \(targetTier.rawValue), got \(tierAfterPurchase.rawValue)"
        )
        isPurchasing = false
        return false
      }
      // User cancelled or pending
      logger.info("Purchase was cancelled or is pending for \(product.id)")
      isPurchasing = false
      return false
    } catch {
      logger.error("Purchase failed: \(error.localizedDescription)")
      self.error = error.localizedDescription
      isPurchasing = false
      return false
    }
  }

  /// Purchase Wagey bonus consumable
  @discardableResult
  func purchaseBonus() async -> Bool {
    guard let product = bonusProduct else { return false }

    isPurchasing = true
    error = nil

    do {
      let uploadSucceeded = try await storeKitManager.purchaseConsumable(product)
      if uploadSucceeded {
        purchaseSucceeded = true
      } else {
        logger.info("Bonus purchase did not complete")
      }
      isPurchasing = false
      return uploadSucceeded
    } catch {
      logger.error("Bonus purchase failed: \(error.localizedDescription)")
      self.error = error.localizedDescription
      isPurchasing = false
      return false
    }
  }

  /// Restore previous purchases
  func restorePurchases() async {
    isLoading = true
    error = nil

    do {
      try await storeKitManager.restorePurchases()

      if currentTier != .free {
        logger.info("Restore successful, tier: \(self.currentTier.rawValue)")
        purchaseSucceeded = true
      } else {
        logger.info("No purchases to restore")
        error = String(localized: .subscriptionRestoreNoPurchases)
      }
    } catch {
      logger.error("Restore failed: \(error.localizedDescription)")
      self.error = String(localized: .subscriptionErrorsRestoreFailed)
    }

    isLoading = false
  }

  /// Clear any error
  func clearError() {
    error = nil
  }
}
