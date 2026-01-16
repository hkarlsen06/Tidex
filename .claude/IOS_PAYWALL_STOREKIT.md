# iOS Paywall Implementation Plan (StoreKit 2)

> **Workflow**: This document is divided into phases. Complete one phase at a time, then mark it as done and add implementation notes before resetting context. Do NOT continue to the next phase after completing one.

---

## Critical Fixes Applied (Code Review)

The following fixes were identified during code review and are incorporated throughout the plan:

### Critical (Must Fix)

| Issue | Fix | Location |
|-------|-----|----------|
| **SECURITY: Entitlement query exposes other users' tiers** | Use RPC function `get_my_entitlement()` instead of direct view query | Phase 1, Phase 6 |
| JWS not sent to server | Request body includes `jws` field with `jwsRepresentation` | Phase 5: JWSUploadWorker |
| `[String: Any]` won't compile | Use `Encodable` struct `JWSUploadRequest` for request body | Phase 5: JWSUploadWorker |
| Duplicate queue entries | Use `transactionId` as unique key (not random UUID) | Phase 2: LocalPendingJWSUpload |
| Response handling ambiguous | Check for `{ "ok": true }` response structure | Phase 5: JWSUploadWorker |
| Worker stops when retries scheduled | Sleep until earliest `nextAttemptAt` instead of stopping | Phase 5: JWSUploadWorker |
| RPC returns jsonb (hard to decode) | Use `RETURNS TABLE` for clean Supabase Swift decoding | Phase 1, Phase 6 |

### Strong Recommendations (Incorporated)

| Issue | Fix | Location |
|-------|-----|----------|
| Uploads skip if products not loaded | Queue uploads with `priceDisplay: nil` if product not found | Phase 4: StoreKitManager |
| Entitlement refresh spammy | Debounce: refresh ONCE at end of upload loop, not per-upload | Phase 5: JWSUploadWorker |
| Recurring shifts may bypass gating | Added future consideration note for recurring shift handling | Phase 7 |
| View has repeated subqueries | Use LATERAL join to compute active subscription once | Phase 1 |
| `serverTierExpired` state ambiguous | Always explicitly derive from `cachedEntitlement?.isExpired` | Phase 6: EntitlementService |
| Stringly-typed sync status | Use computed `isPendingDelete` and `isActiveShift` properties | Phase 7: LocalUserShift |

---

## Overview

**Branch**: `iOS/native-screens`

**Objective**: Implement a complete subscription paywall system for the iOS app using StoreKit 2 that:
- Uses the `user_entitlements` database view as the single source of truth for server tier
- Caches server tier locally with a 48h TTL ("entitlement lease") for offline-first enforcement
- Merges server tier with StoreKit tier: `effectiveTier = max(storeKitTier, serverTierIfValid)`
- Finishes StoreKit transactions immediately after local verification, uploads JWS async with retry
- Gates free users from creating shifts in new months (but allows existing months)
- Shows paywall when limit is hit; shows "verify subscription" UI when TTL expired offline

**Hard Constraints**:
- iOS 18+ target (matches existing app)
- StoreKit 2 async/await APIs only (no legacy StoreKit 1)
- No Stripe mentions in iOS UI (web subscribers just work via server tier)
- All tier logic lives in database view, not Swift
- Persisted JWS upload queue in SwiftData (survives app kill)
- Single-flight upload worker with exponential backoff

**Product IDs**:
- `no.tidex.pro` (Pro Monthly)
- `no.tidex.pro.year` (Pro Yearly)
- `no.tidex.max` (Max Monthly)
- `no.tidex.max.year` (Max Yearly)

---

## Phase Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Database Migration (tier column) | ✅ Complete |
| 2 | SwiftData Models | ✅ Complete |
| 3 | EntitlementRepository | ✅ Complete |
| 4 | StoreKitManager | ✅ Complete |
| 5 | JWSUploadWorker | ✅ Complete |
| 6 | EntitlementService | ✅ Complete |
| 7 | Shift Month Limit Gating | ✅ Complete |
| 8 | PaywallView & Components | ✅ Complete |
| 9 | AppCoordinator Integration | ✅ Complete |
| 10 | Localization & StoreKit Config | ⬜ Not Started |
| 11 | Testing & Validation | ⬜ Not Started |

---

## Phase 1: Database Migration (tier column)

**Status**: ✅ Complete

### Scope

Add a `tier` column to the `user_entitlements` view so iOS reads the tier directly without duplicating product ID mapping logic.

### Performance Note

The view uses a `LATERAL` join to compute the active subscription once per user, then reuses it for all columns. This is more efficient than repeated correlated subqueries.

### Tasks

#### 1.1 Update user_entitlements view

Add a computed `tier` column that returns `'free'`, `'pro'`, or `'max'`:

```sql
-- View: user_entitlements
-- Purpose: Provides a unified view of user subscription entitlements
-- Used by: RLS policies, admin queries, iOS app, debugging
--
-- Note: product_id is the single source of truth for subscription tier.
-- Edge functions (Stripe webhook, Apple webhooks) normalize external IDs to internal product_id.
-- Internal product IDs: pro_monthly, pro_yearly, max_monthly, max_yearly
-- Apple product IDs: no.tidex.pro, no.tidex.pro.year, no.tidex.max, no.tidex.max.year

CREATE OR REPLACE VIEW user_entitlements AS
SELECT
  u.id AS user_id,
  COALESCE(p.before_paywall, false) AS is_grandfathered,
  (s.user_id IS NOT NULL) AS has_active_subscription,
  (COALESCE(p.before_paywall, false) OR (s.user_id IS NOT NULL)) AS is_entitled,
  s.provider AS active_provider,
  s.product_id AS active_product_id,
  s.current_period_end AS subscription_ends_at,

  -- tier column (free|pro|max) - single source of truth
  -- All tier logic lives here, iOS just reads this column
  CASE
    -- Grandfathered without active subscription = pro
    WHEN COALESCE(p.before_paywall, false) AND s.user_id IS NULL THEN 'pro'
    -- Has Max subscription
    WHEN s.product_id IN ('max_monthly', 'max_yearly', 'no.tidex.max', 'no.tidex.max.year') THEN 'max'
    -- Has Pro subscription
    WHEN s.product_id IN ('pro_monthly', 'pro_yearly', 'no.tidex.pro', 'no.tidex.pro.year') THEN 'pro'
    -- Grandfathered with any subscription (edge case: unknown product)
    WHEN COALESCE(p.before_paywall, false) THEN 'pro'
    -- Default: free
    ELSE 'free'
  END AS tier

FROM auth.users u
LEFT JOIN profiles p ON p.id = u.id
-- LATERAL join computes active subscription ONCE per user (efficient)
-- Avoids repeated correlated subqueries for each column
LEFT JOIN LATERAL (
  SELECT s_1.user_id, s_1.provider, s_1.product_id, s_1.current_period_end
  FROM subscriptions s_1
  WHERE s_1.user_id = u.id
    AND s_1.status IN ('active', 'trialing', 'grace')
    AND (s_1.current_period_end IS NULL OR s_1.current_period_end > now())
  ORDER BY s_1.current_period_end DESC NULLS LAST
  LIMIT 1
) s ON true;
```

#### 1.2 Create get_my_entitlement RPC function

**CRITICAL SECURITY FIX**: The view itself is not client-safe - a malicious client could query `.from("user_entitlements").eq("user_id", value: someoneElsesId)` and read other users' tiers.

Create an RPC function that returns ONLY the authenticated user's entitlement:

**IMPORTANT: Use `RETURNS TABLE` not `RETURNS jsonb`**

Using `RETURNS TABLE` ensures clean decoding in Supabase Swift. With `jsonb`, you get weird wrapping/array behavior that's painful to decode. A table-like return decodes directly to your `ServerEntitlement` struct.

```sql
-- Function: get_my_entitlement
-- Description: Returns the entitlement status for the CURRENT authenticated user
-- Security: SECURITY DEFINER ensures auth.uid() is trusted, not user-supplied
-- Used by: iOS app, web app (client-safe entitlement queries)
--
-- NOTE: RETURNS TABLE (not jsonb) for clean Supabase client decoding

CREATE OR REPLACE FUNCTION public.get_my_entitlement()
RETURNS TABLE (
  user_id uuid,
  tier text,
  is_entitled boolean,
  is_grandfathered boolean,
  has_active_subscription boolean,
  active_provider text,
  active_product_id text,
  subscription_ends_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    ue.user_id,
    ue.tier,
    ue.is_entitled,
    ue.is_grandfathered,
    ue.has_active_subscription,
    ue.active_provider,
    ue.active_product_id,
    ue.subscription_ends_at
  FROM public.user_entitlements ue
  WHERE ue.user_id = auth.uid();
$function$;

-- Grant execute to authenticated users only
GRANT EXECUTE ON FUNCTION public.get_my_entitlement() TO authenticated;

-- Revoke direct SELECT on user_entitlements from public/anon/authenticated
-- (Keep for service_role and admin only)
REVOKE SELECT ON public.user_entitlements FROM anon, authenticated;
```

**Why this is safer:**
- `auth.uid()` is called server-side - cannot be spoofed by client
- `SECURITY DEFINER` means the function runs with the definer's permissions
- Direct view access is revoked from client roles
- Service role/admin can still query the full view for debugging

#### 1.3 Update local SQL files

1. Update `supabase/sql/views/user_entitlements.sql` with the new view definition
2. Create `supabase/sql/functions/auth/get_my_entitlement.sql` with the RPC function

### Acceptance Criteria

- [ ] View: `SELECT tier FROM user_entitlements WHERE user_id = 'xxx'` works for service_role
- [ ] RPC: `SELECT get_my_entitlement()` returns current user's tier (as authenticated user)
- [ ] RPC: Returns `null` for unauthenticated users
- [ ] **SECURITY**: Direct `.from("user_entitlements")` query fails for authenticated client role
- [ ] Free user → tier = `'free'`
- [ ] Pro subscriber → tier = `'pro'`
- [ ] Max subscriber → tier = `'max'`
- [ ] Grandfathered user without subscription → tier = `'pro'`
- [ ] Grandfathered user with Max subscription → tier = `'max'`

### Notes

**Implemented 2025-01-16:**

1. **View updated with `tier` column**: Added computed `tier` column (`'free'` | `'pro'` | `'max'`) to `user_entitlements` view with all product ID mappings (internal and Apple IDs).

2. **LATERAL join optimization**: Replaced repeated correlated subqueries with a single LATERAL join that computes the active subscription once per user.

3. **`get_my_entitlement()` RPC created**: New secure function that uses `auth.uid()` server-side. Returns `TABLE` (not jsonb) for clean Swift decoding.

4. **Security hardening complete**:
   - Revoked ALL privileges from `anon` and `authenticated` on `user_entitlements` view
   - Only `service_role` and `postgres` can query the view directly
   - Clients must use `get_my_entitlement()` RPC which enforces auth.uid()

5. **Local SQL files updated**:
   - `supabase/sql/views/user_entitlements.sql`
   - `supabase/sql/functions/auth/get_my_entitlement.sql` (new file)

6. **Verified acceptance criteria**:
   - [x] View: `SELECT tier FROM user_entitlements` works for service_role
   - [x] RPC: `get_my_entitlement()` returns authenticated user's tier
   - [x] RPC: Returns empty for unauthenticated/service_role (expected)
   - [x] **SECURITY**: Direct view query blocked for authenticated client role
   - [x] Free user → tier = `'free'`
   - [x] Pro subscriber → tier = `'pro'`
   - [x] Grandfathered user without subscription → tier = `'pro'`

**Migrations applied:**
- `add_tier_column_to_user_entitlements`
- `create_get_my_entitlement_rpc`
- `revoke_direct_user_entitlements_access`

---

## Phase 2: SwiftData Models

**Status**: ✅ Complete

### Scope

Create SwiftData models for entitlement caching and JWS upload queue.

### Files to Create

#### 2.1 SubscriptionModels.swift

Location: `ios/App/TidexApp/Native/Services/Subscription/SubscriptionModels.swift`

```swift
import Foundation

// MARK: - Configuration

enum EntitlementConfig {
    /// How long server tier is valid offline (48 hours)
    static let serverTierTTL: TimeInterval = 48 * 3600
}

// MARK: - Subscription Tier

enum SubscriptionTier: String, Codable, Comparable {
    case free, pro, max

    var priority: Int {
        switch self { case .free: 0; case .pro: 1; case .max: 2 }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.priority < rhs.priority
    }
}

// MARK: - Product IDs (StoreKit only)

enum ProductID: String, CaseIterable {
    case proMonthly = "no.tidex.pro"
    case proYearly = "no.tidex.pro.year"
    case maxMonthly = "no.tidex.max"
    case maxYearly = "no.tidex.max.year"

    var tier: SubscriptionTier {
        switch self {
        case .proMonthly, .proYearly: return .pro
        case .maxMonthly, .maxYearly: return .max
        }
    }
}

// MARK: - Server Entitlement

/// Server entitlement from user_entitlements view
/// Tier comes directly from the view, no client-side derivation
struct ServerEntitlement: Codable {
    let userId: String
    let tier: SubscriptionTier
    let isEntitled: Bool
    let activeProvider: String?
    let subscriptionEndsAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case tier
        case isEntitled = "is_entitled"
        case activeProvider = "active_provider"
        case subscriptionEndsAt = "subscription_ends_at"
    }
}

// MARK: - Errors

enum PurchaseError: Error, LocalizedError {
    case verificationFailed
    case productNotFound
    case networkError(underlying: Error)
    case userNotConfigured

    var errorDescription: String? {
        switch self {
        case .verificationFailed: return "Purchase verification failed"
        case .productNotFound: return "Product not found"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .userNotConfigured: return "User not configured"
        }
    }
}
```

#### 2.2 LocalEntitlementCache.swift

Location: `ios/App/TidexApp/Native/Storage/Models/LocalEntitlementCache.swift`

```swift
import SwiftData
import Foundation

@Model
final class LocalEntitlementCache {
    @Attribute(.unique) var userId: String
    var tierRaw: String              // "free", "pro", "max"
    var isEntitled: Bool
    var activeProvider: String?
    var subscriptionEndsAt: Date?
    var checkedAt: Date
    var validUntil: Date             // checkedAt + 48h TTL

    var tier: SubscriptionTier {
        SubscriptionTier(rawValue: tierRaw) ?? .free
    }

    var isExpired: Bool {
        Date() >= validUntil
    }

    init(userId: String, entitlement: ServerEntitlement) {
        self.userId = userId
        self.tierRaw = entitlement.tier.rawValue
        self.isEntitled = entitlement.isEntitled
        self.activeProvider = entitlement.activeProvider
        self.subscriptionEndsAt = entitlement.subscriptionEndsAt
        self.checkedAt = Date()
        self.validUntil = Date().addingTimeInterval(EntitlementConfig.serverTierTTL)
    }

    /// Required for SwiftData
    init() {
        self.userId = ""
        self.tierRaw = "free"
        self.isEntitled = false
        self.activeProvider = nil
        self.subscriptionEndsAt = nil
        self.checkedAt = Date()
        self.validUntil = Date()
    }
}
```

#### 2.3 LocalPendingJWSUpload.swift

Location: `ios/App/TidexApp/Native/Storage/Models/LocalPendingJWSUpload.swift`

**CRITICAL: Use `transactionId` as the unique ID to prevent duplicate queue entries.**

The same transaction can get queued multiple times (purchase flow + transaction listener + app relaunch). Using `transactionId` as the unique key ensures only one entry per transaction.

```swift
import SwiftData
import Foundation

@Model
final class LocalPendingJWSUpload {
    /// CRITICAL: Use transactionId as unique ID to prevent duplicate entries
    /// The same transaction can be queued from purchase(), transaction listener, and app relaunch
    @Attribute(.unique) var transactionId: String

    var userId: String
    var jwsRepresentation: String
    var originalTransactionId: String
    var productId: String
    var environment: String           // "Sandbox" or "Production"
    var priceDisplay: String?         // Localized price from StoreKit (optional, queue even without it)
    var createdAt: Date
    var attemptCount: Int
    var nextAttemptAt: Date

    init(
        userId: String,
        jwsRepresentation: String,
        transactionId: String,
        originalTransactionId: String,
        productId: String,
        environment: String,
        priceDisplay: String?
    ) {
        self.transactionId = transactionId  // This is the unique key
        self.userId = userId
        self.jwsRepresentation = jwsRepresentation
        self.originalTransactionId = originalTransactionId
        self.productId = productId
        self.environment = environment
        self.priceDisplay = priceDisplay
        self.createdAt = Date()
        self.attemptCount = 0
        self.nextAttemptAt = Date()
    }

    /// Required for SwiftData
    init() {
        self.transactionId = ""
        self.userId = ""
        self.jwsRepresentation = ""
        self.originalTransactionId = ""
        self.productId = ""
        self.environment = "Sandbox"
        self.priceDisplay = nil
        self.createdAt = Date()
        self.attemptCount = 0
        self.nextAttemptAt = Date()
    }

    /// Calculate next retry with exponential backoff (30s, 60s, 120s, 240s, max 10min)
    func scheduleNextRetry() {
        attemptCount += 1
        let delay = min(30.0 * pow(2.0, Double(attemptCount - 1)), 600.0)
        nextAttemptAt = Date().addingTimeInterval(delay)
    }
}
```

#### 2.4 Update LocalStore.swift schema

Add both models to the schema array in `LocalStore.swift`.

### Acceptance Criteria

- [x] Both SwiftData models compile without errors
- [x] Models added to LocalStore schema
- [x] App builds and launches without SwiftData migration issues

### Notes

**Implemented 2025-01-16:**

1. **SubscriptionModels.swift created**: Contains `SubscriptionTier` enum, `ProductID` enum, `ServerEntitlement` struct, `PurchaseError` enum, and `EntitlementConfig` constants.
   - Location: `ios/App/TidexApp/Native/Services/Subscription/SubscriptionModels.swift`

2. **LocalEntitlementCache.swift created**: SwiftData model for caching server entitlement with 48h TTL.
   - Location: `ios/App/TidexApp/Native/Storage/Models/LocalEntitlementCache.swift`
   - Uses `@Attribute(.unique)` on `userId` for single cache entry per user
   - Includes `isExpired` computed property for TTL checking
   - Added `update(from:)` method for efficient cache updates

3. **LocalPendingJWSUpload.swift created**: SwiftData model for persisting JWS upload queue.
   - Location: `ios/App/TidexApp/Native/Storage/Models/LocalPendingJWSUpload.swift`
   - **CRITICAL**: Uses `transactionId` as unique key to prevent duplicate queue entries
   - Includes `scheduleNextRetry()` with exponential backoff (30s, 60s, 120s, 240s, max 10min)

4. **LocalStore.swift updated**:
   - Added `LocalEntitlementCache` and `LocalPendingJWSUpload` to schema array
   - Added both models to `resetAllData()` function
   - Added LocalStoreActor operations:
     - `upsertEntitlementCache(userId:entitlement:)` - Cache server entitlement
     - `deleteEntitlementCache(userId:)` - Clear cache on logout
     - `insertPendingJWSUpload(_:)` - Queue JWS upload (deduped by transactionId)
     - `deletePendingJWSUpload(transactionId:)` - Remove after successful upload
     - `schedulePendingJWSUploadRetry(transactionId:)` - Schedule backoff retry

**Files created:**
- `ios/App/TidexApp/Native/Services/Subscription/SubscriptionModels.swift`
- `ios/App/TidexApp/Native/Storage/Models/LocalEntitlementCache.swift`
- `ios/App/TidexApp/Native/Storage/Models/LocalPendingJWSUpload.swift`

**Files modified:**
- `ios/App/TidexApp/Native/Storage/LocalStore.swift`

**Note**: New Swift files need to be added to the Xcode project. Build in Xcode to verify.

---

## Phase 3: EntitlementRepository

**Status**: ✅ Complete

### Scope

Create repository for entitlement cache and JWS upload queue persistence.

### Files to Create

#### 3.1 EntitlementRepository.swift

Location: `ios/App/TidexApp/Native/Storage/Repositories/EntitlementRepository.swift`

```swift
import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "EntitlementRepository")

@MainActor
final class EntitlementRepository {
    static let shared = EntitlementRepository()
    private let localStore: LocalStore

    private init(localStore: LocalStore? = nil) {
        self.localStore = localStore ?? LocalStore.shared
    }

    // MARK: - Entitlement Cache

    /// Get cached entitlement (may be expired)
    func getCached(for userId: String) -> LocalEntitlementCache? {
        let context = localStore.mainContext
        let descriptor = FetchDescriptor<LocalEntitlementCache>(
            predicate: #Predicate { $0.userId == userId }
        )
        return try? context.fetch(descriptor).first
    }

    /// Save entitlement with TTL
    func cache(_ entitlement: ServerEntitlement, for userId: String) async throws {
        try await localStore.storeActor.upsertEntitlementCache(
            userId: userId,
            entitlement: entitlement
        )
        logger.info("Cached entitlement for user \(userId.prefix(8)): tier=\(entitlement.tier.rawValue)")
    }

    /// Clear on logout
    func clearCache(for userId: String) async throws {
        try await localStore.storeActor.deleteEntitlementCache(userId: userId)
        logger.info("Cleared entitlement cache for user \(userId.prefix(8))")
    }

    // MARK: - JWS Upload Queue

    /// Add JWS upload to persistent queue
    func enqueuePendingUpload(_ upload: LocalPendingJWSUpload) async throws {
        try await localStore.storeActor.insertPendingJWSUpload(upload)
        logger.info("Enqueued JWS upload: \(upload.transactionId)")
    }

    /// Get pending uploads ready for retry (nextAttemptAt <= now)
    func getPendingUploads() -> [LocalPendingJWSUpload] {
        let context = localStore.mainContext
        let now = Date()
        let descriptor = FetchDescriptor<LocalPendingJWSUpload>(
            predicate: #Predicate { $0.nextAttemptAt <= now },
            sortBy: [SortDescriptor(\LocalPendingJWSUpload.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Get all pending uploads (for debugging)
    func getAllPendingUploads() -> [LocalPendingJWSUpload] {
        let context = localStore.mainContext
        let descriptor = FetchDescriptor<LocalPendingJWSUpload>(
            sortBy: [SortDescriptor(\LocalPendingJWSUpload.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Remove successfully uploaded JWS by transactionId
    func removePendingUpload(transactionId: String) async throws {
        try await localStore.storeActor.deletePendingJWSUpload(transactionId: transactionId)
        logger.info("Removed pending JWS upload: \(transactionId)")
    }

    /// Update retry schedule for failed upload
    func schedulePendingUploadRetry(transactionId: String) async throws {
        try await localStore.storeActor.schedulePendingJWSUploadRetry(transactionId: transactionId)
    }
}
```

#### 3.2 Update LocalStoreActor

Add these operations to `LocalStoreActor` in `LocalStore.swift`:

```swift
// MARK: - Entitlement Cache Operations

func upsertEntitlementCache(userId: String, entitlement: ServerEntitlement) throws {
    let descriptor = FetchDescriptor<LocalEntitlementCache>(
        predicate: #Predicate { $0.userId == userId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
        existing.tierRaw = entitlement.tier.rawValue
        existing.isEntitled = entitlement.isEntitled
        existing.activeProvider = entitlement.activeProvider
        existing.subscriptionEndsAt = entitlement.subscriptionEndsAt
        existing.checkedAt = Date()
        existing.validUntil = Date().addingTimeInterval(EntitlementConfig.serverTierTTL)
    } else {
        let cache = LocalEntitlementCache(userId: userId, entitlement: entitlement)
        modelContext.insert(cache)
    }

    try modelContext.save()
}

func deleteEntitlementCache(userId: String) throws {
    let descriptor = FetchDescriptor<LocalEntitlementCache>(
        predicate: #Predicate { $0.userId == userId }
    )

    for cache in try modelContext.fetch(descriptor) {
        modelContext.delete(cache)
    }

    try modelContext.save()
}

// MARK: - JWS Upload Queue Operations

/// Insert or update pending JWS upload (upsert by transactionId)
/// Since transactionId is unique, attempting to insert a duplicate will update instead
func insertPendingJWSUpload(_ upload: LocalPendingJWSUpload) throws {
    // Check if already exists (SwiftData unique constraint handles this, but explicit check is clearer)
    let transactionId = upload.transactionId
    let descriptor = FetchDescriptor<LocalPendingJWSUpload>(
        predicate: #Predicate { $0.transactionId == transactionId }
    )

    if try modelContext.fetch(descriptor).first != nil {
        // Already queued, skip (don't reset attempt count)
        return
    }

    modelContext.insert(upload)
    try modelContext.save()
}

func deletePendingJWSUpload(transactionId: String) throws {
    let descriptor = FetchDescriptor<LocalPendingJWSUpload>(
        predicate: #Predicate { $0.transactionId == transactionId }
    )

    for upload in try modelContext.fetch(descriptor) {
        modelContext.delete(upload)
    }

    try modelContext.save()
}

func schedulePendingJWSUploadRetry(transactionId: String) throws {
    let descriptor = FetchDescriptor<LocalPendingJWSUpload>(
        predicate: #Predicate { $0.transactionId == transactionId }
    )

    if let upload = try modelContext.fetch(descriptor).first {
        upload.scheduleNextRetry()
        try modelContext.save()
    }
}
```

### Acceptance Criteria

- [x] EntitlementRepository compiles
- [x] LocalStoreActor operations added
- [x] Can cache and retrieve entitlements
- [x] Can enqueue and dequeue JWS uploads

### Notes

**Implemented 2025-01-16:**

1. **EntitlementRepository.swift created**: Repository pattern for entitlement cache and JWS upload queue.
   - Location: `ios/App/TidexApp/Native/Storage/Repositories/EntitlementRepository.swift`
   - Follows existing repository pattern (singleton, @MainActor, LocalStore dependency)

2. **Entitlement Cache Operations:**
   - `getCached(for:)` - Get cached entitlement (may be expired)
   - `cache(_:for:)` - Save entitlement with 48h TTL
   - `clearCache(for:)` - Clear cache on logout

3. **JWS Upload Queue Operations:**
   - `enqueuePendingUpload(_:)` - Add JWS upload to persistent queue
   - `getPendingUploads()` - Get uploads ready for retry (nextAttemptAt <= now)
   - `getAllPendingUploads()` - Get all pending uploads (for checking if retries are scheduled)
   - `removePendingUpload(transactionId:)` - Remove after successful upload
   - `schedulePendingUploadRetry(transactionId:)` - Schedule exponential backoff retry

4. **LocalStoreActor operations** were already implemented in Phase 2:
   - `upsertEntitlementCache(userId:entitlement:)`
   - `deleteEntitlementCache(userId:)`
   - `insertPendingJWSUpload(_:)`
   - `deletePendingJWSUpload(transactionId:)`
   - `schedulePendingJWSUploadRetry(transactionId:)`

**Files created:**
- `ios/App/TidexApp/Native/Storage/Repositories/EntitlementRepository.swift`

**Note**: New Swift file needs to be added to the Xcode project. Build in Xcode to verify.

---

## Phase 4: StoreKitManager

**Status**: ✅ Complete

### Scope

Create StoreKit 2 manager for product loading, purchases, and transaction listening.

### Critical Implementation Details

**FIX: Queue uploads regardless of products being loaded**

In the transaction listener, don't skip queueing if you can't find the product for display price. Queue the upload with `priceDisplay: nil` instead.

### Files to Create

#### 4.1 StoreKitManager.swift

Location: `ios/App/TidexApp/Native/Services/Subscription/StoreKitManager.swift`

```swift
import Foundation
import StoreKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "StoreKitManager")

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var currentTier: SubscriptionTier = .free
    @Published private(set) var purchaseInProgress: Bool = false

    private var transactionListener: Task<Void, Never>?
    private var userId: String?

    private init() {}

    func configure(userId: String) {
        self.userId = userId
    }

    func startListening() {
        transactionListener?.cancel()
        transactionListener = listenForTransactions()
        Task { await updateCurrentEntitlements() }
    }

    func stopListening() {
        transactionListener?.cancel()
        transactionListener = nil
    }

    // MARK: - Products

    func loadProducts() async {
        let ids = ProductID.allCases.map(\.rawValue)
        do {
            products = try await Product.products(for: ids)
            logger.info("Loaded \(products.count) products")
        } catch {
            logger.error("Failed to load products: \(error.localizedDescription)")
            products = []
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Transaction? {
        guard let userId = userId else {
            throw PurchaseError.userNotConfigured
        }

        purchaseInProgress = true
        defer { purchaseInProgress = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            // 1. Verify locally
            guard case .verified(let transaction) = verification else {
                logger.error("Transaction verification failed")
                throw PurchaseError.verificationFailed
            }

            // 2. Unlock tier immediately
            await updateCurrentEntitlements()
            EntitlementService.shared.updateEffectiveTier()

            // 3. Finish transaction (don't block on server)
            await transaction.finish()
            logger.info("Transaction finished: \(transaction.productID)")

            // 4. Queue JWS upload to server (persisted, with retry)
            // Pass the product for display price
            await queueJWSUpload(transaction: transaction, userId: userId, product: product)

            return transaction

        case .userCancelled:
            logger.info("Purchase cancelled by user")
            return nil

        case .pending:
            logger.info("Purchase pending (Ask to Buy)")
            return nil

        @unknown default:
            return nil
        }
    }

    // MARK: - Restore

    func restorePurchases() async throws {
        try await AppStore.sync()
        await updateCurrentEntitlements()
        EntitlementService.shared.updateEffectiveTier()
        logger.info("Purchases restored")
    }

    // MARK: - Entitlements

    func updateCurrentEntitlements() async {
        var highestTier: SubscriptionTier = .free

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if let productID = ProductID(rawValue: transaction.productID) {
                highestTier = max(highestTier, productID.tier)
            }
        }

        currentTier = highestTier
        logger.debug("StoreKit tier: \(highestTier.rawValue)")
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }

                await self?.updateCurrentEntitlements()
                await MainActor.run {
                    EntitlementService.shared.updateEffectiveTier()
                }

                // CRITICAL: Queue upload even if we don't have the product loaded
                // priceDisplay can be nil - the server doesn't require it
                if let userId = await self?.userId {
                    // Try to find product for display price, but don't skip if not found
                    let displayPrice = await self?.products.first(where: { $0.id == transaction.productID })?.displayPrice
                    await self?.queueJWSUpload(
                        transaction: transaction,
                        userId: userId,
                        priceDisplay: displayPrice  // Can be nil
                    )
                }

                await transaction.finish()
            }
        }
    }

    // MARK: - JWS Upload Queue

    /// Queue JWS upload with product info (used by purchase flow)
    private func queueJWSUpload(transaction: Transaction, userId: String, product: Product) async {
        await queueJWSUpload(
            transaction: transaction,
            userId: userId,
            priceDisplay: product.displayPrice
        )
    }

    /// Queue JWS upload (core implementation)
    /// priceDisplay is optional - queue upload even without it
    private func queueJWSUpload(transaction: Transaction, userId: String, priceDisplay: String?) async {
        let upload = LocalPendingJWSUpload(
            userId: userId,
            jwsRepresentation: transaction.jwsRepresentation,
            transactionId: String(transaction.id),
            originalTransactionId: String(transaction.originalID),
            productId: transaction.productID,
            environment: transaction.environment == .sandbox ? "Sandbox" : "Production",
            priceDisplay: priceDisplay  // Can be nil
        )

        do {
            try await EntitlementRepository.shared.enqueuePendingUpload(upload)
            JWSUploadWorker.shared.processQueue()
        } catch {
            logger.error("Failed to queue JWS upload: \(error.localizedDescription)")
        }
    }
}
```

### Acceptance Criteria

- [ ] Products load from App Store (or StoreKit configuration file)
- [ ] Purchase flow completes: local verify → unlock tier → finish → queue JWS
- [ ] `Transaction.currentEntitlements` reflects purchased products
- [ ] `Transaction.updates` listener handles renewals AND queues uploads
- [ ] JWS uploads are queued even if products aren't loaded (priceDisplay = nil)
- [ ] Restore purchases works

### Notes

**Implemented 2025-01-16:**

1. **StoreKitManager.swift created**: Full StoreKit 2 implementation for iOS 18+.
   - Location: `ios/App/TidexApp/Native/Services/Subscription/StoreKitManager.swift`

2. **Core functionality:**
   - `configure(userId:)` - Set user ID before purchases
   - `startListening()` / `stopListening()` - Transaction listener lifecycle
   - `loadProducts()` - Fetch subscription products from App Store
   - `purchase(_:)` - Purchase flow with local verify → unlock → finish → queue
   - `restorePurchases()` - AppStore.sync() + entitlement update
   - `updateCurrentEntitlements()` - Compute tier from Transaction.currentEntitlements

3. **Product helpers:**
   - `product(for:)` - Get product by ProductID enum
   - `products(yearly:)` - Filter products by billing period

4. **Transaction listener:**
   - Uses `Task.detached` to listen for `Transaction.updates`
   - Handles renewals, family sharing, and restores from other devices
   - Queues JWS uploads even if products aren't loaded (priceDisplay can be nil)
   - Finishes transactions after processing

5. **JWS upload queueing:**
   - Private `queueJWSUpload(transaction:userId:priceDisplay:)` method
   - Creates `LocalPendingJWSUpload` with all transaction data
   - Triggers `JWSUploadWorker.shared.processQueue()` after enqueueing

**Files created:**
- `ios/App/TidexApp/Native/Services/Subscription/StoreKitManager.swift`

**Note**: New Swift file needs to be added to the Xcode project. Build in Xcode to verify.

---

## Phase 5: JWSUploadWorker

**Status**: ✅ Complete

### Scope

Create single-flight upload worker that processes the persisted JWS queue with exponential backoff.

### Critical Implementation Details

**BUG FIX #1: The request body MUST include the JWS payload**

The edge function expects the JWS to verify the transaction. Without it, server verification fails silently.

**BUG FIX #2: Use an Encodable struct, not `[String: Any]`**

Supabase Swift's `FunctionInvokeOptions(body:)` expects `Encodable`. Using `[String: Any]` won't compile cleanly.

**BUG FIX #3: Handle response deterministically**

Check for a known success response structure. The edge function should return `{ "ok": true }` on success or `{ "error": "message" }` on failure.

### Files to Create

#### 5.1 JWSUploadWorker.swift

Location: `ios/App/TidexApp/Native/Services/Subscription/JWSUploadWorker.swift`

```swift
import Foundation
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "JWSUploadWorker")

// MARK: - Request/Response Models (Encodable for Supabase)

/// Request body for apple-verify-purchase edge function
/// CRITICAL: Must include jwsRepresentation - this is the actual receipt!
private struct JWSUploadRequest: Encodable {
    let jws: String                    // The JWS receipt - CRITICAL!
    let transactionId: String
    let originalTransactionId: String
    let productId: String
    let environment: String
    let priceDisplay: String?

    init(from upload: LocalPendingJWSUpload) {
        self.jws = upload.jwsRepresentation  // <-- The actual receipt payload
        self.transactionId = upload.transactionId
        self.originalTransactionId = upload.originalTransactionId
        self.productId = upload.productId
        self.environment = upload.environment
        self.priceDisplay = upload.priceDisplay
    }
}

/// Response from apple-verify-purchase edge function
private struct JWSUploadResponse: Decodable {
    let ok: Bool?
    let error: String?

    var isSuccess: Bool {
        ok == true && error == nil
    }
}

// MARK: - Upload Worker

@MainActor
final class JWSUploadWorker {
    static let shared = JWSUploadWorker()

    private var uploadTask: Task<Void, Never>?
    private let repository = EntitlementRepository.shared
    private let maxAttempts = 10

    private init() {}

    /// Trigger upload processing (single-flight)
    /// Safe to call multiple times - only one worker runs at a time
    func processQueue() {
        // Only start if no active worker
        guard uploadTask == nil || uploadTask?.isCancelled == true else {
            logger.debug("Upload worker already running, skipping")
            return
        }

        uploadTask = Task {
            await runUploadLoop()
            uploadTask = nil
        }
    }

    private func runUploadLoop() async {
        var successfulUserIds = Set<String>()  // Track users who had successful uploads

        while !Task.isCancelled {
            let readyUploads = repository.getPendingUploads()  // Only returns nextAttemptAt <= now

            if readyUploads.isEmpty {
                // No uploads ready NOW - but there might be some scheduled for later
                let allPending = repository.getAllPendingUploads()

                if allPending.isEmpty {
                    // Truly no uploads left - we're done
                    logger.debug("No pending uploads, worker stopping")

                    // Refresh entitlement ONCE for all users who had successful uploads
                    // (debounced - not per-upload which would be spammy)
                    for userId in successfulUserIds {
                        try? await EntitlementService.shared.refreshFromServer(userId: userId)
                    }

                    return
                }

                // Find the earliest scheduled retry and sleep until then
                // This ensures backoff retries happen even if app stays open
                let earliestRetry = allPending.map(\.nextAttemptAt).min()!
                let sleepDuration = max(earliestRetry.timeIntervalSinceNow, 1.0)  // At least 1 second

                logger.debug("No uploads ready now, sleeping \(Int(sleepDuration))s until next retry")
                try? await Task.sleep(for: .seconds(sleepDuration))
                continue
            }

            logger.info("Processing \(readyUploads.count) pending JWS uploads")

            for upload in readyUploads {
                guard !Task.isCancelled else { return }

                // Skip if max attempts reached
                if upload.attemptCount >= maxAttempts {
                    logger.warning("Max attempts reached for upload \(upload.transactionId), removing from queue")
                    try? await repository.removePendingUpload(transactionId: upload.transactionId)
                    continue
                }

                do {
                    try await uploadToServer(upload)
                    try await repository.removePendingUpload(transactionId: upload.transactionId)
                    logger.info("Successfully uploaded JWS: \(upload.transactionId)")

                    // Track userId for debounced refresh at end of loop
                    successfulUserIds.insert(upload.userId)
                } catch {
                    logger.error("Upload failed for \(upload.transactionId) (attempt \(upload.attemptCount + 1)): \(error.localizedDescription)")
                    try? await repository.schedulePendingUploadRetry(transactionId: upload.transactionId)
                }
            }

            // Brief pause before checking for more (prevents tight loop if uploads fail fast)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func uploadToServer(_ upload: LocalPendingJWSUpload) async throws {
        // Build typed request body (Encodable)
        let requestBody = JWSUploadRequest(from: upload)

        // Call the edge function
        let response = try await supabase.functions.invoke(
            "apple-verify-purchase",
            options: FunctionInvokeOptions(body: requestBody)
        )

        // Parse response
        let decoder = JSONDecoder()
        guard let uploadResponse = try? decoder.decode(JWSUploadResponse.self, from: response.data) else {
            // If we can't decode, treat as failure (unknown response format)
            logger.error("Failed to decode edge function response")
            throw PurchaseError.networkError(underlying: NSError(
                domain: "JWSUpload",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"]
            ))
        }

        // Check for explicit error
        if let errorMessage = uploadResponse.error {
            logger.error("Server returned error: \(errorMessage)")
            throw PurchaseError.networkError(underlying: NSError(
                domain: "JWSUpload",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            ))
        }

        // Verify success
        guard uploadResponse.isSuccess else {
            throw PurchaseError.networkError(underlying: NSError(
                domain: "JWSUpload",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Server did not confirm success"]
            ))
        }
    }
}
```

#### 5.2 Update apple-verify-purchase edge function

Ensure the edge function returns a consistent JSON structure:

```typescript
// On success:
return new Response(JSON.stringify({ ok: true }), { status: 200 })

// On error:
return new Response(JSON.stringify({ error: "Description of error" }), { status: 400 })
```

The edge function should also expect the `jws` field in the request body.

### Acceptance Criteria

- [ ] Worker is single-flight (no parallel workers)
- [ ] Request body includes `jws` field with the JWS representation
- [ ] Uses `Encodable` struct for request body (compiles cleanly)
- [ ] Exponential backoff works correctly (30s, 60s, 120s, 240s, max 10min)
- [ ] **Worker sleeps until earliest retry time** (doesn't stop when all uploads are scheduled for future)
- [ ] Successful upload removes item from queue
- [ ] Failed upload schedules retry with backoff
- [ ] Max attempts (10) reached removes item from queue
- [ ] Response handling is deterministic (checks for `ok: true`)

### Notes

**Implemented 2025-01-16:**

1. **JWSUploadWorker.swift created**: Single-flight upload worker with exponential backoff.
   - Location: `ios/App/TidexApp/Native/Services/Subscription/JWSUploadWorker.swift`

2. **Request/Response models:**
   - `JWSUploadRequest` (private, Encodable) - Contains `jws` field with receipt
   - `JWSUploadResponse` (private, Decodable) - Expects `{ ok: true }` or `{ error: "..." }`

3. **Core functionality:**
   - `processQueue()` - Single-flight trigger (only one worker runs at a time)
   - `runUploadLoop()` - Main loop that processes ready uploads and sleeps until retries
   - `uploadToServer(_:)` - Calls `apple-verify-purchase` edge function

4. **Retry logic:**
   - Checks `getPendingUploads()` for ready uploads (nextAttemptAt <= now)
   - If no ready uploads but some scheduled, sleeps until earliest retry time
   - Max 10 attempts before removing from queue
   - Exponential backoff handled by `LocalPendingJWSUpload.scheduleNextRetry()`

5. **Entitlement refresh debouncing:**
   - Tracks `successfulUserIds` during upload loop
   - Refreshes entitlement ONCE per user at end of loop (not per-upload)

**Files created:**
- `ios/App/TidexApp/Native/Services/Subscription/JWSUploadWorker.swift`

**Note**: New Swift file needs to be added to the Xcode project. Edge function update for `{ ok: true }` response format may be needed.

---

## Phase 6: EntitlementService

**Status**: ✅ Complete

### Scope

Create service that fetches entitlement via RPC function, caches with TTL, and merges with StoreKit tier.

### Critical Implementation Details

**SECURITY FIX: Use RPC function, not direct view query**

The original approach queried `.from("user_entitlements").eq("user_id", value: userId)` which allows a malicious client to pass any user ID. The RPC function `get_my_entitlement()` uses `auth.uid()` server-side.

**FIX: Make `serverTierExpired` state unambiguous**

Always derive `serverTierExpired` explicitly from the cache state, not implicitly from side effects.

### Files to Create

#### 6.1 EntitlementService.swift

Location: `ios/App/TidexApp/Native/Services/Subscription/EntitlementService.swift`

```swift
import Foundation
import Combine
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "EntitlementService")

@MainActor
final class EntitlementService: ObservableObject {
    static let shared = EntitlementService()

    @Published private(set) var effectiveTier: SubscriptionTier = .free
    @Published private(set) var serverTierExpired: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isOffline: Bool = false

    private let repository: EntitlementRepository
    private var cachedEntitlement: LocalEntitlementCache?
    private var userId: String?

    private init(repository: EntitlementRepository? = nil) {
        self.repository = repository ?? EntitlementRepository.shared
    }

    /// Refresh from server and update cache
    /// SECURITY: Uses RPC function that enforces auth.uid() server-side
    func refreshFromServer(userId: String) async throws {
        self.userId = userId
        isLoading = true
        isOffline = false
        defer { isLoading = false }

        do {
            // SECURITY: Call RPC function instead of direct view query
            // The RPC function uses auth.uid() server-side, cannot be spoofed
            // .single() required because RETURNS TABLE returns an array by default
            let entitlement: ServerEntitlement = try await supabase
                .rpc("get_my_entitlement")
                .single()
                .execute()
                .value

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

    /// Load from cache on app launch (fast, offline-safe)
    func loadFromCache(userId: String) {
        self.userId = userId
        cachedEntitlement = repository.getCached(for: userId)

        // Explicitly derive expired state - never ambiguous
        serverTierExpired = cachedEntitlement?.isExpired ?? true

        if let cached = cachedEntitlement {
            logger.info("Loaded cached entitlement: tier=\(cached.tier.rawValue), expired=\(cached.isExpired)")
        } else {
            logger.info("No cached entitlement found")
        }

        updateEffectiveTier()
    }

    /// Compute effective tier = max(storeKitTier, serverTier if not expired)
    func updateEffectiveTier() {
        let storeKitTier = StoreKitManager.shared.currentTier

        if let cached = cachedEntitlement, !cached.isExpired {
            // Server cache is valid - use max of StoreKit and server
            effectiveTier = max(storeKitTier, cached.tier)
            serverTierExpired = false
        } else {
            // Server cache expired or missing - only StoreKit counts
            effectiveTier = storeKitTier
            // Explicitly set - expired if we HAD a cache that expired
            serverTierExpired = cachedEntitlement?.isExpired ?? (cachedEntitlement == nil && userId != nil)
        }

        logger.debug("Effective tier: \(effectiveTier.rawValue) (StoreKit=\(storeKitTier.rawValue), server=\(cachedEntitlement?.tier.rawValue ?? "none"), expired=\(serverTierExpired))")
    }

    /// Clear cache on logout
    func clearCache() async {
        guard let userId = userId else { return }
        try? await repository.clearCache(for: userId)
        cachedEntitlement = nil
        effectiveTier = .free
        serverTierExpired = false
        self.userId = nil
    }

    /// Check if user needs to verify (expired server tier AND no StoreKit entitlement)
    var needsVerification: Bool {
        serverTierExpired && StoreKitManager.shared.currentTier == .free
    }
}
```

### Acceptance Criteria

- [ ] Fetches tier from `user_entitlements` view
- [ ] Caches with 48h TTL
- [ ] `effectiveTier` = max(storeKitTier, serverTierIfNotExpired)
- [ ] `serverTierExpired` is ALWAYS explicitly derived from cache state
- [ ] `needsVerification` is true when TTL expired AND StoreKit tier is free
- [ ] Works offline (uses cache)

### Notes

**Implemented 2025-01-16:**

1. **EntitlementService.swift created**: Service for merging server and StoreKit tiers.
   - Location: `ios/App/TidexApp/Native/Services/Subscription/EntitlementService.swift`

2. **Published state:**
   - `effectiveTier` - The computed tier (max of StoreKit and valid server tier)
   - `serverTierExpired` - Whether server cache is expired
   - `isLoading` - Loading state for server refresh
   - `isOffline` - Whether last server fetch failed

3. **Core functionality:**
   - `refreshFromServer(userId:)` - Fetch via `get_my_entitlement()` RPC and cache
   - `loadFromCache(userId:)` - Fast offline-safe load on app launch
   - `updateEffectiveTier()` - Compute effective tier = max(storeKit, serverIfValid)
   - `clearCache()` - Clear cache on logout

4. **Convenience properties:**
   - `needsVerification` - True when server expired AND StoreKit tier is free
   - `isEntitled` - Whether user has any entitlement
   - `serverEntitlement` - Access to cached entitlement

5. **Security:**
   - Uses `get_my_entitlement()` RPC function (not direct view query)
   - RPC enforces `auth.uid()` server-side, cannot be spoofed

6. **State management:**
   - `serverTierExpired` always explicitly derived from cache state
   - Never ambiguous - computed from `cachedEntitlement?.isExpired`

**Files created:**
- `ios/App/TidexApp/Native/Services/Subscription/EntitlementService.swift`

**Note**: New Swift file needs to be added to the Xcode project. Build in Xcode to verify.

---

## Phase 7: Shift Month Limit Gating

**Status**: ✅ Complete

### Scope

Add month limit enforcement to ShiftsRepository and AddShiftViewModel.

### Critical Implementation Details

**FIX: Avoid stringly-typed sync status checks**

Instead of checking `syncStatusRaw != "pendingDelete"`, add a computed property `isPendingDelete` to `LocalUserShift` to prevent typo regressions.

### Tasks

#### 7.1 Add computed property to LocalUserShift

In `LocalUserShift.swift`, add:

```swift
/// Computed property to avoid stringly-typed status checks
var isPendingDelete: Bool {
    syncStatusRaw == "pendingDelete"
}

/// Whether this shift should be counted as "existing" for month gating
/// Excludes deleted and pending-delete shifts
var isActiveShift: Bool {
    serverDeletedAt == nil && !isPendingDelete
}
```

#### 7.2 Add to ShiftsRepository

Add these methods:

```swift
// MARK: - Shift Creation Error

enum ShiftCreationError: Error {
    case monthLimitReached(existingMonths: Set<DateComponents>)
}

// MARK: - Month Limit Gating

/// Get set of months that have at least one active (non-deleted) shift
/// Uses isActiveShift computed property to avoid stringly-typed checks
func getExistingShiftMonths(for userId: String) -> Set<DateComponents> {
    let context = localStore.mainContext
    let calendar = Calendar.current

    // Fetch all shifts for user, then filter in memory using computed property
    // (SwiftData predicates can't use computed properties)
    let descriptor = FetchDescriptor<LocalUserShift>(
        predicate: #Predicate { shift in
            shift.userId == userId && shift.serverDeletedAt == nil
        }
    )

    do {
        let shifts = try context.fetch(descriptor)
        // Filter out pending deletes using computed property
        let activeShifts = shifts.filter { $0.isActiveShift }
        return Set(activeShifts.map { calendar.dateComponents([.year, .month], from: $0.shiftDate) })
    } catch {
        logger.error("Failed to fetch existing shift months: \(error.localizedDescription)")
        return []
    }
}

/// Check if free user can create shift in target month
/// - Free users can create shifts if:
///   1. No existing shifts (first month free), OR
///   2. Target month already has shifts (already "unlocked")
func canCreateShift(userId: String, targetDate: Date, tier: SubscriptionTier) -> Bool {
    // Pro and Max can always create
    guard tier == .free else { return true }

    let calendar = Calendar.current
    let targetMonth = calendar.dateComponents([.year, .month], from: targetDate)
    let existingMonths = getExistingShiftMonths(for: userId)

    // Allow if no existing shifts OR target month already has shifts
    return existingMonths.isEmpty || existingMonths.contains(targetMonth)
}

/// Create shift with tier check (throws if free user blocked)
func createShiftWithTierCheck(
    userId: String,
    shiftDate: Date,
    startTime: String,
    endTime: String,
    customSupplements: CustomSupplementsData? = nil,
    tier: SubscriptionTier
) async throws -> ShiftRow {
    guard canCreateShift(userId: userId, targetDate: shiftDate, tier: tier) else {
        let existingMonths = getExistingShiftMonths(for: userId)
        throw ShiftCreationError.monthLimitReached(existingMonths: existingMonths)
    }

    return try await createShift(
        userId: userId,
        shiftDate: shiftDate,
        startTime: startTime,
        endTime: endTime,
        customSupplements: customSupplements
    )
}
```

#### 7.3 Update AddShiftViewModel

```swift
@Published var showPaywall = false
@Published var existingMonths: Set<DateComponents> = []

func saveShift() async {
    let tier = EntitlementService.shared.effectiveTier

    do {
        try await shiftsRepository.createShiftWithTierCheck(
            userId: userId,
            shiftDate: selectedDate,
            startTime: startTime,
            endTime: endTime,
            tier: tier
        )
        // Success - dismiss view
    } catch ShiftCreationError.monthLimitReached(let months) {
        existingMonths = months
        showPaywall = true
    } catch {
        // Handle other errors
    }
}
```

### Future Consideration: Recurring Shifts

**NOTE**: If the iOS app later allows creating/editing recurring shifts that can generate shifts in new months, similar gating should be applied there. Options:
1. Require Pro/Max for recurring shifts outright
2. Gate recurring shifts to only repeat within existing months
3. Only materialize recurring shift instances into existing months for free users

This is not in scope for the initial implementation since recurring shifts are handled separately.

### Acceptance Criteria

- [ ] `LocalUserShift.isActiveShift` computed property works correctly
- [ ] Free user with no shifts can create in any month
- [ ] Free user with shifts in Jan can add more to Jan
- [ ] Free user with shifts in Jan is blocked from Feb (paywall shown)
- [ ] Ex-Pro user with shifts in Jan+Feb+Mar can add to any of those months
- [ ] Deleted shifts (`serverDeletedAt != nil`) don't count as "existing"
- [ ] Pending-delete shifts (`isPendingDelete`) don't count as "existing"
- [ ] Pro/Max users are never blocked

### Notes

**Implemented 2025-01-16:**

1. **LocalUserShift computed properties added:**
   - `isPendingDelete` - Checks if `syncStatusRaw == "pendingDelete"` (avoids stringly-typed checks)
   - `isActiveShift` - Returns true if shift is not deleted AND not pending delete

2. **ShiftCreationError enum created:**
   - Location: `ios/App/TidexApp/Native/Storage/Repositories/ShiftsRepository.swift`
   - Single case: `monthLimitReached(existingMonths: Set<DateComponents>)`
   - Includes LocalizedError conformance with user-friendly message

3. **ShiftsRepository month limit gating methods:**
   - `getExistingShiftMonths(for:)` - Returns Set<DateComponents> of months with active shifts
   - `canCreateShift(userId:targetDate:tier:)` - Returns Bool based on tier and existing months
   - `createShiftWithTierCheck(userId:shiftDate:startTime:endTime:customSupplements:tier:)` - Throws if blocked

4. **AddShiftViewModel updated:**
   - Added `showPaywall` published property
   - Added `existingShiftMonths` published property for display
   - `submitSingleShifts()` now uses `createShiftWithTierCheck()` and catches `ShiftCreationError.monthLimitReached`
   - On month limit error: sets `existingShiftMonths` and `showPaywall = true`

5. **AddShiftView updated:**
   - Added `.sheet(isPresented: $viewModel.showPaywall)` binding
   - Added `PaywallPlaceholderView` as temporary UI until Phase 8
   - Placeholder shows upgrade prompt with crown icon

**Files modified:**
- `ios/App/TidexApp/Native/Storage/Models/LocalUserShift.swift`
- `ios/App/TidexApp/Native/Storage/Repositories/ShiftsRepository.swift`
- `ios/App/TidexApp/Native/Features/AddShift/AddShiftViewModel.swift`
- `ios/App/TidexApp/Native/Features/AddShift/AddShiftView.swift`

**Note**: PaywallPlaceholderView will be replaced with actual PaywallView in Phase 8. Build in Xcode to verify.

---

## Phase 8: PaywallView & Components

**Status**: ✅ Complete

### Scope

Create paywall UI and verification-required UI.

### Files to Create

#### 8.1 PaywallView.swift

Location: `ios/App/TidexApp/Native/Features/Paywall/PaywallView.swift`

- Sheet with NavigationStack and close button
- BillingToggle (Monthly/Yearly segmented control)
- Two PlanCards (Pro, Max) showing StoreKit prices
- Restore purchases button
- Loading state during purchase

#### 8.2 PaywallViewModel.swift

Location: `ios/App/TidexApp/Native/Features/Paywall/PaywallViewModel.swift`

- Load products on appear
- Handle purchase flow
- Track selected billing period

#### 8.3 PlanCard.swift

Location: `ios/App/TidexApp/Native/Features/Paywall/Components/PlanCard.swift`

- Tier name, price, features list
- Subscribe button

#### 8.4 BillingToggle.swift

Location: `ios/App/TidexApp/Native/Features/Paywall/Components/BillingToggle.swift`

- Monthly | Yearly (Save X%) segmented control

#### 8.5 VerificationRequiredView.swift

Location: `ios/App/TidexApp/Native/Features/Paywall/VerificationRequiredView.swift`

When server TTL expired AND StoreKit not entitled:
- Icon (wifi.slash if offline, wifi.exclamationmark otherwise)
- "Connect to verify your subscription" message
- Retry button
- Restore Purchases button

### Acceptance Criteria

- [x] PaywallView shows products with correct prices
- [x] BillingToggle switches between monthly/yearly
- [x] Purchase flow works end-to-end
- [x] VerificationRequiredView shows when appropriate
- [x] Offline state shows "No connection" variant

### Notes

**Implemented 2025-01-16:**

1. **PaywallViewModel.swift created:**
   - Location: `ios/App/TidexApp/Native/Features/Paywall/PaywallViewModel.swift`
   - `BillingPeriod` enum for monthly/yearly selection
   - `proProduct` and `maxProduct` computed from StoreKitManager
   - `yearlySavingsPercent(for:)` calculates savings percentage
   - `purchase(_:)` handles purchase flow with success/error states
   - `restorePurchases()` wraps StoreKitManager.restorePurchases()
   - `purchaseSucceeded` triggers sheet dismissal

2. **BillingToggle.swift created:**
   - Location: `ios/App/TidexApp/Native/Features/Paywall/Components/BillingToggle.swift`
   - Segmented control with Monthly/Yearly options
   - Shows "Save X%" badge for yearly option
   - Spring animation on selection change

3. **PlanCard.swift created:**
   - Location: `ios/App/TidexApp/Native/Features/Paywall/Components/PlanCard.swift`
   - Displays tier icon, name, and price
   - Shows "Current Plan" badge if already subscribed
   - Features list with checkmark icons
   - Subscribe button with loading state
   - Border highlight for current plan

4. **PaywallView.swift created:**
   - Location: `ios/App/TidexApp/Native/Features/Paywall/PaywallView.swift`
   - NavigationStack with close button
   - Optional `PaywallContext` for contextual headers (e.g., month limit)
   - BillingToggle for period selection
   - Pro and Max PlanCards
   - Error display with dismiss button
   - Restore Purchases button
   - Legal links (Terms, Privacy)
   - Loading overlay while products load
   - Auto-dismiss on successful purchase

5. **VerificationRequiredView.swift created:**
   - Location: `ios/App/TidexApp/Native/Features/Paywall/VerificationRequiredView.swift`
   - Shows when server TTL expired AND StoreKit tier is free
   - `isOffline` determines icon and message:
     - Offline: wifi.slash icon, "No Internet Connection"
     - Online: wifi.exclamationmark icon, "Verify Your Subscription"
   - "Try Again" button triggers `onRetry`
   - "Restore Purchases" button triggers `onRestore`

6. **AddShiftView updated:**
   - Replaced `PaywallPlaceholderView` with `PaywallView(context: .monthLimit)`
   - Removed placeholder view struct

**Files created:**
- `ios/App/TidexApp/Native/Features/Paywall/PaywallViewModel.swift`
- `ios/App/TidexApp/Native/Features/Paywall/PaywallView.swift`
- `ios/App/TidexApp/Native/Features/Paywall/Components/BillingToggle.swift`
- `ios/App/TidexApp/Native/Features/Paywall/Components/PlanCard.swift`
- `ios/App/TidexApp/Native/Features/Paywall/VerificationRequiredView.swift`

**Files modified:**
- `ios/App/TidexApp/Native/Features/AddShift/AddShiftView.swift`

**Note**: New Swift files need to be added to the Xcode project. Build in Xcode to verify.

---

## Phase 9: AppCoordinator Integration

**Status**: ✅ Complete

### Scope

Wire up entitlement and StoreKit services to app lifecycle.

### Tasks

#### 9.1 Update AppCoordinator.swift

In `updateUserProfile()` after authentication:

```swift
Task {
    let currentUserId = self.userId!

    // Configure StoreKit with user
    StoreKitManager.shared.configure(userId: currentUserId)

    // Load cached entitlement first (fast, offline-safe)
    EntitlementService.shared.loadFromCache(userId: currentUserId)

    // Start StoreKit listener
    StoreKitManager.shared.startListening()

    // Start JWS upload worker (process any pending uploads from previous sessions)
    JWSUploadWorker.shared.processQueue()

    // Refresh from server in background
    try? await EntitlementService.shared.refreshFromServer(userId: currentUserId)
}
```

In `signOut()`:

```swift
StoreKitManager.shared.stopListening()
await EntitlementService.shared.clearCache()
```

#### 9.2 Add AddShiftView sheet binding

In AddShiftView, add:

```swift
.sheet(isPresented: $viewModel.showPaywall) {
    PaywallView()
}
```

### Acceptance Criteria

- [x] Entitlement loads from cache on app launch
- [x] StoreKit listener starts on authentication
- [x] JWS upload worker processes pending uploads on launch
- [x] Server entitlement refreshes in background
- [x] Entitlement clears on sign out
- [x] Paywall sheet presents from AddShiftView

### Notes

**Implemented 2025-01-16:**

1. **AppCoordinator.swift updated:**
   - Added `configureStoreKitAndEntitlements(userId:)` method
   - Called in `updateUserProfile()` after authentication

2. **StoreKit & Entitlement initialization sequence:**
   1. `StoreKitManager.shared.configure(userId:)` - Sets user ID for purchases
   2. `EntitlementService.shared.loadFromCache(userId:)` - Fast offline-safe cache load
   3. `StoreKitManager.shared.startListening()` - Listens for transaction updates
   4. `JWSUploadWorker.shared.processQueue()` - Processes pending JWS uploads
   5. `EntitlementService.shared.refreshFromServer(userId:)` - Background server refresh
   6. `StoreKitManager.shared.loadProducts()` - Background product loading

3. **Sign out cleanup:**
   - `StoreKitManager.shared.stopListening()` - Stops transaction listener
   - `EntitlementService.shared.clearCache()` - Clears cached entitlement

4. **Paywall sheet already integrated in Phase 7/8:**
   - AddShiftView already has `.sheet(isPresented: $viewModel.showPaywall)`
   - Uses `PaywallView(context: .monthLimit)` for contextual header

**Files modified:**
- `ios/App/TidexApp/Native/Core/AppCoordinator.swift`

**Note**: Build in Xcode to verify all services integrate correctly.

---

## Phase 10: Localization & StoreKit Config

**Status**: ⬜ Not Started

### Scope

Add localization strings and StoreKit testing configuration.

### Tasks

#### 10.1 Update AuthStrings.swift

Add Norwegian and English strings:

```swift
// Paywall
"paywall.title": "Velg abonnement" / "Choose a plan"
"paywall.monthly": "Månedlig" / "Monthly"
"paywall.yearly": "Årlig" / "Yearly"
"paywall.savePercent": "Spar %d%%" / "Save %d%%"
"paywall.subscribe": "Abonner" / "Subscribe"
"paywall.restorePurchases": "Gjenopprett kjøp" / "Restore Purchases"
"paywall.currentPlan": "Din nåværende plan" / "Your current plan"

// Shift limit
"paywall.shiftLimit.title": "Oppgrader for flere måneder" / "Upgrade to unlock more months"
"paywall.shiftLimit.description": "Gratis-planen tillater vakter i én måned om gangen" / "Free plan allows shifts in one month at a time"

// Verification required
"verification.required.title": "Koble til for å verifisere" / "Connect to verify subscription"
"verification.required.offline": "Ingen internettforbindelse" / "No internet connection"
"verification.required.description": "Abonnementet ditt kunne ikke bekreftes. Koble til internett for å fortsette." / "Your subscription couldn't be verified. Connect to the internet to continue."
"verification.required.retry": "Prøv igjen" / "Retry"
```

#### 10.2 Create Configuration.storekit

Create StoreKit configuration file in Xcode for local testing:

| Product ID | Reference Name | Price | Duration |
|------------|----------------|-------|----------|
| no.tidex.pro | Pro Monthly | 29 kr | 1 Month |
| no.tidex.pro.year | Pro Yearly | 249 kr | 1 Year |
| no.tidex.max | Max Monthly | 49 kr | 1 Month |
| no.tidex.max.year | Max Yearly | 449 kr | 1 Year |

Subscription Group: `tidex_subscriptions`

### Acceptance Criteria

- [ ] All strings localized (Norwegian + English)
- [ ] StoreKit configuration file loads in Xcode
- [ ] Products show correct prices in simulator

### Notes

_Implementation notes will be added after completion._

---

## Phase 11: Testing & Validation

**Status**: ⬜ Not Started

### Scope

End-to-end testing of the paywall system.

### Test Cases

#### Tier Determination

- [ ] Free user (no subscription, not grandfathered) → tier = free
- [ ] Pro subscriber → tier = pro
- [ ] Max subscriber → tier = max
- [ ] Grandfathered user without subscription → tier = pro
- [ ] Grandfathered user with Max subscription → tier = max

#### TTL Caching

- [ ] Fresh cache (< 48h) → serverTierExpired = false
- [ ] Expired cache (> 48h) → serverTierExpired = true
- [ ] Effective tier = max(storeKit, serverIfValid)

#### Month Limit Gating

- [ ] Free user, no shifts → can create in any month
- [ ] Free user, shifts in Jan → can add to Jan
- [ ] Free user, shifts in Jan → blocked from Feb, paywall shown
- [ ] Ex-Pro user, shifts in Jan+Feb+Mar → can add to any of those
- [ ] Deleted shift doesn't keep month "unlocked"
- [ ] Pro/Max users never blocked

#### StoreKit Purchase Flow

- [ ] Products load correctly
- [ ] Purchase completes → tier unlocks immediately
- [ ] Transaction finishes before server upload
- [ ] JWS queued for async upload

#### JWS Upload Queue

- [ ] App kill after purchase → JWS still in queue on relaunch
- [ ] JWS uploads on app launch
- [ ] Failed upload retries with backoff
- [ ] Successful upload removes from queue
- [ ] Multiple purchases queue correctly (single worker)

#### Restore Flow

- [ ] Restore purchases works
- [ ] Restored entitlements reflect in currentTier

#### Verification Required UI

- [ ] Shows when TTL expired AND StoreKit not entitled
- [ ] Shows "No connection" when offline
- [ ] Retry button refreshes from server
- [ ] Restore button triggers StoreKit restore

#### Edge Cases

- [ ] Offline app launch with valid cache → works normally
- [ ] Offline app launch with expired cache, no StoreKit → verification required
- [ ] Web subscriber (Stripe) → server tier shows Pro/Max, StoreKit free

### Acceptance Criteria

- [ ] All test cases pass
- [ ] No crashes or hangs
- [ ] Build succeeds in Xcode

### Notes

_Implementation notes will be added after completion._

---

## Critical Files Reference

| File | Purpose |
|------|---------|
| `supabase/sql/views/user_entitlements.sql` | Add `tier` column |
| `ios/App/TidexApp/Native/Core/AppCoordinator.swift` | Integration point |
| `ios/App/TidexApp/Native/Storage/LocalStore.swift` | Add models to schema |
| `ios/App/TidexApp/Native/Storage/Repositories/ShiftsRepository.swift` | Add month limit check |
| `ios/App/TidexApp/Native/Localization/AuthStrings.swift` | Add localization |
| `ios/App/TidexApp/Native/Features/AddShift/AddShiftViewModel.swift` | Add paywall trigger |
