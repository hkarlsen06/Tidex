import Foundation

// MARK: - Configuration

enum EntitlementConfig {
    /// How long server tier is valid offline (1 hour)
    static let serverTierTTL: TimeInterval = 1 * 3600
}

// MARK: - Subscription Tier

/// User's subscription tier
/// Matches tier values from database `user_entitlements` view
enum SubscriptionTier: String, Codable, Comparable {
    case free
    case pro
    case max

    var priority: Int {
        switch self {
        case .free: return 0
        case .pro: return 1
        case .max: return 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.priority < rhs.priority
    }
}

// MARK: - Product IDs (StoreKit only)

/// App Store product identifiers for in-app subscriptions
enum ProductID: String, CaseIterable {
    case proMonthly = "no.tidex.pro"
    case proYearly = "no.tidex.pro.year"
    case maxMonthly = "no.tidex.max"
    case maxYearly = "no.tidex.max.year"

    /// The tier this product unlocks
    var tier: SubscriptionTier {
        switch self {
        case .proMonthly, .proYearly:
            return .pro
        case .maxMonthly, .maxYearly:
            return .max
        }
    }

    /// Whether this is a yearly subscription
    var isYearly: Bool {
        switch self {
        case .proYearly, .maxYearly:
            return true
        case .proMonthly, .maxMonthly:
            return false
        }
    }
}

// MARK: - Server Entitlement

/// Server entitlement from `user_entitlements` view via `get_my_entitlement()` RPC
/// Tier comes directly from the view, no client-side derivation needed
struct ServerEntitlement: Codable {
    let userId: String
    let tier: SubscriptionTier
    let isEntitled: Bool
    let isGrandfathered: Bool
    let hasActiveSubscription: Bool
    let activeProvider: String?
    let activeProductId: String?
    let subscriptionEndsAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case tier
        case isEntitled = "is_entitled"
        case isGrandfathered = "is_grandfathered"
        case hasActiveSubscription = "has_active_subscription"
        case activeProvider = "active_provider"
        case activeProductId = "active_product_id"
        case subscriptionEndsAt = "subscription_ends_at"
    }
}

// MARK: - Errors

/// Errors that can occur during purchase flow
enum PurchaseError: Error, LocalizedError {
    case verificationFailed
    case productNotFound
    case networkError(underlying: Error)
    case userNotConfigured

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "Purchase verification failed"
        case .productNotFound:
            return "Product not found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .userNotConfigured:
            return "User not configured"
        }
    }
}
