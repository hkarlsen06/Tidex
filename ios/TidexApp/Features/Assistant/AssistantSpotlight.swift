import AppIntents
import CoreSpotlight
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "AssistantSpotlight")

protocol AssistantSearchIndex: Sendable {
  func indexAppEntities(_ appEntities: [some IndexedEntity], priority: Int) async throws
  func deleteAppEntities<Entity: IndexedEntity>(ofType entityType: Entity.Type) async throws
  func deleteAllSearchableItems() async throws
}

// CSSearchableIndex is documented as safe to use from any thread.
extension CSSearchableIndex: @retroactive @unchecked Sendable, AssistantSearchIndex {}

/// Keeps Spotlight's copy of the user's shifts and jobs in step with the local store.
@MainActor
enum AssistantSpotlight {
  /// Replaces the indexed shifts and jobs with `userId`'s. Deleted shifts drop out because
  /// every call starts from an empty index. Indexes nothing unless `userId` is signed in and
  /// acting for themself.
  static func reindex(
    userId: String,
    shifts: [ShiftWithComputations],
    jobs: [Job],
    now: Date = Date(),
    access: AssistantAccess? = nil,
    index: any AssistantSearchIndex = CSSearchableIndex.default()
  ) async {
    do {
      try await index.deleteAppEntities(ofType: ShiftEntity.self)
      try await index.deleteAppEntities(ofType: JobEntity.self)

      // Read access after the deletes, so a sign-out or impersonation that started meanwhile wins.
      guard (access ?? .current) == .user(id: userId.lowercased()) else { return }

      let window = AssistantShifts.window(around: now)
      let shiftEntities = AssistantShifts.entities(from: shifts, jobs: jobs).filter {
        $0.end >= window.startDate && $0.start <= window.endDate
      }
      try await index.indexAppEntities(shiftEntities, priority: 0)
      try await index.indexAppEntities(
        jobs.filter { $0.archived_at == nil }.map(JobEntity.init), priority: 0)
    } catch {
      logger.error("Spotlight update failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Sign-out and account switches call this, so the next account never finds these items.
  static func removeAll(index: any AssistantSearchIndex = CSSearchableIndex.default()) async {
    do {
      try await index.deleteAllSearchableItems()
    } catch {
      logger.error("Spotlight cleanup failed: \(error.localizedDescription, privacy: .public)")
    }
  }
}
