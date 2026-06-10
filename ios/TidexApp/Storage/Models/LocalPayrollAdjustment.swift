// swiftlint:disable cyclomatic_complexity explicit_acl
// swiftlint:disable:previous blanket_disable_command
import Foundation
import SwiftData

private func parsePayrollAdjustmentISO8601(_ string: String) -> Date? {
  let fractional = ISO8601DateFormatter()
  fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  let internet = ISO8601DateFormatter()
  internet.formatOptions = [.withInternetDateTime]
  return fractional.date(from: string)
    ?? internet.date(from: string)
    ?? ISO8601DateFormatter().date(from: string)
}

private func formatPayrollAdjustmentTimestamp(_ date: Date) -> String {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter.string(from: date)
}

@Model
final class LocalPayrollAdjustment {
  @Attribute(.unique)
  var id: String
  var userId: String
  var jobId: String?
  var amount: Double
  var currency: String
  var categoryRaw: String
  var taxTreatmentRaw: String
  @Attribute(originalName: "title")
  var descriptionText: String
  var note: String?
  var curatedNote: String?
  var curatedDescription: String?
  var curatedLink: String?
  var curatedLinkTitle: String?
  var earnedFromDate: Date?
  var earnedToDate: Date?
  var payoutDate: Date

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

  var category: PayrollAdjustmentCategory {
    get { PayrollAdjustmentCategory(rawValue: categoryRaw) ?? .other }
    set { categoryRaw = newValue.rawValue }
  }

  var taxTreatment: PayrollAdjustmentTaxTreatment {
    get { PayrollAdjustmentTaxTreatment(rawValue: taxTreatmentRaw) ?? .grossTaxable }
    set { taxTreatmentRaw = newValue.rawValue }
  }

  var dirtyFieldKeys: Set<PayrollAdjustmentField> {
    get {
      guard !dirtyFields.isEmpty else { return [] }
      do {
        let keys = try kSyncJSONDecoder.decode([String].self, from: dirtyFields)
        return Set(keys.compactMap { PayrollAdjustmentField(rawValue: $0) })
      } catch {
        SyncLogger.shared.log(
          "Corrupted dirtyFields for payroll adjustment \(id), treating as fully dirty: \(error.localizedDescription)",
          level: .error
        )
        return Set(PayrollAdjustmentField.allCases)
      }
    }
    set {
      dirtyFields = (try? kCanonicalJSONEncoder.encode(newValue.map(\.rawValue))) ?? Data()
    }
  }

  var payoutDateString: String {
    FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone).string(from: payoutDate)
  }

  var earnedFromDateString: String? {
    earnedFromDate.map {
      FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone).string(from: $0)
    }
  }

  var earnedToDateString: String? {
    earnedToDate.map {
      FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone).string(from: $0)
    }
  }

  init(
    id: String,
    userId: String,
    jobId: String? = nil,
    amount: Double,
    currency: String,
    category: PayrollAdjustmentCategory,
    taxTreatment: PayrollAdjustmentTaxTreatment,
    description: String,
    note: String? = nil,
    curatedNote: String? = nil,
    curatedDescription: String? = nil,
    curatedLink: String? = nil,
    curatedLinkTitle: String? = nil,
    earnedFromDate: Date? = nil,
    earnedToDate: Date? = nil,
    payoutDate: Date,
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
    self.jobId = jobId
    self.amount = amount
    self.currency = currency
    self.categoryRaw = category.rawValue
    self.taxTreatmentRaw = taxTreatment.rawValue
    self.descriptionText = description
    self.note = note
    self.curatedNote = curatedNote
    self.curatedDescription = curatedDescription
    self.curatedLink = curatedLink
    self.curatedLinkTitle = curatedLinkTitle
    self.earnedFromDate = earnedFromDate
    self.earnedToDate = earnedToDate
    self.payoutDate = payoutDate
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
    (try? kCanonicalJSONEncoder.encode([String]())) ?? Data()
  }
}

struct PayrollAdjustmentServerSnapshot: Codable, Equatable {
  let jobId: String?
  let amount: Double
  let currency: String
  let category: PayrollAdjustmentCategory
  let taxTreatment: PayrollAdjustmentTaxTreatment
  let description: String
  let note: String?
  let curatedNote: String?
  let curatedDescription: String?
  let curatedLink: String?
  let curatedLinkTitle: String?
  let earnedFromDate: String?
  let earnedToDate: String?
  let payoutDate: String
  let updatedAt: Date
  let revision: Int64
  let deletedAt: Date?

  func encoded() -> Data {
    (try? kCanonicalJSONEncoder.encode(self)) ?? Data()
  }

  static func decode(from data: Data) -> Self? {
    try? kSyncJSONDecoder.decode(Self.self, from: data)
  }

  static func from(
    row: SyncPayrollAdjustmentRow,
    updatedAt: Date,
    deletedAt: Date?
  ) -> Self {
    Self(
      jobId: row.job_id,
      amount: row.amount,
      currency: row.currency,
      category: row.category,
      taxTreatment: row.tax_treatment,
      description: row.description,
      note: row.note,
      curatedNote: row.curated_note,
      curatedDescription: row.curated_description,
      curatedLink: row.curated_link,
      curatedLinkTitle: row.curated_link_title,
      earnedFromDate: row.earned_from_date,
      earnedToDate: row.earned_to_date,
      payoutDate: row.payout_date,
      updatedAt: updatedAt,
      revision: row.revision,
      deletedAt: deletedAt
    )
  }

  func changedFields(from other: Self) -> Set<PayrollAdjustmentField> {
    var changed: Set<PayrollAdjustmentField> = []
    if jobId != other.jobId { changed.insert(.jobId) }
    if amount != other.amount { changed.insert(.amount) }
    if currency != other.currency { changed.insert(.currency) }
    if category != other.category { changed.insert(.category) }
    if taxTreatment != other.taxTreatment { changed.insert(.taxTreatment) }
    if description != other.description { changed.insert(.description) }
    if note != other.note { changed.insert(.note) }
    if curatedNote != other.curatedNote { changed.insert(.curatedNote) }
    if curatedDescription != other.curatedDescription { changed.insert(.curatedDescription) }
    if curatedLink != other.curatedLink { changed.insert(.curatedLink) }
    if curatedLinkTitle != other.curatedLinkTitle { changed.insert(.curatedLinkTitle) }
    if earnedFromDate != other.earnedFromDate { changed.insert(.earnedFromDate) }
    if earnedToDate != other.earnedToDate { changed.insert(.earnedToDate) }
    if payoutDate != other.payoutDate { changed.insert(.payoutDate) }
    return changed
  }
}

extension LocalPayrollAdjustment {
  func toPayrollAdjustment() -> PayrollAdjustment {
    PayrollAdjustment(
      id: id,
      user_id: userId,
      job_id: jobId,
      amount: amount,
      currency: currency,
      category: category,
      tax_treatment: taxTreatment,
      description: descriptionText,
      note: note,
      curated_note: curatedNote,
      curated_description: curatedDescription,
      curated_link: curatedLink,
      curated_link_title: curatedLinkTitle,
      earned_from_date: earnedFromDateString,
      earned_to_date: earnedToDateString,
      payout_date: payoutDateString,
      created_at: nil,
      updated_at: formatPayrollAdjustmentTimestamp(serverUpdatedAt),
      revision: serverRevision,
      deleted_at: serverDeletedAt.map(formatPayrollAdjustmentTimestamp)
    )
  }

  static func from(serverRow: SyncPayrollAdjustmentRow, serverUpdatedAt: Date)
    -> LocalPayrollAdjustment
  {
    let dateFormatter = FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone)
    let deletedAt = serverRow.deleted_at.flatMap { parsePayrollAdjustmentISO8601($0) }
    let snapshot = PayrollAdjustmentServerSnapshot.from(
      row: serverRow,
      updatedAt: serverUpdatedAt,
      deletedAt: deletedAt
    )

    return LocalPayrollAdjustment(
      id: serverRow.id,
      userId: serverRow.user_id,
      jobId: serverRow.job_id,
      amount: serverRow.amount,
      currency: serverRow.currency,
      category: serverRow.category,
      taxTreatment: serverRow.tax_treatment,
      description: serverRow.description,
      note: serverRow.note,
      curatedNote: serverRow.curated_note,
      curatedDescription: serverRow.curated_description,
      curatedLink: serverRow.curated_link,
      curatedLinkTitle: serverRow.curated_link_title,
      earnedFromDate: serverRow.earned_from_date.flatMap { dateFormatter.date(from: $0) },
      earnedToDate: serverRow.earned_to_date.flatMap { dateFormatter.date(from: $0) },
      payoutDate: dateFormatter.date(from: serverRow.payout_date) ?? Date(),
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRow.revision,
      serverDeletedAt: deletedAt,
      syncStatus: .clean,
      dirtyFields: emptyDirtyFields(),
      lastSyncedSnapshot: snapshot.encoded(),
      localUpdatedAt: Date()
    )
  }
}
