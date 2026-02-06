import Foundation
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "JWSUploadWorker")

// MARK: - Request/Response Models

/// Request body for apple-verify-purchase edge function
/// CRITICAL: Must include jwsRepresentation - this is the actual receipt!
private struct JWSUploadRequest: Encodable {
  let jws: String  // The JWS receipt - CRITICAL!
  let transactionId: String
  let originalTransactionId: String
  let productId: String
  let environment: String
  let priceDisplay: String?

  init(from upload: LocalPendingJWSUpload) {
    self.jws = upload.jwsRepresentation  // The actual receipt payload
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

/// Single-flight upload worker that processes the persisted JWS queue
/// Uses exponential backoff for retries (30s, 60s, 120s, 240s, max 10min)
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

  /// Upload a JWS immediately and wait for completion
  /// Use this for purchase flow where we need to wait for server to have the subscription
  /// - Parameter upload: The pending upload to process
  /// - Returns: true if upload succeeded, false otherwise
  func uploadImmediately(_ upload: LocalPendingJWSUpload) async -> Bool {
    logger.info("Uploading JWS immediately for transaction: \(upload.transactionId)")

    do {
      try await uploadToServer(upload)
      // Remove from queue if it was also queued
      try? await repository.removePendingUpload(transactionId: upload.transactionId)
      logger.info("Immediate upload succeeded for: \(upload.transactionId)")

      // Refresh entitlement from server so we have the latest tier
      do {
        try await EntitlementService.shared.refreshFromServer(userId: upload.userId)
        logger.info("Entitlement refreshed after immediate upload")
      } catch {
        logger.warning("Failed to refresh entitlement after upload: \(error.localizedDescription)")
        // Still return true - the upload succeeded, just couldn't refresh
      }

      return true
    } catch {
      logger.error("Immediate upload failed: \(error.localizedDescription)")
      // Queue it for retry via the background worker
      try? await repository.enqueuePendingUpload(upload)
      processQueue()
      return false
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
            do {
              try await EntitlementService.shared.refreshFromServer(userId: userId)
            } catch {
              logger.warning(
                "Failed to refresh entitlement for \(userId.prefix(8)): \(error.localizedDescription)"
              )
            }
          }

          return
        }

        // Find the earliest scheduled retry and sleep until then
        // This ensures backoff retries happen even if app stays open
        guard let earliestRetry = allPending.map(\.nextAttemptAt).min() else { continue }
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
          logger.warning(
            "Max attempts reached for upload \(upload.transactionId), removing from queue")
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
          logger.error(
            "Upload failed for \(upload.transactionId) (attempt \(upload.attemptCount + 1)): \(error.localizedDescription)"
          )
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

    // Call the edge function - Supabase Swift SDK decodes directly to Decodable type
    // See: https://supabase.com/docs/reference/swift/functions-invoke
    let uploadResponse: JWSUploadResponse
    do {
      uploadResponse = try await supabase.functions.invoke(
        "apple-verify-purchase",
        options: FunctionInvokeOptions(body: requestBody)
      )
    } catch {
      logger.error("Edge function call failed: \(error.localizedDescription)")
      throw PurchaseError.networkError(underlying: error)
    }

    // Check for explicit error from the edge function
    if let errorMessage = uploadResponse.error {
      logger.error("Server returned error: \(errorMessage)")
      throw PurchaseError.networkError(
        underlying: NSError(
          domain: "JWSUpload",
          code: -2,
          userInfo: [NSLocalizedDescriptionKey: errorMessage]
        ))
    }

    // Verify success
    guard uploadResponse.isSuccess else {
      throw PurchaseError.networkError(
        underlying: NSError(
          domain: "JWSUpload",
          code: -3,
          userInfo: [NSLocalizedDescriptionKey: "Server did not confirm success"]
        ))
    }
  }
}
