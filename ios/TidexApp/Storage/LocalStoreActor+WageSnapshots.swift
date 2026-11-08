import Foundation
import SwiftData
import os.log

extension LocalStoreActor {

  // MARK: - Wage Snapshot Operations

  /// Upsert a wage snapshot from server data
  internal func upsertWageSnapshot(_ snapshot: LocalWageSnapshot) throws {
    let snapshotId = snapshot.id
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == snapshotId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      // Update existing
      existing.jobId = snapshot.jobId
      existing.fromDate = snapshot.fromDate
      existing.hourlyWage = snapshot.hourlyWage
      existing.wageLevel = snapshot.wageLevel
      existing.supplements = snapshot.supplements
      existing.taxEnabled = snapshot.taxEnabled
      existing.taxPercentage = snapshot.taxPercentage
      existing.breakEnabled = snapshot.breakEnabled
      existing.breakMethod = snapshot.breakMethod
      existing.breakThresholdHours = snapshot.breakThresholdHours
      existing.breakDeductionMinutes = snapshot.breakDeductionMinutes
      existing.serverUpdatedAt = snapshot.serverUpdatedAt
      existing.serverRevision = snapshot.serverRevision
      existing.serverDeletedAt = snapshot.serverDeletedAt
      existing.syncStatusRaw = snapshot.syncStatusRaw
      existing.dirtyFields = snapshot.dirtyFields
      existing.lastSyncedSnapshot = snapshot.lastSyncedSnapshot
      existing.localUpdatedAt = snapshot.localUpdatedAt
      existing.conflictServerSnapshot = snapshot.conflictServerSnapshot
    } else {
      // Insert new
      modelContext.insert(snapshot)
    }
  }

  /// Get wage snapshot by ID
  internal func getWageSnapshot(id: String) throws -> LocalWageSnapshot? {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  /// Get all wage snapshots for a user
  internal func getAllWageSnapshots(userId: String) throws -> [LocalWageSnapshot] {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.userId == userId },
      sortBy: [SortDescriptor(\.fromDate, order: .reverse)]
    )
    return try modelContext.fetch(descriptor)
  }

  /// Get dirty wage snapshots that need to be pushed
  internal func getDirtyWageSnapshots(userId: String) throws -> [LocalWageSnapshot] {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { snapshot in
        snapshot.userId == userId
          && (snapshot.syncStatusRaw == "dirty" || snapshot.syncStatusRaw == "pendingDelete"
            // Include conflict records that were never synced (serverRevision=0)
            // These are new local records that failed initial sync and need INSERT
            || (snapshot.syncStatusRaw == "conflict" && snapshot.serverRevision == 0))
      }
    )
    return try modelContext.fetch(descriptor)
  }

  internal func hasDirtyWageSnapshots(userId: String) throws -> Bool {
    var descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { snapshot in
        snapshot.userId == userId
          && (snapshot.syncStatusRaw == "dirty" || snapshot.syncStatusRaw == "pendingDelete"
            || (snapshot.syncStatusRaw == "conflict" && snapshot.serverRevision == 0))
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  // MARK: - Local Wage Snapshot Write Operations

  // swiftlint:disable:next function_parameter_count
  internal func createWageSnapshot(
    userId: String,
    jobId: String? = nil,
    fromDate: Date?,
    hourlyWage: Double,
    wageLevel: Int?,
    tariffTypeId: String?,
    supplements: SupplementRulesSnapshot,
    overtime: OvertimeConfig = .disabled,
    taxEnabled: Bool?,
    taxPercentage: Double?,
    breakEnabled: Bool?,
    breakMethod: String?,
    breakThresholdHours: Double?,
    breakDeductionMinutes: Int?
  ) throws -> WageSnapshot {
    let id = UUID().lowercasedString
    let now = Date()

    let supplementsData = (try? kCanonicalJSONEncoder.encode(supplements)) ?? Data()
    let overtimeData = (try? kCanonicalJSONEncoder.encode(overtime)) ?? Data()

    let dateFormatter = isoDateFormatter
    let fromDateString = fromDate.map { dateFormatter.string(from: $0) }

    let serverSnapshot = WageSnapshotServerSnapshot(
      jobId: jobId,
      fromDate: fromDateString,
      hourlyWage: hourlyWage,
      wageLevel: wageLevel,
      tariffTypeId: tariffTypeId,
      supplements: supplementsData,
      overtime: overtimeData,
      taxEnabled: taxEnabled,
      taxPercentage: taxPercentage,
      breakEnabled: breakEnabled,
      breakMethod: breakMethod,
      breakThresholdHours: breakThresholdHours,
      breakDeductionMinutes: breakDeductionMinutes,
      updatedAt: now,
      revision: 0,
      deletedAt: nil
    )

    let allFields = WageSnapshotField.allCases.map(\.rawValue)
    let dirtyFieldsData = (try? kCanonicalJSONEncoder.encode(allFields)) ?? Data()

    let localSnapshot = LocalWageSnapshot(
      id: id,
      userId: userId,
      jobId: jobId,
      fromDate: fromDate,
      hourlyWage: hourlyWage,
      wageLevel: wageLevel,
      tariffTypeId: tariffTypeId,
      supplements: supplementsData,
      overtime: overtimeData,
      taxEnabled: taxEnabled,
      taxPercentage: taxPercentage,
      breakEnabled: breakEnabled,
      breakMethod: breakMethod,
      breakThresholdHours: breakThresholdHours,
      breakDeductionMinutes: breakDeductionMinutes,
      serverUpdatedAt: now,
      serverRevision: 0,
      serverDeletedAt: nil,
      syncStatus: .dirty,
      dirtyFields: dirtyFieldsData,
      lastSyncedSnapshot: serverSnapshot.encoded(),
      localUpdatedAt: now,
      conflictServerSnapshot: nil
    )

    modelContext.insert(localSnapshot)
    try modelContext.save()
    return localSnapshot.toWageSnapshot()
  }

  // swiftlint:disable:next function_parameter_count
  internal func updateWageSnapshot(
    id: String,
    jobId: String? = nil,
    fromDate: Date? = nil,
    hourlyWage: Double?,
    wageLevel: Int?,
    updateWageLevel: Bool = false,
    tariffTypeId: String?,
    updateTariffTypeId: Bool = false,
    supplements: SupplementRulesSnapshot?,
    overtime: OvertimeConfig? = nil,
    taxEnabled: Bool?,
    taxPercentage: Double?,
    updateTaxPercentage: Bool = false,
    breakEnabled: Bool?,
    breakMethod: String?,
    breakThresholdHours: Double?,
    breakDeductionMinutes: Int?
  ) throws -> WageSnapshot {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localSnapshot = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    if let fromDate {
      guard !localSnapshot.isBaseline else {
        throw WageSnapshotDateError.baselineMustRemainUndated
      }
      let userId = localSnapshot.userId
      let effectiveJobId = jobId ?? localSnapshot.jobId
      let snapshots = try modelContext.fetch(
        FetchDescriptor<LocalWageSnapshot>(
          predicate: #Predicate {
            $0.userId == userId && $0.serverDeletedAt == nil && $0.syncStatusRaw != "pendingDelete"
          }
        ))
      guard
        !snapshots.contains(where: {
          $0.id != id && $0.jobId == effectiveJobId
            && $0.fromDateString == fromDate.toISODateString()
        })
      else {
        throw WageSnapshotDateError.dateConflict
      }
    }

    var newDirtyFields = localSnapshot.dirtyFieldKeys
    let now = Date()

    if let fromDate, fromDate.toISODateString() != localSnapshot.fromDateString {
      localSnapshot.fromDate = Calendar.gregorianCurrent.startOfDay(for: fromDate)
      newDirtyFields.insert(.fromDate)
    }

    if let newJobId = jobId, newJobId != localSnapshot.jobId {
      localSnapshot.jobId = newJobId
      newDirtyFields.insert(.jobId)
    }

    if let newWage = hourlyWage, newWage != localSnapshot.hourlyWage {
      localSnapshot.hourlyWage = newWage
      newDirtyFields.insert(.hourlyWage)
    }

    if updateWageLevel, wageLevel != localSnapshot.wageLevel {
      localSnapshot.wageLevel = wageLevel
      newDirtyFields.insert(.wageLevel)
    }

    if updateTariffTypeId, tariffTypeId != localSnapshot.tariffTypeId {
      localSnapshot.tariffTypeId = tariffTypeId
      newDirtyFields.insert(.tariffTypeId)
    }

    if let newSupplements = supplements {
      let newData = (try? kCanonicalJSONEncoder.encode(newSupplements)) ?? Data()
      if newData != localSnapshot.supplements {
        localSnapshot.supplements = newData
        newDirtyFields.insert(.supplements)
      }
    }

    if let newOvertime = overtime {
      let newData = (try? kCanonicalJSONEncoder.encode(newOvertime)) ?? Data()
      if newData != localSnapshot.overtime {
        localSnapshot.overtime = newData
        newDirtyFields.insert(.overtime)
      }
    }

    if let newTaxEnabled = taxEnabled, newTaxEnabled != localSnapshot.taxEnabled {
      localSnapshot.taxEnabled = newTaxEnabled
      newDirtyFields.insert(.taxEnabled)
    }

    if updateTaxPercentage, taxPercentage != localSnapshot.taxPercentage {
      localSnapshot.taxPercentage = taxPercentage
      newDirtyFields.insert(.taxPercentage)
    }

    if let newBreakEnabled = breakEnabled, newBreakEnabled != localSnapshot.breakEnabled {
      localSnapshot.breakEnabled = newBreakEnabled
      newDirtyFields.insert(.breakEnabled)
    }

    if let newBreakMethod = breakMethod, newBreakMethod != localSnapshot.breakMethod {
      localSnapshot.breakMethod = newBreakMethod
      newDirtyFields.insert(.breakMethod)
    }

    if let newThreshold = breakThresholdHours, newThreshold != localSnapshot.breakThresholdHours {
      localSnapshot.breakThresholdHours = newThreshold
      newDirtyFields.insert(.breakThresholdHours)
    }

    if let newDeduction = breakDeductionMinutes, newDeduction != localSnapshot.breakDeductionMinutes
    {
      localSnapshot.breakDeductionMinutes = newDeduction
      newDirtyFields.insert(.breakDeductionMinutes)
    }

    localSnapshot.dirtyFieldKeys = newDirtyFields
    localSnapshot.localUpdatedAt = now

    if !newDirtyFields.isEmpty, localSnapshot.syncStatus == .clean {
      localSnapshot.syncStatus = .dirty
    }

    try modelContext.save()
    return localSnapshot.toWageSnapshot()
  }

  internal func markWageSnapshotPendingDelete(id: String) throws {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localSnapshot = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    localSnapshot.syncStatus = .pendingDelete
    localSnapshot.localUpdatedAt = Date()

    try modelContext.save()
  }

  internal func resolveStoredWageSnapshotConflictKeepLocal(id: String) throws {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localSnapshot = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localSnapshot.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    guard
      let serverSnapshot = WageSnapshotServerSnapshot.decode(
        from: localSnapshot.conflictServerSnapshot ?? Data()
      )
    else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localSnapshot.serverRevision = serverSnapshot.revision
    localSnapshot.serverUpdatedAt = serverSnapshot.updatedAt
    localSnapshot.syncStatus = .dirty
    localSnapshot.conflictServerSnapshot = nil
    localSnapshot.localUpdatedAt = Date()

    try modelContext.save()
  }

  internal func resolveStoredWageSnapshotConflictKeepServer(id: String) throws {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localSnapshot = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localSnapshot.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    let conflictData = localSnapshot.conflictServerSnapshot ?? Data()
    guard let serverSnapshot = WageSnapshotServerSnapshot.decode(from: conflictData) else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    let dateFormatter = isoDateFormatter

    localSnapshot.fromDate = serverSnapshot.fromDate.flatMap { dateFormatter.date(from: $0) }
    localSnapshot.jobId = serverSnapshot.jobId
    localSnapshot.hourlyWage = serverSnapshot.hourlyWage
    localSnapshot.wageLevel = serverSnapshot.wageLevel
    localSnapshot.tariffTypeId = serverSnapshot.tariffTypeId
    localSnapshot.supplements = serverSnapshot.supplements
    localSnapshot.taxEnabled = serverSnapshot.taxEnabled
    localSnapshot.taxPercentage = serverSnapshot.taxPercentage
    localSnapshot.breakEnabled = serverSnapshot.breakEnabled
    localSnapshot.breakMethod = serverSnapshot.breakMethod
    localSnapshot.breakThresholdHours = serverSnapshot.breakThresholdHours
    localSnapshot.breakDeductionMinutes = serverSnapshot.breakDeductionMinutes
    localSnapshot.serverRevision = serverSnapshot.revision
    localSnapshot.serverUpdatedAt = serverSnapshot.updatedAt
    localSnapshot.serverDeletedAt = serverSnapshot.deletedAt
    localSnapshot.syncStatus = .clean
    localSnapshot.dirtyFieldKeys = []
    localSnapshot.lastSyncedSnapshot = conflictData
    localSnapshot.conflictServerSnapshot = nil
    localSnapshot.localUpdatedAt = Date()

    try modelContext.save()
  }
}
