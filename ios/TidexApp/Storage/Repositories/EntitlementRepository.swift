import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "EntitlementRepository")

// MARK: - Entitlement Repository

/// Local-first repository for entitlement caching and JWS upload queue
/// Provides persistence for offline-first subscription enforcement
@MainActor
final class EntitlementRepository {
  static let shared = EntitlementRepository()

  private let localStore: LocalStore

  private init(localStore: LocalStore? = nil) {
    self.localStore = localStore ?? LocalStore.shared
  }

  // MARK: - Entitlement Cache

  /// Get cached entitlement for a user (may be expired)
  /// - Parameter userId: User ID to get cache for
  /// - Returns: LocalEntitlementCache if found, nil otherwise
  func getCached(for userId: String) -> LocalEntitlementCache? {
    let context = localStore.mainContext
    let descriptor = FetchDescriptor<LocalEntitlementCache>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try? context.fetch(descriptor).first
  }

  /// Save entitlement to cache with TTL
  /// - Parameters:
  ///   - entitlement: Server entitlement to cache
  ///   - userId: User ID to cache for
  func cache(_ entitlement: ServerEntitlement, for userId: String) async throws {
    try await localStore.storeActor.upsertEntitlementCache(
      userId: userId,
      entitlement: entitlement
    )
    logger.info(
      "Cached entitlement for user \(userId.prefix(8)): tier=\(entitlement.tier.rawValue)")
  }

  /// Clear cache on logout
  /// - Parameter userId: User ID to clear cache for
  func clearCache(for userId: String) async throws {
    try await localStore.storeActor.deleteEntitlementCache(userId: userId)
    logger.info("Cleared entitlement cache for user \(userId.prefix(8))")
  }

  // MARK: - JWS Upload Queue

  /// Add JWS upload to persistent queue
  /// - Parameter upload: The pending upload to queue
  func enqueuePendingUpload(_ upload: LocalPendingJWSUpload) async throws {
    try await localStore.storeActor.insertPendingJWSUpload(upload)
    logger.info("Enqueued JWS upload: \(upload.transactionId)")
  }

  /// Get pending uploads ready for retry (nextAttemptAt <= now)
  /// - Returns: Array of uploads ready to be sent
  func getPendingUploads() -> [LocalPendingJWSUpload] {
    let context = localStore.mainContext
    let now = Date()
    let descriptor = FetchDescriptor<LocalPendingJWSUpload>(
      predicate: #Predicate { $0.nextAttemptAt <= now },
      sortBy: [SortDescriptor(\.createdAt)]
    )
    return (try? context.fetch(descriptor)) ?? []
  }

  /// Get all pending uploads (including those scheduled for future)
  /// Used to check if there are uploads waiting for retry
  /// - Returns: Array of all pending uploads
  func getAllPendingUploads() -> [LocalPendingJWSUpload] {
    let context = localStore.mainContext
    let descriptor = FetchDescriptor<LocalPendingJWSUpload>(
      sortBy: [SortDescriptor(\.createdAt)]
    )
    return (try? context.fetch(descriptor)) ?? []
  }

  /// Remove successfully uploaded JWS from queue
  /// - Parameter transactionId: Transaction ID of the upload to remove
  func removePendingUpload(transactionId: String) async throws {
    try await localStore.storeActor.deletePendingJWSUpload(transactionId: transactionId)
    logger.info("Removed pending JWS upload: \(transactionId)")
  }

  /// Schedule next retry for a failed upload
  /// - Parameter transactionId: Transaction ID of the upload to schedule
  func schedulePendingUploadRetry(transactionId: String) async throws {
    try await localStore.storeActor.schedulePendingJWSUploadRetry(transactionId: transactionId)
  }
}
