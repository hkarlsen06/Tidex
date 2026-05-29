import Foundation

struct WorkSetupStatus: Equatable {
  let isWorkSetupComplete: Bool
  let hasActiveJob: Bool
  let hasBaselineSnapshotForActiveSetupJob: Bool
  let activeSetupJobId: String?
}

enum WorkSetupPresentationState: Equatable {
  case loading
  case ready(WorkSetupStatus)
  case incomplete(WorkSetupStatus)

  var status: WorkSetupStatus? {
    switch self {
    case .loading:
      return nil
    case .ready(let status), .incomplete(let status):
      return status
    }
  }

  var shouldShowPlaceholder: Bool {
    if case .incomplete = self {
      return true
    }
    return false
  }
}

enum WorkSetupPresentationStateResolver {
  static func resolve(
    status: WorkSetupStatus,
    initialSyncComplete: Bool
  ) -> WorkSetupPresentationState {
    if status.isWorkSetupComplete {
      return .ready(status)
    }

    return initialSyncComplete ? .incomplete(status) : .loading
  }
}

enum WorkSetupStatusResolver {
  static func resolve(
    activeJobs: [Job],
    hasBaselineSnapshotForJob: (String) -> Bool
  ) -> WorkSetupStatus {
    let activeSetupJob = activeJobs.first(where: \.is_default) ?? activeJobs.first
    let activeSetupJobId = activeSetupJob?.id
    let hasBaselineSnapshotForActiveSetupJob =
      activeSetupJobId.map(hasBaselineSnapshotForJob) ?? false

    return WorkSetupStatus(
      isWorkSetupComplete: activeSetupJobId != nil && hasBaselineSnapshotForActiveSetupJob,
      hasActiveJob: activeSetupJobId != nil,
      hasBaselineSnapshotForActiveSetupJob: hasBaselineSnapshotForActiveSetupJob,
      activeSetupJobId: activeSetupJobId
    )
  }
}

@MainActor
final class WorkSetupStatusService {
  static let shared = WorkSetupStatusService()

  private let jobsRepository: JobsRepository
  private let jobPaySetupStatusService: JobPaySetupStatusService

  init(
    jobsRepository: JobsRepository? = nil,
    jobPaySetupStatusService: JobPaySetupStatusService? = nil
  ) {
    self.jobsRepository = jobsRepository ?? JobsRepository.shared
    self.jobPaySetupStatusService = jobPaySetupStatusService ?? JobPaySetupStatusService.shared
  }

  func status(for userId: String) -> WorkSetupStatus {
    let activeJobs = jobsRepository.getActiveJobs(for: userId)
    let configuredJobIds = jobPaySetupStatusService.configuredJobIds(for: userId)

    return WorkSetupStatusResolver.resolve(activeJobs: activeJobs) { jobId in
      configuredJobIds.contains(jobId)
    }
  }

  func presentationState(
    for userId: String,
    initialSyncComplete: Bool
  ) -> WorkSetupPresentationState {
    WorkSetupPresentationStateResolver.resolve(
      status: status(for: userId),
      initialSyncComplete: initialSyncComplete
    )
  }
}
