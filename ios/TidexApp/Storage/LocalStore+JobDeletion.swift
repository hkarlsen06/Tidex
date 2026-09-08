import Foundation
import SwiftData

extension LocalStoreActor {
  func validateArchivedJobDeletion(userId: String, jobId: String) throws {
    let records = try jobDeletionRecords(userId: userId, jobId: jobId)
    guard records.job.deletedAt == nil else { throw JobsRepositoryError.jobDeleted }
    guard records.job.archivedAt != nil else {
      throw JobsRepositoryError.cannotDeleteUnarchivedJob
    }
    guard !records.job.isDefault else { throw JobsRepositoryError.cannotDeleteDefaultJob }
    guard records.isSynced else { throw JobsRepositoryError.deletionSyncRequired }
  }

  /// Applies a committed server deletion in one local save, including cached history.
  /// The next sync refreshes individual history revisions from the server.
  func applyConfirmedJobDeletion(userId: String, receipt: JobDeletionPreview) throws {
    guard receipt.userId == userId, let epoch = receipt.deletedAtEpoch, epoch.isFinite else {
      throw JobsRepositoryError.deletionRefreshFailed
    }
    let records = try jobDeletionRecords(userId: userId, jobId: receipt.jobId)
    let deletedAt = Date(timeIntervalSince1970: epoch)

    for shift in records.shifts where shift.serverDeletedAt == nil {
      markShiftDeleted(
        id: shift.id, serverUpdatedAt: deletedAt,
        serverRevision: shift.serverRevision, serverDeletedAt: deletedAt
      )
    }
    for recurring in records.recurringShifts where recurring.serverDeletedAt == nil {
      markRecurringShiftDeleted(
        id: recurring.id, serverUpdatedAt: deletedAt,
        serverRevision: recurring.serverRevision, serverDeletedAt: deletedAt
      )
    }
    for adjustment in records.adjustments where adjustment.serverDeletedAt == nil {
      markPayrollAdjustmentDeleted(
        id: adjustment.id, serverUpdatedAt: deletedAt,
        serverRevision: adjustment.serverRevision, serverDeletedAt: deletedAt
      )
    }
    for snapshot in records.snapshots where snapshot.serverDeletedAt == nil {
      markWageSnapshotDeleted(
        id: snapshot.id, serverUpdatedAt: deletedAt,
        serverRevision: snapshot.serverRevision, serverDeletedAt: deletedAt
      )
    }
    markJobDeleted(
      id: receipt.jobId, serverUpdatedAt: deletedAt,
      serverRevision: receipt.jobRevision, deletedAt: deletedAt
    )
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  private func jobDeletionRecords(userId: String, jobId: String) throws -> JobDeletionRecords {
    guard let job = try getJob(id: jobId), job.userId == userId else {
      throw JobsRepositoryError.jobNotFound
    }
    return try JobDeletionRecords(
      job: job,
      shifts: modelContext.fetch(
        FetchDescriptor<LocalUserShift>(
          predicate: #Predicate { $0.userId == userId && $0.jobId == jobId }
        )),
      recurringShifts: modelContext.fetch(
        FetchDescriptor<LocalRecurringShift>(
          predicate: #Predicate { $0.userId == userId && $0.jobId == jobId }
        )),
      adjustments: modelContext.fetch(
        FetchDescriptor<LocalPayrollAdjustment>(
          predicate: #Predicate { $0.userId == userId && $0.jobId == jobId }
        )),
      snapshots: modelContext.fetch(
        FetchDescriptor<LocalWageSnapshot>(
          predicate: #Predicate { $0.userId == userId && $0.jobId == jobId }
        ))
    )
  }
}

private struct JobDeletionRecords {
  let job: LocalJob
  let shifts: [LocalUserShift]
  let recurringShifts: [LocalRecurringShift]
  let adjustments: [LocalPayrollAdjustment]
  let snapshots: [LocalWageSnapshot]

  var isSynced: Bool {
    job.syncStatus == .clean
      && shifts.allSatisfy { $0.syncStatus == .clean }
      && recurringShifts.allSatisfy { $0.syncStatus == .clean }
      && adjustments.allSatisfy { $0.syncStatus == .clean }
      && snapshots.allSatisfy { $0.syncStatus == .clean }
  }
}
