import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "EventsRepository")

/// Local-first repository for private events.
@MainActor
final class EventsRepository: ObservableObject {
  static let shared = EventsRepository()

  private let localStore: LocalStore
  private let syncCoordinator: SyncCoordinator

  private init(localStore: LocalStore? = nil, syncCoordinator: SyncCoordinator? = nil) {
    self.localStore = localStore ?? LocalStore.shared
    self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
  }

  private func triggerSync(userId: String) {
    Task {
      _ = await syncCoordinator.sync(reason: .localChange, userId: userId)
    }
  }

  func getEvents(
    for userId: String,
    startDate: Date,
    endDate: Date
  ) -> [EventRow] {
    let context = localStore.mainContext

    do {
      let descriptor = FetchDescriptor<LocalEvent>(
        predicate: #Predicate { event in
          event.userId == userId && event.serverDeletedAt == nil
            && event.syncStatusRaw != "pendingDelete"
            && event.endDate >= startDate
            && event.startDate <= endDate
        },
        sortBy: [
          SortDescriptor(\LocalEvent.startDate, order: .forward),
          SortDescriptor(\LocalEvent.endDate, order: .forward),
        ]
      )
      return try context.fetch(descriptor).map { $0.toEventRow() }
    } catch {
      logger.error("Failed to fetch events: \(error.localizedDescription)")
      return []
    }
  }

  func getEventsOffMain(
    for userId: String,
    startDate: Date,
    endDate: Date
  ) async -> [EventRow] {
    await localStore.storeActor.fetchEvents(userId: userId, startDate: startDate, endDate: endDate)
  }

  func getEvent(id: String) -> EventRow? {
    let context = localStore.mainContext
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    do {
      return try context.fetch(descriptor).first?.toEventRow()
    } catch {
      logger.error("Failed to fetch event by ID: \(error.localizedDescription)")
      return nil
    }
  }

  func getConflictingEvents(for userId: String) -> [LocalEvent] {
    let context = localStore.mainContext
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { event in
        event.userId == userId && event.syncStatusRaw == "conflict"
      }
    )

    do {
      return try context.fetch(descriptor)
    } catch {
      logger.error("Failed to fetch conflicting events: \(error.localizedDescription)")
      return []
    }
  }

  func createEvent(
    eventId: String? = nil,
    userId: String,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool,
    startTime: String?,
    endTime: String?,
    note: String
  ) async throws -> EventRow {
    let createdEvent = try await localStore.storeActor.createEvent(
      id: eventId,
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      isAllDay: isAllDay,
      startTime: startTime,
      endTime: endTime,
      note: note
    )

    logger.info("Created new local event: \(createdEvent.id)")
    triggerSync(userId: userId)
    return createdEvent
  }

  func updateEvent(
    id: String,
    startDate: Date? = nil,
    endDate: Date? = nil,
    isAllDay: Bool? = nil,
    startTime: String? = nil,
    endTime: String? = nil,
    note: String? = nil
  ) async throws -> EventRow? {
    do {
      let updatedEvent = try await localStore.storeActor.updateEvent(
        id: id,
        startDate: startDate,
        endDate: endDate,
        isAllDay: isAllDay,
        startTime: startTime,
        endTime: endTime,
        note: note
      )

      logger.info("Updated local event: \(id)")
      if let userId = updatedEvent.user_id {
        triggerSync(userId: userId)
      }
      return updatedEvent
    } catch LocalStoreWriteError.notFound {
      logger.warning("Event not found for update: \(id)")
      return nil
    } catch {
      throw error
    }
  }

  func deleteEvent(id: String) async throws {
    let userId = try await localStore.storeActor.markEventPendingDelete(id: id)
    logger.info("Marked local event pending delete: \(id)")
    triggerSync(userId: userId)
  }

  func resolveConflictKeepLocal(id: String) async throws {
    do {
      try await localStore.storeActor.resolveStoredEventConflictKeepLocal(id: id)
      if let localEvent = try await localStore.storeActor.getEvent(id: id) {
        triggerSync(userId: localEvent.userId)
      }
    } catch LocalStoreWriteError.notFound {
      logger.warning("Event not found for local conflict resolution: \(id)")
    } catch {
      throw error
    }
  }

  func resolveConflictKeepServer(id: String) async throws {
    do {
      try await localStore.storeActor.resolveStoredEventConflictKeepServer(id: id)
    } catch LocalStoreWriteError.notFound {
      logger.warning("Event not found for server conflict resolution: \(id)")
    } catch {
      throw error
    }
  }
}
