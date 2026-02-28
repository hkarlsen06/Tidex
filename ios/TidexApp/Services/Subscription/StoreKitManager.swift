import Foundation
import StoreKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "StoreKitManager")

// MARK: - StoreKit Manager

/// Manages StoreKit 2 operations: product loading, purchases, and transaction listening
/// Finishes transactions immediately after local verification, queues JWS for async server upload
@MainActor
final class StoreKitManager: ObservableObject {
  static let shared = StoreKitManager()

  // MARK: - Published State

  @Published private(set) var products: [Product] = []
  @Published private(set) var currentTier: SubscriptionTier = .free
  @Published private(set) var currentProductId: String?
  @Published private(set) var purchaseInProgress: Bool = false
  @Published private(set) var isLoadingProducts: Bool = false

  // MARK: - Private State

  private var transactionListener: Task<Void, Never>?
  private var userId: String?

  private init() {}

  // MARK: - Configuration

  /// Configure the manager with the current user ID
  /// Must be called before any purchase operations
  /// - Parameter userId: The authenticated user's ID
  func configure(userId: String) {
    self.userId = userId
    logger.info("Configured StoreKitManager for user \(userId.prefix(8))")
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
    logger.info("Stopped transaction listener")
  }

  // MARK: - Products

  /// Load subscription products from the App Store
  func loadProducts() async {
    guard !isLoadingProducts else { return }

    isLoadingProducts = true
    defer { isLoadingProducts = false }

    var productIds = ProductID.allCases.map(\.rawValue)
    productIds.append(ConsumableProductID.wageyBonus20.rawValue)

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

  /// Get a consumable product by its ID
  /// - Parameter productId: The ConsumableProductID to find
  /// - Returns: The Product if found
  func consumableProduct(for productId: ConsumableProductID) -> Product? {
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
    guard let userId = userId else {
      throw PurchaseError.userNotConfigured
    }

    purchaseInProgress = true
    defer { purchaseInProgress = false }

    logger.info("Starting purchase for product: \(product.id)")

    let result: Product.PurchaseResult
    do {
      result = try await product.purchase()
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

      // 3. Finish transaction locally
      await transaction.finish()
      logger.info("Transaction finished: \(transaction.productID)")

      // 4. Upload JWS to server IMMEDIATELY and wait for it
      // This ensures the server knows about the subscription before user tries to use features
      let upload = LocalPendingJWSUpload(
        userId: userId,
        jwsRepresentation: jwsRepresentation,
        transactionId: String(transaction.id),
        originalTransactionId: String(transaction.originalID),
        productId: transaction.productID,
        environment: transaction.environment == .sandbox ? "Sandbox" : "Production",
        priceDisplay: product.displayPrice
      )

      let uploadSuccess = await JWSUploadWorker.shared.uploadImmediately(upload)
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

  /// Purchase a consumable product
  /// Flow: local verify -> finish transaction -> upload JWS
  /// Does not update subscription entitlements.
  /// - Parameter product: The consumable product to purchase
  /// - Returns: Whether JWS upload succeeded immediately
  /// - Throws: PurchaseError on failure
  func purchaseConsumable(_ product: Product) async throws -> Bool {
    guard let userId = userId else {
      throw PurchaseError.userNotConfigured
    }

    purchaseInProgress = true
    defer { purchaseInProgress = false }

    logger.info("Starting consumable purchase for product: \(product.id)")

    let result: Product.PurchaseResult
    do {
      result = try await product.purchase()
    } catch {
      logger.error("Consumable purchase failed: \(error.localizedDescription)")
      throw PurchaseError.networkError(underlying: error)
    }

    switch result {
    case .success(let verification):
      guard case .verified(let transaction) = verification else {
        logger.error("Consumable transaction verification failed for \(product.id)")
        throw PurchaseError.verificationFailed
      }

      // jwsRepresentation is on VerificationResult, not Transaction — access after verified guard
      let jwsRepresentation = verification.jwsRepresentation

      await transaction.finish()
      logger.info("Consumable transaction finished: \(transaction.productID)")

      let upload = LocalPendingJWSUpload(
        userId: userId,
        jwsRepresentation: jwsRepresentation,
        transactionId: String(transaction.id),
        originalTransactionId: String(transaction.originalID),
        productId: transaction.productID,
        environment: transaction.environment == .sandbox ? "Sandbox" : "Production",
        priceDisplay: product.displayPrice
      )

      return await JWSUploadWorker.shared.uploadImmediately(upload)

    case .userCancelled:
      logger.info("Consumable purchase cancelled by user")
      return false

    case .pending:
      logger.info("Consumable purchase pending")
      return false

    @unknown default:
      logger.warning("Unknown consumable purchase result")
      return false
    }
  }

  // MARK: - Restore

  /// Restore previous purchases from the App Store
  /// - Throws: Error if sync fails
  func restorePurchases() async throws {
    guard let userId = userId else {
      throw PurchaseError.userNotConfigured
    }

    logger.info("Restoring purchases...")

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

      let isProduction = transaction.environment != .sandbox
      let currentIsProduction =
        bestTransaction.map { $0.verification.unsafePayloadValue.environment != .sandbox } ?? false

      // Prefer Production over Sandbox
      if isProduction && !currentIsProduction {
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
    var highestTier: SubscriptionTier = .free
    var highestProductId: String?

    for await result in Transaction.currentEntitlements {
      guard case .verified(let transaction) = result else {
        continue
      }

      // Map product ID to tier
      if let productId = ProductID(rawValue: transaction.productID) {
        if productId.tier > highestTier {
          highestTier = productId.tier
          highestProductId = transaction.productID
        } else if productId.tier == highestTier && highestProductId == nil {
          highestProductId = transaction.productID
        }
      }
    }

    let previousTier = currentTier
    currentTier = highestTier
    currentProductId = highestProductId
    logger.debug(
      "StoreKit entitlements updated: tier=\(highestTier.rawValue), productId=\(highestProductId ?? "none")"
    )

    // Notify EntitlementService of tier change for proper synchronization
    // This ensures EntitlementService always uses the freshest tier value
    if previousTier != highestTier {
      EntitlementService.shared.handleStoreKitTierChange(highestTier)
    }
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

        // Queue JWS upload even if products aren't loaded
        // priceDisplay can be nil - server doesn't require it
        if let userId = await self?.userId {
          // Try to find product for display price, but don't skip if not found
          let displayPrice = await self?.products.first(where: { $0.id == transaction.productID })?
            .displayPrice
          await self?.queueJWSUpload(
            transaction: transaction,
            jwsRepresentation: jwsRepresentation,
            userId: userId,
            priceDisplay: displayPrice
          )
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
  private func queueJWSUpload(
    transaction: Transaction, jwsRepresentation: String, userId: String, priceDisplay: String?
  ) async {
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
    } catch {
      logger.error("Failed to queue JWS upload: \(error.localizedDescription)")
    }
  }
}
