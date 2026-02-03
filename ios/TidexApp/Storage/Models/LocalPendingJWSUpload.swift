import Foundation
import SwiftData

// MARK: - Local Pending JWS Upload

/// SwiftData model for persisting JWS uploads that need to be sent to the server
/// Survives app kill and handles retry with exponential backoff
///
/// CRITICAL: Uses `transactionId` as unique key to prevent duplicate queue entries.
/// The same transaction can get queued multiple times from:
/// - Purchase flow completion
/// - Transaction listener receiving updates
/// - App relaunch processing currentEntitlements
@Model
final class LocalPendingJWSUpload {
    // MARK: - Primary Key

    /// Transaction ID from StoreKit (unique to prevent duplicate entries)
    /// Using this as the unique key ensures only one queue entry per transaction
    @Attribute(.unique)
    var transactionId: String

    // MARK: - Upload Data

    /// User who made the purchase
    var userId: String

    /// The JWS representation of the transaction (the actual receipt)
    /// This is the critical payload that gets sent to the server
    var jwsRepresentation: String

    /// Original transaction ID (for subscription renewals, this links to the original purchase)
    var originalTransactionId: String

    /// Product ID that was purchased
    var productId: String

    /// StoreKit environment ("Sandbox" or "Production")
    var environment: String

    /// Localized price display from StoreKit (optional - may be nil if products weren't loaded)
    var priceDisplay: String?

    // MARK: - Retry Metadata

    /// When this upload was first queued
    var createdAt: Date

    /// Number of upload attempts made
    var attemptCount: Int

    /// When the next retry should be attempted
    var nextAttemptAt: Date

    // MARK: - Initialization

    init(
        userId: String,
        jwsRepresentation: String,
        transactionId: String,
        originalTransactionId: String,
        productId: String,
        environment: String,
        priceDisplay: String?
    ) {
        self.transactionId = transactionId
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

    /// Required empty initializer for SwiftData
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

    // MARK: - Retry Logic

    /// Calculate next retry with exponential backoff
    /// Delays: 30s, 60s, 120s, 240s, 480s, max 10min (600s)
    func scheduleNextRetry() {
        attemptCount += 1
        let baseDelay: Double = 30.0
        let maxDelay: Double = 600.0
        let delay = min(baseDelay * pow(2.0, Double(attemptCount - 1)), maxDelay)
        nextAttemptAt = Date().addingTimeInterval(delay)
    }
}
