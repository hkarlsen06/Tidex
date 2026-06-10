import Combine
import Foundation
import os.log
import Supabase

private let logger = Logger(subsystem: "com.tidex.app", category: "EntitlementService")

// MARK: - Entitlement Service

/// Service that fetches entitlement via RPC function, caches with TTL, and merges with StoreKit tier
/// Effective tier = max(storeKitTier, serverTierIfNotExpired)
@MainActor
final class EntitlementService: ObservableObject {
  static let shared = EntitlementService()

  // MARK: - Published State

  /// The effective tier (max of StoreKit and valid server tier)
  @Published private(set) var effectiveTier: SubscriptionTier = .free

  /// Whether the server tier cache has expired (need to refresh)
  @Published private(set) var serverTierExpired: Bool = false

  /// Whether currently loading from server
  @Published private(set) var isLoading: Bool = false

  /// Whether offline (last server fetch failed)
  @Published private(set) var isOffline: Bool = false

  // MARK: - Private State

  private let repository: EntitlementRepository
  private var cachedEntitlement: LocalEntitlementCache?
  private var userId: String?

  private init(repository: EntitlementRepository? = nil) {
    self.repository = repository ?? EntitlementRepository.shared
  }

  // MARK: - Server Refresh

  /// Refresh entitlement from server and update cache
  /// SECURITY: Uses RPC function that enforces auth.uid() server-side
  /// - Parameter userId: The user ID to refresh for
  /// - Throws: Error if server fetch fails
  func refreshFromServer(userId: String) async throws {
    self.userId = userId
    isLoading = true
    isOffline = false
    defer { isLoading = false }

    do {
      // SECURITY: Call RPC function instead of direct view query
      // The RPC function uses auth.uid() server-side, cannot be spoofed
      // .single() required because RETURNS TABLE returns an array by default
      let entitlement: ServerEntitlement =
        try await supabase
        .rpc("get_my_entitlement")
        .single()
        .execute()
        .value

      // Cache the entitlement
      try await repository.cache(entitlement, for: userId)
      cachedEntitlement = repository.getCached(for: userId)

      // Explicitly set expired state from cache
      serverTierExpired = cachedEntitlement?.isExpired ?? true

      updateEffectiveTier()
      logger.info("Refreshed entitlement from server: tier=\(entitlement.tier.rawValue)")
    } catch {
      isOffline = true
      logger.error("Failed to refresh entitlement: \(error.localizedDescription)")
      throw error
    }
  }

  // MARK: - Cache Loading

  /// Load entitlement from cache on app launch (fast, offline-safe)
  /// - Parameter userId: The user ID to load cache for
  func loadFromCache(userId: String) {
    self.userId = userId
    cachedEntitlement = repository.getCached(for: userId)

    // Explicitly derive expired state - never ambiguous
    serverTierExpired = cachedEntitlement?.isExpired ?? true

    if let cached = cachedEntitlement {
      logger.info(
        "Loaded cached entitlement: tier=\(cached.tier.rawValue), expired=\(cached.isExpired)")
    } else {
      logger.info("No cached entitlement found")
    }

    updateEffectiveTier()
  }

  // MARK: - Tier Computation

  /// Compute effective tier = max(storeKitTier, serverTier if not expired)
  /// Uses the current StoreKit tier from StoreKitManager
  func updateEffectiveTier() {
    updateEffectiveTier(withStoreKitTier: StoreKitManager.shared.currentTier)
  }

  /// Compute effective tier with an explicit StoreKit tier value.
  /// Called by StoreKitManager when tier changes to ensure synchronization.
  /// - Parameter storeKitTier: The current tier from StoreKit
  func updateEffectiveTier(withStoreKitTier storeKitTier: SubscriptionTier) {
    if let cached = cachedEntitlement, !cached.isExpired {
      // Server cache is valid - use max of StoreKit and server
      effectiveTier = max(storeKitTier, cached.tier)
      serverTierExpired = false
    } else {
      // Server cache expired or missing - only StoreKit counts
      effectiveTier = storeKitTier
      // Explicitly set - expired if we HAD a cache that expired
      serverTierExpired =
        cachedEntitlement?.isExpired ?? (cachedEntitlement == nil && userId != nil)
    }

    logger.debug(
      "Effective tier: \(self.effectiveTier.rawValue) (StoreKit=\(storeKitTier.rawValue), server=\(self.cachedEntitlement?.tier.rawValue ?? "none"), expired=\(self.serverTierExpired))"
    )
  }

  /// Called by StoreKitManager when StoreKit tier changes.
  /// This ensures EntitlementService always uses the freshest tier value.
  func handleStoreKitTierChange(_ newTier: SubscriptionTier) {
    updateEffectiveTier(withStoreKitTier: newTier)
  }

  // MARK: - Cache Management

  /// Clear cache on logout
  func clearCache() async {
    guard let userId else {
      return
    }
    try? await repository.clearCache(for: userId)
    cachedEntitlement = nil
    effectiveTier = .free
    serverTierExpired = false
    self.userId = nil
    logger.info("Cleared entitlement cache")
  }

  // MARK: - Verification State

  /// Check if user needs to verify subscription
  /// True when server TTL expired AND no StoreKit entitlement
  /// This means we can't prove they're entitled and need network access
  var needsVerification: Bool {
    serverTierExpired && StoreKitManager.shared.currentTier == .free
  }

  /// Whether the user has any active entitlement (server or StoreKit)
  var isEntitled: Bool {
    effectiveTier != .free
  }

  /// The cached server entitlement (may be expired)
  var serverEntitlement: LocalEntitlementCache? {
    cachedEntitlement
  }
}
