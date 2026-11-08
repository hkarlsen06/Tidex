import Foundation
import Observation
import Synchronization
import os.log

extension SyncCoordinator {

  // MARK: - Notification Preferences Pull

  func pullNotificationPreferencesPage(
    userId: String, page: SyncPullPage<SyncNotificationPreferencesRow>
  ) async throws
    -> PagePullResult
  {
    try Task.checkCancellation()
    let rows = page.rows

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        cursor: page.cursor,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let pageStartTime = Date()

    // Apply each row to local storage using the repository
    for row in rows {
      let serverUpdatedAt = parseUpdatedAt(
        row.updated_at, table: .notificationPreferences, id: row.user_id)
      await MainActor.run {
        NotificationPreferencesRepository.shared
          .saveFromServer(row: row.toNotificationPreferencesRow(), serverUpdatedAt: serverUpdatedAt)
      }
    }

    let duration = Date().timeIntervalSince(pageStartTime)
    syncCoordinatorLogger.info(
      "notification_preferences: page complete - \(rows.count) rows in \(String(format: "%.2f", duration))s"
    )

    return PagePullResult(
      rowsProcessed: rows.count,
      cursor: page.cursor,
      newConflicts: 0,
      autoMerged: 0,
      hasMore: !page.done
    )
  }

  // MARK: - Notification Preferences Push

  func pushNotificationPreferences(userId: String) async throws -> TablePushResult {
    struct NotificationPreferencesPayload {
      let shiftRemindersEnabled: Bool
      let shiftReminderMinutesArray: [Int]
      let sharedShiftsEnabled: Bool
      let localUpdatedAt: Date
    }

    // Get dirty preferences (if any)
    let preferences = await MainActor.run(resultType: NotificationPreferencesPayload?.self) {
      guard let dirty = NotificationPreferencesRepository.shared.getDirtyPreferences(for: userId)
      else {
        return nil
      }
      return NotificationPreferencesPayload(
        shiftRemindersEnabled: dirty.shiftRemindersEnabled,
        shiftReminderMinutesArray: dirty.shiftReminderMinutesArray,
        sharedShiftsEnabled: dirty.sharedShiftsEnabled,
        localUpdatedAt: dirty.localUpdatedAt
      )
    }

    guard let preferences else {
      return TablePushResult(
        table: .notificationPreferences, rowsPushed: 0, newConflicts: 0, rebased: 0)
    }

    // iOS is the source of truth, so every push sends all fields.
    let returnedRow: SyncNotificationPreferencesRow =
      try await SyncConvex.upsertNotificationPreferences(
        owner: userId,
        shiftRemindersEnabled: preferences.shiftRemindersEnabled,
        shiftReminderMinutesArray: preferences.shiftReminderMinutesArray,
        sharedShiftsEnabled: preferences.sharedShiftsEnabled)

    let serverUpdatedAt = parseUpdatedAt(
      returnedRow.updated_at, table: .notificationPreferences, id: userId)
    await MainActor.run {
      // Keeps the preferences dirty when the user edited them during the push.
      NotificationPreferencesRepository.shared.markClean(
        for: userId,
        serverUpdatedAt: serverUpdatedAt,
        pushedLocalUpdatedAt: preferences.localUpdatedAt
      )
    }
    syncCoordinatorLogger.debug("Pushed notification preferences for user \(userId.prefix(8))")
    return TablePushResult(
      table: .notificationPreferences, rowsPushed: 1, newConflicts: 0, rebased: 0)
  }
}
