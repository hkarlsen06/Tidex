// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface no_empty_block required_deinit
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable sorted_enum_cases switch_case_on_newline
import Foundation
import Observation

/// Sync indicator status states for UI display
/// Named to avoid collision with SyncStatus in SyncTypes.swift (used for record sync state)
enum SyncIndicatorStatus: Equatable {
  case synced
  case syncing
  case failed(message: String, lastSync: Date?)
  case offline

  var isIdle: Bool {
    switch self {
    case .synced: return true
    default: return false
    }
  }

  var showsIndicator: Bool {
    switch self {
    case .synced: return false
    default: return true
    }
  }
}

/// Observable manager for app-wide sync status
/// Used by views to display sync state indicators
@MainActor
@Observable
final class SyncStatusManager {
  static let shared = SyncStatusManager()

  private(set) var status: SyncIndicatorStatus = .synced
  private(set) var lastSuccessfulSync: Date?
  private(set) var lastSuccessfulSyncSummary: SyncCompletionSummary?

  init() {}

  // MARK: - Status Updates

  /// Called when sync starts. Background syncs keep an offline status so the pill does not flicker.
  func syncStarted(isBackground: Bool = false) {
    if isBackground, status == .offline { return }
    status = .syncing
  }

  /// Called when sync completes successfully
  func syncSucceeded(summary: SyncCompletionSummary? = nil) {
    let completedAt = summary?.completedAt ?? Date()
    lastSuccessfulSync = completedAt
    lastSuccessfulSyncSummary = summary
    status = .synced
  }

  /// Called when sync fails
  func syncFailed(message: String) {
    status = .failed(message: message, lastSync: lastSuccessfulSync)
  }

  /// Set status to offline (e.g., no network)
  func setOffline() {
    status = .offline
  }

  /// Called when the network returns. Drops a stale offline status and lets the next sync result decide.
  func connectivityRestored() {
    if status == .offline {
      status = .synced
    }
  }

  /// Clear failed status (e.g., user dismissed banner)
  func clearFailure() {
    if case .failed = status {
      status = .synced
    }
  }

  /// Reset all state (e.g., on logout)
  func reset() {
    status = .synced
    lastSuccessfulSync = nil
    lastSuccessfulSyncSummary = nil
  }
}
