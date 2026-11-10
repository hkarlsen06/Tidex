import Foundation

// MARK: - Shared Compute Models

struct SharingComputedShiftComputed: Equatable, Sendable {
  let durationHours: Double
  let paidHours: Double
  let basePay: Double
  let supplementPay: Double
  let gross: Double
  let wagePeriods: [SharingRPCWagePeriod]
  let originalWagePeriods: [SharingRPCWagePeriod]
  let breakAudit: SharingRPCBreakAudit
  var overtimeApplied: Bool = false
  var overtimeMinutes: Double = 0
  var preOvertimeGross: Double?
}

struct SharingShiftCalculationContext: Equatable, Sendable {
  let wageSnapshotId: String?
  let taxSnapshotId: String?
  let scheduledPayoutDate: String
  let savedTaxPercentage: Double
  let halfTaxApplied: Bool
}

struct SharingComputedShift: Identifiable, Equatable, Sendable {
  let id: String
  let userId: String
  let jobId: String?
  let jobName: String?
  let jobColor: String?
  let shiftDate: String
  let startTime: String
  let endTime: String
  let customPauseWindows: CustomPauseWindows?
  let customSupplements: SharingRPCCustomSupplements?
  let recurringId: String?
  let recurringAnchorWeekday: Int?
  let computed: SharingComputedShiftComputed
  let taxEnabled: Bool
  let taxPercentage: Double
  var calculationContext: SharingShiftCalculationContext?
}

enum SharingPreviewStatus: String, Codable, Sendable {
  case active
  case upcoming
  case past
}

struct SharingComputedPreview: Sendable {
  let sharerId: String
  let shift: SharingComputedShift?
  let status: SharingPreviewStatus?
  let showEarnings: Bool
  var ownerTimeZone: String?
}

typealias SharingRPCBreakMethod = BreakMethod
typealias SharingRPCWagePeriod = WagePeriod
typealias SharingRPCBreakAudit = BreakAudit

struct SharingRecurringVirtualShift: Equatable, Sendable {
  let date: String
  let weekday: Int
}

private struct SharingPayrollContext {
  let fallbackPayrollDay: Int
  let fallbackHalfTaxMonth: Int?
  let jobsById: [String: SharingRPCJobRow]
  let defaultJobId: String?
  let snapshotsByJobId: [String?: [SharingRPCWageSnapshot]]
  let legacyNilJobSnapshots: [SharingRPCWageSnapshot]
  let allSnapshots: [SharingRPCWageSnapshot]
}

struct PayrollPayTotals {
  let base: Double
  let supplement: Double
  let gross: Double
}

struct PayrollConflictShift {
  let id: String
  let date: String
  let startTime: String
  let endTime: String
  let gross: Double

  func overlaps(_ other: PayrollConflictShift) -> Bool {
    func minutes(_ value: String) -> Int {
      let parts = value.split(separator: ":").compactMap { Int($0) }
      return parts.count >= 2 ? parts[0] * 60 + parts[1] : 0
    }
    let start = minutes(startTime)
    let end = minutes(endTime)
    let otherStart = minutes(other.startTime)
    let otherEnd = minutes(other.endTime)
    return start < (otherEnd <= otherStart ? otherEnd + 24 * 60 : otherEnd)
      && otherStart < (end <= start ? end + 24 * 60 : end)
  }
}

struct PayrollConflictAnalysis {
  let excludedIds: Set<String>
  let conflictingIds: Set<String>
  let conflictDates: Set<String>
}

// MARK: - Shared Compute Core (Foundation-only)

enum SharingComputeCore {
  private static let defaultBreakEnabled = true
  private static let defaultBreakThresholdHours = 5.5
  private static let defaultBreakDeductionMinutes = 30
  private static let fallbackBaseRate = 184.54

  static let presetSupplementRules: [SharingRPCSupplementRule] = [
    SharingRPCSupplementRule(
      days: [1, 2, 3, 4, 5], from: "18:00", to: "21:00", rate: 22, percent: nil),
    SharingRPCSupplementRule(
      days: [1, 2, 3, 4, 5], from: "21:00", to: "24:00", rate: 45, percent: nil),
    SharingRPCSupplementRule(days: [6], from: "13:00", to: "15:00", rate: 45, percent: nil),
    SharingRPCSupplementRule(days: [6], from: "15:00", to: "18:00", rate: 55, percent: nil),
    SharingRPCSupplementRule(days: [6], from: "18:00", to: "24:00", rate: 110, percent: nil),
    SharingRPCSupplementRule(days: [7], from: "00:00", to: "24:00", rate: 115, percent: nil),
  ]

  /// DateFormatter isn't safe to share across threads, so this caches one instance per
  /// thread (matching `FormatterCache`) instead of allocating one on every call in a loop.
  private static var isoDateFormatter: DateFormatter {
    let key = "tidex.sharing.isoDateFormatter"
    let dictionary = Thread.current.threadDictionary
    if let cached = dictionary[key] as? DateFormatter {
      return cached
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    dictionary[key] = formatter
    return formatter
  }

  static func isoDateString(_ date: Date) -> String {
    isoDateFormatter.string(from: date)
  }

  static func monthStart(year: Int, month: Int) -> String {
    String(format: "%04d-%02d-01", year, month)
  }

  static func monthEnd(year: Int, month: Int) -> String {
    let day = daysInMonth(year: year, month: month)
    return String(format: "%04d-%02d-%02d", year, month, day)
  }

  static func computeShiftsInRange(
    payload: SharingRPCPayloadInput,
    startDate: String,
    endDate: String,
    mode: SharingRPCMode
  ) -> [SharingComputedShift] {
    let mode: SharingRPCMode = payload.showEarnings ? mode : .hidden
    var computed: [SharingComputedShift] = []
    let context = makePayrollContext(
      settings: payload.settings,
      snapshots: payload.snapshots,
      jobs: payload.jobs
    )
    let calculationRange = expandedISOWeekRange(startDate: startDate, endDate: endDate)

    let regularShifts = payload.shifts.filter { shift in
      shift.shiftDate >= calculationRange.startDate && shift.shiftDate <= calculationRange.endDate
    }

    for shift in regularShifts {
      computed.append(
        computeShiftWithTax(
          shift: shift,
          context: context,
          mode: mode
        ))
    }

    let months = monthsInRange(
      startDate: calculationRange.startDate,
      endDate: calculationRange.endDate
    )
    var seenVirtualIds = Set(regularShifts.map(\.id))

    for recurring in payload.recurringShifts {
      for (year, month) in months {
        let virtualShifts = generateVirtualShiftsForMonth(
          year: year,
          month: month,
          recurring: recurring
        )

        for virtual in virtualShifts {
          guard virtual.date >= calculationRange.startDate,
            virtual.date <= calculationRange.endDate
          else {
            continue
          }

          let virtualId = "virtual-\(recurring.id)-\(virtual.date)"
          guard !seenVirtualIds.contains(virtualId) else { continue }
          seenVirtualIds.insert(virtualId)

          let virtualShift = SharingRPCShiftRow(
            id: virtualId,
            userId: recurring.userId,
            jobId: recurring.jobId,
            shiftDate: virtual.date,
            startTime: recurring.cleanStartTime,
            endTime: recurring.cleanEndTime,
            customPauseWindows: recurring.dateSpecificPauseWindows?[virtual.date],
            customSupplements: recurring.dateSpecificSupplements?[virtual.date],
            recurringId: recurring.id,
            recurringAnchorWeekday: virtual.weekday
          )

          computed.append(
            computeShiftWithTax(
              shift: virtualShift,
              context: context,
              mode: mode
            ))
        }
      }
    }

    // Resolve conflicts before overtime, using the same ordering for equal gross pay.
    let ordered = computed.sorted(by: isInOutputOrder)
    let excludedIds = excludedShiftIds(in: ordered)
    let overtimeAdjusted =
      applyOvertime(
        to: ordered.filter { !excludedIds.contains($0.id) }, context: context, mode: mode
      ) + ordered.filter { excludedIds.contains($0.id) }
    let visible = overtimeAdjusted.filter { shift in
      shift.shiftDate >= startDate && shift.shiftDate <= endDate
    }

    let sorted = visible.sorted(by: isInOutputOrder)

    if mode == .hidden {
      return enforceHiddenEarnings(on: sorted)
    }

    return sorted
  }

  private static func isInOutputOrder(_ lhs: SharingComputedShift, _ rhs: SharingComputedShift)
    -> Bool
  {
    if lhs.shiftDate != rhs.shiftDate { return lhs.shiftDate < rhs.shiftDate }
    if lhs.startTime != rhs.startTime { return lhs.startTime < rhs.startTime }
    return lhs.id < rhs.id
  }

  static func conflictAnalysis(_ shifts: [PayrollConflictShift]) -> PayrollConflictAnalysis {
    var excludedIds = Set<String>()
    var conflictingIds = Set<String>()
    var conflictDates = Set<String>()
    let ordered = shifts.sorted {
      if $0.date != $1.date { return $0.date < $1.date }
      if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
      return $0.id < $1.id
    }
    for (date, shiftsOnDate) in Dictionary(grouping: ordered, by: \.date) {
      var parent = Dictionary(
        shiftsOnDate.map { ($0.id, $0.id) }, uniquingKeysWith: { first, _ in first })
      func find(_ id: String) -> String {
        guard let ancestor = parent[id], ancestor != id else { return id }
        let root = find(ancestor)
        parent[id] = root
        return root
      }
      for first in shiftsOnDate.indices {
        for second in (first + 1)..<shiftsOnDate.count
        where shiftsOnDate[first].overlaps(shiftsOnDate[second]) {
          let firstRoot = find(shiftsOnDate[first].id)
          let secondRoot = find(shiftsOnDate[second].id)
          parent[firstRoot] = secondRoot
        }
      }
      let clusters = Dictionary(grouping: shiftsOnDate) { find($0.id) }
      for cluster in clusters.values where cluster.count > 1 {
        conflictDates.insert(date)
        conflictingIds.formUnion(cluster.map(\.id))
        let ranked = cluster.enumerated().sorted {
          if $0.element.gross != $1.element.gross { return $0.element.gross < $1.element.gross }
          return $0.offset < $1.offset
        }
        excludedIds.formUnion(ranked.dropFirst().map { $0.element.id })
      }
    }
    return PayrollConflictAnalysis(
      excludedIds: excludedIds, conflictingIds: conflictingIds, conflictDates: conflictDates)
  }

  static func excludedShiftIds(in shifts: [SharingComputedShift]) -> Set<String> {
    conflictAnalysis(
      shifts.map {
        PayrollConflictShift(
          id: $0.id, date: $0.shiftDate, startTime: $0.startTime, endTime: $0.endTime,
          gross: $0.computed.preOvertimeGross ?? $0.computed.gross)
      }
    ).excludedIds
  }

  static func computeMonthShifts(
    payload: SharingRPCPayloadInput,
    year: Int,
    month: Int,
    mode: SharingRPCMode
  ) -> [SharingComputedShift] {
    computeShiftsInRange(
      payload: payload,
      startDate: monthStart(year: year, month: month),
      endDate: monthEnd(year: year, month: month),
      mode: mode
    )
  }

  static func payoutTaxSettings(
    year: Int,
    month: Int,
    settings: SharingRPCUserSettings,
    snapshots: [SharingRPCWageSnapshot],
    jobs: [SharingRPCJobRow],
    mode: SharingRPCMode
  ) -> SharingRPCPayoutTaxSettings? {
    guard mode == .visible else { return nil }
    let context = makePayrollContext(
      settings: settings,
      snapshots: snapshots,
      jobs: jobs
    )
    let summaryJobId = context.defaultJobId
    let payrollDay =
      summaryJobId.flatMap { context.jobsById[$0]?.payrollDay } ?? settings.effectivePayrollDay
    let scopedSnapshots = snapshotsForJob(jobId: summaryJobId, context: context)

    let schedule = PayoutSchedule(
      period: summaryJobId.flatMap { context.jobsById[$0]?.payPeriod } ?? .calendarMonth,
      payrollDay: payrollDay)
    let payoutDate = schedule.payoutDate(for: monthStart(year: year, month: month))

    guard let snapshot = snapshotForDate(payoutDate, from: scopedSnapshots) else {
      return nil
    }

    return SharingRPCPayoutTaxSettings(
      enabled: snapshot.effectiveTaxEnabled,
      percentage: snapshot.effectiveTaxPercentage
    )
  }

  static func enforceHiddenEarnings(on shifts: [SharingComputedShift]) -> [SharingComputedShift] {
    shifts.map { shift in
      SharingComputedShift(
        id: shift.id,
        userId: shift.userId,
        jobId: shift.jobId,
        jobName: shift.jobName,
        jobColor: shift.jobColor,
        shiftDate: shift.shiftDate,
        startTime: shift.startTime,
        endTime: shift.endTime,
        customPauseWindows: shift.customPauseWindows,
        customSupplements: nil,
        recurringId: shift.recurringId,
        recurringAnchorWeekday: shift.recurringAnchorWeekday,
        computed: SharingComputedShiftComputed(
          durationHours: shift.computed.durationHours,
          paidHours: shift.computed.paidHours,
          basePay: 0,
          supplementPay: 0,
          gross: 0,
          wagePeriods: [],
          originalWagePeriods: [],
          breakAudit: shift.computed.breakAudit
        ),
        taxEnabled: false,
        taxPercentage: 0
      )
    }
  }

  static func selectPreview(
    sharerId: String,
    shifts: [SharingComputedShift],
    showEarnings: Bool,
    ownerTimeZone: String? = nil,
    now: Date = Date()
  ) -> SharingComputedPreview {
    let timed = shifts.compactMap { shift -> (SharingComputedShift, SharedShiftInterval)? in
      guard
        let interval = SharedShiftInterval(
          date: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime,
          timeZoneIdentifier: ownerTimeZone
        )
      else { return nil }
      return (shift, interval)
    }.sorted { $0.1.start < $1.1.start }
    let selected =
      timed.first { $0.1.status(at: now) == .active }
      ?? timed.first { $0.1.status(at: now) == .upcoming }
      ?? timed.last
    return SharingComputedPreview(
      sharerId: sharerId, shift: selected?.0, status: selected?.1.status(at: now),
      showEarnings: showEarnings, ownerTimeZone: ownerTimeZone
    )
  }

  static func sortPreviews(_ previews: [SharingComputedPreview]) -> [SharingComputedPreview] {
    previews.sorted { lhs, rhs in
      let priority: [SharingPreviewStatus?] = [.active, .upcoming, .past, nil]
      let left = priority.firstIndex(of: lhs.status) ?? 3
      let right = priority.firstIndex(of: rhs.status) ?? 3
      if left != right { return left < right }
      func start(_ preview: SharingComputedPreview) -> Date? {
        guard let shift = preview.shift else { return nil }
        return SharedShiftInterval(
          date: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime,
          timeZoneIdentifier: preview.ownerTimeZone
        )?.start
      }
      if let leftStart = start(lhs), let rightStart = start(rhs), leftStart != rightStart {
        return lhs.status == .past ? leftStart > rightStart : leftStart < rightStart
      }
      return lhs.sharerId < rhs.sharerId
    }
  }

  // MARK: - Core Calculation

  private static func computeShiftWithTax(
    shift: SharingRPCShiftRow,
    context: SharingPayrollContext,
    mode: SharingRPCMode
  ) -> SharingComputedShift {
    let effectiveJobId = shift.jobId ?? context.defaultJobId
    let payrollDay =
      effectiveJobId.flatMap { context.jobsById[$0]?.payrollDay } ?? context.fallbackPayrollDay
    let scopedSnapshots = snapshotsForJob(jobId: effectiveJobId, context: context)

    let schedule = PayoutSchedule(
      period: effectiveJobId.flatMap { context.jobsById[$0]?.payPeriod } ?? .calendarMonth,
      payrollDay: payrollDay)
    let payoutDate = schedule.payoutDate(for: shift.shiftDate)

    let wageSnapshot = snapshotForDate(shift.shiftDate, from: scopedSnapshots)
    let taxSnapshot = snapshotForDate(payoutDate, from: scopedSnapshots)

    var computed = computeShift(shift: shift, snapshot: wageSnapshot, mode: mode)

    let taxEnabled = mode == .hidden ? false : (taxSnapshot?.effectiveTaxEnabled ?? false)
    let job = effectiveJobId.flatMap { context.jobsById[$0] }
    let halfTaxMonth = job.map(\.halfTaxMonth) ?? context.fallbackHalfTaxMonth
    let payoutMonth = dateFromISO(payoutDate).map { sharingCalendar.component(.month, from: $0) }
    let savedTaxPercentage = taxSnapshot?.effectiveTaxPercentage ?? 0
    let clampedTaxPercentage =
      savedTaxPercentage.isFinite ? min(max(savedTaxPercentage, 0), 100) : 0
    let taxPercentage =
      taxEnabled
      ? clampedTaxPercentage / (halfTaxMonth != nil && halfTaxMonth == payoutMonth ? 2 : 1) : 0

    if mode == .hidden {
      computed = SharingComputedShiftComputed(
        durationHours: computed.durationHours,
        paidHours: computed.paidHours,
        basePay: 0,
        supplementPay: 0,
        gross: 0,
        wagePeriods: [],
        originalWagePeriods: [],
        breakAudit: computed.breakAudit
      )
    }

    return SharingComputedShift(
      id: shift.id,
      userId: shift.userId,
      jobId: effectiveJobId,
      jobName: job?.name,
      jobColor: job?.color,
      shiftDate: shift.shiftDate,
      startTime: shift.startTime,
      endTime: shift.endTime,
      customPauseWindows: shift.customPauseWindows,
      customSupplements: mode == .hidden ? nil : shift.customSupplements,
      recurringId: shift.recurringId,
      recurringAnchorWeekday: shift.recurringAnchorWeekday,
      computed: computed,
      taxEnabled: taxEnabled,
      taxPercentage: taxPercentage,
      calculationContext: mode == .visible
        ? SharingShiftCalculationContext(
          wageSnapshotId: wageSnapshot?.id, taxSnapshotId: taxSnapshot?.id,
          scheduledPayoutDate: payoutDate, savedTaxPercentage: savedTaxPercentage,
          halfTaxApplied: taxEnabled && halfTaxMonth == payoutMonth) : nil
    )
  }

  private struct SharingOvertimeSegment {
    let shift: SharingComputedShift
    let period: SharingRPCWagePeriod
    let absoluteStart: Date
    let absoluteEnd: Date
    let shiftDayStart: Date
    let config: SharingRPCOvertimeConfig?
  }

  private struct SharingOvertimePiece {
    let shiftId: String
    let start: Date
    let period: SharingRPCWagePeriod
    let overtimeMinutes: Double
  }

  private static func applyOvertime(
    to shifts: [SharingComputedShift],
    context: SharingPayrollContext,
    mode: SharingRPCMode
  ) -> [SharingComputedShift] {
    guard mode == .visible else { return shifts }

    var grouped: [String: [SharingOvertimeSegment]] = [:]
    var fallbackPieces: [String: [SharingOvertimePiece]] = [:]

    for shift in shifts {
      let scoped = snapshotsForJob(jobId: shift.jobId, context: context)
      let snapshot = snapshotForDate(shift.shiftDate, from: scoped)
      let config = runtimeOvertimeConfig(snapshot?.effectiveOvertime)
      guard let shiftDayStart = dateFromISO(shift.shiftDate) else { continue }

      for period in shift.computed.wagePeriods {
        let absoluteStart = shiftDayStart.addingTimeInterval(period.fromMin * 60)
        let absoluteEnd = shiftDayStart.addingTimeInterval(period.toMin * 60)
        guard absoluteEnd > absoluteStart else { continue }

        for (partStart, partEnd) in splitByISOWeek(start: absoluteStart, end: absoluteEnd) {
          let partPeriod = SharingRPCWagePeriod(
            fromMin: minutesBetween(shiftDayStart, partStart),
            toMin: minutesBetween(shiftDayStart, partEnd),
            baseRate: period.baseRate,
            supplementRate: period.supplementRate
          )
          let key = "\(shift.jobId ?? "__nil__")|\(isoDateString(isoWeekStart(for: partStart)))"
          let segment = SharingOvertimeSegment(
            shift: shift,
            period: partPeriod,
            absoluteStart: partStart,
            absoluteEnd: partEnd,
            shiftDayStart: shiftDayStart,
            config: config
          )
          grouped[key, default: []].append(segment)
          fallbackPieces[shift.id, default: []].append(
            SharingOvertimePiece(
              shiftId: shift.id,
              start: partStart,
              period: partPeriod,
              overtimeMinutes: 0
            ))
        }
      }
    }

    var piecesByShift: [String: [SharingOvertimePiece]] = [:]
    for segments in grouped.values {
      var cumulativeMinutes: Double = 0
      for segment in segments.sorted(by: {
        if $0.absoluteStart != $1.absoluteStart {
          return $0.absoluteStart < $1.absoluteStart
        }
        return $0.shift.id < $1.shift.id
      }) {
        for piece in applyOvertime(to: segment, cumulativeMinutes: cumulativeMinutes) {
          piecesByShift[piece.shiftId, default: []].append(piece)
        }
        cumulativeMinutes += segment.period.durationMinutes
      }
    }

    return shifts.map { shift in
      let pieces = piecesByShift[shift.id] ?? fallbackPieces[shift.id] ?? []
      guard !pieces.isEmpty else { return shift }
      return replacingPeriods(of: shift, with: pieces)
    }
  }

  private static func replacingPeriods(
    of shift: SharingComputedShift,
    with pieces: [SharingOvertimePiece]
  ) -> SharingComputedShift {
    let sortedPieces = pieces.sorted {
      if $0.start != $1.start {
        return $0.start < $1.start
      }
      return $0.period.fromMin < $1.period.fromMin
    }
    let periods = mergeAdjacentSharingPeriods(sortedPieces.map(\.period))
    let overtimeMinutes = sortedPieces.reduce(0.0) { $0 + $1.overtimeMinutes }
    let computed = recomputeSharingComputed(
      shift.computed,
      periods: periods,
      overtimeMinutes: overtimeMinutes
    )
    return SharingComputedShift(
      id: shift.id,
      userId: shift.userId,
      jobId: shift.jobId,
      jobName: shift.jobName,
      jobColor: shift.jobColor,
      shiftDate: shift.shiftDate,
      startTime: shift.startTime,
      endTime: shift.endTime,
      customPauseWindows: shift.customPauseWindows,
      customSupplements: shift.customSupplements,
      recurringId: shift.recurringId,
      recurringAnchorWeekday: shift.recurringAnchorWeekday,
      computed: computed,
      taxEnabled: shift.taxEnabled,
      taxPercentage: shift.taxPercentage,
      calculationContext: shift.calculationContext
    )
  }

  private static func applyOvertime(
    to segment: SharingOvertimeSegment,
    cumulativeMinutes: Double
  ) -> [SharingOvertimePiece] {
    guard let config = segment.config else {
      return [
        SharingOvertimePiece(
          shiftId: segment.shift.id,
          start: segment.absoluteStart,
          period: segment.period,
          overtimeMinutes: 0
        )
      ]
    }

    let thresholdMinutes = config.weeklyThresholdHours * 60
    var cursor = segment.absoluteStart
    var cursorCumulative = cumulativeMinutes
    var pieces: [SharingOvertimePiece] = []
    let retainedPeriods = buildWagePeriods(
      startTime: segment.shift.startTime, endTime: segment.shift.endTime,
      weekday: weekday(from: segment.shiftDayStart),
      baseRate: config.baseRate ?? segment.period.baseRate,
      rules: segment.shift.customSupplements?.rules.isEmpty == true
        ? [] : config.retainedSupplements ?? [], shiftDate: segment.shift.shiftDate)

    while cursor < segment.absoluteEnd {
      var next = nextSharingOvertimeBoundary(
        after: cursor,
        segmentEnd: segment.absoluteEnd,
        config: config,
        cumulativeMinutes: cursorCumulative,
        thresholdMinutes: thresholdMinutes
      )
      for period in retainedPeriods {
        for minute in [period.fromMin, period.toMin] {
          let boundary = segment.shiftDayStart.addingTimeInterval(minute * 60)
          if boundary > cursor && boundary < next { next = boundary }
        }
      }
      let durationMinutes = minutesBetween(cursor, next)
      guard durationMinutes > 0 else { break }

      let percent =
        cursorCumulative >= thresholdMinutes
        ? sharingOvertimePercent(config: config, at: cursor)
        : nil
      let minute = minutesBetween(segment.shiftDayStart, cursor)
      let retained =
        config.retainedSupplements != nil
        ? retainedPeriods.first { $0.fromMin <= minute && minute < $0.toMin }?.supplementRate ?? 0
        : config.retainSupplements == true ? segment.period.supplementRate : 0
      let baseRate =
        percent == nil ? segment.period.baseRate : config.baseRate ?? segment.period.baseRate
      let supplementRate =
        percent.map {
          baseRate * (config.premiumBaseMultiplier ?? 1) * $0 / 100 + retained
        }
        ?? segment.period.supplementRate

      pieces.append(
        SharingOvertimePiece(
          shiftId: segment.shift.id,
          start: cursor,
          period: SharingRPCWagePeriod(
            fromMin: minutesBetween(segment.shiftDayStart, cursor),
            toMin: minutesBetween(segment.shiftDayStart, next),
            baseRate: baseRate,
            supplementRate: supplementRate,
            isOvertime: percent != nil
          ),
          overtimeMinutes: percent == nil ? 0 : durationMinutes
        ))

      cursorCumulative += durationMinutes
      cursor = next
    }

    return pieces
  }

  private static func recomputeSharingComputed(
    _ computed: SharingComputedShiftComputed,
    periods: [SharingRPCWagePeriod],
    overtimeMinutes: Double
  ) -> SharingComputedShiftComputed {
    let pay = payTotals(for: periods)
    return SharingComputedShiftComputed(
      durationHours: computed.durationHours,
      paidHours: computed.paidHours,
      basePay: pay.base,
      supplementPay: pay.supplement,
      gross: pay.gross,
      wagePeriods: periods,
      originalWagePeriods: computed.originalWagePeriods,
      breakAudit: computed.breakAudit,
      overtimeApplied: overtimeMinutes > 0,
      overtimeMinutes: roundTo(overtimeMinutes, decimals: 2),
      preOvertimeGross: overtimeMinutes > 0 ? computed.gross : computed.preOvertimeGross
    )
  }

  private static func runtimeOvertimeConfig(_ config: SharingRPCOvertimeConfig?)
    -> SharingRPCOvertimeConfig?
  {
    if let baseRate = config?.baseRate,
      !baseRate.isFinite || baseRate <= 0
    {
      return nil
    }
    if let multiplier = config?.premiumBaseMultiplier,
      !multiplier.isFinite || multiplier <= 0
    {
      return nil
    }
    guard let config, config.enabled, config.weeklyThresholdHours.isFinite,
      config.weeklyThresholdHours > 0, !config.rules.isEmpty
    else {
      return nil
    }
    guard config.rules.allSatisfy(isValidSharingOvertimeRule),
      sharingRulesCoverFullDay(config.rules, holiday: false),
      sharingRulesCoverFullDay(config.rules, holiday: true)
    else {
      return nil
    }
    return config
  }

  private nonisolated static func isValidSharingOvertimeRule(_ rule: SharingRPCOvertimeRule) -> Bool
  {
    guard !rule.days.isEmpty,
      Set(rule.days).isSubset(of: Set(1...7)),
      rule.percent.isFinite,
      rule.percent > 0,
      let from = timeToMinutes(rule.from),
      let to = timeToMinutes(rule.to)
    else {
      return false
    }
    return from < to && to <= 24 * 60
  }

  private static func sharingRulesCoverFullDay(
    _ rules: [SharingRPCOvertimeRule],
    holiday: Bool
  ) -> Bool {
    for day in 1...7 {
      let intervals = rules.compactMap { rule -> (Int, Int)? in
        guard rule.dates == nil, rule.days.contains(day) else {
          return nil
        }
        if holiday {
          guard rule.appliesOnHolidays else { return nil }
        } else if isHolidayOnlyRule(rule) {
          return nil
        }
        guard let from = timeToMinutes(rule.from),
          let to = timeToMinutes(rule.to)
        else {
          return nil
        }
        return (from, to)
      }
      guard intervalsCoverFullDay(intervals) else { return false }
    }
    return true
  }

  private static func nextSharingOvertimeBoundary(
    after date: Date,
    segmentEnd: Date,
    config: SharingRPCOvertimeConfig,
    cumulativeMinutes: Double,
    thresholdMinutes: Double
  ) -> Date {
    var boundary = segmentEnd
    let dayStart = sharingCalendar.startOfDay(for: date)

    if let nextDay = sharingCalendar.date(byAdding: .day, value: 1, to: dayStart),
      nextDay > date
    {
      boundary = min(boundary, nextDay)
    }

    if cumulativeMinutes < thresholdMinutes {
      let thresholdDate = date.addingTimeInterval((thresholdMinutes - cumulativeMinutes) * 60)
      if thresholdDate > date {
        boundary = min(boundary, thresholdDate)
      }
    }

    let minuteOfDay = minutesBetween(dayStart, date)
    for rule in config.rules where sharingOvertimeRuleCanMatch(rule, at: date) {
      guard let from = timeToMinutes(rule.from), let to = timeToMinutes(rule.to) else {
        continue
      }
      for value in [Double(from), Double(to)] where value > minuteOfDay {
        let candidate = dayStart.addingTimeInterval(value * 60)
        if candidate > date {
          boundary = min(boundary, candidate)
        }
      }
    }

    return boundary
  }

  private static func sharingOvertimePercent(
    config: SharingRPCOvertimeConfig,
    at date: Date
  ) -> Double? {
    let minute = minutesBetween(sharingCalendar.startOfDay(for: date), date)
    return config.rules.compactMap { rule -> Double? in
      guard sharingOvertimeRuleCanMatch(rule, at: date),
        let from = timeToMinutes(rule.from),
        let to = timeToMinutes(rule.to),
        minute >= Double(from),
        minute < Double(to)
      else {
        return nil
      }
      return rule.percent
    }.max()
  }

  private static func sharingOvertimeRuleCanMatch(
    _ rule: SharingRPCOvertimeRule,
    at date: Date
  ) -> Bool {
    guard rule.days.contains(weekday(from: date)) else { return false }
    let components = sharingCalendar.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year, let month = components.month, let day = components.day else {
      return false
    }
    let iso = String(format: "%04d-%02d-%02d", year, month, day)
    if rule.excludedDates?.contains(iso) == true { return false }
    if let dates = rule.dates { return dates.contains(iso) }
    if NorwegianHolidays.isPublicHoliday(date) {
      return rule.appliesOnHolidays
    }
    return !isHolidayOnlyRule(rule)
  }

  private static func isHolidayOnlyRule(_ rule: SharingRPCOvertimeRule) -> Bool {
    rule.appliesOnHolidays && Set(rule.days) == Set(1...7)
  }

  private static func intervalsCoverFullDay(_ intervals: [(Int, Int)]) -> Bool {
    var coveredUntil = 0
    for interval in intervals.sorted(by: { $0.0 < $1.0 }) {
      guard interval.0 <= coveredUntil else { return false }
      coveredUntil = max(coveredUntil, interval.1)
      if coveredUntil >= 24 * 60 {
        return true
      }
    }
    return false
  }

  private nonisolated static func timeToMinutes(_ value: String) -> Int? {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
      let hours = Int(parts[0]),
      let minutes = Int(parts[1]),
      minutes >= 0,
      minutes < 60,
      hours >= 0,
      hours <= 24,
      hours < 24 || minutes == 0
    else {
      return nil
    }
    return hours * 60 + minutes
  }

  private static func splitByISOWeek(start: Date, end: Date) -> [(Date, Date)] {
    var result: [(Date, Date)] = []
    var cursor = start

    while cursor < end {
      let weekEnd =
        sharingISOCalendar.date(byAdding: .day, value: 7, to: isoWeekStart(for: cursor))
        ?? end
      let partEnd = min(end, weekEnd)
      result.append((cursor, partEnd))
      cursor = partEnd
    }

    return result
  }

  private static func isoWeekStart(for date: Date) -> Date {
    sharingISOCalendar.dateInterval(of: .weekOfYear, for: date)?.start
      ?? sharingCalendar.startOfDay(for: date)
  }

  private static func expandedISOWeekRange(startDate: String, endDate: String) -> (
    startDate: String, endDate: String
  ) {
    guard let start = dateFromISO(startDate), let end = dateFromISO(endDate) else {
      return (startDate, endDate)
    }
    let expandedStart = isoWeekStart(for: start)
    let endWeekStart = isoWeekStart(for: end)
    let expandedEnd = sharingISOCalendar.date(byAdding: .day, value: 6, to: endWeekStart) ?? end
    let carryInStart =
      sharingISOCalendar.date(byAdding: .day, value: -1, to: expandedStart)
      ?? expandedStart
    return (isoDateString(carryInStart), isoDateString(expandedEnd))
  }

  private static func weekday(from date: Date) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let value = calendar.component(.weekday, from: date)
    return value == 1 ? 7 : value - 1
  }

  private static func minutesBetween(_ start: Date, _ end: Date) -> Double {
    end.timeIntervalSince(start) / 60
  }

  private static func mergeAdjacentSharingPeriods(_ periods: [SharingRPCWagePeriod])
    -> [SharingRPCWagePeriod]
  {
    var merged: [SharingRPCWagePeriod] = []
    for period in periods where period.toMin > period.fromMin {
      if let last = merged.last,
        abs(last.toMin - period.fromMin) < 0.0001,
        last.baseRate == period.baseRate,
        last.supplementRate == period.supplementRate,
        last.isOvertime == period.isOvertime
      {
        merged[merged.count - 1] = SharingRPCWagePeriod(
          fromMin: last.fromMin,
          toMin: period.toMin,
          baseRate: last.baseRate,
          supplementRate: last.supplementRate,
          isOvertime: last.isOvertime
        )
      } else {
        merged.append(period)
      }
    }
    return merged
  }

  private static let sharingCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar
  }()

  private static let sharingISOCalendar: Calendar = {
    var calendar = Calendar(identifier: .iso8601)
    calendar.timeZone = .current
    return calendar
  }()

  private static func makePayrollContext(
    settings: SharingRPCUserSettings,
    snapshots: [SharingRPCWageSnapshot],
    jobs: [SharingRPCJobRow]
  ) -> SharingPayrollContext {
    let activeJobs = jobs.filter { $0.deletedAt == nil }
    let jobsById = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
    let defaultJobId =
      activeJobs.first(where: { $0.isDefault && $0.archivedAt == nil })?.id
      ?? activeJobs.first(where: \.isDefault)?.id
      ?? activeJobs.first?.id
      ?? jobs.first(where: { $0.isDefault && $0.archivedAt == nil })?.id
      ?? jobs.first(where: \.isDefault)?.id
      ?? jobs.first?.id
    let snapshotsByJobId = Dictionary(grouping: snapshots, by: { $0.jobId })
    let legacyNilJobSnapshots = snapshotsByJobId[nil] ?? []

    return SharingPayrollContext(
      fallbackPayrollDay: settings.effectivePayrollDay,
      fallbackHalfTaxMonth: settings.halfTaxMonth,
      jobsById: jobsById,
      defaultJobId: defaultJobId,
      snapshotsByJobId: snapshotsByJobId,
      legacyNilJobSnapshots: legacyNilJobSnapshots,
      allSnapshots: snapshots
    )
  }

  private static func snapshotsForJob(
    jobId: String?,
    context: SharingPayrollContext
  ) -> [SharingRPCWageSnapshot] {
    guard let jobId else {
      return context.legacyNilJobSnapshots.isEmpty
        ? context.allSnapshots : context.legacyNilJobSnapshots
    }
    if let scoped = context.snapshotsByJobId[jobId], !scoped.isEmpty {
      return scoped
    }
    if let defaultJobId = context.defaultJobId,
      let scoped = context.snapshotsByJobId[defaultJobId], !scoped.isEmpty
    {
      return scoped
    }
    return context.legacyNilJobSnapshots.isEmpty
      ? context.allSnapshots : context.legacyNilJobSnapshots
  }

  static func computeShift(
    shift: SharingRPCShiftRow,
    snapshot: SharingRPCWageSnapshot?,
    mode: SharingRPCMode
  ) -> SharingComputedShiftComputed {
    let weekday = weekdayFromISO(shift.shiftDate)
    let normalizedPauseWindows = PauseWindowSupport.normalize(shift.customPauseWindows)

    let baseRate = resolveBaseRate(snapshot: snapshot, mode: mode)
    let rules = resolveSupplementRules(
      snapshot: snapshot,
      customSupplements: shift.customSupplements,
      mode: mode
    )

    var periods = buildWagePeriods(
      startTime: shift.startTime,
      endTime: shift.endTime,
      weekday: weekday,
      baseRate: baseRate,
      rules: rules,
      shiftDate: shift.shiftDate
    )
    let originalPeriods = periods

    let totalMinutes = periods.reduce(0.0) { $0 + $1.durationMinutes }
    let durationHours = totalMinutes / 60.0
    let breakAudit: SharingRPCBreakAudit

    if let normalizedPauseWindows {
      let clipped = PauseWindowSupport.apply(
        customPauseWindows: normalizedPauseWindows,
        startTime: shift.startTime,
        endTime: shift.endTime,
        periods: periods.map {
          PauseClipPeriod(
            fromMin: $0.fromMin,
            toMin: $0.toMin,
            baseRate: $0.baseRate,
            supplementRate: $0.supplementRate
          )
        }
      )
      periods = clipped.periods.map {
        SharingRPCWagePeriod(
          fromMin: $0.fromMin,
          toMin: $0.toMin,
          baseRate: $0.baseRate,
          supplementRate: $0.supplementRate
        )
      }
      breakAudit = SharingRPCBreakAudit(
        method: .none,
        thresholdHours: 0,
        deductedHours: clipped.deductedHours,
        source: .customPauseWindows,
        appliedPauseWindows: clipped.appliedPauseWindows,
        notes: clipped.appliedPauseWindows?.isEmpty == false
          ? ["Deducted using custom pause windows"] : []
      )
    } else {
      let breakEnabled = snapshot?.effectiveBreakEnabled ?? defaultBreakEnabled
      let breakMethod = snapshot?.effectiveBreakMethod ?? .proportional
      let savedThreshold = snapshot?.effectiveBreakThresholdHours ?? defaultBreakThresholdHours
      let breakThreshold =
        savedThreshold.isFinite && savedThreshold >= 0
        ? savedThreshold : defaultBreakThresholdHours
      let breakMinutes =
        breakEnabled
        ? (snapshot?.effectiveBreakDeductionMinutes ?? defaultBreakDeductionMinutes) : 0

      let breakResult = BreakDeduction.applyBreakDeduction(
        periods: periods,
        method: breakMethod,
        thresholdHours: breakThreshold,
        deductionHours: Double(breakMinutes) / 60.0
      )

      periods = breakResult.periods
      breakAudit = breakResult.audit
    }

    let paidMinutes = periods.reduce(0.0) { $0 + $1.durationMinutes }
    let paidHours = paidMinutes / 60.0

    let pay = payTotals(for: periods)

    return SharingComputedShiftComputed(
      durationHours: durationHours,
      paidHours: paidHours,
      basePay: pay.base,
      supplementPay: pay.supplement,
      gross: pay.gross,
      wagePeriods: mode == .hidden ? [] : periods,
      originalWagePeriods: mode == .hidden ? [] : originalPeriods,
      breakAudit: breakAudit
    )
  }

  private static func resolveBaseRate(snapshot: SharingRPCWageSnapshot?, mode: SharingRPCMode)
    -> Double
  {
    if let wage = snapshot?.hourlyWage, wage.isFinite, wage > 0 {
      return wage
    }

    if mode == .hidden {
      return 0
    }

    return fallbackBaseRate
  }

  private static func resolveSupplementRules(
    snapshot: SharingRPCWageSnapshot?,
    customSupplements: SharingRPCCustomSupplements?,
    mode: SharingRPCMode
  ) -> [SharingRPCSupplementRule] {
    if let customSupplements {
      if customSupplements.rules.isEmpty {
        return []
      }

      return customSupplements.rules.map { rule in
        SharingRPCSupplementRule(
          stackingGroup: rule.stackingGroup, dates: rule.dates, excludedDates: rule.excludedDates,
          shiftStartDates: rule.shiftStartDates,
          excludedShiftStartDates: rule.excludedShiftStartDates,
          shiftStartBefore: rule.shiftStartBefore,
          minimumRate: rule.minimumRate, percentageBaseRate: rule.percentageBaseRate,
          days: Array(1...7),
          from: rule.from,
          to: rule.to,
          rate: rule.rate,
          percent: rule.percent
        )
      }
    }

    if let snapshot {
      return snapshot.supplements.rules
    }

    if mode == .hidden {
      return []
    }

    return presetSupplementRules
  }

  // MARK: - Wage Periods + Break Deduction

  private static func buildWagePeriods(
    startTime: String,
    endTime: String,
    weekday: Int,
    baseRate: Double,
    rules: [SharingRPCSupplementRule],
    shiftDate: String
  ) -> [SharingRPCWagePeriod] {
    WagePeriodBuilder.buildWagePeriods(
      startTime: startTime, endTime: endTime, weekday: weekday, baseRate: baseRate,
      rules: rules.map(payrollRule), shiftDate: shiftDate)
  }

  private static func payrollRule(_ rule: SharingRPCSupplementRule) -> SupplementRule {
    SupplementRule(
      days: rule.days, from: rule.from, to: rule.to, rate: rule.rate, percent: rule.percent,
      stackingGroup: rule.stackingGroup, dates: rule.dates, excludedDates: rule.excludedDates,
      shiftStartDates: rule.shiftStartDates, excludedShiftStartDates: rule.excludedShiftStartDates,
      shiftStartBefore: rule.shiftStartBefore, minimumRate: rule.minimumRate,
      percentageBaseRate: rule.percentageBaseRate)
  }

  // MARK: - Snapshot Helpers

  private static func snapshotForDate(
    _ date: String,
    from snapshots: [SharingRPCWageSnapshot]
  ) -> SharingRPCWageSnapshot? {
    snapshotForDate(date, from: snapshots, effectiveFrom: \.fromDate)
  }

  static func snapshotForDate<Snapshot>(
    _ date: String, from snapshots: [Snapshot], effectiveFrom: (Snapshot) -> String?
  ) -> Snapshot? {
    var baseline: Snapshot?
    var result: Snapshot?
    var latestDate = ""
    for snapshot in snapshots {
      guard let fromDate = effectiveFrom(snapshot) else {
        if baseline == nil { baseline = snapshot }
        continue
      }
      // Equal dates keep the last entry, matching the historical stable-sort lookup.
      if fromDate <= date, fromDate >= latestDate {
        result = snapshot
        latestDate = fromDate
      }
    }
    return result ?? baseline
  }

  // MARK: - Recurring Helpers

  static func generateVirtualShiftsForMonth(
    year: Int,
    month: Int,
    recurring: SharingRPCRecurringShiftRow
  ) -> [SharingRecurringVirtualShift] {
    guard !recurring.selectedDays.isEmpty else { return [] }

    let monthStartISO = monthStart(year: year, month: month)
    let monthEndISO = monthEnd(year: year, month: month)
    let exclusionSet = Set(recurring.exclusions ?? [])

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current

    var startComponents = DateComponents()
    startComponents.year = year
    startComponents.month = month
    startComponents.day = 1
    startComponents.hour = 12

    var endComponents = DateComponents()
    endComponents.year = year
    endComponents.month = month
    endComponents.day = daysInMonth(year: year, month: month)
    endComponents.hour = 12

    guard let monthStartDate = calendar.date(from: startComponents),
      let monthEndDate = calendar.date(from: endComponents)
    else {
      return []
    }

    var virtualShifts: [SharingRecurringVirtualShift] = []

    for (weekdayKey, anchorISO) in recurring.selectedDays {
      guard let weekday = Int(weekdayKey) else { continue }

      var current = monthStartDate
      let currentWeekday = calendar.component(.weekday, from: current) - 1
      let daysUntilTarget = (weekday - currentWeekday + 7) % 7
      current = calendar.date(byAdding: .day, value: daysUntilTarget, to: current) ?? current

      while current <= monthEndDate {
        let currentISO = isoDateString(current)

        if currentISO < monthStartISO || currentISO > monthEndISO {
          current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
          continue
        }

        if currentISO < anchorISO {
          current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
          continue
        }

        let inPhase = isInPhase(
          dateISO: currentISO,
          anchorISO: anchorISO,
          interval: recurring.repeatIntervalWeeks
        )

        let withinWindow = checkEndCondition(
          currentDate: current,
          currentISO: currentISO,
          endCondition: recurring.endCondition,
          selectedDays: recurring.selectedDays
        )

        let notExcluded = !exclusionSet.contains(currentISO)

        if inPhase, withinWindow, notExcluded {
          virtualShifts.append(SharingRecurringVirtualShift(date: currentISO, weekday: weekday))
        }

        current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
      }
    }

    return virtualShifts.sorted { $0.date < $1.date }
  }

  static func isInPhase(dateISO: String, anchorISO: String, interval: Int) -> Bool {
    if interval == 0 { return true }
    let dayDiff = daysBetween(anchorISO, dateISO)
    let weeksDiff = dayDiff / 7
    return weeksDiff.isMultiple(of: interval + 1)
  }

  private static func checkEndCondition(
    currentDate: Date,
    currentISO: String,
    endCondition: SharingRPCEndCondition?,
    selectedDays: [String: String]
  ) -> Bool {
    guard let endCondition else {
      return true
    }

    let anchorDates = selectedDays.values.sorted()
    guard let earliestAnchor = anchorDates.first,
      let anchorDate = dateFromISO(earliestAnchor)
    else {
      return true
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current

    switch endCondition {
    case .months(let value):
      guard let endDate = calendar.date(byAdding: .month, value: value, to: anchorDate) else {
        return true
      }
      return currentISO <= isoDateString(endDate)

    case .years(let value):
      guard let endDate = calendar.date(byAdding: .year, value: value, to: anchorDate) else {
        return true
      }
      return currentISO <= isoDateString(endDate)

    case .endDate(let date):
      return currentISO <= date
    }
  }

  // MARK: - Date + Time Helpers

  private static func weekdayFromISO(_ dateString: String) -> Int {
    guard let date = dateFromISO(dateString) else { return 1 }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let weekday = calendar.component(.weekday, from: date)
    return weekday == 1 ? 7 : weekday - 1
  }

  private static func dateFromISO(_ dateString: String) -> Date? {
    isoDateFormatter.date(from: dateString)
  }

  private static func daysBetween(_ from: String, _ to: String) -> Int {
    guard let fromDate = dateFromISO(from),
      let toDate = dateFromISO(to)
    else {
      return 0
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current

    let fromStart = calendar.startOfDay(for: fromDate)
    let toStart = calendar.startOfDay(for: toDate)

    return calendar.dateComponents([.day], from: fromStart, to: toStart).day ?? 0
  }

  private static func monthsInRange(startDate: String, endDate: String) -> [(Int, Int)] {
    let startParts = startDate.split(separator: "-")
    let endParts = endDate.split(separator: "-")

    guard startParts.count >= 2,
      endParts.count >= 2,
      let startYear = Int(startParts[0]),
      let startMonth = Int(startParts[1]),
      let endYear = Int(endParts[0]),
      let endMonth = Int(endParts[1])
    else {
      return []
    }

    var result: [(Int, Int)] = []
    var year = startYear
    var month = startMonth

    while year < endYear || (year == endYear && month <= endMonth) {
      result.append((year, month))
      month += 1
      if month > 12 {
        month = 1
        year += 1
      }
    }

    return result
  }

  private static func daysInMonth(year: Int, month: Int) -> Int {
    var components = DateComponents()
    components.year = year
    components.month = month + 1
    components.day = 0

    let calendar = Calendar(identifier: .gregorian)
    guard let date = calendar.date(from: components) else {
      return 30
    }

    return calendar.component(.day, from: date)
  }

  static func payTotals(for periods: [WagePeriod]) -> PayrollPayTotals {
    let base = periods.reduce(0) { $0 + max(0, $1.durationHours) * $1.baseRate }
    let supplement = periods.reduce(0) { $0 + max(0, $1.durationHours) * $1.supplementRate }
    let basePay = roundedPay(base, periodCount: periods.count)
    let supplementPay = roundedPay(supplement, periodCount: periods.count)
    return PayrollPayTotals(
      base: basePay, supplement: supplementPay, gross: roundTo(basePay + supplementPay, decimals: 2)
    )
  }

  private static func roundedPay(_ amount: Double, periodCount: Int) -> Double {
    let cents = amount * 100
    // Allow for floating-point error from each contribution and the final scaling.
    let tolerance = abs(cents) * Double.ulpOfOne * Double(periodCount + 2)
    return round(cents + tolerance) / 100
  }

  private static func roundTo(_ value: Double, decimals: Int) -> Double {
    let precision = pow(10.0, Double(decimals))
    return round(value * precision) / precision
  }
}
