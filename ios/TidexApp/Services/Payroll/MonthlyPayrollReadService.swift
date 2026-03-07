import Foundation

struct PayrollReadContext {
  let userId: String
  let settings: UserSettings?
  let snapshots: [WageSnapshot]
  let recurringShifts: [RecurringShiftRow]
  let jobs: [Job]
}

struct PayrollReadMonth: Hashable {
  let year: Int
  let month: Int
}

@MainActor
final class MonthlyPayrollReadService {
  static let shared = MonthlyPayrollReadService()

  private let shiftsRepository: ShiftsRepository
  private let settingsRepository: SettingsRepository
  private let snapshotsRepository: SnapshotsRepository
  private let recurringShiftsRepository: RecurringShiftsRepository
  private let jobsRepository: JobsRepository

  init(
    shiftsRepository: ShiftsRepository? = nil,
    settingsRepository: SettingsRepository? = nil,
    snapshotsRepository: SnapshotsRepository? = nil,
    recurringShiftsRepository: RecurringShiftsRepository? = nil,
    jobsRepository: JobsRepository? = nil
  ) {
    self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
    self.settingsRepository = settingsRepository ?? SettingsRepository.shared
    self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
    self.recurringShiftsRepository = recurringShiftsRepository ?? RecurringShiftsRepository.shared
    self.jobsRepository = jobsRepository ?? JobsRepository.shared
  }

  func loadContext(for userId: String, jobId: String? = nil) -> PayrollReadContext {
    PayrollReadContext(
      userId: userId,
      settings: settingsRepository.getSettings(for: userId),
      snapshots: snapshotsRepository.getSnapshots(for: userId, jobId: jobId),
      recurringShifts: recurringShiftsRepository.getRecurringShifts(for: userId, jobId: jobId),
      jobs: jobsRepository.getNonDeletedJobs(for: userId)
    )
  }

  func loadShiftRows(
    for userId: String,
    year: Int,
    month: Int,
    jobId: String? = nil
  ) async -> [ShiftRow] {
    let startDate = Date.firstDayOfMonthDate(year: year, month: month)
    let endDate = Date.lastDayOfMonthDate(year: year, month: month)

    return await shiftsRepository.getShiftsOffMain(
      for: userId,
      startDate: startDate,
      endDate: endDate,
      jobId: jobId
    )
  }

  func loadShiftRows(
    for userId: String,
    startDate: Date,
    endDate: Date,
    jobId: String? = nil
  ) async -> [ShiftRow] {
    await shiftsRepository.getShiftsOffMain(
      for: userId,
      startDate: startDate,
      endDate: endDate,
      jobId: jobId
    )
  }

  func loadShiftRows(
    for userId: String,
    months: [PayrollReadMonth],
    jobId: String? = nil
  ) async -> [PayrollReadMonth: [ShiftRow]] {
    var results: [PayrollReadMonth: [ShiftRow]] = [:]

    for month in months {
      results[month] = await loadShiftRows(
        for: userId,
        year: month.year,
        month: month.month,
        jobId: jobId
      )
    }

    return results
  }
}
