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

struct PayrollReadWindow: Hashable {
  let startDate: Date
  let endDate: Date

  static func month(year: Int, month: Int) -> PayrollReadWindow {
    PayrollReadWindow(
      startDate: Date.firstDayOfMonthDate(year: year, month: month),
      endDate: Date.lastDayOfMonthDate(year: year, month: month)
    )
  }

  static func visibleCalendarMonth(year: Int, month: Int) -> PayrollReadWindow {
    let range = Date.visibleCalendarRange(year: year, month: month)
    return PayrollReadWindow(startDate: range.start, endDate: range.end)
  }
}

struct PayrollRawWindowData {
  let window: PayrollReadWindow
  let shifts: [ShiftRow]
  let events: [EventRow]
}

@MainActor
final class MonthlyPayrollReadService {
  static let shared = MonthlyPayrollReadService()

  private let shiftsRepository: ShiftsRepository
  private let eventsRepository: EventsRepository
  private let settingsRepository: SettingsRepository
  private let snapshotsRepository: SnapshotsRepository
  private let recurringShiftsRepository: RecurringShiftsRepository
  private let jobsRepository: JobsRepository

  init(
    shiftsRepository: ShiftsRepository? = nil,
    eventsRepository: EventsRepository? = nil,
    settingsRepository: SettingsRepository? = nil,
    snapshotsRepository: SnapshotsRepository? = nil,
    recurringShiftsRepository: RecurringShiftsRepository? = nil,
    jobsRepository: JobsRepository? = nil
  ) {
    self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
    self.eventsRepository = eventsRepository ?? EventsRepository.shared
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

  func loadRawWindow(
    for userId: String,
    window: PayrollReadWindow,
    jobId: String? = nil
  ) async -> PayrollRawWindowData {
    async let shifts = shiftsRepository.getShiftsOffMain(
      for: userId,
      startDate: window.startDate,
      endDate: window.endDate,
      jobId: jobId
    )
    async let events = eventsRepository.getEventsOffMain(
      for: userId,
      startDate: window.startDate,
      endDate: window.endDate
    )

    return await PayrollRawWindowData(window: window, shifts: shifts, events: events)
  }

  func loadRawWindows(
    for userId: String,
    windows: [PayrollReadMonth: PayrollReadWindow],
    jobId: String? = nil
  ) async -> [PayrollReadMonth: PayrollRawWindowData] {
    var results: [PayrollReadMonth: PayrollRawWindowData] = [:]

    for (month, window) in windows {
      results[month] = await loadRawWindow(
        for: userId,
        window: window,
        jobId: jobId
      )
    }

    return results
  }
}
