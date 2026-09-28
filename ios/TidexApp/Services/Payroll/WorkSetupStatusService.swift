import Foundation
import Observation

extension Notification.Name {
  static let workSetupDataDidChange = Notification.Name("com.tidex.workSetupDataDidChange")
}

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
  private let snapshotsRepository: SnapshotsRepository

  init(
    jobsRepository: JobsRepository? = nil,
    snapshotsRepository: SnapshotsRepository? = nil
  ) {
    self.jobsRepository = jobsRepository ?? JobsRepository.shared
    self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
  }

  func status(for userId: String) -> WorkSetupStatus {
    let activeJobs = jobsRepository.getActiveJobs(for: userId)

    return WorkSetupStatusResolver.resolve(activeJobs: activeJobs) { [snapshotsRepository] jobId in
      snapshotsRepository.getBaselineSnapshot(for: userId, jobId: jobId) != nil
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

@MainActor
@Observable
final class WorkSetupPresentationViewModel {
  private(set) var presentationState: WorkSetupPresentationState?

  private let workSetupStatusService: WorkSetupStatusService

  init(workSetupStatusService: WorkSetupStatusService? = nil) {
    self.workSetupStatusService = workSetupStatusService ?? .shared
  }

  var shouldShowPlaceholder: Bool {
    presentationState?.shouldShowPlaceholder == true
  }

  func refresh(userId: String?, initialSyncComplete: Bool) {
    guard let userId else {
      if presentationState != nil {
        presentationState = nil
      }
      return
    }

    let updatedState = workSetupStatusService.presentationState(
      for: userId,
      initialSyncComplete: initialSyncComplete
    )
    if presentationState != updatedState {
      presentationState = updatedState
    }
  }
}
