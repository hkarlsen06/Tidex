import Foundation

/// Server-verified counts and a version token for an explicit deletion confirmation.
struct JobDeletionPreview: Decodable {
  let jobId: String
  let userId: String
  let jobName: String
  let jobRevision: Int64
  let confirmationToken: String
  let userShifts: Int
  let recurringShifts: Int
  let payrollAdjustments: Int
  let wageSnapshots: Int
  let deletedAtEpoch: TimeInterval?

  enum CodingKeys: String, CodingKey {
    case jobId = "job_id"
    case userId = "user_id"
    case jobName = "job_name"
    case jobRevision = "job_revision"
    case confirmationToken = "confirmation_token"
    case userShifts = "user_shifts"
    case recurringShifts = "recurring_shifts"
    case payrollAdjustments = "payroll_adjustments"
    case wageSnapshots = "wage_snapshots"
    case deletedAtEpoch = "deleted_at_epoch"
  }

  var confirmationMessage: String {
    String(
      localized: .settingsPayJobActionsDeleteHistoryConfirmMessage(
        jobName, userShifts.formatted(), recurringShifts.formatted(),
        payrollAdjustments.formatted(), wageSnapshots.formatted()
      ))
  }
}
