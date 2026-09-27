import Foundation
import StoreKit
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "StoreKitManager")
private let kUserIdLogPrefixLength: Int = 8
private let kServerUploadFailureCode: Int = -2

// MARK: - StoreKit Manager

/// Manages StoreKit 2 operations: product loading, purchases, and transaction listening
/// Persists the JWS upload before finishing a transaction, then uploads it to the server
@MainActor
final class StoreKitManager: ObservableObject {
  internal static let shared: StoreKitManager = .init()

  // MARK: - Published State

  @Published private(set) var products: [Product] = []
  @Published private(set) var currentTier: SubscriptionTier = .free
  @Published private(set) var currentProductId: String?
  @Published private(set) var purchaseInProgress: Bool = false
  @Published private(set) var isLoadingProducts: Bool = false

  // MARK: - Private State

  private var transactionListener: Task<Void, Never>?
  private var userId: String?
  private var cachedAppAccountToken: UUID?

  private init() {
    // Singleton instance.
  }

  // MARK: - Configuration

  /// Configure the manager with the current user ID
  /// Must be called before any purchase operations
  /// - Parameter userId: The authenticated user's ID
  func configure(userId: String) {
    if self.userId != userId {
      cachedAppAccountToken = nil
      setCurrentEntitlement(tier: .free, productId: nil)
    }

    self.userId = userId
    logger.info("Configured StoreKitManager for user \(userId.prefix(kUserIdLogPrefixLength))")
  }

  /// Start listening for transaction updates (renewals, restores, family sharing)
  func startListening() {
    transactionListener?.cancel()
    transactionListener = listenForTransactions()
    Task { await updateCurrentEntitlements() }
    logger.info("Started transaction listener")
  }

  /// Stop listening for transactions (call on sign out)
  func stopListening() {
    transactionListener?.cancel()
    transactionListener = nil
    userId = nil
    cachedAppAccountToken = nil
    setCurrentEntitlement(tier: .free, productId: nil)
    logger.info("Stopped transaction listener")
  }

  // MARK: - Products

  /// Load subscription products from the App Store
  func loadProducts() async {
    guard !isLoadingProducts else {
      return
    }

    isLoadingProducts = true
    defer { isLoadingProducts = false }

    let productIds: [String] = ProductID.allCases.map(\.rawValue)

    do {
      products = try await Product.products(for: productIds)
      logger.info(
        "Loaded \(self.products.count) products: \(self.products.map(\.id).joined(separator: ", "))"
      )
    } catch {
      logger.error("Failed to load products: \(error.localizedDescription)")
      products = []
    }
  }

  /// Get a product by its ID
  /// - Parameter productId: The ProductID to find
  /// - Returns: The Product if found
  func product(for productId: ProductID) -> Product? {
    products.first { $0.id == productId.rawValue }
  }

  /// Get products filtered by billing period
  /// - Parameter yearly: Whether to get yearly products
  /// - Returns: Array of products matching the billing period
  func products(yearly: Bool) -> [Product] {
    let targetIds = ProductID.allCases
      .filter { $0.isYearly == yearly }
      .map(\.rawValue)
    return products.filter { targetIds.contains($0.id) }
  }

  // MARK: - Purchase

  /// Purchase a subscription product
  /// Flow: local verify → unlock tier → finish transaction → queue JWS upload
  /// - Parameter product: The Product to purchase
  /// - Returns: The verified Transaction if successful, nil if cancelled/pending
  /// - Throws: PurchaseError on failure
  func purchase(_ product: Product) async throws -> Transaction? {
    guard let userId else {
      throw PurchaseError.userNotConfigured
    }

    purchaseInProgress = true
    defer { purchaseInProgress = false }

    logger.info("Starting purchase for product: \(product.id)")

    let appAccountToken = try await appAccountToken(for: userId)
    let result: Product.PurchaseResult
    do {
      result = try await product.purchase(options: [.appAccountToken(appAccountToken)])
    } catch {
      logger.error("Purchase failed: \(error.localizedDescription)")
      throw PurchaseError.networkError(underlying: error)
    }

    switch result {
    case .success(let verification):
      // Capture JWS from verification result BEFORE unwrapping
      // jwsRepresentation is on VerificationResult, not Transaction
      let jwsRepresentation = verification.jwsRepresentation

      // 1. Verify transaction locally (StoreKit 2 does this automatically)
      guard case .verified(let transaction) = verification else {
        logger.error("Transaction verification failed for \(product.id)")
        throw PurchaseError.verificationFailed
      }

      logger.info("Transaction verified: \(transaction.productID), id=\(transaction.id)")

      // 2. Update local entitlements immediately (unlock tier)
      await updateCurrentEntitlements()
      EntitlementService.shared.updateEffectiveTier()

      // 3. Persist the receipt, then upload it and wait so the server knows about the
      // subscription before the user tries to use features.
      let makeUpload = {
        LocalPendingJWSUpload(
          userId: userId,
          jwsRepresentation: jwsRepresentation,
          transactionId: String(transaction.id),
          originalTransactionId: String(transaction.originalID),
          productId: transaction.productID,
          environment: transaction.environment == .sandbox ? "Sandbox" : "Production",
          priceDisplay: product.displayPrice
        )
      }
      let queued = await enqueueBeforeFinishing(makeUpload())
      let uploadSuccess = await JWSUploadWorker.shared.uploadImmediately(makeUpload())

      // 4. Finish only once the receipt is uploaded or queued. Otherwise StoreKit
      // redelivers the transaction through Transaction.updates.
      if queued || uploadSuccess {
        await transaction.finish()
        logger.info("Transaction finished: \(transaction.productID)")
      }
      if !uploadSuccess {
        // Upload failed but will retry in background
        // Log but don't fail the purchase - user still has local entitlement
        logger.warning("JWS upload failed, will retry in background. User has local entitlement.")
      }

      return transaction

    case .userCancelled:
      logger.info("Purchase cancelled by user")
      return nil

    case .pending:
      logger.info("Purchase pending (Ask to Buy or other deferral)")
      return nil

    @unknown default:
      logger.warning("Unknown purchase result")
      return nil
    }
  }

  // MARK: - Restore

  /// Restore previous purchases from the App Store
  /// - Throws: Error if sync fails
  func restorePurchases() async throws {
    guard let userId else {
      throw PurchaseError.userNotConfigured
    }

    logger.info("Restoring purchases...")

    let expectedAppAccountToken = try await appAccountToken(for: userId)

    try await AppStore.sync()
    await updateCurrentEntitlements()
    EntitlementService.shared.updateEffectiveTier()

    // After sync, find and upload the best subscription to the server
    // Prefer Production over Sandbox, and highest tier
    var bestTransaction: (verification: VerificationResult<Transaction>, tier: SubscriptionTier)?

    for await result in Transaction.currentEntitlements {
      guard case .verified(let transaction) = result else {
        continue
      }

      guard let productId = ProductID(rawValue: transaction.productID) else {
        continue
      }

      guard
        transactionBelongsToCurrentUser(
          transaction,
          expectedAppAccountToken: expectedAppAccountToken
        )
      else {
        continue
      }

      let isProduction = transaction.environment != .sandbox
      let currentIsProduction =
        bestTransaction.map { $0.verification.unsafePayloadValue.environment != .sandbox } ?? false

      // Prefer Production over Sandbox
      if isProduction, !currentIsProduction {
        bestTransaction = (result, productId.tier)
      } else if isProduction == currentIsProduction {
        // Same environment, prefer higher tier
        if let best = bestTransaction {
          if productId.tier > best.tier {
            bestTransaction = (result, productId.tier)
          }
        } else {
          bestTransaction = (result, productId.tier)
        }
      }

      logger.info(
        "Found entitlement: \(transaction.productID), env=\(transaction.environment == .sandbox ? "Sandbox" : "Production"), tier=\(productId.tier.rawValue)"
      )
    }

    // Upload the best transaction to the server
    if let best = bestTransaction, case .verified(let transaction) = best.verification {
      let jwsRepresentation = best.verification.jwsRepresentation
      let displayPrice = products.first(where: { $0.id == transaction.productID })?.displayPrice

      let upload = LocalPendingJWSUpload(
        userId: userId,
        jwsRepresentation: jwsRepresentation,
        transactionId: String(transaction.id),
        originalTransactionId: String(transaction.originalID),
        productId: transaction.productID,
        environment: transaction.environment == .sandbox ? "Sandbox" : "Production",
        priceDisplay: displayPrice
      )

      let uploadSuccess = await JWSUploadWorker.shared.uploadImmediately(upload)
      if uploadSuccess {
        logger.info(
          "Uploaded restored subscription to server: \(transaction.productID), env=\(transaction.environment == .sandbox ? "Sandbox" : "Production")"
        )
      } else {
        logger.warning("Failed to upload restored subscription, will retry in background")
      }
    }

    logger.info("Purchases restored, current tier: \(self.currentTier.rawValue)")
  }

  // MARK: - Entitlements

  /// Update the current StoreKit tier from Transaction.currentEntitlements
  /// This reflects what StoreKit says the user is entitled to, independent of server
  /// Notifies EntitlementService when tier changes for proper synchronization
  func updateCurrentEntitlements() async {
    guard let userId else {
      setCurrentEntitlement(tier: .free, productId: nil)
      return
    }

    let expectedAppAccountToken: UUID
    do {
      expectedAppAccountToken = try await appAccountToken(for: userId)
    } catch {
      // Keep the previous tier. Offline launches must not downgrade a paying user.
      logger.error("Unable to verify StoreKit entitlement owner: \(error.localizedDescription)")
      return
    }

    var highestTier: SubscriptionTier = .free
    var highestProductId: String?

    for await result in Transaction.currentEntitlements {
      guard case .verified(let transaction) = result else {
        continue
      }

      guard
        transactionBelongsToCurrentUser(
          transaction,
          expectedAppAccountToken: expectedAppAccountToken
        )
      else {
        continue
      }

      // Map product ID to tier
      if let productId = ProductID(rawValue: transaction.productID) {
        if productId.tier > highestTier {
          highestTier = productId.tier
          highestProductId = transaction.productID
        } else if productId.tier == highestTier, highestProductId == nil {
          highestProductId = transaction.productID
        }
      }
    }

    setCurrentEntitlement(tier: highestTier, productId: highestProductId)
    logger.debug(
      "StoreKit entitlements updated: tier=\(highestTier.rawValue), productId=\(highestProductId ?? "none")"
    )
  }

  // MARK: - Transaction Listener

  /// Listen for transaction updates (renewals, restores from other devices, family sharing)
  private func listenForTransactions() -> Task<Void, Never> {
    Task.detached { [weak self] in
      for await result in Transaction.updates {
        // Capture JWS from the verification result BEFORE unwrapping
        // jwsRepresentation is on VerificationResult, not Transaction
        let jwsRepresentation = result.jwsRepresentation

        guard case .verified(let transaction) = result else {
          continue
        }

        logger.info("Transaction update received: \(transaction.productID), id=\(transaction.id)")

        // Update local entitlements - this also notifies EntitlementService of tier changes
        await self?.updateCurrentEntitlements()

        // Leave the transaction unfinished when the owner can't be verified (signed out
        // or offline without a stored token). StoreKit redelivers it on the next launch.
        guard let userId = await self?.userId,
          let expectedAppAccountToken = try? await self?.appAccountToken(for: userId)
        else {
          continue
        }

        // Queue JWS upload even if products aren't loaded
        // priceDisplay can be nil - server doesn't require it
        if await self?.transactionBelongsToCurrentUser(
          transaction,
          expectedAppAccountToken: expectedAppAccountToken
        ) == true {
          // Try to find product for display price, but don't skip if not found
          let displayPrice = await self?.products.first(where: { $0.id == transaction.productID })?
            .displayPrice
          let queued =
            await self?.queueJWSUpload(
              transaction: transaction,
              jwsRepresentation: jwsRepresentation,
              userId: userId,
              priceDisplay: displayPrice
            ) ?? false
          guard queued else { continue }
        }

        // Finish the transaction
        await transaction.finish()
      }
    }
  }

  // MARK: - JWS Upload Queue (Background Updates)

  /// Queue JWS upload with product info (used by transaction listener for renewals)
  private func queueJWSUpload(
    transaction: Transaction, jwsRepresentation: String, userId: String, product: Product
  ) async {
    await queueJWSUpload(
      transaction: transaction,
      jwsRepresentation: jwsRepresentation,
      userId: userId,
      priceDisplay: product.displayPrice
    )
  }

  /// Queue JWS upload (core implementation)
  /// jwsRepresentation must be passed from VerificationResult (not available on Transaction)
  /// priceDisplay is optional - queue upload even without it
  /// - Returns: false if the upload could not be persisted
  @discardableResult
  private func queueJWSUpload(
    transaction: Transaction, jwsRepresentation: String, userId: String, priceDisplay: String?
  ) async -> Bool {
    let upload = LocalPendingJWSUpload(
      userId: userId,
      jwsRepresentation: jwsRepresentation,
      transactionId: String(transaction.id),
      originalTransactionId: String(transaction.originalID),
      productId: transaction.productID,
      environment: transaction.environment == .sandbox ? "Sandbox" : "Production",
      priceDisplay: priceDisplay
    )

    do {
      try await EntitlementRepository.shared.enqueuePendingUpload(upload)
      logger.info("Queued JWS upload for transaction: \(transaction.id)")

      // Trigger upload worker
      JWSUploadWorker.shared.processQueue()
      return true
    } catch {
      logger.error("Failed to queue JWS upload: \(error.localizedDescription)")
      return false
    }
  }

  /// Persists an upload before its transaction is finished. Returns false if the
  /// queue write failed, in which case the caller leaves the transaction unfinished.
  private func enqueueBeforeFinishing(_ upload: LocalPendingJWSUpload) async -> Bool {
    do {
      try await EntitlementRepository.shared.enqueuePendingUpload(upload)
      return true
    } catch {
      logger.error("Failed to queue JWS upload before finishing: \(error.localizedDescription)")
      return false
    }
  }

  private func setCurrentEntitlement(tier: SubscriptionTier, productId: String?) {
    let previousTier = currentTier
    currentTier = tier
    currentProductId = productId

    // Notify EntitlementService of tier change for proper synchronization.
    if previousTier != tier {
      EntitlementService.shared.handleStoreKitTierChange(tier)
    }
  }

  private func transactionBelongsToCurrentUser(
    _ transaction: Transaction,
    expectedAppAccountToken: UUID
  ) -> Bool {
    guard let transactionAppAccountToken = transaction.appAccountToken else {
      logger.info(
        "Ignoring StoreKit entitlement without appAccountToken: \(transaction.productID), id=\(transaction.id)"
      )
      return false
    }

    guard transactionAppAccountToken == expectedAppAccountToken else {
      logger.info(
        "Ignoring StoreKit entitlement for a different app account: \(transaction.productID), id=\(transaction.id)"
      )
      return false
    }

    return true
  }

  private func appAccountToken(for userId: String) async throws -> UUID {
    if let cachedAppAccountToken {
      return cachedAppAccountToken
    }

    // The token is stable per user, so a stored copy lets offline launches verify
    // StoreKit entitlements without the RPC.
    if let storedToken = Self.storedAppAccountToken(for: userId) {
      cachedAppAccountToken = storedToken
      return storedToken
    }

    guard UUID(uuidString: userId) != nil else {
      throw PurchaseError.networkError(
        underlying: NSError(
          domain: "StoreKitManager",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"]
        ))
    }

    do {
      let token: String =
        try await supabase
        .rpc("get_or_create_app_account_token", params: ["p_user_id": userId])
        .execute()
        .value

      guard let uuid = UUID(uuidString: token) else {
        throw NSError(
          domain: "StoreKitManager",
          code: kServerUploadFailureCode,
          userInfo: [NSLocalizedDescriptionKey: "Invalid app account token"]
        )
      }

      cachedAppAccountToken = uuid
      Self.storeAppAccountToken(uuid, for: userId)
      return uuid
    } catch {
      logger.error("Failed to get app account token: \(error.localizedDescription)")
      throw PurchaseError.networkError(underlying: error)
    }
  }

  // MARK: - App Account Token Storage

  /// The token isn't secret; it only links StoreKit transactions to a Tidex user.
  nonisolated static func storedAppAccountToken(
    for userId: String,
    defaults: UserDefaults = .standard
  ) -> UUID? {
    defaults.string(forKey: appAccountTokenKey(for: userId)).flatMap(UUID.init(uuidString:))
  }

  nonisolated static func storeAppAccountToken(
    _ token: UUID,
    for userId: String,
    defaults: UserDefaults = .standard
  ) {
    defaults.set(token.uuidString, forKey: appAccountTokenKey(for: userId))
  }

  private nonisolated static func appAccountTokenKey(for userId: String) -> String {
    "storekit.appAccountToken.\(userId.lowercased())"
  }
}
