import Foundation

// MARK: - Configuration

internal enum EntitlementConfig {
  /// How long server tier is valid offline (1 hour)
  internal static let serverTierTTL: TimeInterval = 1 * 3_600  // swiftlint:disable:this no_magic_numbers
}

// MARK: - Subscription Tier

/// User's subscription tier
/// Matches tier values from database `user_entitlements` view
internal enum SubscriptionTier: String, Codable, Comparable {
  case free
  case max
  case pro

  private static let proPriority: Int = 1
  private static let maxPriority: Int = 2

  internal var priority: Int {
    switch self {
    case .free:
      return 0

    case .max:
      return Self.maxPriority

    case .pro:
      return Self.proPriority
    }
  }

  internal static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.priority < rhs.priority
  }
}

// MARK: - Product IDs (StoreKit only)

/// App Store product identifiers for in-app subscriptions
internal enum ProductID: String, CaseIterable {
  case maxMonthly = "no.tidex.max"
  case maxYearly = "no.tidex.max.year"
  case proMonthly = "no.tidex.pro"
  case proYearly = "no.tidex.pro.year"

  /// The tier this product unlocks
  internal var tier: SubscriptionTier {
    switch self {
    case .maxMonthly, .maxYearly:
      return .max

    case .proMonthly, .proYearly:
      return .pro
    }
  }

  /// Whether this is a yearly subscription
  internal var isYearly: Bool {
    switch self {
    case .maxYearly, .proYearly:
      return true

    case .maxMonthly, .proMonthly:
      return false
    }
  }
}

/// App Store product identifiers for consumable IAPs
internal enum ConsumableProductID: String {
  case wageyBonus20 = "no.tidex.wagey.20"

  private static let wageyBonusCredits: Int = 20

  internal var credits: Int {
    switch self {
    case .wageyBonus20:
      return Self.wageyBonusCredits
    }
  }
}

// MARK: - Server Entitlement

/// Server entitlement from `user_entitlements` view via `get_my_entitlement()` RPC
/// Tier comes directly from the view, no client-side derivation needed
internal struct ServerEntitlement: Codable {
  internal enum CodingKeys: String, CodingKey {
    case userId = "user_id"
    case tier = "tier"
    case isEntitled = "is_entitled"
    case isGrandfathered = "is_grandfathered"
    case hasActiveSubscription = "has_active_subscription"
    case activeProvider = "active_provider"
    case activeProductId = "active_product_id"
    case subscriptionEndsAt = "subscription_ends_at"
  }

  internal let userId: String
  internal let tier: SubscriptionTier
  internal let isEntitled: Bool
  internal let isGrandfathered: Bool
  internal let hasActiveSubscription: Bool
  internal let activeProvider: String?
  internal let activeProductId: String?
  internal let subscriptionEndsAt: Date?
}

// MARK: - Paywall Config

/// Backend-controlled paywall offer metadata.
internal struct PaywallConfig: Codable, Equatable {
  internal enum CodingKeys: String, CodingKey {
    case freeTrialEnabled = "free_trial_enabled"
    case freeTrialDurationDays = "free_trial_duration_days"
    case freeTrialReminderDaysBeforeEnd = "free_trial_reminder_days_before_end"
  }

  private static let fallbackFreeTrialDurationDays: Int = 14
  private static let fallbackReminderDaysBeforeEnd: Int = 2
  private static let minimumTrialDays: Int = 1

  // swiftlint:disable:next redundant_type_annotation
  internal static let fallback: Self = Self(
    freeTrialEnabled: true,
    freeTrialDurationDays: fallbackFreeTrialDurationDays,
    freeTrialReminderDaysBeforeEnd: fallbackReminderDaysBeforeEnd
  )

  internal let freeTrialEnabled: Bool
  internal let freeTrialDurationDays: Int
  internal let freeTrialReminderDaysBeforeEnd: Int

  internal var normalized: Self {
    let durationDays: Int = max(freeTrialDurationDays, Self.minimumTrialDays)
    let reminderDays: Int = min(max(freeTrialReminderDaysBeforeEnd, Self.minimumTrialDays), durationDays)

    return Self(
      freeTrialEnabled: freeTrialEnabled,
      freeTrialDurationDays: durationDays,
      freeTrialReminderDaysBeforeEnd: reminderDays
    )
  }

  internal var hasFreeTrial: Bool {
    freeTrialEnabled && freeTrialDurationDays > 0
  }

  internal var reminderDay: Int {
    max(freeTrialDurationDays - freeTrialReminderDaysBeforeEnd, Self.minimumTrialDays)
  }

}

// MARK: - Errors

/// Errors that can occur during purchase flow
internal enum PurchaseError: Error, LocalizedError {
  case networkError(underlying: Error)
  case productNotFound
  case userNotConfigured
  case verificationFailed

  internal var errorDescription: String? {
    switch self {
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"

    case .productNotFound:
      return "Product not found"

    case .userNotConfigured:
      return "User not configured"

    case .verificationFailed:
      return "Purchase verification failed"
    }
  }
}
