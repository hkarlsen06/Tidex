import Foundation

/// Plain description of one row stuck in a sync conflict.
/// Built inside the store actor so no SwiftData model leaves it.
internal struct SyncConflictRow: Identifiable, Equatable, Sendable {
  internal enum Kind: String, Sendable {
    case job, shift, event, recurringShift, wageSnapshot, payrollAdjustment, settings
  }

  internal let kind: Kind
  /// Row id. For user settings this is the user id.
  internal let entityId: String
  internal let title: String
  internal let detail: String?
  /// False when the server rejected the row or the server row is missing.
  internal let hasServerVersion: Bool

  internal var id: String { "\(kind.rawValue)-\(entityId)" }
}

// MARK: - Mapping

extension SyncConflictRow {
  private static func join(_ parts: [String?]) -> String? {
    let text = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    return text.isEmpty ? nil : text
  }

  private static func date(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
  }

  private static func timeRange(_ start: String, _ end: String) -> String {
    "\(start.prefix(5)) - \(end.prefix(5))"
  }

  internal static func make(job: LocalJob) -> Self {
    Self(
      kind: .job, entityId: job.id, title: job.name, detail: nil,
      hasServerVersion: job.conflictServerSnapshot != nil)
  }

  internal static func make(shift: LocalUserShift, jobName: String?) -> Self {
    Self(
      kind: .shift, entityId: shift.id, title: date(shift.shiftDate),
      detail: join([timeRange(shift.startTime, shift.endTime), jobName]),
      hasServerVersion: shift.conflictServerSnapshot != nil)
  }

  internal static func make(event: LocalEvent) -> Self {
    let note = event.note.trimmingCharacters(in: .whitespacesAndNewlines)
    return Self(
      kind: .event, entityId: event.id,
      title: note.isEmpty ? String(localized: .syncConflictsEventTitle) : note,
      detail: date(event.startDate), hasServerVersion: event.conflictServerSnapshot != nil)
  }

  internal static func make(recurringShift: LocalRecurringShift, jobName: String?) -> Self {
    let days =
      (try? kSyncJSONDecoder.decode(SelectedDays.self, from: recurringShift.selectedDays)) ?? [:]
    let symbols = Calendar.current.shortWeekdaySymbols
    // Weekday keys are "0" (Sunday) to "6", shown Monday first.
    let weekdays = ["1", "2", "3", "4", "5", "6", "0"]
      .filter { days[$0] != nil }
      .compactMap { key in Int(key).flatMap { symbols.indices.contains($0) ? symbols[$0] : nil } }
      .joined(separator: ", ")
    return Self(
      kind: .recurringShift, entityId: recurringShift.id,
      title: timeRange(recurringShift.startTime, recurringShift.endTime),
      detail: join([weekdays, jobName]),
      hasServerVersion: recurringShift.conflictServerSnapshot != nil)
  }

  internal static func make(wageSnapshot: LocalWageSnapshot, jobName: String?, currency: String)
    -> Self
  {
    Self(
      kind: .wageSnapshot, entityId: wageSnapshot.id,
      title: String(localized: .syncConflictsWageTitle),
      detail: join([
        wageSnapshot.fromDate.map { $0.formatted(date: .abbreviated, time: .omitted) },
        CurrencyConfig.format(wageSnapshot.hourlyWage, currency: currency, includeDecimals: true),
        jobName,
      ]),
      hasServerVersion: wageSnapshot.conflictServerSnapshot != nil)
  }

  internal static func make(payrollAdjustment adjustment: LocalPayrollAdjustment) -> Self {
    let label = adjustment.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
    return Self(
      kind: .payrollAdjustment, entityId: adjustment.id,
      title: label.isEmpty ? String(localized: .syncConflictsAdjustmentTitle) : label,
      detail: join([
        CurrencyConfig.format(adjustment.amount, currency: adjustment.currency, includeDecimals: true),
        adjustment.payoutDate.formatted(date: .abbreviated, time: .omitted),
      ]),
      hasServerVersion: adjustment.conflictServerSnapshot != nil)
  }

  internal static func make(settings: LocalUserSettings) -> Self {
    Self(
      kind: .settings, entityId: settings.userId,
      title: String(localized: .syncConflictsSettingsTitle), detail: nil,
      hasServerVersion: settings.conflictServerSnapshot != nil)
  }
}

// MARK: - Store access

extension LocalStoreActor {
  /// Conflicted rows for a user as plain values, in a stable order by type.
  internal func conflictRows(userId: String) throws -> [SyncConflictRow] {
    let conflicts = try getConflicts(userId: userId)
    let job = { (id: String?) -> LocalJob? in
      id.flatMap { try? self.getJob(id: $0) }
    }

    var rows: [SyncConflictRow] = []
    rows += conflicts.jobs.map { SyncConflictRow.make(job: $0) }
    rows += conflicts.shifts.map { SyncConflictRow.make(shift: $0, jobName: job($0.jobId)?.name) }
    rows += conflicts.events.map { SyncConflictRow.make(event: $0) }
    rows += conflicts.recurringShifts.map {
      SyncConflictRow.make(recurringShift: $0, jobName: job($0.jobId)?.name)
    }
    rows += conflicts.wageSnapshots.map {
      let owner = job($0.jobId)
      return SyncConflictRow.make(
        wageSnapshot: $0, jobName: owner?.name, currency: owner?.currency ?? "kr")
    }
    rows += conflicts.payrollAdjustments.map { SyncConflictRow.make(payrollAdjustment: $0) }
    if let settings = conflicts.settings { rows.append(.make(settings: settings)) }
    return rows
  }
}
