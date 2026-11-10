// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_empty_block no_magic_numbers required_deinit type_contents_order
import Foundation
import Observation
import SwiftUI

/// Highlights newly added shift dates in the Shifts tab for a few seconds, and holds the
/// first-shift confetti until `MainTabView` plays it.
@MainActor
@Observable
final class CelebrationManager {

  // MARK: - Singleton

  static let shared = CelebrationManager()

  // MARK: - Observed State

  /// Set of newly added shift dates (ISO strings) that should be highlighted
  private(set) var newlyAddedDates: Set<String> = []

  /// Stays set until a host consumes it, because a calendar import from onboarding finishes
  /// before `MainTabView` exists.
  private(set) var isFirstShiftCelebrationPending = false

  // MARK: - Private State

  /// Timer for auto-clearing the celebration state
  @ObservationIgnored private var clearTimer: Timer?

  /// Duration to show highlights before clearing (matches web: 3 seconds)
  private static let highlightDuration: TimeInterval = 3.0

  // MARK: - Initialization

  private init() {}

  // MARK: - Public Methods

  /// Highlight newly added shifts
  /// - Parameter dates: ISO date strings of the newly added shifts
  func celebrate(dates: Set<String>) {
    guard !dates.isEmpty else { return }

    // Cancel any existing timer
    clearTimer?.invalidate()

    // Set the new celebration state
    newlyAddedDates = dates

    // Start timer to clear celebration after duration
    clearTimer = Timer.scheduledTimer(withTimeInterval: Self.highlightDuration, repeats: false) {
      [weak self] _ in
      Task { @MainActor in
        self?.clearCelebration()
      }
    }
  }

  /// Whether a save for this user would add their first shift. Call it before the first write.
  /// Until the first sync finishes this is false, so a returning user on a new device is not new.
  func isFirstShiftSave(for userId: String) -> Bool {
    !ShiftsRepository.shared.hasAnyShifts(
      for: userId,
      initialSyncComplete: SyncStatusManager.shared.hasCompletedInitialSync(for: userId)
    )
  }

  func celebrateFirstShift() {
    isFirstShiftCelebrationPending = true
  }

  /// Returns whether a first-shift celebration was pending, and clears it.
  func consumeFirstShiftCelebration() -> Bool {
    defer { isFirstShiftCelebrationPending = false }
    return isFirstShiftCelebrationPending
  }

  func resetForUserChange() {
    clearTimer?.invalidate()
    clearTimer = nil
    newlyAddedDates = []
    isFirstShiftCelebrationPending = false
  }

  /// Manually clear the celebration state
  func clearCelebration() {
    clearTimer?.invalidate()
    clearTimer = nil

    withAnimation(.easeOut(duration: 0.3)) {
      newlyAddedDates.removeAll()
    }
  }
}
