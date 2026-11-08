import Foundation
import SwiftData
import os.log

extension LocalStoreActor {

  // MARK: - Event Operations

  internal func upsertEvent(_ event: LocalEvent) throws {
    let eventId = event.id
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == eventId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      existing.startDate = event.startDate
      existing.endDate = event.endDate
      existing.isAllDay = event.isAllDay
      existing.startTime = event.startTime
      existing.endTime = event.endTime
      existing.note = event.note
      existing.serverUpdatedAt = event.serverUpdatedAt
      existing.serverRevision = event.serverRevision
      existing.serverDeletedAt = event.serverDeletedAt
      existing.syncStatusRaw = event.syncStatusRaw
      existing.dirtyFields = event.dirtyFields
      existing.lastSyncedSnapshot = event.lastSyncedSnapshot
      existing.localUpdatedAt = event.localUpdatedAt
      existing.conflictServerSnapshot = event.conflictServerSnapshot
    } else {
      modelContext.insert(event)
    }
  }

  internal func getEvent(id: String) throws -> LocalEvent? {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  /// For callers outside the actor, which can't read a `LocalEvent` from this context.
  internal func eventUserId(id: String) throws -> String? {
    try getEvent(id: id)?.userId
  }

  internal func getAllEvents(userId: String) throws -> [LocalEvent] {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor)
  }

  internal func getDirtyEvents(userId: String) throws -> [LocalEvent] {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { event in
        event.userId == userId
          && (event.syncStatusRaw == "dirty" || event.syncStatusRaw == "pendingDelete"
            || (event.syncStatusRaw == "conflict" && event.serverRevision == 0))
      }
    )
    return try modelContext.fetch(descriptor)
  }

  internal func hasDirtyEvents(userId: String) throws -> Bool {
    var descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { event in
        event.userId == userId
          && (event.syncStatusRaw == "dirty" || event.syncStatusRaw == "pendingDelete"
            || (event.syncStatusRaw == "conflict" && event.serverRevision == 0))
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  // swiftlint:disable:next function_parameter_count
  internal func createEvent(
    id: String? = nil,
    userId: String,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool,
    startTime: String?,
    endTime: String?,
    note: String,
    notificationMinutesArray: [Int]? = nil,
    notificationAnchorTime: String? = nil
  ) throws -> EventRow {
    let resolvedId = id ?? UUID().lowercasedString

    if let existing = try getEvent(id: resolvedId), existing.userId == userId {
      return existing.toEventRow()
    }

    let now = Date()
    let dateFormatter = isoDateFormatter
    let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedReminderMinutes = LocalEvent.normalizedReminderMinutesOptional(
      notificationMinutesArray
    )
    let normalizedAnchorTime =
      isAllDay ? LocalEvent.normalizedAnchorTime(notificationAnchorTime) : nil

    let snapshot = EventServerSnapshot(
      startDate: dateFormatter.string(from: startDate),
      endDate: dateFormatter.string(from: endDate),
      isAllDay: isAllDay,
      startTime: startTime,
      endTime: endTime,
      note: trimmedNote,
      notificationMinutesArray: normalizedReminderMinutes,
      notificationAnchorTime: normalizedAnchorTime,
      updatedAt: now,
      revision: 0,
      deletedAt: nil
    )

    let allFields = EventField.allCases.map(\.rawValue)
    let dirtyFieldsData = (try? kCanonicalJSONEncoder.encode(allFields)) ?? Data()

    let localEvent = LocalEvent(
      id: resolvedId,
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      isAllDay: isAllDay,
      startTime: startTime,
      endTime: endTime,
      note: trimmedNote,
      notificationMinutesArray: normalizedReminderMinutes ?? [],
      notificationAnchorTime: normalizedAnchorTime,
      serverUpdatedAt: now,
      serverRevision: 0,
      serverDeletedAt: nil,
      syncStatus: .dirty,
      dirtyFields: dirtyFieldsData,
      lastSyncedSnapshot: snapshot.encoded(),
      localUpdatedAt: now,
      conflictServerSnapshot: nil
    )

    modelContext.insert(localEvent)
    try modelContext.save()
    return localEvent.toEventRow()
  }

  // swiftlint:disable:next function_parameter_count
  internal func updateEvent(
    id: String,
    startDate: Date?,
    endDate: Date?,
    isAllDay: Bool?,
    startTime: String?,
    endTime: String?,
    note: String?,
    notificationMinutesArray: [Int]? = nil,
    notificationAnchorTime: String? = nil
  ) throws -> EventRow {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localEvent = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var newDirtyFields = localEvent.dirtyFieldKeys
    let now = Date()

    if let startDate, startDate != localEvent.startDate {
      localEvent.startDate = startDate
      newDirtyFields.insert(.startDate)
    }

    if let endDate, endDate != localEvent.endDate {
      localEvent.endDate = endDate
      newDirtyFields.insert(.endDate)
    }

    if let isAllDay, isAllDay != localEvent.isAllDay {
      localEvent.isAllDay = isAllDay
      newDirtyFields.insert(.isAllDay)
    }

    if startTime != localEvent.startTime {
      localEvent.startTime = startTime
      newDirtyFields.insert(.startTime)
    }

    if endTime != localEvent.endTime {
      localEvent.endTime = endTime
      newDirtyFields.insert(.endTime)
    }

    if let note {
      let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmedNote != localEvent.note {
        localEvent.note = trimmedNote
        newDirtyFields.insert(.note)
      }
    }

    let resolvedIsAllDay = isAllDay ?? localEvent.isAllDay
    let normalizedReminderMinutes = LocalEvent.normalizedReminderMinutes(notificationMinutesArray)
    if normalizedReminderMinutes != localEvent.notificationMinutesArray {
      localEvent.notificationMinutesArray = normalizedReminderMinutes
      newDirtyFields.insert(.notificationMinutesArray)
    }

    let normalizedAnchorTime =
      resolvedIsAllDay ? LocalEvent.normalizedAnchorTime(notificationAnchorTime) : nil
    if normalizedAnchorTime != localEvent.notificationAnchorTime {
      localEvent.notificationAnchorTime = normalizedAnchorTime
      newDirtyFields.insert(.notificationAnchorTime)
    }

    localEvent.dirtyFieldKeys = newDirtyFields
    localEvent.localUpdatedAt = now

    if !newDirtyFields.isEmpty, localEvent.syncStatus == .clean {
      localEvent.syncStatus = .dirty
    }

    try modelContext.save()
    return localEvent.toEventRow()
  }

  internal func markEventPendingDelete(id: String) throws -> String {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localEvent = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    localEvent.syncStatus = .pendingDelete
    localEvent.localUpdatedAt = Date()

    try modelContext.save()
    return localEvent.userId
  }

  internal func resolveStoredEventConflictKeepLocal(id: String) throws {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localEvent = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localEvent.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    guard
      let serverSnapshot = EventServerSnapshot.decode(
        from: localEvent.conflictServerSnapshot ?? Data()
      )
    else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localEvent.serverRevision = serverSnapshot.revision
    localEvent.serverUpdatedAt = serverSnapshot.updatedAt
    localEvent.syncStatus = .dirty
    localEvent.conflictServerSnapshot = nil
    localEvent.localUpdatedAt = Date()

    try modelContext.save()
  }

  internal func resolveStoredEventConflictKeepServer(id: String) throws {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localEvent = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localEvent.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    let conflictData = localEvent.conflictServerSnapshot ?? Data()
    guard let serverSnapshot = EventServerSnapshot.decode(from: conflictData) else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    let dateFormatter = isoDateFormatter

    localEvent.startDate =
      dateFormatter.date(from: serverSnapshot.startDate) ?? localEvent.startDate
    localEvent.endDate =
      dateFormatter.date(from: serverSnapshot.endDate) ?? localEvent.endDate
    localEvent.isAllDay = serverSnapshot.isAllDay
    localEvent.startTime = serverSnapshot.startTime
    localEvent.endTime = serverSnapshot.endTime
    localEvent.note = serverSnapshot.note
    localEvent.notificationMinutesArray =
      LocalEvent.normalizedReminderMinutes(serverSnapshot.notificationMinutesArray)
    localEvent.notificationAnchorTime =
      LocalEvent.normalizedAnchorTime(serverSnapshot.notificationAnchorTime)
    localEvent.serverRevision = serverSnapshot.revision
    localEvent.serverUpdatedAt = serverSnapshot.updatedAt
    localEvent.serverDeletedAt = serverSnapshot.deletedAt
    localEvent.syncStatus = .clean
    localEvent.dirtyFieldKeys = []
    localEvent.lastSyncedSnapshot = conflictData
    localEvent.conflictServerSnapshot = nil
    localEvent.localUpdatedAt = Date()

    try modelContext.save()
  }
}
