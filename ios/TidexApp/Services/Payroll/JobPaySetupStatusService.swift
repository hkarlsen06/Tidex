import Foundation

struct JobPaySetupStatus: Equatable {
  let jobId: String
  let isActive: Bool
  let hasBaselineSnapshot: Bool

  var isConfigured: Bool {
    isActive && hasBaselineSnapshot
  }
}

enum JobPaySetupError: Error, LocalizedError, Equatable {
  case jobNotAvailable
  case jobPaySetupRequired(jobId: String)

  var errorDescription: String? {
    switch self {
    case .jobNotAvailable:
      return "Choose an active job before adding a shift."

    case .jobPaySetupRequired:
      return "Finish pay setup for this job before adding shifts."
    }
  }
}

enum JobPaySetupStatusResolver {
  static func status(
    for jobId: String,
    activeJobs: [Job],
    hasBaselineSnapshotForJob: (String) -> Bool
  ) -> JobPaySetupStatus {
    let isActive = activeJobs.contains { $0.id == jobId }
    return JobPaySetupStatus(
      jobId: jobId,
      isActive: isActive,
      hasBaselineSnapshot: hasBaselineSnapshotForJob(jobId)
    )
  }

  static func configuredJobIds(
    activeJobs: [Job],
    hasBaselineSnapshotForJob: (String) -> Bool
  ) -> Set<String> {
    Set(activeJobs.filter { hasBaselineSnapshotForJob($0.id) }.map(\.id))
  }
}

@MainActor
final class JobPaySetupStatusService {
  static let shared = JobPaySetupStatusService()

  private let jobsRepository: JobsRepository
  private let snapshotsRepository: SnapshotsRepository

  init(
    jobsRepository: JobsRepository? = nil,
    snapshotsRepository: SnapshotsRepository? = nil
  ) {
    self.jobsRepository = jobsRepository ?? JobsRepository.shared
    self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
  }

  func status(for userId: String, jobId: String) -> JobPaySetupStatus {
    let activeJobs = jobsRepository.getActiveJobs(for: userId)
    return JobPaySetupStatusResolver.status(
      for: jobId,
      activeJobs: activeJobs
    ) { [snapshotsRepository] jobId in
      snapshotsRepository.getBaselineSnapshot(for: userId, jobId: jobId) != nil
    }
  }

  func isJobConfigured(userId: String, jobId: String) -> Bool {
    status(for: userId, jobId: jobId).isConfigured
  }

  func configuredJobIds(for userId: String) -> Set<String> {
    let activeJobs = jobsRepository.getActiveJobs(for: userId)
    return JobPaySetupStatusResolver.configuredJobIds(
      activeJobs: activeJobs
    ) { [snapshotsRepository] jobId in
      snapshotsRepository.getBaselineSnapshot(for: userId, jobId: jobId) != nil
    }
  }

  func requireConfiguredActiveJob(userId: String, requestedJobId: String?) throws -> Job {
    let activeJobs = jobsRepository.getActiveJobs(for: userId)

    let job: Job?
    if let requestedJobId {
      job = activeJobs.first { $0.id == requestedJobId }
    } else {
      job = activeJobs.first(where: \.is_default) ?? activeJobs.first
    }

    guard let job else {
      throw JobPaySetupError.jobNotAvailable
    }

    guard snapshotsRepository.getBaselineSnapshot(for: userId, jobId: job.id) != nil else {
      throw JobPaySetupError.jobPaySetupRequired(jobId: job.id)
    }

    return job
  }
}
