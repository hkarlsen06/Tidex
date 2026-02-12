import Combine
import Foundation
import SwiftUI

/// Shared month context that synchronizes the displayed month across multiple tabs
/// Used by Dashboard, Shifts, and AddShift views to maintain consistent month navigation
///
/// When the user navigates to a different month in any of these tabs, all other tabs
/// will display the same month when switched to.
@MainActor
final class SharedMonthContext: ObservableObject {

  // MARK: - Shared Instance

  static let shared = SharedMonthContext()

  private static let gregorianCalendar = Calendar(identifier: .gregorian)

  // MARK: - Published State

  /// Currently displayed year
  @Published private(set) var displayYear: Int

  /// Currently displayed month (1-12)
  @Published private(set) var displayMonth: Int

  /// Direction of last navigation (for animations)
  @Published private(set) var navigationDirection: MonthNavigationDirection?

  /// Pre-selected date for AddShift (ISO format, e.g., "2025-01-15")
  /// Set when navigating from an empty calendar day to the Add tab
  /// AddShiftViewModel consumes and clears this on load
  @Published var preselectedDate: String?

  /// Whether the currently displayed month has any shift conflicts
  /// Updated by ShiftsViewModel when conflicts are detected
  @Published var hasConflictsInMonth: Bool = false

  /// Emits exactly one event per month navigation to avoid transient year/month pairs.
  private let monthChangedSubject = PassthroughSubject<(year: Int, month: Int), Never>()

  // MARK: - Computed Properties

  /// Whether viewing the current (real) month
  var isCurrentMonth: Bool {
    let current = Date.currentYearMonth()
    return displayYear == current.year && displayMonth == current.month
  }

  /// Computed month name for immediate display (localized)
  var displayMonthName: String {
    var components = DateComponents()
    components.year = displayYear
    components.month = displayMonth
    components.day = 1
    guard let date = Self.gregorianCalendar.date(from: components) else { return "" }
    return FormatterCache.monthNameFormatter(locale: .current).string(from: date)
  }

  /// Combined publisher for year and month changes
  var monthChanged: AnyPublisher<(year: Int, month: Int), Never> {
    monthChangedSubject
      .prepend((year: displayYear, month: displayMonth))
      .eraseToAnyPublisher()
  }

  // MARK: - Initialization

  private init() {
    // Initialize to current month
    let current = Date.currentYearMonth()
    self.displayYear = current.year
    self.displayMonth = current.month
  }

  // MARK: - Navigation Methods

  /// Navigate to the previous month
  func goToPreviousMonth() {
    navigationDirection = .previous
    SoundManager.shared.play("tap")

    if displayMonth == 1 {
      displayMonth = 12
      displayYear -= 1
    } else {
      displayMonth -= 1
    }

    monthChangedSubject.send((year: displayYear, month: displayMonth))
  }

  /// Navigate to the next month
  func goToNextMonth() {
    navigationDirection = .next
    SoundManager.shared.play("tap")

    if displayMonth == 12 {
      displayMonth = 1
      displayYear += 1
    } else {
      displayMonth += 1
    }

    monthChangedSubject.send((year: displayYear, month: displayMonth))
  }

  /// Reset to current month
  func goToCurrentMonth() {
    let current = Date.currentYearMonth()

    // Determine navigation direction for animation
    let displayedMonthIndex = displayYear * 12 + displayMonth
    let currentMonthIndex = current.year * 12 + current.month

    if displayedMonthIndex < currentMonthIndex {
      navigationDirection = .next
    } else if displayedMonthIndex > currentMonthIndex {
      navigationDirection = .previous
    } else {
      // Already on current month - no navigation needed
      return
    }

    displayYear = current.year
    displayMonth = current.month
    monthChangedSubject.send((year: displayYear, month: displayMonth))
  }

  /// Navigate to a specific year and month
  /// - Parameters:
  ///   - year: Target year
  ///   - month: Target month (1-12)
  func navigateTo(year: Int, month: Int) {
    guard month >= 1 && month <= 12 else { return }

    // Determine direction for animation
    let currentIndex = displayYear * 12 + displayMonth
    let targetIndex = year * 12 + month

    if targetIndex > currentIndex {
      navigationDirection = .next
    } else if targetIndex < currentIndex {
      navigationDirection = .previous
    } else {
      // Same month - no navigation needed
      return
    }

    displayYear = year
    displayMonth = month
    monthChangedSubject.send((year: displayYear, month: displayMonth))
  }

  /// Reset to current month without animation (for initial load)
  func resetToCurrentMonth() {
    let current = Date.currentYearMonth()
    navigationDirection = nil
    displayYear = current.year
    displayMonth = current.month
    monthChangedSubject.send((year: displayYear, month: displayMonth))
  }
}
