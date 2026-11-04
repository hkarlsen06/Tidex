import AppIntents
import CoreSpotlight
import Foundation

// App Intents metadata needs literal keys, so titles name catalog keys instead of symbols.
// Pay is not an entity property: this SDK cannot require authentication per property, and
// entities reach Spotlight and the lock screen.

struct ShiftEntity: IndexedEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "assistant.shift.type")
  static let defaultQuery = ShiftEntityQuery()

  let id: String

  @Property(title: "assistant.shift.job", indexingKey: \.title)
  var jobName: String

  @Property(title: "assistant.shift.start", indexingKey: \.startDate)
  var start: Date

  @Property(title: "assistant.shift.end", indexingKey: \.endDate)
  var end: Date

  /// Recurring shifts are projected from a pattern and can't be edited one by one.
  let isRecurring: Bool

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(jobName)",
      subtitle: "\((start..<end).formatted(date: .abbreviated, time: .shortened))"
    )
  }

  init?(_ shift: ShiftWithComputations, jobs: [Job]) {
    guard
      let start = Date.fromDateAndTime(shift.shiftDate, time: shift.startTime),
      let end = Date.shiftEndDate(
        shiftDate: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime)
    else {
      return nil
    }
    let job =
      shift.shift.job_id.flatMap { jobId in jobs.first { $0.id == jobId } }
      ?? jobs.first(where: \.is_default)
    id = shift.id
    isRecurring = shift.isVirtual
    jobName = job?.name ?? String(localized: .assistantShiftFallbackJobName)
    self.start = start
    self.end = end
  }
}

struct ShiftEntityQuery: EntityQuery {
  @MainActor
  func entities(for identifiers: [ShiftEntity.ID]) async throws -> [ShiftEntity] {
    let ids = Set(identifiers)
    return try await AssistantShifts.entities(access: .current).filter { ids.contains($0.id) }
  }

  @MainActor
  func suggestedEntities() async throws -> [ShiftEntity] {
    let now = Date()
    return try await AssistantShifts.entities(access: .current).filter { $0.end > now }
  }
}

struct JobEntity: IndexedEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "assistant.job.type")
  static let defaultQuery = JobEntityQuery()

  let id: String

  @Property(title: "assistant.job.name", indexingKey: \.title)
  var name: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }

  init(_ job: Job) {
    id = job.id
    name = job.name
  }
}

struct JobEntityQuery: EntityStringQuery {
  @MainActor
  func entities(for identifiers: [JobEntity.ID]) throws -> [JobEntity] {
    let ids = Set(identifiers)
    return try activeJobs().filter { ids.contains($0.id) }
  }

  @MainActor
  func entities(matching string: String) throws -> [JobEntity] {
    try activeJobs().filter { $0.name.localizedStandardContains(string) }
  }

  @MainActor
  func suggestedEntities() throws -> [JobEntity] {
    try activeJobs()
  }

  @MainActor
  private func activeJobs() throws -> [JobEntity] {
    let userId = try AssistantAccess.current.requireUserId()
    return JobsRepository.shared.getActiveJobs(for: userId).map(JobEntity.init)
  }
}

/// A friend who shares their shifts with the user.
struct FriendEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "assistant.friend.type")
  static let defaultQuery = FriendEntityQuery()

  let id: String

  @Property(title: "assistant.friend.name")
  var name: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }

  init(_ sharer: SharedUser) {
    id = sharer.id
    name = sharer.displayName
  }
}

struct FriendEntityQuery: EntityStringQuery {
  @MainActor
  func entities(for identifiers: [FriendEntity.ID]) throws -> [FriendEntity] {
    let ids = Set(identifiers)
    return try sharers().filter { ids.contains($0.id) }
  }

  @MainActor
  func entities(matching string: String) throws -> [FriendEntity] {
    try sharers().filter { $0.name.localizedStandardContains(string) }
  }

  @MainActor
  func suggestedEntities() throws -> [FriendEntity] {
    try sharers()
  }

  @MainActor
  private func sharers() throws -> [FriendEntity] {
    let userId = try AssistantAccess.current.requireUserId()
    return SharedShiftsRepository.shared.getSharers(for: userId).map(FriendEntity.init)
  }
}

/// Reads the user's shifts the way the app shows them, recurring shifts included.
@MainActor
enum AssistantShifts {
  /// Siri and Spotlight see shifts from 30 days back to 60 days ahead.
  static func window(around now: Date) -> PayrollReadWindow {
    let calendar = Calendar.gregorianCurrent
    let today = calendar.startOfDay(for: now)
    return PayrollReadWindow(
      startDate: calendar.date(byAdding: .day, value: -30, to: today) ?? today,
      endDate: calendar.date(byAdding: .day, value: 60, to: today) ?? today
    )
  }

  static func entities(
    access: AssistantAccess,
    now: Date = Date(),
    readService: MonthlyPayrollReadService = .shared
  ) async throws -> [ShiftEntity] {
    let userId = try access.requireUserId()
    let window = window(around: now)
    let context = await readService.loadContextOffMain(for: userId)
    let shifts = await readService.loadShiftRows(
      for: userId, startDate: window.startDate, endDate: window.endDate)
    let yearMonth = now.yearMonth()
    let computed = PayrollEngine.computeShiftsForMonth(
      .init(
        year: yearMonth.year,
        month: yearMonth.month,
        shifts: shifts,
        recurring: context.recurringShifts,
        snapshots: context.snapshots,
        settings: context.settings,
        visibleRange: (window.startDate, window.endDate),
        jobs: context.jobs
      ))
    return entities(from: computed, jobs: context.jobs)
  }

  /// Sorted by start time.
  nonisolated static func entities(from shifts: [ShiftWithComputations], jobs: [Job])
    -> [ShiftEntity]
  {
    shifts.compactMap { ShiftEntity($0, jobs: jobs) }.sorted { $0.start < $1.start }
  }
}
