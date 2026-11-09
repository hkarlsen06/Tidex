import AppIntents
import Foundation

struct AddShiftIntent: AppIntent {
  static let title: LocalizedStringResource = "assistant.addShift.title"
  static let description = IntentDescription("assistant.addShift.description")
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @Parameter(title: "assistant.shift.job", description: "assistant.addShift.job.description")
  var job: JobEntity?

  @Parameter(
    title: "assistant.addShift.date", description: "assistant.addShift.date.description",
    kind: .date)
  var date: Date?

  @Parameter(
    title: "assistant.shift.start", description: "assistant.addShift.start.description", kind: .time
  )
  var start: Date?

  @Parameter(
    title: "assistant.shift.end", description: "assistant.addShift.end.description", kind: .time)
  var end: Date?

  init() {}

  init(job: JobEntity?, date: Date, start: Date, end: Date) {
    self.job = job
    self.date = date
    self.start = start
    self.end = end
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let userId = try AssistantAccess.current.requireUserId()
    guard let date else { throw $date.needsValueError() }
    guard let start else { throw $start.needsValueError() }
    guard let end else { throw $end.needsValueError() }
    let jobs = JobsRepository.shared.getActiveJobs(for: userId)
    let chosenJob =
      job.flatMap { job in jobs.first { $0.id == job.id } }
      ?? jobs.first(where: \.is_default) ?? jobs.first
    let schedule = ShiftSchedule(day: date, start: start, end: end)
    guard let shiftDate = Date.fromISODateString(schedule.shiftDate),
      let interval = schedule.interval
    else {
      throw AssistantError.invalidTimes
    }
    let summary = AssistantShiftSummary(
      jobName: chosenJob?.name ?? String(localized: .assistantShiftFallbackJobName),
      interval: interval)

    try await requestConfirmation(
      actionName: .add, dialog: IntentDialog(.assistantAddShiftConfirm(summary.text)))

    _ = try await ShiftsRepository.shared.createShift(
      userId: userId,
      jobId: chosenJob?.id,
      shiftDate: shiftDate,
      startTime: schedule.startTime,
      endTime: schedule.endTime,
      creationMethod: "siri"
    )
    NotificationCenter.default.postShiftsDidChange(context: .affecting(isoDate: schedule.shiftDate))
    return .result(dialog: IntentDialog(.assistantAddShiftDone(summary.text)))
  }
}

struct MoveShiftIntent: AppIntent {
  static let title: LocalizedStringResource = "assistant.moveShift.title"
  static let description = IntentDescription("assistant.moveShift.description")
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @Parameter(title: "assistant.shift.type", description: "assistant.moveShift.shift.description")
  var shift: ShiftEntity

  @Parameter(
    title: "assistant.moveShift.newDate", description: "assistant.moveShift.newDate.description",
    kind: .date)
  var newDate: Date?

  @Parameter(
    title: "assistant.moveShift.newStart", description: "assistant.moveShift.newStart.description",
    kind: .time)
  var newStart: Date?

  @Parameter(
    title: "assistant.moveShift.newEnd", description: "assistant.moveShift.newEnd.description",
    kind: .time)
  var newEnd: Date?

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let userId = try AssistantAccess.current.requireUserId()
    guard !shift.isRecurring else { throw AssistantError.recurringShift }
    guard newDate != nil || newStart != nil || newEnd != nil else { throw AssistantError.noChange }
    guard
      let stored = ShiftsRepository.shared.getShift(id: shift.id),
      stored.user_id?.lowercased() == userId.lowercased()
    else {
      throw AssistantError.shiftNotFound
    }
    let current = ShiftSchedule(stored)
    let moved = current.moved(to: newDate, start: newStart, end: newEnd)
    guard let shiftDate = Date.fromISODateString(moved.shiftDate), let interval = moved.interval
    else {
      throw AssistantError.invalidTimes
    }
    let summary = AssistantShiftSummary(jobName: shift.jobName, interval: interval)

    try await requestConfirmation(
      actionName: .set, dialog: IntentDialog(.assistantMoveShiftConfirm(summary.text)))

    guard
      try await ShiftsRepository.shared.updateShift(
        id: shift.id, shiftDate: shiftDate, startTime: moved.startTime, endTime: moved.endTime)
        != nil
    else {
      throw AssistantError.shiftNotFound
    }
    NotificationCenter.default.postShiftsDidChange(
      context: .affecting(isoDates: [current.shiftDate, moved.shiftDate]))
    return .result(dialog: IntentDialog(.assistantMoveShiftDone(summary.text)))
  }
}

/// "Café, Friday 6 November, 22:00 to 06:00", read back before Siri writes a shift.
private struct AssistantShiftSummary {
  let text: String

  init(jobName: String, interval: DateInterval) {
    text = String(
      localized: .assistantShiftSummary(
        jobName,
        interval.start.formatted(.dateTime.weekday(.wide).day().month(.wide)),
        interval.start.formatted(date: .omitted, time: .shortened),
        interval.end.formatted(date: .omitted, time: .shortened)))
  }
}
