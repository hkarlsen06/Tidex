import Foundation
import SwiftData
import os.log

extension LocalStoreActor {

  // MARK: - User Shift Operations

  // MARK: - Jobs Operations

  internal func fetchNonDeletedJobs(userId: String) -> [Job] {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId
      },
      sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
    )

    do {
      return try modelContext.fetch(descriptor)
        .filter { job in
          if job.syncStatusRaw == "pendingDelete" {
            return false
          }
          return job.deletedAt == nil
        }
        .map { $0.toJob() }
    } catch {
      kLocalStoreLogger.error("Failed to fetch jobs: \(error.localizedDescription)")
      return []
    }
  }

  /// Upsert a job from server data.
  /// Kept manual: a plain `insert` looked safe (unique id, no relationships) but
  /// `testUpsertJobTwiceBeforeSaveKeepsOneRowWithLatestValues` showed SwiftData keeps the
  /// first insert's values when two unsaved inserts share a unique id in one context, so it
  /// silently drops the update instead of upserting. Fetch-then-copy avoids that.
  internal func upsertJob(_ job: LocalJob) throws {
    let jobId = job.id
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == jobId }
    )
    let existing = try modelContext.fetch(descriptor).first

    if let existing {
      existing.userId = job.userId
      existing.name = job.name
      existing.color = job.color
      existing.currency = job.currency
      existing.isDefault = job.isDefault
      existing.sortOrder = job.sortOrder
      existing.payrollDay = job.payrollDay
      existing.halfTaxMonth = job.halfTaxMonth
      existing.payPeriodJSON = job.payPeriodJSON
      existing.monthlyGoal = job.monthlyGoal
      existing.archivedAt = job.archivedAt
      existing.deletedAt = job.deletedAt
      existing.createdAt = job.createdAt
      existing.serverUpdatedAt = job.serverUpdatedAt
      existing.serverRevision = job.serverRevision
      existing.syncStatusRaw = job.syncStatusRaw
      existing.dirtyFields = job.dirtyFields
      existing.lastSyncedSnapshot = job.lastSyncedSnapshot
      existing.localUpdatedAt = job.localUpdatedAt
      existing.conflictServerSnapshot = job.conflictServerSnapshot
    } else {
      modelContext.insert(job)
    }
  }

  internal func getJob(id: String) throws -> LocalJob? {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  internal func getAllJobs(userId: String) throws -> [LocalJob] {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor)
  }

  /// Get dirty jobs that need to be pushed
  internal func getDirtyJobs(userId: String) throws -> [LocalJob] {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId
          && (job.syncStatusRaw == "dirty" || job.syncStatusRaw == "pendingDelete"
            || (job.syncStatusRaw == "conflict" && job.serverRevision == 0))
      }
    )
    return try modelContext.fetch(descriptor)
  }

  internal func hasDirtyJobs(userId: String) throws -> Bool {
    var descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId
          && (job.syncStatusRaw == "dirty" || job.syncStatusRaw == "pendingDelete"
            || (job.syncStatusRaw == "conflict" && job.serverRevision == 0))
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  // MARK: - Local Job Write Operations

  // swiftlint:disable:next function_parameter_count
  internal func createJob(
    userId: String,
    name: String,
    color: String?,
    currency: String,
    isDefault: Bool,
    sortOrder: Int,
    payrollDay: Int?,
    halfTaxMonth: Int?,
    payPeriod: PayPeriod? = nil,
    monthlyGoal: Int?
  ) throws -> Job {
    let id = UUID().lowercasedString
    let now = Date()
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

    if isDefault {
      let existingDescriptor = FetchDescriptor<LocalJob>(
        predicate: #Predicate { job in
          job.userId == userId && job.deletedAt == nil && job.archivedAt == nil
        }
      )
      let existingJobs = try modelContext.fetch(existingDescriptor)
      for existing in existingJobs where existing.isDefault {
        existing.isDefault = false
        existing.dirtyFieldKeys.insert(.isDefault)
        existing.localUpdatedAt = now
        if existing.syncStatus == .clean {
          existing.syncStatus = .dirty
        }
      }
    }

    let serverSnapshot = JobServerSnapshot(
      name: trimmedName,
      color: color,
      currency: currency,
      isDefault: isDefault,
      sortOrder: sortOrder,
      payrollDay: payrollDay,
      halfTaxMonth: halfTaxMonth,
      payPeriod: payPeriod ?? .calendarMonth,
      monthlyGoal: monthlyGoal,
      archivedAt: nil,
      deletedAt: nil,
      updatedAt: now,
      revision: 0
    )

    let dirtyFieldsData =
      (try? kCanonicalJSONEncoder.encode(JobField.allCases.map(\.rawValue)))
      ?? Data()

    let localJob = LocalJob(
      id: id,
      userId: userId,
      name: trimmedName,
      color: color,
      currency: currency,
      isDefault: isDefault,
      sortOrder: sortOrder,
      payrollDay: payrollDay,
      halfTaxMonth: halfTaxMonth,
      payPeriodJSON: payPeriod?.storageJSON,
      monthlyGoal: monthlyGoal,
      archivedAt: nil,
      deletedAt: nil,
      createdAt: now,
      serverUpdatedAt: now,
      serverRevision: 0,
      syncStatus: .dirty,
      dirtyFields: dirtyFieldsData,
      lastSyncedSnapshot: serverSnapshot.encoded(),
      localUpdatedAt: now,
      conflictServerSnapshot: nil
    )

    modelContext.insert(localJob)
    try modelContext.save()
    return localJob.toJob()
  }

  internal func updateJobMetadata(
    id: String,
    name: String,
    color: String?
  ) throws -> Job {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var newDirtyFields = localJob.dirtyFieldKeys
    let now = Date()
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

    if localJob.name != trimmedName {
      localJob.name = trimmedName
      newDirtyFields.insert(.name)
    }

    if localJob.color != color {
      localJob.color = color
      newDirtyFields.insert(.color)
    }

    localJob.dirtyFieldKeys = newDirtyFields
    localJob.localUpdatedAt = now

    if !newDirtyFields.isEmpty, localJob.syncStatus == .clean {
      localJob.syncStatus = .dirty
    }

    try modelContext.save()
    return localJob.toJob()
  }

  internal func updateJobCurrency(
    id: String,
    currency: String
  ) throws -> Job {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localJob.currency != currency else {
      return localJob.toJob()
    }

    var newDirtyFields = localJob.dirtyFieldKeys
    let now = Date()

    localJob.currency = currency
    newDirtyFields.insert(.currency)
    localJob.dirtyFieldKeys = newDirtyFields
    localJob.localUpdatedAt = now

    if !newDirtyFields.isEmpty, localJob.syncStatus == .clean {
      localJob.syncStatus = .dirty
    }

    try modelContext.save()
    return localJob.toJob()
  }

  internal func updateJobPaySettings(
    id: String,
    payrollDay: Int,
    halfTaxMonth: Int?,
    monthlyGoal: Int?,
    payPeriod: PayPeriod?
  ) throws -> Job {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var newDirtyFields = localJob.dirtyFieldKeys
    let now = Date()

    if localJob.payrollDay != payrollDay {
      localJob.payrollDay = payrollDay
      newDirtyFields.insert(.payrollDay)
    }

    if localJob.halfTaxMonth != halfTaxMonth {
      localJob.halfTaxMonth = halfTaxMonth
      newDirtyFields.insert(.halfTaxMonth)
    }

    if localJob.monthlyGoal != monthlyGoal {
      localJob.monthlyGoal = monthlyGoal
      newDirtyFields.insert(.monthlyGoal)
    }

    let payPeriodJSON = payPeriod?.storageJSON
    if localJob.payPeriodJSON != payPeriodJSON {
      localJob.payPeriodJSON = payPeriodJSON
      newDirtyFields.insert(.payPeriod)
    }

    localJob.dirtyFieldKeys = newDirtyFields
    localJob.localUpdatedAt = now

    if !newDirtyFields.isEmpty, localJob.syncStatus == .clean {
      localJob.syncStatus = .dirty
    }

    try modelContext.save()
    return localJob.toJob()
  }

  internal func setJobDefault(userId: String, jobId: String) throws {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId && job.deletedAt == nil && job.archivedAt == nil
      }
    )
    let jobs = try modelContext.fetch(descriptor)
    let now = Date()

    for job in jobs {
      let shouldBeDefault = job.id == jobId
      guard job.isDefault != shouldBeDefault else { continue }
      job.isDefault = shouldBeDefault
      job.dirtyFieldKeys.insert(.isDefault)
      job.localUpdatedAt = now
      if job.syncStatus == .clean {
        job.syncStatus = .dirty
      }
    }

    try modelContext.save()
  }

  internal func archiveJob(id: String, archivedAt: Date = Date()) throws -> String {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )
    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    localJob.archivedAt = archivedAt
    localJob.isDefault = false
    localJob.dirtyFieldKeys.insert(.archivedAt)
    localJob.dirtyFieldKeys.insert(.isDefault)
    localJob.localUpdatedAt = archivedAt
    if localJob.syncStatus == .clean {
      localJob.syncStatus = .dirty
    }

    try modelContext.save()
    return localJob.userId
  }

  internal func restoreJob(id: String, sortOrder: Int) throws -> String {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )
    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    let now = Date()
    localJob.archivedAt = nil
    localJob.sortOrder = sortOrder
    localJob.dirtyFieldKeys.insert(.archivedAt)
    localJob.dirtyFieldKeys.insert(.sortOrder)
    localJob.localUpdatedAt = now
    if localJob.syncStatus == .clean {
      localJob.syncStatus = .dirty
    }

    try modelContext.save()
    return localJob.userId
  }

  internal func reorderJobs(userId: String, orderedJobIds: [String]) throws {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId && job.deletedAt == nil && job.archivedAt == nil
      }
    )

    let jobs = try modelContext.fetch(descriptor)
    let now = Date()
    let orderById = Dictionary(uniqueKeysWithValues: orderedJobIds.enumerated().map { ($1, $0) })

    for job in jobs {
      guard let newOrder = orderById[job.id], job.sortOrder != newOrder else { continue }
      job.sortOrder = newOrder
      job.dirtyFieldKeys.insert(.sortOrder)
      job.localUpdatedAt = now
      if job.syncStatus == .clean {
        job.syncStatus = .dirty
      }
    }

    try modelContext.save()
  }

  // Also used to roll back failed creation and discard incomplete onboarding jobs.
  internal func markJobPendingDelete(id: String) throws -> String {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    let now = Date()
    localJob.deletedAt = now
    localJob.isDefault = false
    localJob.syncStatus = .pendingDelete
    localJob.dirtyFieldKeys.insert(.deletedAt)
    localJob.dirtyFieldKeys.insert(.isDefault)
    localJob.localUpdatedAt = now

    try modelContext.save()
    return localJob.userId
  }

  internal func resolveStoredJobConflictKeepLocal(id: String) throws {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localJob.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    guard
      let serverSnapshot = JobServerSnapshot.decode(
        from: localJob.conflictServerSnapshot ?? Data()
      )
    else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localJob.serverRevision = serverSnapshot.revision
    localJob.serverUpdatedAt = serverSnapshot.updatedAt
    localJob.syncStatus = .dirty
    localJob.conflictServerSnapshot = nil
    localJob.localUpdatedAt = Date()

    try modelContext.save()
  }

  internal func resolveStoredJobConflictKeepServer(id: String) throws {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localJob.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    let conflictData = localJob.conflictServerSnapshot ?? Data()
    guard let serverSnapshot = JobServerSnapshot.decode(from: conflictData) else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localJob.name = serverSnapshot.name
    localJob.color = serverSnapshot.color
    localJob.currency = serverSnapshot.currency
    localJob.isDefault = serverSnapshot.isDefault
    localJob.sortOrder = serverSnapshot.sortOrder
    localJob.payrollDay = serverSnapshot.payrollDay
    localJob.halfTaxMonth = serverSnapshot.halfTaxMonth
    localJob.payPeriodJSON = serverSnapshot.payPeriod.storageJSON
    localJob.monthlyGoal = serverSnapshot.monthlyGoal
    localJob.archivedAt = serverSnapshot.archivedAt
    localJob.deletedAt = serverSnapshot.deletedAt
    localJob.serverRevision = serverSnapshot.revision
    localJob.serverUpdatedAt = serverSnapshot.updatedAt
    localJob.syncStatus = .clean
    localJob.dirtyFieldKeys = []
    localJob.lastSyncedSnapshot = conflictData
    localJob.conflictServerSnapshot = nil
    localJob.localUpdatedAt = Date()

    try modelContext.save()
  }
}
