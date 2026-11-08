import Foundation
import SwiftData
import os.log

extension LocalStoreActor {

  /// Upsert a user shift from server data
  internal func upsertUserShift(_ shift: LocalUserShift) throws {
    let shiftId = shift.id
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == shiftId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      // Update existing - copy all fields
      existing.jobId = shift.jobId
      existing.shiftDate = shift.shiftDate
      existing.startTime = shift.startTime
      existing.endTime = shift.endTime
      existing.customPauseWindows = shift.customPauseWindows
      existing.customSupplements = shift.customSupplements
      existing.serverUpdatedAt = shift.serverUpdatedAt
      existing.serverRevision = shift.serverRevision
      existing.serverDeletedAt = shift.serverDeletedAt
      existing.syncStatusRaw = shift.syncStatusRaw
      existing.dirtyFields = shift.dirtyFields
      existing.lastSyncedSnapshot = shift.lastSyncedSnapshot
      existing.localUpdatedAt = shift.localUpdatedAt
      existing.conflictServerSnapshot = shift.conflictServerSnapshot
    } else {
      // Insert new
      modelContext.insert(shift)
    }
  }

  /// Get user shift by ID
  internal func getUserShift(id: String) throws -> LocalUserShift? {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  /// Get all user shifts for a user (including soft-deleted for sync)
  internal func getAllUserShifts(userId: String) throws -> [LocalUserShift] {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor)
  }

  /// Get dirty user shifts that need to be pushed
  internal func getDirtyUserShifts(userId: String) throws -> [LocalUserShift] {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { shift in
        shift.userId == userId
          && (shift.syncStatusRaw == "dirty" || shift.syncStatusRaw == "pendingDelete"
            // Include conflict records that were never synced (serverRevision=0)
            // These are new local records that failed initial sync and need INSERT
            || (shift.syncStatusRaw == "conflict" && shift.serverRevision == 0))
      }
    )
    return try modelContext.fetch(descriptor)
  }

  internal func hasDirtyUserShifts(userId: String) throws -> Bool {
    var descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { shift in
        shift.userId == userId
          && (shift.syncStatusRaw == "dirty" || shift.syncStatusRaw == "pendingDelete"
            || (shift.syncStatusRaw == "conflict" && shift.serverRevision == 0))
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  // MARK: - Local User Shift Write Operations

  internal func createUserShift(
    id: String? = nil,
    userId: String,
    jobId: String? = nil,
    shiftDate: Date,
    startTime: String,
    endTime: String,
    note: String? = nil,
    customPauseWindows: CustomPauseWindows? = nil,
    customSupplements: CustomSupplementsData?
  ) throws -> ShiftRow {
    let resolvedId = id ?? UUID().lowercasedString

    // Idempotent create path: when a deterministic shift ID is provided and already exists,
    // return the existing local row instead of creating a duplicate.
    if let existing = try getUserShift(id: resolvedId), existing.userId == userId {
      return existing.toShiftRow()
    }

    let now = Date()

    let pauseWindowsData = PauseWindowSupport.normalize(customPauseWindows).flatMap { value in
      try? kCanonicalJSONEncoder.encode(value)
    }
    let supplementsData = customSupplements.flatMap { try? kCanonicalJSONEncoder.encode($0) }
    let normalizedNote = ShiftNoteSupport.normalize(note)

    let dateFormatter = isoDateFormatter
    let shiftDateString = dateFormatter.string(from: shiftDate)

    let snapshot = UserShiftServerSnapshot(
      jobId: jobId,
      shiftDate: shiftDateString,
      startTime: startTime,
      endTime: endTime,
      note: normalizedNote,
      customPauseWindows: pauseWindowsData,
      customSupplements: supplementsData,
      updatedAt: now,
      revision: 0,
      deletedAt: nil
    )

    let allFields = UserShiftField.allCases.map(\.rawValue)
    let dirtyFieldsData = (try? kCanonicalJSONEncoder.encode(allFields)) ?? Data()

    let localShift = LocalUserShift(
      id: resolvedId,
      userId: userId,
      jobId: jobId,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      note: normalizedNote,
      customPauseWindows: pauseWindowsData,
      customSupplements: supplementsData,
      serverUpdatedAt: now,
      serverRevision: 0,
      serverDeletedAt: nil,
      syncStatus: .dirty,
      dirtyFields: dirtyFieldsData,
      lastSyncedSnapshot: snapshot.encoded(),
      localUpdatedAt: now,
      conflictServerSnapshot: nil
    )

    modelContext.insert(localShift)
    try modelContext.save()
    return localShift.toShiftRow()
  }

  internal func updateUserShiftCustomPauseWindows(
    id: String,
    customPauseWindows: CustomPauseWindows?
  ) throws -> ShiftRow {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    let normalizedData = PauseWindowSupport.normalize(customPauseWindows).flatMap { value in
      try? kCanonicalJSONEncoder.encode(value)
    }

    var dirtyFields = localShift.dirtyFieldKeys
    if normalizedData != localShift.customPauseWindows {
      localShift.customPauseWindows = normalizedData
      dirtyFields.insert(.customPauseWindows)
      localShift.dirtyFieldKeys = dirtyFields
      localShift.localUpdatedAt = Date()
      if localShift.syncStatus == .clean {
        localShift.syncStatus = .dirty
      }
      try modelContext.save()
    }

    return localShift.toShiftRow()
  }

  internal func updateUserShift(
    id: String,
    jobId: String? = nil,
    shiftDate: Date?,
    startTime: String?,
    endTime: String?,
    note: String? = nil,
    noteWasEdited: Bool = false,
    customSupplements: CustomSupplementsData?
  ) throws -> ShiftRow {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var newDirtyFields = localShift.dirtyFieldKeys
    let now = Date()

    if let newJobId = jobId, newJobId != localShift.jobId {
      localShift.jobId = newJobId
      newDirtyFields.insert(.jobId)
    }

    if let newDate = shiftDate, newDate != localShift.shiftDate {
      localShift.shiftDate = newDate
      newDirtyFields.insert(.shiftDate)
    }

    if let newStart = startTime, newStart != localShift.startTime {
      localShift.startTime = newStart
      newDirtyFields.insert(.startTime)
    }

    if let newEnd = endTime, newEnd != localShift.endTime {
      localShift.endTime = newEnd
      newDirtyFields.insert(.endTime)
    }

    if noteWasEdited {
      let normalizedNote = ShiftNoteSupport.normalize(note)
      if normalizedNote != localShift.note {
        localShift.note = normalizedNote
        newDirtyFields.insert(.note)
      }
    }

    if let newSupplements = customSupplements {
      let newData = try? kCanonicalJSONEncoder.encode(newSupplements)
      if newData != localShift.customSupplements {
        localShift.customSupplements = newData
        newDirtyFields.insert(.customSupplements)
      }
    }

    localShift.dirtyFieldKeys = newDirtyFields
    localShift.localUpdatedAt = now

    if !newDirtyFields.isEmpty, localShift.syncStatus == .clean {
      localShift.syncStatus = .dirty
    }

    try modelContext.save()
    return localShift.toShiftRow()
  }

  internal func markShiftPendingDelete(id: String) throws -> String {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    localShift.syncStatus = .pendingDelete
    localShift.localUpdatedAt = Date()

    try modelContext.save()
    return localShift.userId
  }

  /// Mark multiple shifts for deletion in one transaction.
  /// Returns affected user IDs so callers can trigger side effects once per user.
  internal func markShiftsPendingDelete(ids: [String]) throws -> Set<String> {
    guard !ids.isEmpty else {
      return []
    }

    var affectedUserIds: Set<String> = []
    var didMutate = false
    let now = Date()

    for id in Set(ids) {
      let descriptor = FetchDescriptor<LocalUserShift>(
        predicate: #Predicate { $0.id == id }
      )

      guard let localShift = try modelContext.fetch(descriptor).first else {
        continue
      }

      localShift.syncStatus = .pendingDelete
      localShift.localUpdatedAt = now
      affectedUserIds.insert(localShift.userId)
      didMutate = true
    }

    if didMutate {
      try modelContext.save()
    }

    return affectedUserIds
  }

  internal func resolveStoredShiftConflictKeepLocal(id: String) throws {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localShift.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    guard
      let serverSnapshot = UserShiftServerSnapshot.decode(
        from: localShift.conflictServerSnapshot ?? Data()
      )
    else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localShift.serverRevision = serverSnapshot.revision
    localShift.serverUpdatedAt = serverSnapshot.updatedAt
    localShift.syncStatus = .dirty
    localShift.conflictServerSnapshot = nil
    localShift.localUpdatedAt = Date()

    try modelContext.save()
  }

  internal func resolveStoredShiftConflictKeepServer(id: String) throws {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localShift.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    let conflictData = localShift.conflictServerSnapshot ?? Data()
    guard let serverSnapshot = UserShiftServerSnapshot.decode(from: conflictData) else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    let dateFormatter = isoDateFormatter

    localShift.shiftDate =
      dateFormatter.date(from: serverSnapshot.shiftDate) ?? localShift.shiftDate
    localShift.jobId = serverSnapshot.jobId
    localShift.startTime = serverSnapshot.startTime
    localShift.endTime = serverSnapshot.endTime
    localShift.note = serverSnapshot.note
    localShift.customPauseWindows = serverSnapshot.customPauseWindows
    localShift.customSupplements = serverSnapshot.customSupplements
    localShift.serverRevision = serverSnapshot.revision
    localShift.serverUpdatedAt = serverSnapshot.updatedAt
    localShift.serverDeletedAt = serverSnapshot.deletedAt
    localShift.syncStatus = .clean
    localShift.dirtyFieldKeys = []
    localShift.lastSyncedSnapshot = conflictData
    localShift.conflictServerSnapshot = nil
    localShift.localUpdatedAt = Date()

    try modelContext.save()
  }
}
