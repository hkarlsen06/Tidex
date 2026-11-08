import Combine
import Foundation
import Observation
import UIKit
import os.log

extension ShiftsViewModel {

  // MARK: - Memory Management

  /// Handle memory warning by clearing the cache
  func handleMemoryWarning() {
    kScheduleLogger.warning(
      "⚠️ Memory warning received - clearing month cache (\(self.monthCache.count) entries)"
    )
    monthCache.removeAll()
    cancelPrefetchTasks()
  }

  // MARK: - Deep Linking

  /// Handle shift reminder notification tap - navigate to the shift's date
  func handleShiftReminderTap(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
      let shiftDateString = userInfo["shift_date"] as? String
    else {
      kScheduleLogger.warning("Shift reminder tap missing shift_date")
      return
    }

    kScheduleLogger.info("Deep linking to shift date: \(shiftDateString)")

    // Parse the shift date (format: "yyyy-MM-dd")
    guard let shiftDate = kScheduleISODateFormatter.date(from: shiftDateString) else {
      kScheduleLogger.warning("Failed to parse shift date: \(shiftDateString)")
      return
    }

    let calendar = Calendar.gregorianCurrent
    let year = calendar.component(.year, from: shiftDate)
    let month = calendar.component(.month, from: shiftDate)

    // Navigate to the month and select the date
    monthContext.navigateTo(year: year, month: month)
    selectedDates = [shiftDateString]
  }

  /// Evict least recently used cache entries if over limit
  func evictCacheIfNeeded() {
    guard monthCache.count > Self.maxCacheSize else {
      return
    }

    // Sort by last accessed time (oldest first)
    let sortedKeys = monthCache.keys.sorted { key1, key2 in
      guard let entry1 = monthCache[key1], let entry2 = monthCache[key2] else {
        return false
      }
      return entry1.lastAccessed < entry2.lastAccessed
    }

    // Remove oldest entries until we're under the limit
    let entriesToRemove = monthCache.count - Self.maxCacheSize
    for i in 0..<entriesToRemove {
      let key = sortedKeys[i]
      monthCache.removeValue(forKey: key)
      kScheduleLogger.info("🗑️ Evicted cache entry: \(key)")
    }
  }

  // MARK: - Month Navigation

  /// Navigate to the previous month (non-blocking)
  /// Delegates to SharedMonthContext - data reload happens via subscription
  func goToPreviousMonth() {
    monthContext.goToPreviousMonth()
  }

  /// Navigate to the next month (non-blocking)
  /// Delegates to SharedMonthContext - data reload happens via subscription
  func goToNextMonth() {
    monthContext.goToNextMonth()
  }

  /// Reset to current month (non-blocking)
  /// Delegates to SharedMonthContext - data reload happens via subscription
  func goToCurrentMonth() {
    monthContext.goToCurrentMonth()
  }
}
