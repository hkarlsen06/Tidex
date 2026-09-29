import Foundation

struct JobBaselineSnapshotInput {
  let hourlyWage: Double
  let wageLevel: Int?
  let tariffTypeId: String?
  let supplements: SupplementRulesSnapshot
  let overtime: OvertimeConfig
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
  case jobDeleted
  case cannotChangeTariffJobCurrency
  case cannotArchiveLastActiveJob
  case cannotArchiveDefaultJob
  case cannotDeleteUnarchivedJob
  case cannotDeleteDefaultJob
  case cannotDeleteJobWithHistory
  case deletionSyncRequired
  case deletionChanged
  case deletionRefreshFailed
  case cannotSetArchivedOrDeletedDefault

  var errorDescription: String? {
    switch self {
    case .jobNameEmpty:
      return String(localized: .settingsPayErrorJobNameEmpty)

    case .jobNotFound:
      return String(localized: .settingsPayErrorJobNotFound)

    case .jobDeleted:
      return String(localized: .settingsPayErrorJobDeleted)

    case .cannotChangeTariffJobCurrency:
      return String(localized: .settingsPayErrorTariffCurrencyLocked)

    case .cannotArchiveLastActiveJob:
      return String(localized: .settingsPayErrorCannotArchiveLastActiveJob)

    case .cannotArchiveDefaultJob:
      return String(localized: .settingsPayErrorCannotArchiveDefaultJob)

    case .cannotDeleteUnarchivedJob:
      return String(localized: .settingsPayErrorArchiveBeforeDeleting)

    case .cannotDeleteDefaultJob:
      return String(localized: .settingsPayErrorCannotDeleteDefaultJob)

    case .cannotDeleteJobWithHistory:
      return String(localized: .settingsPayErrorCannotDeleteWorkplaceWithHistoryMessage)

    case .deletionSyncRequired:
      return String(localized: .settingsPayErrorDeletionSyncRequired)

    case .deletionChanged:
      return String(localized: .settingsPayErrorDeletionChanged)

    case .deletionRefreshFailed:
      return String(localized: .settingsPayErrorDeletionRefreshFailed)

    case .cannotSetArchivedOrDeletedDefault:
      return String(localized: .settingsPayErrorCannotSetInactiveDefault)
    }
  }

  var alertTitle: String? {
    switch self {
    case .cannotDeleteJobWithHistory:
      return String(localized: .settingsPayErrorCannotDeleteWorkplaceWithHistoryTitle)

    default:
      return nil
    }
  }
}

struct JobDeletionDependencyCounts: Equatable {
  let userShifts: Int
  let recurringShifts: Int
  let payrollAdjustments: Int

  var total: Int {
    userShifts + recurringShifts + payrollAdjustments
  }
}

enum JobDeletionPolicy {
  static func shouldBlockDeletion(dependencyCounts: JobDeletionDependencyCounts) -> Bool {
    dependencyCounts.total > 0
  }

  static func shouldCountBlockingDependency(
    syncStatusRaw: String,
    serverRevision: Int64,
    serverDeletedAt: Date?
  ) -> Bool {
    guard serverDeletedAt == nil else {
      return false
    }
    return syncStatusRaw != SyncStatus.pendingDelete.rawValue || serverRevision > 0
  }
}
