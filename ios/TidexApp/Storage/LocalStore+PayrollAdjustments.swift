import Foundation
import SwiftData

extension LocalStoreActor {
  private var payrollAdjustmentDateFormatter: DateFormatter {
    FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone)
  }

  func getPayrollAdjustment(id: String) throws -> LocalPayrollAdjustment? {
    let descriptor = FetchDescriptor<LocalPayrollAdjustment>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  func getAllPayrollAdjustments(userId: String) throws -> [LocalPayrollAdjustment] {
    let descriptor = FetchDescriptor<LocalPayrollAdjustment>(
      predicate: #Predicate { $0.userId == userId },
      sortBy: [SortDescriptor(\LocalPayrollAdjustment.payoutDate)]
    )
    return try modelContext.fetch(descriptor)
  }

  func getDirtyPayrollAdjustments(userId: String) throws -> [LocalPayrollAdjustment] {
    let descriptor = FetchDescriptor<LocalPayrollAdjustment>(
      predicate: #Predicate { adjustment in
        adjustment.userId == userId
          && (adjustment.syncStatusRaw == "dirty" || adjustment.syncStatusRaw == "pendingDelete")
      }
    )
    return try modelContext.fetch(descriptor)
  }

  func hasDirtyPayrollAdjustments(userId: String) throws -> Bool {
    var descriptor = FetchDescriptor<LocalPayrollAdjustment>(
      predicate: #Predicate { adjustment in
        adjustment.userId == userId
          && (adjustment.syncStatusRaw == "dirty" || adjustment.syncStatusRaw == "pendingDelete")
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  func upsertPayrollAdjustment(_ adjustment: LocalPayrollAdjustment) throws {
    let adjustmentId = adjustment.id
    let descriptor = FetchDescriptor<LocalPayrollAdjustment>(
      predicate: #Predicate { $0.id == adjustmentId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      existing.userId = adjustment.userId
      existing.jobId = adjustment.jobId
      existing.amount = adjustment.amount
      existing.currency = adjustment.currency
      existing.categoryRaw = adjustment.categoryRaw
      existing.taxTreatmentRaw = adjustment.taxTreatmentRaw
      existing.descriptionText = adjustment.descriptionText
      existing.note = adjustment.note
      existing.curatedNote = adjustment.curatedNote
      existing.curatedDescription = adjustment.curatedDescription
      existing.curatedLink = adjustment.curatedLink
      existing.curatedLinkTitle = adjustment.curatedLinkTitle
      existing.earnedFromDate = adjustment.earnedFromDate
      existing.earnedToDate = adjustment.earnedToDate
      existing.payoutDate = adjustment.payoutDate
      existing.serverUpdatedAt = adjustment.serverUpdatedAt
      existing.serverRevision = adjustment.serverRevision
      existing.serverDeletedAt = adjustment.serverDeletedAt
      existing.syncStatusRaw = adjustment.syncStatusRaw
      existing.dirtyFields = adjustment.dirtyFields
      existing.lastSyncedSnapshot = adjustment.lastSyncedSnapshot
      existing.localUpdatedAt = adjustment.localUpdatedAt
      existing.conflictServerSnapshot = adjustment.conflictServerSnapshot
    } else {
      modelContext.insert(adjustment)
    }
  }

  // swiftlint:disable:next function_parameter_count
  func createPayrollAdjustment(
    userId: String,
    jobId: String?,
    amount: Double,
    currency: String,
    category: PayrollAdjustmentCategory,
    taxTreatment: PayrollAdjustmentTaxTreatment,
    description: String,
    note: String?,
    earnedFromDate: Date?,
    earnedToDate: Date?,
    payoutDate: Date
  ) throws -> PayrollAdjustment {
    let id = UUID().lowercasedString
    let now = Date()
    let snapshot = PayrollAdjustmentServerSnapshot(
      jobId: jobId,
      amount: amount,
      currency: currency,
      category: category,
      taxTreatment: taxTreatment,
      description: description,
      note: note,
      curatedNote: nil,
      curatedDescription: nil,
      curatedLink: nil,
      curatedLinkTitle: nil,
      earnedFromDate: earnedFromDate.map { payrollAdjustmentDateFormatter.string(from: $0) },
      earnedToDate: earnedToDate.map { payrollAdjustmentDateFormatter.string(from: $0) },
      payoutDate: payrollAdjustmentDateFormatter.string(from: payoutDate),
      updatedAt: now,
      revision: 0,
      deletedAt: nil
    )
    let dirtyFields =
      (try? kCanonicalJSONEncoder.encode(PayrollAdjustmentField.allCases.map(\.rawValue)))
      ?? Data()
    let local = LocalPayrollAdjustment(
      id: id,
      userId: userId,
      jobId: jobId,
      amount: amount,
      currency: currency,
      category: category,
      taxTreatment: taxTreatment,
      description: description,
      note: note,
      curatedNote: nil,
      curatedDescription: nil,
      curatedLink: nil,
      curatedLinkTitle: nil,
      earnedFromDate: earnedFromDate,
      earnedToDate: earnedToDate,
      payoutDate: payoutDate,
      serverUpdatedAt: now,
      serverRevision: 0,
      syncStatus: .dirty,
      dirtyFields: dirtyFields,
      lastSyncedSnapshot: snapshot.encoded(),
      localUpdatedAt: now
    )

    modelContext.insert(local)
    try modelContext.save()
    return local.toPayrollAdjustment()
  }

  func markPayrollAdjustmentPendingDelete(id: String) throws {
    guard let existing = try getPayrollAdjustment(id: id) else {
      throw LocalStoreWriteError.notFound
    }
    // Keep the row even before its first push. An insert may be in flight, and its completion
    // needs the row to learn the server revision so the delete reaches the server.
    existing.syncStatus = .pendingDelete
    existing.localUpdatedAt = Date()
    try modelContext.save()
  }

  // swiftlint:disable:next function_parameter_count
  func updatePayrollAdjustment(
    id: String,
    jobId: String?,
    amount: Double,
    currency: String,
    category: PayrollAdjustmentCategory,
    taxTreatment: PayrollAdjustmentTaxTreatment,
    description: String,
    note: String?,
    earnedFromDate: Date?,
    earnedToDate: Date?,
    payoutDate: Date
  ) throws -> PayrollAdjustment {
    guard let existing = try getPayrollAdjustment(id: id) else {
      throw LocalStoreWriteError.notFound
    }

    existing.jobId = jobId
    existing.amount = amount
    existing.currency = currency
    existing.category = category
    existing.taxTreatment = taxTreatment
    existing.descriptionText = description
    existing.note = note
    existing.earnedFromDate = earnedFromDate
    existing.earnedToDate = earnedToDate
    existing.payoutDate = payoutDate
    existing.localUpdatedAt = Date()
    existing.syncStatus = .dirty
    existing.dirtyFieldKeys = Set(PayrollAdjustmentField.allCases)
    try modelContext.save()
    return existing.toPayrollAdjustment()
  }

  func updatePayrollAdjustmentFromServer(
    id: String,
    serverRow: SyncPayrollAdjustmentRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    snapshot: PayrollAdjustmentServerSnapshot
  ) {
    guard let existing = try? getPayrollAdjustment(id: id) else {
      return
    }
    let formatter = payrollAdjustmentDateFormatter
    existing.jobId = serverRow.job_id
    existing.amount = serverRow.amount
    existing.currency = serverRow.currency
    existing.category = serverRow.category
    existing.taxTreatment = serverRow.tax_treatment
    existing.descriptionText = serverRow.description
    existing.note = serverRow.note
    existing.curatedNote = serverRow.curated_note
    existing.curatedDescription = serverRow.curated_description
    existing.curatedLink = serverRow.curated_link
    existing.curatedLinkTitle = serverRow.curated_link_title
    existing.earnedFromDate = serverRow.earned_from_date.flatMap { formatter.date(from: $0) }
    existing.earnedToDate = serverRow.earned_to_date.flatMap { formatter.date(from: $0) }
    existing.payoutDate = formatter.date(from: serverRow.payout_date) ?? existing.payoutDate
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRow.revision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()
  }

  // swiftlint:disable:next function_parameter_count
  func markPayrollAdjustmentPushed(
    id: String,
    serverRow: SyncPayrollAdjustmentRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    snapshot: PayrollAdjustmentServerSnapshot,
    baseline: SyncPushBaseline
  ) {
    guard let existing = try? getPayrollAdjustment(id: id) else {
      return
    }
    if keepChangesMadeDuringPush(
      existing,
      baseline: baseline,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRow.revision,
      snapshot: snapshot.encoded()
    ) {
      return
    }
    updatePayrollAdjustmentFromServer(
      id: id,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverDeletedAt: serverDeletedAt,
      snapshot: snapshot
    )
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  /// Merges a newer server row into a dirty local adjustment.
  /// Pushes send the whole row, so this merges whole rows. The server row replaces the local
  /// values when no local value still needs pushing. Otherwise the local values stay and only
  /// the server revision is adopted, so the next push updates the server row.
  func mergePayrollAdjustmentFromServer(
    id: String,
    serverRow: SyncPayrollAdjustmentRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    snapshot: PayrollAdjustmentServerSnapshot
  ) {
    guard let existing = try? getPayrollAdjustment(id: id) else {
      return
    }
    let keepLocal = SyncMerge.fieldsToKeepLocally(existing, server: snapshot)
    if keepLocal.isEmpty {
      updatePayrollAdjustmentFromServer(
        id: id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        snapshot: snapshot
      )
    } else {
      adoptServerRevision(
        existing,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: serverRow.revision,
        snapshot: snapshot.encoded()
      )
    }
    settleMergedDirtyFields(existing, keepingLocal: keepLocal)
  }

  func markPayrollAdjustmentClean(id: String) {
    guard let existing = try? getPayrollAdjustment(id: id) else {
      return
    }
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  func markPayrollAdjustmentDeleted(
    id: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?
  ) {
    guard let existing = try? getPayrollAdjustment(id: id) else {
      return
    }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  func markMissingCleanPayrollAdjustmentsDeleted(userId: String, serverIds: Set<String>) throws
    -> (count: Int, affectedMonths: Set<ShiftChangeAffectedMonth>)
  {
    let adjustments = try getAllPayrollAdjustments(userId: userId)
    let deletedAt = Date()
    var deletedCount = 0
    var affectedMonths: Set<ShiftChangeAffectedMonth> = []

    for adjustment in adjustments
    where adjustment.syncStatus == .clean
      && adjustment.serverDeletedAt == nil
      && !serverIds.contains(adjustment.id)
    {
      affectedMonths.insert(ShiftChangeAffectedMonth(date: adjustment.payoutDate))
      adjustment.serverDeletedAt = deletedAt
      adjustment.syncStatus = .clean
      adjustment.dirtyFieldKeys = []
      adjustment.conflictServerSnapshot = nil
      deletedCount += 1
    }

    if deletedCount > 0 {
      try modelContext.save()
    }

    return (deletedCount, affectedMonths)
  }

  func markPayrollAdjustmentConflict(
    id: String,
    serverSnapshot: PayrollAdjustmentServerSnapshot?
  ) {
    guard let existing = try? getPayrollAdjustment(id: id) else {
      return
    }
    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }
}
