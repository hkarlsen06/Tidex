import Foundation
import Observation
import os.log

private let kLogger = Logger(subsystem: "com.tidex.app", category: "SyncConflictsViewModel")

@MainActor
@Observable
internal final class SyncConflictsViewModel {
  internal private(set) var rows: [SyncConflictRow] = []
  internal private(set) var isLoading = true
  internal private(set) var resolvingId: String?
  internal var errorMessage: String?

  private var userId: String? { AppCoordinator.shared.getCurrentUserId() }

  internal func load() async {
    defer { isLoading = false }
    guard let userId else { return }
    let store = LocalStore.shared.storeActor
    rows = (try? await store.conflictRows(userId: userId)) ?? []
  }

  internal func resolve(_ row: SyncConflictRow, _ resolution: ConflictResolution) async {
    guard let userId, resolvingId == nil else { return }
    resolvingId = row.id
    defer { resolvingId = nil }

    let sync = SyncCoordinator.shared
    do {
      try await apply(resolution, to: row, userId: userId)
      errorMessage = nil
    } catch {
      kLogger.error("Resolving \(row.kind.rawValue) conflict failed: \(error.localizedDescription)")
      errorMessage =
        ErrorTranslations.isOffline(error)
        ? ErrorTranslations.offlineMessage : String(localized: .commonErrorGeneric)
    }

    await load()
    await sync.loadTrackingState(userId: userId)
  }

  private func apply(_ resolution: ConflictResolution, to row: SyncConflictRow, userId: String)
    async throws
  {
    let sync = SyncCoordinator.shared
    switch row.kind {
    case .job:
      try await sync.resolveJobConflict(jobId: row.entityId, resolution: resolution, userId: userId)
    case .shift:
      try await sync.resolveShiftConflict(
        shiftId: row.entityId, resolution: resolution, userId: userId)
    case .event:
      try await sync.resolveEventConflict(
        eventId: row.entityId, resolution: resolution, userId: userId)
    case .recurringShift:
      try await sync.resolveRecurringShiftConflict(
        shiftId: row.entityId, resolution: resolution, userId: userId)
    case .wageSnapshot:
      try await sync.resolveWageSnapshotConflict(
        snapshotId: row.entityId, resolution: resolution, userId: userId)
    case .payrollAdjustment:
      try await sync.resolvePayrollAdjustmentConflict(
        adjustmentId: row.entityId, resolution: resolution, userId: userId)
    case .settings:
      try await sync.resolveUserSettingsConflict(resolution: resolution, userId: userId)
    }
  }
}
