import Foundation
import SwiftData
import os.log

extension LocalStoreActor {

  // MARK: - Sync State Operations

  /// Get or create sync state for a user
  internal func getOrCreateSyncState(userId: String) throws -> LocalSyncState {
    let descriptor = FetchDescriptor<LocalSyncState>(
      predicate: #Predicate { $0.userId == userId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      return existing
    }

    let newState = LocalSyncState(userId: userId)
    modelContext.insert(newState)
    try modelContext.save()
    return newState
  }

  /// Get sync state for a user (returns nil if not found)
  internal func getSyncState(userId: String) throws -> LocalSyncState? {
    let descriptor = FetchDescriptor<LocalSyncState>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor).first
  }

  // MARK: - Conflict Helpers

  // Get all records with conflicts for a user
  // swiftlint:disable:next function_body_length
  internal func getConflicts(userId: String) throws -> (
    jobs: [LocalJob],
    shifts: [LocalUserShift],
    events: [LocalEvent],
    recurringShifts: [LocalRecurringShift],
    wageSnapshots: [LocalWageSnapshot],
    payrollAdjustments: [LocalPayrollAdjustment],
    settings: LocalUserSettings?
  ) {
    let jobsDescriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId && job.syncStatusRaw == "conflict"
      }
    )
    let jobs = try modelContext.fetch(jobsDescriptor)

    let shiftsDescriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { shift in
        shift.userId == userId && shift.syncStatusRaw == "conflict"
      }
    )
    let shifts = try modelContext.fetch(shiftsDescriptor)

    let eventsDescriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { event in
        event.userId == userId && event.syncStatusRaw == "conflict"
      }
    )
    let events = try modelContext.fetch(eventsDescriptor)

    let recurringDescriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { shift in
        shift.userId == userId && shift.syncStatusRaw == "conflict"
      }
    )
    let recurringShifts = try modelContext.fetch(recurringDescriptor)

    let snapshotsDescriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { snapshot in
        snapshot.userId == userId && snapshot.syncStatusRaw == "conflict"
      }
    )
    let wageSnapshots = try modelContext.fetch(snapshotsDescriptor)

    let adjustmentsDescriptor = FetchDescriptor<LocalPayrollAdjustment>(
      predicate: #Predicate { adjustment in
        adjustment.userId == userId && adjustment.syncStatusRaw == "conflict"
      }
    )
    let payrollAdjustments = try modelContext.fetch(adjustmentsDescriptor)

    let settingsDescriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { settings in
        settings.userId == userId && settings.syncStatusRaw == "conflict"
      }
    )
    let settings = try modelContext.fetch(settingsDescriptor).first

    return (jobs, shifts, events, recurringShifts, wageSnapshots, payrollAdjustments, settings)
  }

  /// Check if user has any conflicts
  internal func hasConflicts(userId: String) throws -> Bool {
    let conflicts = try getConflicts(userId: userId)
    return !conflicts.jobs.isEmpty || !conflicts.shifts.isEmpty
      || !conflicts.events.isEmpty || !conflicts.recurringShifts.isEmpty
      || !conflicts.wageSnapshots.isEmpty || !conflicts.payrollAdjustments.isEmpty
      || conflicts.settings != nil
  }

  /// Whether notification preferences have edits that were not pushed.
  /// The repository normalizes the user id to upper case.
  internal func hasDirtyNotificationPreferences(userId: String) throws -> Bool {
    let normalizedUserId = userId.uppercased()
    var descriptor = FetchDescriptor<LocalNotificationPreferences>(
      predicate: #Predicate { preferences in
        preferences.userId == normalizedUserId && preferences.syncStatusRaw == "dirty"
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  /// Whether the user has chat messages that the server has not accepted.
  /// A message in the sending or failed state exists only on this device.
  internal func hasUnsentMessages(userId: String) throws -> Bool {
    var descriptor = FetchDescriptor<LocalMessage>(
      predicate: #Predicate { message in
        message.viewerUserId == userId
          && (message.sendStateRaw == "sending" || message.sendStateRaw == "failed")
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  /// Whether signing out would delete data that never reached the server.
  /// This covers dirty rows, conflicted rows, notification preferences and unsent chat messages.
  /// A conflicted row holds a local edit or a never pushed row until the user resolves it.
  internal func hasPendingChanges(userId: String) throws -> Bool {
    try hasDirtyJobs(userId: userId)
      || hasDirtyUserShifts(userId: userId)
      || hasDirtyEvents(userId: userId)
      || hasDirtyRecurringShifts(userId: userId)
      || hasDirtyWageSnapshots(userId: userId)
      || hasDirtyPayrollAdjustments(userId: userId)
      || hasDirtyUserSettings(userId: userId)
      || hasDirtyNotificationPreferences(userId: userId)
      || hasConflicts(userId: userId)
      || hasUnsentMessages(userId: userId)
  }

  /// Count total conflicts for a user
  internal func countConflicts(userId: String) throws -> Int {
    let conflicts = try getConflicts(userId: userId)
    return conflicts.jobs.count + conflicts.shifts.count + conflicts.events.count
      + conflicts.recurringShifts.count
      + conflicts.wageSnapshots.count
      + conflicts.payrollAdjustments.count
      + (conflicts.settings != nil ? 1 : 0)
  }

  /// Update sync state with a closure
  internal func updateSyncState(userId: String, update: (LocalSyncState) -> Void) {
    let descriptor = FetchDescriptor<LocalSyncState>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let state = try? modelContext.fetch(descriptor).first else {
      return
    }

    update(state)
    try? modelContext.save()
  }
}
