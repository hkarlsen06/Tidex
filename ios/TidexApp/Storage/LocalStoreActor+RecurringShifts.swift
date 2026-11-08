import Foundation
import SwiftData
import os.log

extension LocalStoreActor {

  // MARK: - Recurring Shift Operations

  /// Upsert a recurring shift from server data
  internal func upsertRecurringShift(_ shift: LocalRecurringShift) throws {
    let shiftId = shift.id
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == shiftId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      // Update existing
      existing.jobId = shift.jobId
      existing.startTime = shift.startTime
      existing.endTime = shift.endTime
      existing.repeatIntervalWeeks = shift.repeatIntervalWeeks
      existing.selectedDays = shift.selectedDays
      existing.endCondition = shift.endCondition
      existing.exclusions = shift.exclusions
      existing.dateSpecificPauseWindows = shift.dateSpecificPauseWindows
      existing.dateSpecificSupplements = shift.dateSpecificSupplements
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

  /// Get recurring shift by ID
  internal func getRecurringShift(id: String) throws -> LocalRecurringShift? {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  /// Get all recurring shifts for a user
  internal func getAllRecurringShifts(userId: String) throws -> [LocalRecurringShift] {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor)
  }

  /// Get dirty recurring shifts that need to be pushed
  internal func getDirtyRecurringShifts(userId: String) throws -> [LocalRecurringShift] {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
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

  internal func hasDirtyRecurringShifts(userId: String) throws -> Bool {
    var descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { shift in
        shift.userId == userId
          && (shift.syncStatusRaw == "dirty" || shift.syncStatusRaw == "pendingDelete"
            || (shift.syncStatusRaw == "conflict" && shift.serverRevision == 0))
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  // MARK: - Local Recurring Shift Write Operations

  // swiftlint:disable:next function_parameter_count
  internal func createRecurringShift(
    userId: String,
    jobId: String? = nil,
    startTime: String,
    endTime: String,
    repeatIntervalWeeks: Int,
    selectedDays: SelectedDays,
    endCondition: EndCondition?,
    exclusions: [String]?,
    dateSpecificPauseWindows: DateSpecificPauseWindows? = nil,
    dateSpecificSupplements: [String: CustomSupplementsData]?,
    dateSpecificNotes: [String: String]? = nil
  ) throws -> RecurringShiftRow {
    let id = UUID().lowercasedString
    let now = Date()

    let selectedDaysData = (try? kCanonicalJSONEncoder.encode(selectedDays)) ?? Data()
    let endConditionData = endCondition.flatMap { try? kCanonicalJSONEncoder.encode($0) }
    let exclusionsData = exclusions.flatMap { try? kCanonicalJSONEncoder.encode($0) }
    let pauseWindowsData = PauseWindowSupport.normalize(dateSpecificPauseWindows).flatMap { value in
      try? kCanonicalJSONEncoder.encode(value)
    }
    let supplementsData = dateSpecificSupplements.flatMap { try? kCanonicalJSONEncoder.encode($0) }
    let notesData = ShiftNoteSupport.normalizeDateSpecificNotes(dateSpecificNotes).flatMap {
      value in
      try? kCanonicalJSONEncoder.encode(value)
    }

    let serverSnapshot = RecurringShiftServerSnapshot(
      jobId: jobId,
      startTime: startTime,
      endTime: endTime,
      repeatIntervalWeeks: repeatIntervalWeeks,
      selectedDays: selectedDaysData,
      endCondition: endConditionData,
      exclusions: exclusionsData,
      dateSpecificPauseWindows: pauseWindowsData,
      dateSpecificSupplements: supplementsData,
      dateSpecificNotes: notesData,
      updatedAt: now,
      revision: 0,
      deletedAt: nil
    )

    let allFields = RecurringShiftField.allCases.map(\.rawValue)
    let dirtyFieldsData = (try? kCanonicalJSONEncoder.encode(allFields)) ?? Data()

    let localShift = LocalRecurringShift(
      id: id,
      userId: userId,
      jobId: jobId,
      startTime: startTime,
      endTime: endTime,
      repeatIntervalWeeks: repeatIntervalWeeks,
      selectedDays: selectedDaysData,
      endCondition: endConditionData,
      exclusions: exclusionsData,
      dateSpecificPauseWindows: pauseWindowsData,
      dateSpecificSupplements: supplementsData,
      dateSpecificNotes: notesData,
      serverUpdatedAt: now,
      serverRevision: 0,
      serverDeletedAt: nil,
      syncStatus: .dirty,
      dirtyFields: dirtyFieldsData,
      lastSyncedSnapshot: serverSnapshot.encoded(),
      localUpdatedAt: now,
      conflictServerSnapshot: nil
    )

    modelContext.insert(localShift)
    try modelContext.save()
    return localShift.toRecurringShiftRow()
  }

  // swiftlint:disable:next function_parameter_count
  internal func updateRecurringShift(
    id: String,
    jobId: String? = nil,
    startTime: String?,
    endTime: String?,
    repeatIntervalWeeks: Int?,
    selectedDays: SelectedDays?,
    endCondition: EndCondition?,
    exclusions: [String]?,
    dateSpecificSupplements: [String: CustomSupplementsData]?,
    dateSpecificNotes: [String: String]? = nil
  ) throws -> RecurringShiftRow {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
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

    if let newStart = startTime, newStart != localShift.startTime {
      localShift.startTime = newStart
      newDirtyFields.insert(.startTime)
    }

    if let newEnd = endTime, newEnd != localShift.endTime {
      localShift.endTime = newEnd
      newDirtyFields.insert(.endTime)
    }

    if let newInterval = repeatIntervalWeeks, newInterval != localShift.repeatIntervalWeeks {
      localShift.repeatIntervalWeeks = newInterval
      newDirtyFields.insert(.repeatIntervalWeeks)
    }

    if let newDays = selectedDays {
      let newData = (try? kCanonicalJSONEncoder.encode(newDays)) ?? Data()
      if newData != localShift.selectedDays {
        localShift.selectedDays = newData
        newDirtyFields.insert(.selectedDays)
      }
    }

    if let newCondition = endCondition {
      let newData = try? kCanonicalJSONEncoder.encode(newCondition)
      if newData != localShift.endCondition {
        localShift.endCondition = newData
        newDirtyFields.insert(.endCondition)
      }
    }

    if let newExclusions = exclusions {
      let newData = try? kCanonicalJSONEncoder.encode(newExclusions)
      if newData != localShift.exclusions {
        localShift.exclusions = newData
        newDirtyFields.insert(.exclusions)
      }
    }

    if let newSupplements = dateSpecificSupplements {
      let newData = try? kCanonicalJSONEncoder.encode(newSupplements)
      if newData != localShift.dateSpecificSupplements {
        localShift.dateSpecificSupplements = newData
        newDirtyFields.insert(.dateSpecificSupplements)
      }
    }

    if let newNotes = ShiftNoteSupport.normalizeDateSpecificNotes(dateSpecificNotes) {
      let newData = try? kCanonicalJSONEncoder.encode(newNotes)
      if newData != localShift.dateSpecificNotes {
        localShift.dateSpecificNotes = newData
        newDirtyFields.insert(.dateSpecificNotes)
      }
    }

    localShift.dirtyFieldKeys = newDirtyFields
    localShift.localUpdatedAt = now

    if !newDirtyFields.isEmpty, localShift.syncStatus == .clean {
      localShift.syncStatus = .dirty
    }

    try modelContext.save()
    return localShift.toRecurringShiftRow()
  }

  internal func updateRecurringShiftDateSpecificPauseWindows(
    id: String,
    dateSpecificPauseWindows: DateSpecificPauseWindows?
  ) throws -> RecurringShiftRow {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    let normalizedData = PauseWindowSupport.normalize(dateSpecificPauseWindows).flatMap { value in
      try? kCanonicalJSONEncoder.encode(value)
    }

    var dirtyFields = localShift.dirtyFieldKeys
    if normalizedData != localShift.dateSpecificPauseWindows {
      localShift.dateSpecificPauseWindows = normalizedData
      dirtyFields.insert(.dateSpecificPauseWindows)
      localShift.dirtyFieldKeys = dirtyFields
      localShift.localUpdatedAt = Date()
      if localShift.syncStatus == .clean {
        localShift.syncStatus = .dirty
      }
      try modelContext.save()
    }

    return localShift.toRecurringShiftRow()
  }

  internal func updateRecurringShiftDateSpecificNotes(
    id: String,
    dateSpecificNotes: [String: String]?
  ) throws -> RecurringShiftRow {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    let normalizedData = ShiftNoteSupport.normalizeDateSpecificNotes(dateSpecificNotes).flatMap {
      value in
      try? kCanonicalJSONEncoder.encode(value)
    }

    var dirtyFields = localShift.dirtyFieldKeys
    if normalizedData != localShift.dateSpecificNotes {
      localShift.dateSpecificNotes = normalizedData
      dirtyFields.insert(.dateSpecificNotes)
      localShift.dirtyFieldKeys = dirtyFields
      localShift.localUpdatedAt = Date()
      if localShift.syncStatus == .clean {
        localShift.syncStatus = .dirty
      }
      try modelContext.save()
    }

    return localShift.toRecurringShiftRow()
  }

  internal func addRecurringShiftExclusion(id: String, date: String) throws -> Bool {
    try addRecurringShiftExclusions(id: id, dates: [date]) > 0
  }

  internal func addRecurringShiftExclusions(id: String, dates: [String]) throws -> Int {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var exclusions = localShift.decodedExclusions
    var existingExclusions = Set(exclusions)
    let datesToAdd = dates.filter { existingExclusions.insert($0).inserted }

    guard !datesToAdd.isEmpty else {
      return 0
    }

    exclusions.append(contentsOf: datesToAdd)
    localShift.decodedExclusions = exclusions

    var dirtyFields = localShift.dirtyFieldKeys
    dirtyFields.insert(.exclusions)
    localShift.dirtyFieldKeys = dirtyFields

    if localShift.syncStatus == .clean {
      localShift.syncStatus = .dirty
    }
    localShift.localUpdatedAt = Date()

    try modelContext.save()
    return datesToAdd.count
  }

  internal func markRecurringShiftPendingDelete(id: String) throws {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    localShift.syncStatus = .pendingDelete
    localShift.localUpdatedAt = Date()

    try modelContext.save()
  }

  internal func resolveStoredRecurringShiftConflictKeepLocal(id: String) throws {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localShift.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    guard
      let serverSnapshot = RecurringShiftServerSnapshot.decode(
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

  internal func resolveStoredRecurringShiftConflictKeepServer(id: String) throws {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localShift.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    let conflictData = localShift.conflictServerSnapshot ?? Data()
    guard let serverSnapshot = RecurringShiftServerSnapshot.decode(from: conflictData) else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localShift.startTime = serverSnapshot.startTime
    localShift.jobId = serverSnapshot.jobId
    localShift.endTime = serverSnapshot.endTime
    localShift.repeatIntervalWeeks = serverSnapshot.repeatIntervalWeeks
    localShift.selectedDays = serverSnapshot.selectedDays
    localShift.endCondition = serverSnapshot.endCondition
    localShift.exclusions = serverSnapshot.exclusions
    localShift.dateSpecificSupplements = serverSnapshot.dateSpecificSupplements
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
