import Foundation
import SwiftUI
import Combine

/// Shared month context that synchronizes the displayed month across multiple tabs
/// Used by Dashboard, Shifts, and AddShift views to maintain consistent month navigation
///
/// When the user navigates to a different month in any of these tabs, all other tabs
/// will display the same month when switched to.
@MainActor
final class SharedMonthContext: ObservableObject {

    // MARK: - Shared Instance

    static let shared = SharedMonthContext()

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
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        formatter.locale = Locale(identifier: LocalizationManager.shared.currentLocale.localeIdentifier)
        return formatter.string(from: date)
    }

    /// Combined publisher for year and month changes
    var monthChanged: AnyPublisher<(year: Int, month: Int), Never> {
        Publishers.CombineLatest($displayYear, $displayMonth)
            .map { (year: $0, month: $1) }
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

        if displayMonth == 1 {
            displayMonth = 12
            displayYear -= 1
        } else {
            displayMonth -= 1
        }
    }

    /// Navigate to the next month
    func goToNextMonth() {
        navigationDirection = .next

        if displayMonth == 12 {
            displayMonth = 1
            displayYear += 1
        } else {
            displayMonth += 1
        }
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
    }

    /// Reset to current month without animation (for initial load)
    func resetToCurrentMonth() {
        let current = Date.currentYearMonth()
        navigationDirection = nil
        displayYear = current.year
        displayMonth = current.month
    }
}
