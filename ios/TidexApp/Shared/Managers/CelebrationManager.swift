import Combine
import Foundation
import SwiftUI

/// Manager for tracking and displaying celebration effects when shifts are added
/// Handles passing newly added shift dates from AddShift tab to Shifts tab
@MainActor
final class CelebrationManager: ObservableObject {

  // MARK: - Singleton

  static let shared = CelebrationManager()

  // MARK: - Published State

  /// Set of newly added shift dates (ISO strings) that should be highlighted
  @Published private(set) var newlyAddedDates: Set<String> = []

  /// Whether confetti should be shown
  @Published private(set) var shouldShowConfetti: Bool = false

  /// The month (year, month) where confetti should originate
  /// This is the month the user was viewing when they hit the add button
  @Published private(set) var confettiOriginMonth: (year: Int, month: Int)?

  // MARK: - Private State

  /// Timer for auto-clearing the celebration state
  private var clearTimer: Timer?

  /// Duration to show highlights before clearing (matches web: 3 seconds)
  private static let highlightDuration: TimeInterval = 3.0

  // MARK: - Initialization

  private init() {}

  // MARK: - Public Methods

  /// Trigger celebration for newly added shifts
  /// - Parameters:
  ///   - dates: ISO date strings of the newly added shifts
  ///   - originMonth: The month the user was in when they hit add (year, month)
  func celebrate(dates: Set<String>, originMonth: (year: Int, month: Int)) {
    guard !dates.isEmpty else { return }

    // Cancel any existing timer
    clearTimer?.invalidate()

    // Set the new celebration state
    newlyAddedDates = dates
    confettiOriginMonth = originMonth
    shouldShowConfetti = true

    // Start timer to clear celebration after duration
    clearTimer = Timer.scheduledTimer(withTimeInterval: Self.highlightDuration, repeats: false) {
      [weak self] _ in
      Task { @MainActor in
        self?.clearCelebration()
      }
    }
  }

  /// Manually clear the celebration state
  func clearCelebration() {
    clearTimer?.invalidate()
    clearTimer = nil

    withAnimation(.easeOut(duration: 0.3)) {
      newlyAddedDates.removeAll()
      shouldShowConfetti = false
      confettiOriginMonth = nil
    }
  }

  /// Mark confetti as shown (don't show again on re-render)
  func confettiDidShow() {
    shouldShowConfetti = false
  }

  /// Check if a specific date is newly added
  func isNewlyAdded(_ dateISO: String) -> Bool {
    newlyAddedDates.contains(dateISO)
  }

  /// Check if confetti should show for the given month
  func shouldShowConfetti(forYear year: Int, month: Int) -> Bool {
    guard shouldShowConfetti,
      let origin = confettiOriginMonth
    else { return false }
    return origin.year == year && origin.month == month
  }
}
