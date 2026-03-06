import Combine
import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "JobsRepository")

struct JobBaselineSnapshotInput {
  let hourlyWage: Double
  let wageLevel: Int?
  let tariffTypeId: String?
  let supplements: SupplementRulesSnapshot
  let taxEnabled: Bool?
  let taxPercentage: Double?
  let breakEnabled: Bool?
  let breakMethod: String?
  let breakThresholdHours: Double?
  let breakDeductionMinutes: Int?
}

enum JobsRepositoryError: LocalizedError {
  case jobNameEmpty
  case jobNotFound
  case cannotChangeTariffJobCurrency
  case cannotArchiveLastActiveJob
  case cannotArchiveDefaultJob
  case cannotDeleteLastActiveJob
  case cannotDeleteDefaultJob
  case cannotSetArchivedOrDeletedDefault

  var errorDescription: String? {
    switch self {
    case .jobNameEmpty:
      return "Job name cannot be empty."
    case .jobNotFound:
      return "Job not found."
    case .cannotChangeTariffJobCurrency:
      return "Currency cannot be changed for jobs using tariff rates."
    case .cannotArchiveLastActiveJob:
      return "Cannot archive the last active job."
    case .cannotArchiveDefaultJob:
      return "Set another job as default before archiving this one."
    case .cannotDeleteLastActiveJob:
      return "Cannot delete the last active job."
    case .cannotDeleteDefaultJob:
      return "Set another job as default before deleting this one."
    case .cannotSetArchivedOrDeletedDefault:
      return "Cannot set archived or deleted job as default."
    }
  }
}

@MainActor
final class JobsRepository: ObservableObject {
  static let shared = JobsRepository()

  private let localStore: LocalStore
  private let syncCoordinator: SyncCoordinator
  private let snapshotsRepository: SnapshotsRepository

  private init(
    localStore: LocalStore? = nil,
    syncCoordinator: SyncCoordinator? = nil,
    snapshotsRepository: SnapshotsRepository? = nil
  ) {
    self.localStore = localStore ?? LocalStore.shared
    self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
    self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
  }

  private func triggerSync(userId: String) {
    Task {
      _ = await syncCoordinator.sync(reason: .localChange, userId: userId)
    }
  }

  private func usesTariffRates(_ snapshot: JobBaselineSnapshotInput) -> Bool {
    snapshot.wageLevel != nil || snapshot.tariffTypeId != nil
  }

  private func jobUsesTariffRates(userId: String, jobId: String) -> Bool {
    snapshotsRepository.getSnapshots(for: userId, jobId: jobId).contains {
      $0.wage_level != nil || $0.tariff_type_id != nil
    }
  }

  func getAllJobs(
    for userId: String,
    includeArchived: Bool = false,
    includeDeleted: Bool = false
  ) -> [Job] {
    let context = localStore.mainContext
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId
      },
      sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
    )

    do {
      return try context.fetch(descriptor)
        .filter { job in
          if job.syncStatusRaw == "pendingDelete" {
            return false
          }
          if !includeDeleted && job.deletedAt != nil {
            return false
          }
          if !includeArchived && job.archivedAt != nil {
            return false
          }
          return true
        }
        .map { $0.toJob() }
    } catch {
      logger.error("Failed to fetch jobs: \(error.localizedDescription)")
      return []
    }
  }

  func getActiveJobs(for userId: String) -> [Job] {
    getAllJobs(for: userId, includeArchived: false, includeDeleted: false)
  }

  /// Returns all non-deleted jobs, including archived jobs.
  /// Use for read/display contexts where archived jobs should still be visible.
  func getNonDeletedJobs(for userId: String) -> [Job] {
    getAllJobs(for: userId, includeArchived: true, includeDeleted: false)
  }

  func getDefaultJob(for userId: String) -> Job? {
    let context = localStore.mainContext
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId
          && job.deletedAt == nil
          && job.archivedAt == nil
          && job.isDefault == true
      },
      sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
    )

    do {
      return try context.fetch(descriptor).first?.toJob()
    } catch {
      logger.error("Failed to fetch default job: \(error.localizedDescription)")
      return nil
    }
  }

  func getJob(id: String) -> Job? {
    let context = localStore.mainContext
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    do {
      guard let localJob = try context.fetch(descriptor).first else {
        return nil
      }
      if localJob.syncStatusRaw == "pendingDelete" {
        return nil
      }
      return localJob.toJob()
    } catch {
      logger.error("Failed to fetch job by id: \(error.localizedDescription)")
      return nil
    }
  }

  // swiftlint:disable:next function_parameter_count
  func createJob(
    userId: String,
    name: String,
    color: String?,
    currency: String,
    payrollDay: Int?,
    halfTaxMonth: Int?,
    monthlyGoal: Int?
  ) async throws -> Job {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      throw JobsRepositoryError.jobNameEmpty
    }

    let activeJobs = getActiveJobs(for: userId)
    let nextSortOrder = (activeJobs.map(\.sort_order).max() ?? -1) + 1
    let shouldBeDefault = activeJobs.isEmpty

    let createdJob = try await localStore.storeActor.createJob(
      userId: userId,
      name: trimmedName,
      color: color,
      currency: currency,
      isDefault: shouldBeDefault,
      sortOrder: nextSortOrder,
      payrollDay: payrollDay ?? 15,
      halfTaxMonth: halfTaxMonth,
      monthlyGoal: monthlyGoal
    )

    logger.info("Created local job: \(createdJob.id)")
    triggerSync(userId: userId)
    return createdJob
  }

  // swiftlint:disable:next function_parameter_count
  func createJobWithBaselineSnapshot(
    userId: String,
    name: String,
    color: String?,
    currency: String,
    payrollDay: Int?,
    halfTaxMonth: Int?,
    monthlyGoal: Int?,
    baselineSnapshot: JobBaselineSnapshotInput
  ) async throws -> Job {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      throw JobsRepositoryError.jobNameEmpty
    }

    let activeJobs = getActiveJobs(for: userId)
    let nextSortOrder = (activeJobs.map(\.sort_order).max() ?? -1) + 1
    let shouldBeDefault = activeJobs.isEmpty
    let resolvedCurrency = usesTariffRates(baselineSnapshot) ? "kr" : currency

    let createdJob = try await localStore.storeActor.createJob(
      userId: userId,
      name: trimmedName,
      color: color,
      currency: resolvedCurrency,
      isDefault: shouldBeDefault,
      sortOrder: nextSortOrder,
      payrollDay: payrollDay ?? 15,
      halfTaxMonth: halfTaxMonth,
      monthlyGoal: monthlyGoal
    )

    do {
      _ = try await snapshotsRepository.createSnapshot(
        userId: userId,
        jobId: createdJob.id,
        fromDate: nil,
        hourlyWage: baselineSnapshot.hourlyWage,
        wageLevel: baselineSnapshot.wageLevel,
        tariffTypeId: baselineSnapshot.tariffTypeId,
        supplements: baselineSnapshot.supplements,
        taxEnabled: baselineSnapshot.taxEnabled,
        taxPercentage: baselineSnapshot.taxPercentage,
        breakEnabled: baselineSnapshot.breakEnabled,
        breakMethod: baselineSnapshot.breakMethod,
        breakThresholdHours: baselineSnapshot.breakThresholdHours,
        breakDeductionMinutes: baselineSnapshot.breakDeductionMinutes
      )

      triggerSync(userId: userId)
      logger.info("Created local job with baseline snapshot: \(createdJob.id)")
      return createdJob
    } catch {
      if let rollbackUserId = try? await localStore.storeActor.markJobPendingDelete(
        id: createdJob.id)
      {
        triggerSync(userId: rollbackUserId)
      }
      logger.error(
        "Failed to create baseline snapshot for job \(createdJob.id), rolled back job: \(error.localizedDescription)"
      )
      throw error
    }
  }

  func updateJob(
    userId: String,
    jobId: String,
    name: String,
    color: String?
  ) async throws -> Job? {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      throw JobsRepositoryError.jobNameEmpty
    }

    do {
      let updated = try await localStore.storeActor.updateJobMetadata(
        id: jobId,
        name: trimmedName,
        color: color
      )
      logger.info("Updated job metadata for job: \(jobId)")
      triggerSync(userId: userId)
      return updated
    } catch LocalStoreWriteError.notFound {
      logger.warning("Job not found for metadata update: \(jobId)")
      return nil
    } catch {
      throw error
    }
  }

  func updateJobCurrency(
    userId: String,
    jobId: String,
    currency: String
  ) async throws -> Job? {
    if jobUsesTariffRates(userId: userId, jobId: jobId) {
      if let existingJob = getJob(id: jobId), existingJob.currency == currency {
        return existingJob
      }
      throw JobsRepositoryError.cannotChangeTariffJobCurrency
    }

    do {
      let updated = try await localStore.storeActor.updateJobCurrency(
        id: jobId,
        currency: currency
      )
      logger.info("Updated job currency for job: \(jobId)")
      triggerSync(userId: userId)
      return updated
    } catch LocalStoreWriteError.notFound {
      logger.warning("Job not found for currency update: \(jobId)")
      return nil
    } catch {
      throw error
    }
  }

  func updateJobPaySettings(
    userId: String,
    jobId: String,
    payrollDay: Int,
    halfTaxMonth: Int?,
    monthlyGoal: Int?
  ) async throws -> Job? {
    do {
      let updated = try await localStore.storeActor.updateJobPaySettings(
        id: jobId,
        payrollDay: payrollDay,
        halfTaxMonth: halfTaxMonth,
        monthlyGoal: monthlyGoal
      )
      logger.info("Updated pay settings for job: \(jobId)")
      triggerSync(userId: userId)
      return updated
    } catch LocalStoreWriteError.notFound {
      logger.warning("Job not found for pay settings update: \(jobId)")
      return nil
    } catch {
      throw error
    }
  }

  func setDefaultJob(userId: String, jobId: String) async throws {
    guard let target = getActiveJobs(for: userId).first(where: { $0.id == jobId }) else {
      throw JobsRepositoryError.cannotSetArchivedOrDeletedDefault
    }

    if target.archived_at != nil || target.deleted_at != nil {
      throw JobsRepositoryError.cannotSetArchivedOrDeletedDefault
    }

    try await localStore.storeActor.setJobDefault(userId: userId, jobId: jobId)
    logger.info("Set default job: \(jobId)")
    triggerSync(userId: userId)
  }

  func archiveJob(userId: String, jobId: String) async throws {
    let activeJobs = getActiveJobs(for: userId)
    guard let target = activeJobs.first(where: { $0.id == jobId }) else {
      throw JobsRepositoryError.jobNotFound
    }
    if activeJobs.count <= 1 {
      throw JobsRepositoryError.cannotArchiveLastActiveJob
    }
    if target.is_default {
      throw JobsRepositoryError.cannotArchiveDefaultJob
    }

    let affectedUserId = try await localStore.storeActor.archiveJob(id: jobId)
    logger.info("Archived job: \(jobId)")
    triggerSync(userId: affectedUserId)
  }

  func restoreJob(userId: String, jobId: String) async throws {
    let jobs = getAllJobs(for: userId, includeArchived: true, includeDeleted: false)
    guard let target = jobs.first(where: { $0.id == jobId }) else {
      throw JobsRepositoryError.jobNotFound
    }
    guard target.archived_at != nil else {
      return
    }

    let activeJobs = getActiveJobs(for: userId)
    let nextSortOrder = (activeJobs.map(\.sort_order).max() ?? -1) + 1
    let affectedUserId = try await localStore.storeActor.restoreJob(
      id: jobId, sortOrder: nextSortOrder)
    logger.info("Restored job: \(jobId)")
    triggerSync(userId: affectedUserId)
  }

  func deleteJob(userId: String, jobId: String) async throws {
    let nonDeletedJobs = getAllJobs(for: userId, includeArchived: true, includeDeleted: false)
    guard let target = nonDeletedJobs.first(where: { $0.id == jobId }) else {
      throw JobsRepositoryError.jobNotFound
    }

    let activeJobs = getActiveJobs(for: userId)
    let isActiveTarget = target.archived_at == nil
    if isActiveTarget && activeJobs.count <= 1 {
      throw JobsRepositoryError.cannotDeleteLastActiveJob
    }
    if target.is_default {
      throw JobsRepositoryError.cannotDeleteDefaultJob
    }

    let affectedUserId = try await localStore.storeActor.markJobPendingDelete(id: jobId)
    logger.info("Marked job pending delete: \(jobId)")
    triggerSync(userId: affectedUserId)
  }

  func reorderJobs(userId: String, orderedJobIds: [String]) async throws {
    try await localStore.storeActor.reorderJobs(userId: userId, orderedJobIds: orderedJobIds)
    logger.info("Reordered jobs for user \(userId.prefix(8))")
    triggerSync(userId: userId)
  }
}
