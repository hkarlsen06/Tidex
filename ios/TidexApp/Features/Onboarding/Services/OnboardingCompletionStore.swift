import Foundation
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "OnboardingCompletionStore")

/// Records that a user finished onboarding on this device.
///
/// The `finishedOnboarding` auth metadata update needs a network, so onboarding does not wait
/// for it. The local flag is what lets a user in, and the metadata update is queued and retried.
@MainActor
enum OnboardingCompletionStore {
  typealias MetadataUpdater = () async throws -> Void

  nonisolated private static func completedKey(_ userId: String) -> String {
    "onboardingCompletedLocally.\(userId)"
  }

  nonisolated private static func pendingKey(_ userId: String) -> String {
    "onboardingMetadataPending.\(userId)"
  }

  /// True once this user finished onboarding on this device, even if the server does not know yet.
  nonisolated static func isCompletedLocally(
    userId: String, defaults: UserDefaults = .standard
  ) -> Bool {
    defaults.bool(forKey: completedKey(userId))
  }

  nonisolated static func hasPendingMetadataUpdate(
    userId: String, defaults: UserDefaults = .standard
  ) -> Bool {
    defaults.bool(forKey: pendingKey(userId))
  }

  /// Marks onboarding finished locally and queues the metadata update.
  /// Call `retryPendingMetadataIfNeeded` afterwards to send it.
  nonisolated static func markCompleted(userId: String, defaults: UserDefaults = .standard) {
    guard !isCompletedLocally(userId: userId, defaults: defaults) else { return }
    defaults.set(true, forKey: completedKey(userId))
    defaults.set(true, forKey: pendingKey(userId))
  }

  /// Sends the queued metadata update. Call it for the signed-in user on launch, foreground and reconnect.
  static func retryPendingMetadataIfNeeded(
    userId: String,
    defaults: UserDefaults = .standard,
    updateMetadata: MetadataUpdater = pushFinishedMetadata
  ) async {
    guard hasPendingMetadataUpdate(userId: userId, defaults: defaults) else { return }

    do {
      try await updateMetadata()
      defaults.removeObject(forKey: pendingKey(userId))
      logger.info("Marked onboarding as finished in user metadata")
    } catch {
      logger.warning(
        "Onboarding metadata update queued for retry: \(error.localizedDescription)")
    }
  }

  static func pushFinishedMetadata() async throws {
    _ = try await supabase.auth.update(
      user: UserAttributes(data: ["finishedOnboarding": .bool(true)])
    )
  }
}
