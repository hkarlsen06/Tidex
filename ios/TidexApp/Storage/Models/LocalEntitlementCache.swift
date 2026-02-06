import Foundation
import SwiftData

// MARK: - Local Entitlement Cache

/// SwiftData model for caching server entitlement with TTL
/// Used for offline-first tier enforcement
@Model
final class LocalEntitlementCache {
  // MARK: - Primary Key

  /// User ID (unique - one cache entry per user)
  @Attribute(.unique)
  var userId: String

  // MARK: - Entitlement Data

  /// Tier as raw string ("free", "pro", "max")
  /// Stored as string for SwiftData compatibility
  var tierRaw: String

  /// Whether user is entitled to premium features
  var isEntitled: Bool

  /// Whether user is grandfathered (pre-paywall user)
  var isGrandfathered: Bool

  /// Whether user has an active subscription
  var hasActiveSubscription: Bool

  /// Active subscription provider (e.g., "apple", "stripe")
  var activeProvider: String?

  /// Active subscription product ID
  var activeProductId: String?

  /// When the subscription ends (for display purposes)
  var subscriptionEndsAt: Date?

  // MARK: - TTL Metadata

  /// When this cache entry was last refreshed from server
  var checkedAt: Date

  /// When this cache entry expires (checkedAt + 48h TTL)
  var validUntil: Date

  // MARK: - Computed Properties

  /// Tier as typed enum
  var tier: SubscriptionTier {
    SubscriptionTier(rawValue: tierRaw) ?? .free
  }

  /// Whether the cache has expired and needs refresh
  var isExpired: Bool {
    Date() >= validUntil
  }

  // MARK: - Initialization

  /// Initialize from server entitlement response
  init(userId: String, entitlement: ServerEntitlement) {
    self.userId = userId
    self.tierRaw = entitlement.tier.rawValue
    self.isEntitled = entitlement.isEntitled
    self.isGrandfathered = entitlement.isGrandfathered
    self.hasActiveSubscription = entitlement.hasActiveSubscription
    self.activeProvider = entitlement.activeProvider
    self.activeProductId = entitlement.activeProductId
    self.subscriptionEndsAt = entitlement.subscriptionEndsAt
    self.checkedAt = Date()
    self.validUntil = Date().addingTimeInterval(EntitlementConfig.serverTierTTL)
  }

  /// Required empty initializer for SwiftData
  init() {
    self.userId = ""
    self.tierRaw = SubscriptionTier.free.rawValue
    self.isEntitled = false
    self.isGrandfathered = false
    self.hasActiveSubscription = false
    self.activeProvider = nil
    self.activeProductId = nil
    self.subscriptionEndsAt = nil
    self.checkedAt = Date()
    self.validUntil = Date()
  }
}

// MARK: - Update Extension

extension LocalEntitlementCache {
  /// Update cache from new server entitlement
  func update(from entitlement: ServerEntitlement) {
    self.tierRaw = entitlement.tier.rawValue
    self.isEntitled = entitlement.isEntitled
    self.isGrandfathered = entitlement.isGrandfathered
    self.hasActiveSubscription = entitlement.hasActiveSubscription
    self.activeProvider = entitlement.activeProvider
    self.activeProductId = entitlement.activeProductId
    self.subscriptionEndsAt = entitlement.subscriptionEndsAt
    self.checkedAt = Date()
    self.validUntil = Date().addingTimeInterval(EntitlementConfig.serverTierTTL)
  }
}
