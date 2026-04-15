import Foundation
import SwiftData

// MARK: - Local Event

/// SwiftData model for locally persisted private events.
@Model
final class LocalEvent {
  @Attribute(.unique)
  var id: String

  var userId: String
  var startDate: Date
  var endDate: Date
  var isAllDay: Bool
  var startTime: String?
  var endTime: String?
  var note: String
  /// Must have a persisted default for lightweight migration from older stores.
  var notificationMinutesArray: [Int] = []
  var notificationAnchorTime: String?

  var serverUpdatedAt: Date
  var serverRevision: Int64
  var serverDeletedAt: Date?

  var syncStatusRaw: String
  var dirtyFields: Data
  var lastSyncedSnapshot: Data
  var localUpdatedAt: Date
  var conflictServerSnapshot: Data?

  var syncStatus: SyncStatus {
    get { SyncStatus(rawValue: syncStatusRaw) ?? .clean }
    set { syncStatusRaw = newValue.rawValue }
  }

  var dirtyFieldKeys: Set<EventField> {
    get {
      guard !dirtyFields.isEmpty else { return [] }

      do {
        let keys = try syncJSONDecoder.decode([String].self, from: dirtyFields)
        return Set(keys.compactMap { EventField(rawValue: $0) })
      } catch {
        SyncLogger.shared.log(
          "Corrupted dirtyFields for event \(id), treating as fully dirty: \(error.localizedDescription)",
          level: .error
        )
        return Set(EventField.allCases)
      }
    }
    set {
      let keys = newValue.map(\.rawValue)
      dirtyFields = (try? canonicalJSONEncoder.encode(keys)) ?? Data()
    }
  }

  var startDateString: String {
    FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone).string(from: startDate)
  }

  var endDateString: String {
    FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone).string(from: endDate)
  }

  init(
    id: String,
    userId: String,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool,
    startTime: String?,
    endTime: String?,
    note: String,
    notificationMinutesArray: [Int] = [],
    notificationAnchorTime: String? = nil,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date? = nil,
    syncStatus: SyncStatus = .clean,
    dirtyFields: Data = Data(),
    lastSyncedSnapshot: Data,
    localUpdatedAt: Date,
    conflictServerSnapshot: Data? = nil
  ) {
    self.id = id
    self.userId = userId
    self.startDate = startDate
    self.endDate = endDate
    self.isAllDay = isAllDay
    self.startTime = startTime
    self.endTime = endTime
    self.note = note
    self.notificationMinutesArray = Self.normalizedReminderMinutes(notificationMinutesArray)
    self.notificationAnchorTime = Self.normalizedAnchorTime(notificationAnchorTime)
    self.serverUpdatedAt = serverUpdatedAt
    self.serverRevision = serverRevision
    self.serverDeletedAt = serverDeletedAt
    self.syncStatusRaw = syncStatus.rawValue
    self.dirtyFields = dirtyFields
    self.lastSyncedSnapshot = lastSyncedSnapshot
    self.localUpdatedAt = localUpdatedAt
    self.conflictServerSnapshot = conflictServerSnapshot
  }

  static func emptyDirtyFields() -> Data {
    (try? canonicalJSONEncoder.encode([String]())) ?? Data()
  }

  static func normalizedReminderMinutes(_ minutes: [Int]?) -> [Int] {
    Array(Set((minutes ?? []).filter { $0 >= 0 })).sorted(by: >)
  }

  static func normalizedReminderMinutesOptional(_ minutes: [Int]?) -> [Int]? {
    let normalized = normalizedReminderMinutes(minutes)
    return normalized.isEmpty ? nil : normalized
  }

  static func normalizedAnchorTime(_ time: String?) -> String? {
    guard let time else { return nil }
    let trimmed = time.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

// MARK: - Server Snapshot

struct EventServerSnapshot: Codable, Equatable {
  let startDate: String
  let endDate: String
  let isAllDay: Bool
  let startTime: String?
  let endTime: String?
  let note: String
  let notificationMinutesArray: [Int]?
  let notificationAnchorTime: String?
  let updatedAt: Date
  let revision: Int64
  let deletedAt: Date?

  static func from(serverRow: SyncEventRow, updatedAt: Date, deletedAt: Date?)
    -> EventServerSnapshot
  {
    EventServerSnapshot(
      startDate: serverRow.start_date,
      endDate: serverRow.end_date,
      isAllDay: serverRow.is_all_day,
      startTime: serverRow.start_time,
      endTime: serverRow.end_time,
      note: serverRow.note,
      notificationMinutesArray: LocalEvent.normalizedReminderMinutesOptional(
        serverRow.notification_minutes_array),
      notificationAnchorTime: LocalEvent.normalizedAnchorTime(serverRow.notification_anchor_time),
      updatedAt: updatedAt,
      revision: serverRow.revision,
      deletedAt: deletedAt
    )
  }

  static func from(
    eventRow: EventRow,
    updatedAt: Date,
    revision: Int64,
    deletedAt: Date?
  ) -> EventServerSnapshot {
    EventServerSnapshot(
      startDate: eventRow.start_date,
      endDate: eventRow.end_date,
      isAllDay: eventRow.is_all_day,
      startTime: eventRow.start_time,
      endTime: eventRow.end_time,
      note: eventRow.note,
      notificationMinutesArray: LocalEvent.normalizedReminderMinutesOptional(
        eventRow.notification_minutes_array),
      notificationAnchorTime: LocalEvent.normalizedAnchorTime(eventRow.notification_anchor_time),
      updatedAt: updatedAt,
      revision: revision,
      deletedAt: deletedAt
    )
  }

  func encodedOrThrow() throws -> Data {
    try requireEncode(self, typeName: "EventServerSnapshot")
  }

  func encoded() -> Data {
    (try? canonicalJSONEncoder.encode(self)) ?? Data()
  }

  static func decode(from data: Data) -> EventServerSnapshot? {
    try? syncJSONDecoder.decode(EventServerSnapshot.self, from: data)
  }

  func changedFields(from other: EventServerSnapshot) -> Set<EventField> {
    var changed: Set<EventField> = []

    if startDate != other.startDate {
      changed.insert(.startDate)
    }
    if endDate != other.endDate {
      changed.insert(.endDate)
    }
    if isAllDay != other.isAllDay {
      changed.insert(.isAllDay)
    }
    if startTime != other.startTime {
      changed.insert(.startTime)
    }
    if endTime != other.endTime {
      changed.insert(.endTime)
    }
    if note != other.note {
      changed.insert(.note)
    }
    if notificationMinutesArray != other.notificationMinutesArray {
      changed.insert(.notificationMinutesArray)
    }
    if notificationAnchorTime != other.notificationAnchorTime {
      changed.insert(.notificationAnchorTime)
    }

    return changed
  }
}

// MARK: - Conversion Extensions

extension LocalEvent {
  func toEventRow() -> EventRow {
    EventRow(
      id: id,
      user_id: userId,
      start_date: startDateString,
      end_date: endDateString,
      is_all_day: isAllDay,
      start_time: startTime,
      end_time: endTime,
      note: note,
      notification_minutes_array: LocalEvent.normalizedReminderMinutesOptional(
        notificationMinutesArray),
      notification_anchor_time: LocalEvent.normalizedAnchorTime(notificationAnchorTime),
      created_at: nil,
      updated_at: serverUpdatedAt
    )
  }

  static func from(
    serverRow: EventRow,
    userId: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?
  ) -> LocalEvent {
    let dateFormatter = FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone)
    let resolvedStartDate = dateFormatter.date(from: serverRow.start_date) ?? Date()
    let resolvedEndDate = dateFormatter.date(from: serverRow.end_date) ?? resolvedStartDate

    let snapshot = EventServerSnapshot.from(
      eventRow: serverRow,
      updatedAt: serverUpdatedAt,
      revision: serverRevision,
      deletedAt: serverDeletedAt
    )

    return LocalEvent(
      id: serverRow.id,
      userId: userId,
      startDate: resolvedStartDate,
      endDate: resolvedEndDate,
      isAllDay: serverRow.is_all_day,
      startTime: serverRow.start_time,
      endTime: serverRow.end_time,
      note: serverRow.note,
      notificationMinutesArray: serverRow.notification_minutes_array ?? [],
      notificationAnchorTime: serverRow.notification_anchor_time,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      syncStatus: .clean,
      dirtyFields: emptyDirtyFields(),
      lastSyncedSnapshot: snapshot.encoded(),
      localUpdatedAt: Date(),
      conflictServerSnapshot: nil
    )
  }
}
