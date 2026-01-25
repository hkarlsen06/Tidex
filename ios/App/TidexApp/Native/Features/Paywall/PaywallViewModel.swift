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
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
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

    /// Current effective tier
    var currentTier: SubscriptionTier {
        entitlementService.effectiveTier
    }

    /// Whether the user already has an active subscription
    var hasActiveSubscription: Bool {
        currentTier != .free
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
              let yearly = storeKitManager.product(for: yearlyId) else {
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

        await storeKitManager.loadProducts()

        if storeKitManager.products.isEmpty {
            error = "Unable to load products. Please check your internet connection."
        }

        isLoading = false
    }

    /// Purchase a product
    /// - Parameter product: The Product to purchase
    /// - Returns: Whether purchase succeeded
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        error = nil

        do {
            let transaction = try await storeKitManager.purchase(product)

            if transaction != nil {
                // Purchase successful
                logger.info("Purchase succeeded for \(product.id)")
                purchaseSucceeded = true
                isPurchasing = false
                return true
            } else {
                // User cancelled or pending
                logger.info("Purchase was cancelled or is pending for \(product.id)")
                isPurchasing = false
                return false
            }
        } catch {
            logger.error("Purchase failed: \(error.localizedDescription)")
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
                error = "No purchases found to restore."
            }
        } catch {
            logger.error("Restore failed: \(error.localizedDescription)")
            self.error = "Failed to restore purchases. Please try again."
        }

        isLoading = false
    }

    /// Clear any error
    func clearError() {
        error = nil
    }
}
